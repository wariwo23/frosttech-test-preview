-- Isolated TEST environment only.
-- Creates a separate test-admin grant path without changing employee records,
-- departmental appointments, admin_accounts, or the appointment-hold guard.

create table public.isolated_test_admin_grants (
  user_id uuid primary key references auth.users(id) on delete restrict,
  role text not null check (role = 'finance_admin'),
  granted_by uuid not null references auth.users(id) on delete restrict,
  granted_at timestamptz not null default now(),
  revoked_at timestamptz,
  is_active boolean not null default true
);

alter table public.isolated_test_admin_grants enable row level security;
revoke all on table public.isolated_test_admin_grants from anon, authenticated, public;

create or replace function public.admin_grant_isolated_test_finance_access(p_user_id uuid)
returns boolean
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_email text;
  v_confirmed_at timestamptz;
  v_profile_active boolean;
  v_profile_role text;
begin
  if auth.uid() is null or not public.is_super_admin() then
    raise exception 'Super Administrator access required';
  end if;

  -- Strict allow-list: this temporary test route can grant only this identity.
  if p_user_id <> '55ef7cb8-6c06-481a-be21-22f4f98c0d6a'::uuid then
    raise exception 'This isolated test route is restricted to the approved Finance test identity';
  end if;

  select u.email, u.email_confirmed_at
    into v_email, v_confirmed_at
  from auth.users u
  where u.id = p_user_id;

  if not found or lower(v_email) <> 'onajite1968@gmail.com' or v_confirmed_at is null then
    raise exception 'Approved Finance test identity is missing, unconfirmed, or does not match';
  end if;

  if exists (
    select 1 from public.admin_accounts a
    where a.user_id = p_user_id and a.role = 'super_admin'
  ) then
    raise exception 'Protected Super Administrator identity cannot receive test access';
  end if;

  select p.is_active, p.role into v_profile_active, v_profile_role
  from public.profiles p where p.id = p_user_id;

  if not found then
    insert into public.profiles(id, role, is_active)
    values (p_user_id, 'customer', true);
  elsif v_profile_active is not true or v_profile_role <> 'customer' then
    raise exception 'Existing profile is not in the expected safe customer state';
  end if;

  insert into public.isolated_test_admin_grants(user_id, role, granted_by, granted_at, revoked_at, is_active)
  values (p_user_id, 'finance_admin', auth.uid(), now(), null, true)
  on conflict (user_id) do update
    set role = 'finance_admin',
        granted_by = excluded.granted_by,
        granted_at = now(),
        revoked_at = null,
        is_active = true;

  insert into public.admin_activity_log(actor_user_id, action, target_user_id, details)
  values (
    auth.uid(),
    'isolated_test_finance_access_granted',
    p_user_id,
    jsonb_build_object(
      'environment', 'isolated_test',
      'role', 'finance_admin',
      'provisioning_type', 'temporary_test_access',
      'employee_record_created', false,
      'departmental_appointment_created', false,
      'appointment_hold_changed', false
    )
  );

  return true;
end;
$$;

create or replace function public.admin_revoke_isolated_test_finance_access(p_user_id uuid)
returns boolean
language plpgsql
security definer
set search_path to ''
as $$
begin
  if auth.uid() is null or not public.is_super_admin() then
    raise exception 'Super Administrator access required';
  end if;

  if p_user_id <> '55ef7cb8-6c06-481a-be21-22f4f98c0d6a'::uuid then
    raise exception 'This isolated test route is restricted to the approved Finance test identity';
  end if;

  update public.isolated_test_admin_grants
  set is_active = false, revoked_at = now()
  where user_id = p_user_id and is_active = true;

  if found then
    insert into public.admin_activity_log(actor_user_id, action, target_user_id, details)
    values (
      auth.uid(),
      'isolated_test_finance_access_revoked',
      p_user_id,
      jsonb_build_object('environment', 'isolated_test', 'role', 'finance_admin')
    );
  end if;

  return true;
end;
$$;

create or replace function public.admin_get_my_role()
returns text
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_role text;
  v_profile_active boolean;
begin
  if auth.uid() is null then return null; end if;

  select p.is_active into v_profile_active
  from public.profiles p where p.id = auth.uid();

  if not found or v_profile_active is not true then return null; end if;

  select a.role into v_role
  from public.admin_accounts a
  where a.user_id = auth.uid() and a.is_active is true;

  if found then
    if v_role = 'super_admin' then
      if public.is_super_admin() then return 'super_admin'; end if;
      return null;
    end if;
    if v_role in ('operations_admin','supplier_admin','finance_admin','catalogue_admin') then
      return v_role;
    end if;
  end if;

  select g.role into v_role
  from public.isolated_test_admin_grants g
  where g.user_id = auth.uid() and g.is_active is true and g.revoked_at is null;

  if found then return v_role; end if;
  return null;
end;
$$;

create or replace function public.admin_has_permission(required_permission text)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select
    exists (
      select 1
      from public.admin_accounts a
      join public.profiles p on p.id = a.user_id
      left join public.admin_role_permissions rp
        on rp.role = a.role and rp.permission = required_permission
      where a.user_id = auth.uid()
        and a.is_active is true
        and p.is_active is true
        and (a.role = 'super_admin' or rp.permission is not null)
    )
    or exists (
      select 1
      from public.isolated_test_admin_grants g
      join public.profiles p on p.id = g.user_id
      join public.admin_role_permissions rp
        on rp.role = g.role and rp.permission = required_permission
      where g.user_id = auth.uid()
        and g.is_active is true
        and g.revoked_at is null
        and p.is_active is true
    );
$$;

revoke all on function public.admin_grant_isolated_test_finance_access(uuid) from public, anon;
revoke all on function public.admin_revoke_isolated_test_finance_access(uuid) from public, anon;
grant execute on function public.admin_grant_isolated_test_finance_access(uuid) to authenticated;
grant execute on function public.admin_revoke_isolated_test_finance_access(uuid) to authenticated;
