-- REVIEW-ONLY DRAFT
-- FrostTech Command Center: Security & System Administration workspace
-- Target: isolated test Supabase project gqnidjifiobhqhnxjlow ONLY.
-- DO NOT APPLY until reviewed and explicitly approved.
-- No production records or settings are referenced by this migration.
--
-- Source compatibility was checked against the existing production page RPC calls.
-- This draft intentionally does not create employee accounts, invite users, or change
-- auth.users / profiles roles. Employee onboarding/account provisioning is a separate
-- dependency and must be audited before this migration is applied.

begin;

-- 1. Employee register used by the Super Admin operator-management workspace.
create table if not exists public.frosttech_employees (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  email text not null,
  job_title text not null,
  department text not null,
  employment_status text not null default 'planned',
  auth_user_id uuid null references auth.users(id) on delete set null,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  account_setup_completed_at timestamptz null
);

comment on table public.frosttech_employees is
  'Employee register. Departmental appointments are controlled only by Super Admin RPCs.';

alter table public.frosttech_employees enable row level security;
revoke all on table public.frosttech_employees from anon, authenticated;

-- 2. Employee listing: Super Admin only; no direct table read is granted.
create or replace function public.admin_list_frosttech_employee_management()
returns table (
  employee_id uuid,
  auth_user_id uuid,
  full_name text,
  email text,
  job_title text,
  department text,
  employment_status text,
  account_setup_completed_at timestamptz,
  administrator_role text,
  administrator_active boolean,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null or not public.is_super_admin() then
    raise exception 'Super Administrator access required';
  end if;

  return query
  select e.id, e.auth_user_id, e.full_name, e.email, e.job_title,
         e.department, e.employment_status, e.account_setup_completed_at,
         a.role, a.is_active, e.created_at
  from public.frosttech_employees e
  left join public.admin_accounts a on a.user_id = e.auth_user_id
  order by e.created_at desc;
end;
$function$;

-- 3. Administrator list: Super Admin only; protects permanent Super Admin from UI actions.
create or replace function public.admin_list_administrator_accounts()
returns table (
  user_id uuid,
  email text,
  full_name text,
  profile_role text,
  profile_active boolean,
  administrator_role text,
  administrator_active boolean,
  appointed_by uuid,
  appointed_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null or not public.is_super_admin() then
    raise exception 'Super Administrator access required';
  end if;

  return query
  select a.user_id, u.email::text, p.full_name::text, p.role::text,
         p.is_active, a.role, a.is_active, a.appointed_by,
         a.appointed_at, a.updated_at
  from public.admin_accounts a
  left join auth.users u on u.id = a.user_id
  left join public.profiles p on p.id = a.user_id
  order by case when a.role = 'super_admin' then 0 else 1 end,
           a.appointed_at;
end;
$function$;

-- 4. Appointment: the employee must already have a verified, completed employee account.
-- Department-to-role mapping is enforced server-side; client-supplied role alone is insufficient.
create or replace function public.admin_appoint_departmental_admin(
  p_user_id uuid,
  p_role text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_employee record;
  v_expected_role text;
begin
  if auth.uid() is null or not public.is_super_admin() then
    raise exception 'Super Administrator access required';
  end if;

  select e.id, e.full_name, e.email, e.department, e.employment_status,
         e.account_setup_completed_at, e.auth_user_id, u.email_confirmed_at,
         u.raw_app_meta_data ->> 'frosttech_account_type' as account_type,
         p.role as profile_role, p.is_active as profile_active
  into v_employee
  from public.frosttech_employees e
  join auth.users u on u.id = e.auth_user_id
  join public.profiles p on p.id = e.auth_user_id
  where e.auth_user_id = p_user_id
  for update of e;

  if not found then
    raise exception 'This account is not linked to a FrostTech employee';
  end if;

  if v_employee.employment_status <> 'active'
     or v_employee.account_setup_completed_at is null
     or v_employee.email_confirmed_at is null
     or v_employee.account_type <> 'employee'
     or v_employee.profile_role <> 'employee'
     or v_employee.profile_active is not true then
    raise exception 'Employee account is not eligible for appointment';
  end if;

  v_expected_role := case v_employee.department
    when 'operations' then 'operations_admin'
    when 'supplier_management' then 'supplier_admin'
    when 'finance' then 'finance_admin'
    when 'catalogue' then 'catalogue_admin'
    else null
  end;

  if v_expected_role is null or p_role <> v_expected_role then
    raise exception 'The administrator role does not match the employee department';
  end if;

  if exists (
    select 1 from public.admin_accounts
    where user_id = p_user_id and role = 'super_admin'
  ) then
    raise exception 'The Super Administrator account is protected';
  end if;

  update public.admin_accounts
  set role = p_role, is_active = true, appointed_by = auth.uid(),
      appointed_at = now(), updated_at = now()
  where user_id = p_user_id;

  if not found then
    insert into public.admin_accounts
      (user_id, role, is_active, appointed_by, appointed_at, updated_at)
    values (p_user_id, p_role, true, auth.uid(), now(), now());
  end if;

  insert into public.admin_activity_log(actor_user_id, action, target_user_id, details)
  values (
    auth.uid(), 'departmental_admin_appointed', p_user_id,
    jsonb_build_object('employee_id', v_employee.id,
      'employee_email', v_employee.email, 'department', v_employee.department,
      'role', p_role)
  );
  return true;
end;
$function$;

-- 5. Suspend/reactivate departmental administrator access only.
create or replace function public.admin_set_departmental_admin_status(
  p_user_id uuid,
  p_is_active boolean
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_current_role text;
  v_old_status boolean;
begin
  if auth.uid() is null or not public.is_super_admin() then
    raise exception 'Super Administrator access required';
  end if;
  if p_user_id is null or p_is_active is null then
    raise exception 'User and new account status are required';
  end if;

  select role, is_active into v_current_role, v_old_status
  from public.admin_accounts where user_id = p_user_id for update;

  if not found then raise exception 'Departmental administrator not found'; end if;
  if v_current_role = 'super_admin' then
    raise exception 'The Super Administrator cannot be suspended or reactivated through this function';
  end if;

  update public.admin_accounts
  set is_active = p_is_active, updated_at = now()
  where user_id = p_user_id;

  insert into public.admin_activity_log(actor_user_id, action, target_user_id, details)
  values (
    auth.uid(),
    case when p_is_active then 'departmental_admin_reactivated'
         else 'departmental_admin_suspended' end,
    p_user_id,
    jsonb_build_object('role', v_current_role,
      'previous_status', v_old_status, 'new_status', p_is_active)
  );
  return true;
end;
$function$;

-- 6. Remove only the departmental appointment; never delete employee/auth/profile records.
create or replace function public.admin_remove_departmental_admin(p_user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_current_role text;
  v_current_status boolean;
begin
  if auth.uid() is null or not public.is_super_admin() then
    raise exception 'Super Administrator access required';
  end if;
  if p_user_id is null then raise exception 'User is required'; end if;

  select role, is_active into v_current_role, v_current_status
  from public.admin_accounts where user_id = p_user_id for update;

  if not found then raise exception 'Departmental administrator not found'; end if;
  if v_current_role = 'super_admin' then
    raise exception 'The Super Administrator cannot be removed';
  end if;

  delete from public.admin_accounts
  where user_id = p_user_id and role <> 'super_admin';

  if not found then raise exception 'Administrator removal was not completed'; end if;

  insert into public.admin_activity_log(actor_user_id, action, target_user_id, details)
  values (
    auth.uid(), 'departmental_admin_removed', p_user_id,
    jsonb_build_object('previous_role', v_current_role,
      'previous_status', v_current_status)
  );
  return true;
end;
$function$;

-- 7. Read-only, paginated audit listing. Existing append-only audit protection is untouched.
create or replace function public.admin_list_activity_log(
  p_limit integer default 100,
  p_offset integer default 0
)
returns setof public.admin_activity_log
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null or not public.is_super_admin() then
    raise exception 'Super Administrator access required';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 200 then
    raise exception 'Limit must be between 1 and 200';
  end if;
  if p_offset is null or p_offset < 0 then
    raise exception 'Offset cannot be negative';
  end if;

  return query
  select l.* from public.admin_activity_log l
  order by l.created_at desc, l.id desc
  limit p_limit offset p_offset;
end;
$function$;



-- 1A. Data integrity rules mirrored from the reviewed employee workflow.
create unique index if not exists frosttech_employees_email_lower_uidx
  on public.frosttech_employees (lower(email));
create unique index if not exists frosttech_employees_auth_user_uidx
  on public.frosttech_employees (auth_user_id)
  where auth_user_id is not null;

do $constraints$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.frosttech_employees'::regclass
      and conname = 'frosttech_employees_department_check'
  ) then
    alter table public.frosttech_employees
      add constraint frosttech_employees_department_check
      check (department in ('operations','supplier_management','finance','catalogue'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.frosttech_employees'::regclass
      and conname = 'frosttech_employees_status_check'
  ) then
    alter table public.frosttech_employees
      add constraint frosttech_employees_status_check
      check (employment_status in ('planned','invited','active'));
  end if;
end;
$constraints$;

-- 1B. Create an employee record only; this never creates an auth account or appointment.
create or replace function public.admin_create_frosttech_employee(
  p_full_name text, p_email text, p_job_title text, p_department text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_employee_id uuid;
  v_email text;
  v_department text;
begin
  if auth.uid() is null or not public.is_super_admin() then
    raise exception 'Access denied. Super Administrator only.';
  end if;
  if p_full_name is null or pg_catalog.btrim(p_full_name) = '' then
    raise exception 'Employee full name is required.';
  end if;
  if p_email is null or pg_catalog.btrim(p_email) = '' then
    raise exception 'Employee email address is required.';
  end if;

  v_email := pg_catalog.lower(pg_catalog.btrim(p_email));
  v_department := pg_catalog.lower(pg_catalog.btrim(p_department));

  if pg_catalog.strpos(v_email,'@') < 2
     or pg_catalog.strpos(v_email,'.') <= pg_catalog.strpos(v_email,'@') + 1
     or pg_catalog.strpos(v_email,' ') > 0 then
    raise exception 'Enter a valid employee email address.';
  end if;
  if p_job_title is null or pg_catalog.btrim(p_job_title) = '' then
    raise exception 'Employee job title is required.';
  end if;
  if v_department not in ('operations','supplier_management','finance','catalogue') then
    raise exception 'Invalid FrostTech department.';
  end if;
  if exists (select 1 from public.frosttech_employees e where pg_catalog.lower(e.email)=v_email) then
    raise exception 'An employee record with this email address already exists.';
  end if;
  if exists (select 1 from auth.users u where pg_catalog.lower(pg_catalog.btrim(u.email))=v_email) then
    raise exception 'This email is already registered with FrostTech. Use a separate employee email address.';
  end if;

  insert into public.frosttech_employees
    (full_name,email,job_title,department,employment_status,created_by)
  values
    (pg_catalog.btrim(p_full_name),v_email,pg_catalog.btrim(p_job_title),v_department,'planned',auth.uid())
  returning id into v_employee_id;

  insert into public.admin_activity_log(actor_user_id,action,details)
  values(auth.uid(),'frosttech_employee_record_created',
    pg_catalog.jsonb_build_object('employee_id',v_employee_id,'email',v_email,'department',v_department));
  return v_employee_id;
end;
$function$;

-- 1C. Service-role-only invitation completion. It verifies the actor and employee marker.
create or replace function public.admin_complete_employee_invitation(
  p_employee_id uuid, p_auth_user_id uuid, p_actor_user_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_employee record;
  v_auth_email text;
  v_account_type text;
  v_employee_marker text;
  v_actor_ok boolean;
begin
  if auth.role() <> 'service_role' then raise exception 'Access denied'; end if;
  select exists (
    select 1 from public.admin_accounts a
    join public.profiles p on p.id=a.user_id
    where a.user_id=p_actor_user_id and a.role='super_admin'
      and a.is_active is true and p.is_active is true
  ) into v_actor_ok;
  if not v_actor_ok then raise exception 'Active Super Administrator actor required'; end if;

  select id,full_name,email,department,employment_status,auth_user_id
  into v_employee
  from public.frosttech_employees where id=p_employee_id for update;
  if not found then raise exception 'Employee record not found'; end if;

  select pg_catalog.lower(pg_catalog.btrim(email)),
         raw_app_meta_data ->> 'frosttech_account_type',
         raw_app_meta_data ->> 'frosttech_employee_id'
  into v_auth_email,v_account_type,v_employee_marker
  from auth.users where id=p_auth_user_id;
  if not found then raise exception 'Authentication account not found'; end if;
  if v_auth_email <> pg_catalog.lower(pg_catalog.btrim(v_employee.email)) then
    raise exception 'Employee email does not match authentication account';
  end if;
  if v_account_type <> 'employee' or v_employee_marker <> p_employee_id::text then
    raise exception 'Authentication account is not securely marked for this employee';
  end if;

  if v_employee.auth_user_id=p_auth_user_id and v_employee.employment_status in ('invited','active') then
    if not exists(select 1 from public.profiles where id=p_auth_user_id and role='employee') then
      raise exception 'Linked employee profile is missing or inconsistent; manual review required';
    end if;
    return true;
  end if;
  if v_employee.employment_status <> 'planned' or v_employee.auth_user_id is not null then
    raise exception 'Employee record is already linked to another account or is not eligible';
  end if;

  insert into public.profiles(id,full_name,phone,role,is_active)
  values(p_auth_user_id,v_employee.full_name,null,'employee',true)
  on conflict(id) do nothing;
  if not exists(select 1 from public.profiles where id=p_auth_user_id and role='employee') then
    raise exception 'Existing profile is not an employee profile; manual review required';
  end if;

  update public.frosttech_employees
  set auth_user_id=p_auth_user_id,employment_status='invited',updated_at=now()
  where id=p_employee_id;

  insert into public.admin_activity_log(actor_user_id,action,target_user_id,details)
  values(p_actor_user_id,'frosttech_employee_invited',p_auth_user_id,
    pg_catalog.jsonb_build_object('employee_id',p_employee_id,'department',v_employee.department,
      'email',v_employee.email,'recovery_safe_linking',true));
  return true;
end;
$function$;

-- 1D. Service-role-only lookup for invitation recovery; no arbitrary auth-user search is exposed.
create or replace function public.admin_find_employee_invitation_user(p_employee_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare v_email text; v_user_id uuid;
begin
  if auth.role() <> 'service_role' then raise exception 'Access denied'; end if;
  select pg_catalog.lower(pg_catalog.btrim(email)) into v_email
  from public.frosttech_employees
  where id=p_employee_id and employment_status='planned' and auth_user_id is null;
  if not found then raise exception 'Employee is not awaiting invitation recovery'; end if;
  select id into v_user_id from auth.users
  where pg_catalog.lower(pg_catalog.btrim(email))=v_email
    and raw_user_meta_data ->> 'frosttech_employee_id'=p_employee_id::text
    and raw_user_meta_data ->> 'account_type'='employee'
  order by created_at desc limit 1;
  return v_user_id;
end;
$function$;

-- 1E. Employee self-service completion; verified account must match the linked invitation.
create or replace function public.employee_complete_frosttech_account_setup()
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare v_user_id uuid; v_email text; v_account_type text;
begin
  v_user_id := auth.uid();
  if v_user_id is null then raise exception 'Authentication required'; end if;

  select pg_catalog.lower(pg_catalog.btrim(email)),
         raw_app_meta_data ->> 'frosttech_account_type'
  into v_email,v_account_type
  from auth.users where id=v_user_id and email_confirmed_at is not null;
  if not found or v_account_type <> 'employee' then
    raise exception 'Verified FrostTech employee account required';
  end if;

  update public.frosttech_employees
  set account_setup_completed_at=coalesce(account_setup_completed_at,now()),updated_at=now()
  where auth_user_id=v_user_id and pg_catalog.lower(pg_catalog.btrim(email))=v_email
    and employment_status='invited';
  if not found then
    if exists(select 1 from public.frosttech_employees
      where auth_user_id=v_user_id and account_setup_completed_at is not null) then
      return true;
    end if;
    raise exception 'Matching invited employee record not found';
  end if;

  insert into public.admin_activity_log(actor_user_id,action,target_user_id,details)
  values(v_user_id,'frosttech_employee_account_setup_completed',v_user_id,
    pg_catalog.jsonb_build_object('email',v_email));
  return true;
end;
$function$;

-- 1F. Employment activation is separate from departmental administrator appointment.
create or replace function public.admin_activate_frosttech_employee(p_employee_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare v_employee record;
begin
  if auth.uid() is null or not public.is_super_admin() then
    raise exception 'Super Administrator access required';
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
    pg_catalog.jsonb_build_object('employee_id',p_employee_id,'department',v_employee.department,'email',v_employee.email));
  return true;
end;
$function$;


-- Explicit RPC grants. Functions verify Super Administrator identity internally.
revoke all on function public.admin_create_frosttech_employee(text,text,text,text) from public, anon;
revoke all on function public.admin_activate_frosttech_employee(uuid) from public, anon;
revoke all on function public.employee_complete_frosttech_account_setup() from public, anon;
revoke all on function public.admin_list_frosttech_employee_management() from public, anon;
revoke all on function public.admin_list_administrator_accounts() from public, anon;
revoke all on function public.admin_appoint_departmental_admin(uuid,text) from public, anon;
revoke all on function public.admin_set_departmental_admin_status(uuid,boolean) from public, anon;
revoke all on function public.admin_remove_departmental_admin(uuid) from public, anon;
revoke all on function public.admin_list_activity_log(integer,integer) from public, anon;
revoke all on function public.admin_complete_employee_invitation(uuid,uuid,uuid) from public, anon, authenticated;
revoke all on function public.admin_find_employee_invitation_user(uuid) from public, anon, authenticated;

grant execute on function public.admin_create_frosttech_employee(text,text,text,text) to authenticated;
grant execute on function public.admin_activate_frosttech_employee(uuid) to authenticated;
grant execute on function public.employee_complete_frosttech_account_setup() to authenticated;
grant execute on function public.admin_list_frosttech_employee_management() to authenticated;
grant execute on function public.admin_list_administrator_accounts() to authenticated;
grant execute on function public.admin_appoint_departmental_admin(uuid,text) to authenticated;
grant execute on function public.admin_set_departmental_admin_status(uuid,boolean) to authenticated;
grant execute on function public.admin_remove_departmental_admin(uuid) to authenticated;
grant execute on function public.admin_list_activity_log(integer,integer) to authenticated;
grant execute on function public.admin_complete_employee_invitation(uuid,uuid,uuid) to service_role;
grant execute on function public.admin_find_employee_invitation_user(uuid) to service_role;

commit;

-- TEST EDGE-FUNCTION DEPENDENCY (NOT DEPLOYED BY THIS SQL):
-- A test-only invitation function source is staged separately in this repository.
-- It uses the test preview host and test Supabase environment variables, not production.
-- Before deployment, add the test redirect URL to the test project's Auth redirect allow-list.
-- It writes the employee UUID to raw user metadata and protected app metadata so that
-- admin_complete_employee_invitation and admin_find_employee_invitation_user agree.
-- Do not deploy the Edge Function or send invitations without separate explicit approval.

-- PRE-EXECUTION REVIEW CHECKLIST
-- [ ] Confirm is_super_admin() and admin_accounts protection in test.
-- [ ] Confirm audit table is append-only and direct client mutation remains denied.
-- [ ] Confirm employee table has no direct anon/authenticated read/write policies.
-- [ ] Confirm function owners can read auth.users and protected public tables.
-- [ ] Run static SQL validation and compare every RPC signature with frontend calls.
-- [ ] Confirm the isolated Edge Function is deployed only after separate approval.
-- [ ] Add the isolated invitation redirect URL to the test Auth redirect allow-list.
-- [ ] Apply SQL only to isolated test project after separate explicit approval.
-- [ ] Do not send test invitations until the user separately authorises a test invitation.
