-- FrostTech TEST only: launch appointment hold safeguard.
-- Default is ON. Employee planning and invitation/account setup remain separate.
-- Employment activation and departmental appointment/reactivation are blocked until
-- the Super Administrator explicitly releases the hold after launch authorisation.

create table if not exists public.frosttech_appointment_controls (
  control_key text primary key check (control_key = 'departmental_appointments'),
  is_on_hold boolean not null default true,
  hold_reason text not null default 'Appointments are on hold until FrostTech officially launches.',
  updated_by uuid,
  updated_at timestamptz not null default now()
);
insert into public.frosttech_appointment_controls(control_key,is_on_hold)
values ('departmental_appointments',true)
on conflict (control_key) do nothing;

alter table public.frosttech_appointment_controls enable row level security;
revoke all on public.frosttech_appointment_controls from public, anon, authenticated;

create or replace function public.frosttech_departmental_appointments_on_hold()
returns boolean language sql stable security definer set search_path = ''
as $$
  select coalesce((select c.is_on_hold from public.frosttech_appointment_controls c
    where c.control_key='departmental_appointments'),true);
$$;
revoke all on function public.frosttech_departmental_appointments_on_hold() from public, anon, authenticated;

create or replace function public.admin_get_appointment_hold_status()
returns table(is_on_hold boolean, hold_reason text, updated_at timestamptz)
language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null or not public.is_super_admin() then
    raise exception 'Super Administrator access required';
  end if;
  return query select c.is_on_hold,c.hold_reason,c.updated_at
    from public.frosttech_appointment_controls c
    where c.control_key='departmental_appointments';
end;
$$;

create or replace function public.admin_set_appointment_hold(p_is_on_hold boolean,p_reason text default null)
returns boolean language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null or not public.is_super_admin() then
    raise exception 'Super Administrator access required';
  end if;
  if p_is_on_hold is null then raise exception 'Appointment hold status is required'; end if;
  if p_is_on_hold is false and (p_reason is null or length(btrim(p_reason)) < 12) then
    raise exception 'A clear launch-authorisation reason is required before releasing the appointment hold';
  end if;
  update public.frosttech_appointment_controls
  set is_on_hold=p_is_on_hold,
      hold_reason=coalesce(nullif(btrim(p_reason),''),case when p_is_on_hold then 'Appointments are on hold until FrostTech officially launches.' else hold_reason end),
      updated_by=auth.uid(),updated_at=now()
  where control_key='departmental_appointments';
  insert into public.admin_activity_log(actor_user_id,action,details)
  values(auth.uid(),case when p_is_on_hold then 'departmental_appointment_hold_enabled' else 'departmental_appointment_hold_released' end,
    jsonb_build_object('is_on_hold',p_is_on_hold,'reason',p_reason,'environment','isolated_test'));
  return true;
end;
$$;

create or replace function public.frosttech_enforce_appointment_hold()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if not public.frosttech_departmental_appointments_on_hold() then return new; end if;
  if tg_table_name='frosttech_employees' then
    -- Do not block invitations or self-service account setup.
    if new.employment_status='active'
       and (tg_op='INSERT' or old.employment_status is distinct from new.employment_status) then
      raise exception 'FrostTech employee activation is on hold until launch';
    end if;
    return new;
  end if;
  if tg_table_name='admin_accounts' then
    -- Preserve existing access; suspension/removal remain possible.
    if new.role in ('operations_admin','supplier_admin','finance_admin','catalogue_admin')
       and (tg_op='INSERT' or old.role is distinct from new.role or
            (new.is_active is true and old.is_active is distinct from new.is_active)) then
      raise exception 'Departmental administrator appointments and reactivation are on hold until FrostTech launches';
    end if;
    return new;
  end if;
  return new;
end;
$$;

revoke all on function public.frosttech_enforce_appointment_hold() from public, anon, authenticated;

drop trigger if exists frosttech_employee_appointment_hold_guard on public.frosttech_employees;
create trigger frosttech_employee_appointment_hold_guard
before insert or update on public.frosttech_employees
for each row execute function public.frosttech_enforce_appointment_hold();

drop trigger if exists frosttech_admin_appointment_hold_guard on public.admin_accounts;
create trigger frosttech_admin_appointment_hold_guard
before insert or update on public.admin_accounts
for each row execute function public.frosttech_enforce_appointment_hold();

-- Replace the appointment RPC with a server-side hold check in addition to table trigger.
create or replace function public.admin_appoint_departmental_admin(p_user_id uuid,p_role text)
returns boolean language plpgsql security definer set search_path = ''
as $function$
declare v_employee record; v_expected_role text;
begin
  if auth.uid() is null or not public.is_super_admin() then
    raise exception 'Super Administrator access required';
  end if;
  if public.frosttech_departmental_appointments_on_hold() then
    raise exception 'Departmental administrator appointments are on hold until FrostTech officially launches';
  end if;
  select e.id,e.full_name,e.email,e.department,e.employment_status,
         e.account_setup_completed_at,e.auth_user_id,u.email_confirmed_at,
         u.raw_app_meta_data ->> 'frosttech_account_type' as account_type,
         p.role as profile_role,p.is_active as profile_active
  into v_employee
  from public.frosttech_employees e
  join auth.users u on u.id=e.auth_user_id
  join public.profiles p on p.id=e.auth_user_id
  where e.auth_user_id=p_user_id
  for update of e;
  if not found then raise exception 'This account is not linked to a FrostTech employee'; end if;
  if v_employee.employment_status <> 'active' or v_employee.account_setup_completed_at is null
     or v_employee.email_confirmed_at is null or v_employee.account_type <> 'employee'
     or v_employee.profile_role <> 'employee' or v_employee.profile_active is not true then
    raise exception 'Employee account is not eligible for appointment';
  end if;
  v_expected_role := case v_employee.department
    when 'operations' then 'operations_admin'
    when 'supplier_management' then 'supplier_admin'
    when 'finance' then 'finance_admin'
    when 'catalogue' then 'catalogue_admin' else null end;
  if v_expected_role is null or p_role <> v_expected_role then
    raise exception 'The administrator role does not match the employee department';
  end if;
  if exists(select 1 from public.admin_accounts where user_id=p_user_id and role='super_admin') then
    raise exception 'The Super Administrator account is protected';
  end if;
  update public.admin_accounts set role=p_role,is_active=true,appointed_by=auth.uid(),
    appointed_at=now(),updated_at=now() where user_id=p_user_id;
  if not found then
    insert into public.admin_accounts(user_id,role,is_active,appointed_by,appointed_at,updated_at)
    values(p_user_id,p_role,true,auth.uid(),now(),now());
  end if;
  insert into public.admin_activity_log(actor_user_id,action,target_user_id,details)
  values(auth.uid(),'departmental_admin_appointed',p_user_id,
    jsonb_build_object('employee_id',v_employee.id,'employee_email',v_employee.email,
      'department',v_employee.department,'role',p_role));
  return true;
end;
$function$;

-- Replace activation RPC with a server-side hold check.
create or replace function public.admin_activate_frosttech_employee(p_employee_id uuid)
returns boolean language plpgsql security definer set search_path = ''
as $function$
declare v_employee record;
begin
  if auth.uid() is null or not public.is_super_admin() then
    raise exception 'Super Administrator access required';
  end if;
  if public.frosttech_departmental_appointments_on_hold() then
    raise exception 'Employee employment activation is on hold until FrostTech officially launches';
  end if;
  select id,full_name,email,department,auth_user_id,employment_status,account_setup_completed_at
  into v_employee from public.frosttech_employees where id=p_employee_id for update;
  if not found then raise exception 'Employee record not found'; end if;
  if v_employee.employment_status <> 'invited' or v_employee.auth_user_id is null
     or v_employee.account_setup_completed_at is null then
    raise exception 'Employee must complete account setup before activation';
  end if;
  update public.frosttech_employees set employment_status='active',updated_at=now()
  where id=p_employee_id;
  insert into public.admin_activity_log(actor_user_id,action,target_user_id,details)
  values(auth.uid(),'frosttech_employee_activated',v_employee.auth_user_id,
    jsonb_build_object('employee_id',p_employee_id,'department',v_employee.department,'email',v_employee.email));
  return true;
end;
$function$;

revoke all on function public.admin_get_appointment_hold_status() from public, anon;
revoke all on function public.admin_set_appointment_hold(boolean,text) from public, anon;
grant execute on function public.admin_get_appointment_hold_status() to authenticated;
grant execute on function public.admin_set_appointment_hold(boolean,text) to authenticated;
