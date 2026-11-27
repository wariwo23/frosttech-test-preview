begin;
alter table public.admin_accounts drop constraint admin_accounts_role_check;
alter table public.admin_accounts add constraint admin_accounts_role_check check (role = any (array['super_admin','operations_admin','supplier_admin','finance_admin','catalogue_admin','advertisers_admin']::text[]));
alter table public.admin_role_permissions drop constraint admin_role_permissions_role_check;
alter table public.admin_role_permissions add constraint admin_role_permissions_role_check check (role = any (array['super_admin','operations_admin','supplier_admin','finance_admin','catalogue_admin','advertisers_admin']::text[]));
alter table public.frosttech_employees drop constraint frosttech_employees_department_check;
alter table public.frosttech_employees add constraint frosttech_employees_department_check check (department = any (array['operations','supplier_management','finance','catalogue','advertisers_communications']::text[]));
create or replace function public.admin_get_my_role()
returns text language plpgsql stable security definer set search_path to ''
as $function$
declare v_role text; v_profile_active boolean;
begin
 if auth.uid() is null then return null; end if;
 select p.is_active into v_profile_active from public.profiles p where p.id=auth.uid();
 if not found or v_profile_active is not true then return null; end if;
 select a.role into v_role from public.admin_accounts a where a.user_id=auth.uid() and a.is_active is true;
 if found then
  if v_role='super_admin' then if public.is_super_admin() then return 'super_admin'; end if; return null; end if;
  if v_role in ('operations_admin','supplier_admin','finance_admin','catalogue_admin','advertisers_admin') then return v_role; end if;
 end if;
 select g.role into v_role from public.isolated_test_admin_grants g where g.user_id=auth.uid() and g.is_active is true and g.revoked_at is null;
 if found then return v_role; end if;
 return null;
end;
$function$;
create or replace function public.admin_appoint_departmental_admin(p_user_id uuid,p_role text)
returns boolean language plpgsql security definer set search_path to ''
as $function$
declare v_employee record; v_expected_role text;
begin
 if auth.uid() is null or not public.is_super_admin() then raise exception 'Super Administrator access required'; end if;
 if public.frosttech_departmental_appointments_on_hold() then raise exception 'Departmental administrator appointments are on hold until FrostTech officially launches'; end if;
 select e.id,e.full_name,e.email,e.department,e.employment_status,e.account_setup_completed_at,e.auth_user_id,u.email_confirmed_at,u.raw_app_meta_data ->> 'frosttech_account_type' as account_type,p.role as profile_role,p.is_active as profile_active
 into v_employee from public.frosttech_employees e join auth.users u on u.id=e.auth_user_id join public.profiles p on p.id=e.auth_user_id where e.auth_user_id=p_user_id for update of e;
 if not found then raise exception 'This account is not linked to a FrostTech employee'; end if;
 if v_employee.employment_status <> 'active' or v_employee.account_setup_completed_at is null or v_employee.email_confirmed_at is null or v_employee.account_type <> 'employee' or v_employee.profile_role <> 'employee' or v_employee.profile_active is not true then raise exception 'Employee account is not eligible for appointment'; end if;
 v_expected_role:=case v_employee.department when 'operations' then 'operations_admin' when 'supplier_management' then 'supplier_admin' when 'finance' then 'finance_admin' when 'catalogue' then 'catalogue_admin' when 'advertisers_communications' then 'advertisers_admin' else null end;
 if v_expected_role is null or p_role <> v_expected_role then raise exception 'The administrator role does not match the employee department'; end if;
 if exists(select 1 from public.admin_accounts where user_id=p_user_id and role='super_admin') then raise exception 'The Super Administrator account is protected'; end if;
 update public.admin_accounts set role=p_role,is_active=true,appointed_by=auth.uid(),appointed_at=now(),updated_at=now() where user_id=p_user_id;
 if not found then insert into public.admin_accounts(user_id,role,is_active,appointed_by,appointed_at,updated_at) values(p_user_id,p_role,true,auth.uid(),now(),now()); end if;
 insert into public.admin_activity_log(actor_user_id,action,target_user_id,details) values(auth.uid(),'departmental_admin_appointed',p_user_id,jsonb_build_object('employee_id',v_employee.id,'employee_email',v_employee.email,'department',v_employee.department,'role',p_role));
 return true;
end;
$function$;
commit;