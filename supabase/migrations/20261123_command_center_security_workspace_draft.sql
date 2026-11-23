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

-- Explicit authenticated execution only; each function independently verifies Super Admin.
revoke all on function public.admin_list_frosttech_employee_management() from public, anon;
revoke all on function public.admin_list_administrator_accounts() from public, anon;
revoke all on function public.admin_appoint_departmental_admin(uuid,text) from public, anon;
revoke all on function public.admin_set_departmental_admin_status(uuid,boolean) from public, anon;
revoke all on function public.admin_remove_departmental_admin(uuid) from public, anon;
revoke all on function public.admin_list_activity_log(integer,integer) from public, anon;

grant execute on function public.admin_list_frosttech_employee_management() to authenticated;
grant execute on function public.admin_list_administrator_accounts() to authenticated;
grant execute on function public.admin_appoint_departmental_admin(uuid,text) to authenticated;
grant execute on function public.admin_set_departmental_admin_status(uuid,boolean) to authenticated;
grant execute on function public.admin_remove_departmental_admin(uuid) to authenticated;
grant execute on function public.admin_list_activity_log(integer,integer) to authenticated;

commit;

-- PRE-EXECUTION REVIEW CHECKLIST
-- [ ] Confirm employee onboarding/account provisioning workflow exists in test and creates
--     profiles.role='employee', auth.users app_metadata frosttech_account_type='employee',
--     verified email, and account_setup_completed_at.
-- [ ] Confirm is_super_admin() and admin_accounts protection in test.
-- [ ] Confirm audit table is append-only and direct client mutation remains denied.
-- [ ] Confirm employee table has no direct anon/authenticated read/write policies.
-- [ ] Confirm function owners can read auth.users and protected public tables.
-- [ ] Run static SQL validation and compare RPC return column names with frontend code.
-- [ ] Apply only to isolated test project after separate explicit approval.
