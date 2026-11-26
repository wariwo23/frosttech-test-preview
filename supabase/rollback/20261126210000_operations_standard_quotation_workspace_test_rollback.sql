-- Emergency rollback: FrostTech Operations standard quotation workspace (isolated test only).
-- Restores the prior Operations request-list RPC definition and removes only
-- the permission and functions introduced by this workspace migration.

drop function if exists public.ops_submit_standard_quotation_v1(uuid);
drop function if exists public.ops_save_standard_quotation_draft_v1(uuid,uuid,text,integer,numeric,numeric,numeric,numeric,date,text,jsonb);
drop function if exists public.ops_get_standard_quotation_draft_v1(uuid);

create or replace function public.ops_list_customer_requests()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  result jsonb;
begin
  if auth.uid() is null
     or not public.admin_has_permission('customer_requests.manage') then
    raise exception 'Access denied';
  end if;

  select coalesce(
    jsonb_agg(to_jsonb(q) order by q.created_at desc),
    '[]'::jsonb
  )
  into result
  from (
    select *
    from public.quote_requests
    order by created_at desc
    limit 500
  ) q;

  return result;
end;
$function$;

revoke all on function public.ops_list_customer_requests() from public,anon;
grant execute on function public.ops_list_customer_requests() to authenticated;

delete from public.admin_role_permissions
where role='operations_admin'
  and permission='quotations.manage_operational';
