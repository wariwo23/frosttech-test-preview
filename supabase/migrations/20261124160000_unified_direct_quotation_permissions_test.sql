-- Unified direct quotation permission enforcement.
-- Applied only to isolated test project gqnidjifiobhqhnxjlow on 2026-11-24.
-- Production must receive a separately reviewed migration and approval.

create or replace function public.frosttech_admin_actor_has_permission(
  p_actor uuid,
  p_permission text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select
    p_actor is not null
    and nullif(btrim(coalesce(p_permission, '')), '') is not null
    and exists (
      select 1 from public.profiles p
      where p.id = p_actor and p.is_active is true
    )
    and (
      exists (
        select 1 from public.admin_accounts a
        where a.user_id = p_actor and a.is_active is true
          and (
            a.role = 'super_admin'
            or exists (
              select 1 from public.admin_role_permissions rp
              where rp.role = a.role and rp.permission = p_permission
            )
          )
      )
      or exists (
        select 1 from public.isolated_test_admin_grants g
        where g.user_id = p_actor and g.is_active is true
          and g.revoked_at is null
          and exists (
            select 1 from public.admin_role_permissions rp
            where rp.role = g.role and rp.permission = p_permission
          )
      )
    );
$function$;

revoke all on function public.frosttech_admin_actor_has_permission(uuid, text)
  from public, anon, authenticated;
grant execute on function public.frosttech_admin_actor_has_permission(uuid, text)
  to service_role;

-- These four RPCs are service_role-only. Their trusted Edge Function callers
-- validate the bearer session and pass the verified auth user ID as p_actor.
-- This helper independently checks that actor's active profile and permission.
do $migration$
declare
  v_signature text;
  v_definition text;
  v_start integer;
  v_select_end integer;
  v_check_start integer;
  v_check_end integer;
  v_marker text := 'if v_role is null then';
  v_replacement text;
begin
  foreach v_signature in array array[
    'public.frosttech_create_direct_quotation_draft(jsonb,jsonb,uuid)',
    'public.frosttech_update_direct_quotation_draft(uuid,jsonb,jsonb,uuid)',
    'public.frosttech_issue_direct_quotation(uuid,uuid,text,timestamp with time zone)',
    'public.frosttech_confirm_direct_quote_bank_payment(uuid,uuid,text,text)'
  ]
  loop
    v_definition := pg_get_functiondef(v_signature::regprocedure);
    v_definition := replace(v_definition, 'v_role text;', '');
    v_start := strpos(v_definition, 'select a.role into v_role');
    v_select_end := case when v_start > 0
      then strpos(substring(v_definition from v_start), ';') + v_start - 1
      else 0 end;
    v_check_start := case when v_select_end > 0
      then strpos(substring(v_definition from v_select_end + 1), v_marker) + v_select_end
      else 0 end;
    v_check_end := case when v_check_start > v_select_end
      then strpos(substring(v_definition from v_check_start), 'end if;') + v_check_start + length('end if;') - 1
      else 0 end;

    if v_start = 0 or v_select_end = 0 or v_check_start = 0 or v_check_end < v_check_start then
      raise exception 'Could not safely identify the existing administrator guard in %', v_signature;
    end if;

    if v_signature like '%confirm_direct_quote_bank_payment%' then
      v_replacement := 'if not public.frosttech_admin_actor_has_permission(p_actor, ''payments.verify'') then raise exception ''Payment verification permission is required''; end if;';
    else
      v_replacement := 'if not public.frosttech_admin_actor_has_permission(p_actor, ''quotations.read_operational'') then raise exception ''Operational quotation permission is required''; end if;';
    end if;

    v_definition :=
      left(v_definition, v_start - 1)
      || v_replacement
      || substring(v_definition from v_check_end + 1);

    execute v_definition;
  end loop;
end;
$migration$;

create or replace function public.frosttech_admin_count_direct_quotations()
returns bigint
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.admin_has_permission('quotations.read_operational') then
    raise exception 'Operational quotation permission is required';
  end if;
  return (select count(*)::bigint from public.frosttech_direct_quotations);
end;
$function$;
