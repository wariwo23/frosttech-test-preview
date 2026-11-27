-- PRODUCTION RELEASE CANDIDATE ONLY — NOT APPLIED.
-- FrostTech Operations authorization compatibility and request-list redaction.
-- Requires independent backup, schema/role preflight, and release approval.
-- This migration preserves the existing quotation business logic verbatim and
-- changes only the authorization predicate in the three existing RPCs.

begin;

do $preflight$
declare
  v_name text;
  v_def text;
  v_old text := 'public.is_admin()';
  v_new text := 'public.admin_has_permission(''quotations.manage_operational'')';
  v_count integer;
begin
  if to_regprocedure('public.admin_has_permission(text)') is null
     or to_regprocedure('public.is_admin()') is null
     or to_regclass('public.admin_role_permissions') is null
     or to_regclass('public.quote_requests') is null
     or to_regclass('public.admin_quotations') is null
     or to_regclass('public.admin_quotation_items') is null
     or to_regclass('public.admin_quotation_pricing_snapshots') is null
     or to_regclass('public.alternative_proposal_decisions') is null
     or to_regclass('public.alternative_proposals') is null
     or to_regclass('public.quote_request_original_snapshots') is null then
    raise exception 'Preflight failed: required production Operations dependencies are missing';
  end if;

  foreach v_name in array array[
    'admin_create_direct_quotation_revision_v2(uuid)',
    'admin_replace_direct_quotation_items_v2(uuid,jsonb)',
    'admin_submit_direct_quotation(uuid)'
  ] loop
    if to_regprocedure('public.'||v_name) is null then
      raise exception 'Preflight failed: required existing function % is missing',v_name;
    end if;
    select pg_get_functiondef(to_regprocedure('public.'||v_name)) into v_def;
    v_count := (length(v_def)-length(replace(v_def,v_old,v_old)))/greatest(length(v_old),1);
    if position(v_old in v_def)=0 then
      raise exception 'Preflight failed: expected legacy authorization predicate not found in %',v_name;
    end if;
    if position(v_new in v_def)>0 then
      raise exception 'Preflight failed: % appears already migrated; inspect before retry',v_name;
    end if;
  end loop;

  if not exists (
    select 1 from public.admin_role_permissions
    where role='operations_admin' and permission='customer_requests.manage'
  ) then
    raise exception 'Preflight failed: Operations customer-request permission mapping missing';
  end if;
end;
$preflight$;

-- Preserve all existing function bodies, revision/version checks, private pricing
-- snapshot copying, item validation, accepted-alternative checks and fee logic.
do $authorize$
declare
  v_signature text;
  v_definition text;
  v_old text := 'public.is_admin()';
  v_new text := 'public.admin_has_permission(''quotations.manage_operational'')';
begin
  foreach v_signature in array array[
    'public.admin_create_direct_quotation_revision_v2(uuid)',
    'public.admin_replace_direct_quotation_items_v2(uuid,jsonb)',
    'public.admin_submit_direct_quotation(uuid)'
  ] loop
    select pg_get_functiondef(to_regprocedure(v_signature)) into v_definition;
    if position(v_old in v_definition)=0 then
      raise exception 'Authorization replacement aborted: expected predicate absent in %',v_signature;
    end if;
    v_definition := replace(v_definition,v_old,v_new);
    execute v_definition;
  end loop;
end;
$authorize$;

-- Operations must never receive Finance-only consultation-fee amount/status/
-- transaction-reference/paid timestamp from the request listing.
do $redact$
declare
  v_definition text;
  v_old text := 'jsonb_agg(to_jsonb(q) ORDER BY q.created_at DESC)';
  v_new text := 'jsonb_agg((to_jsonb(q) - ARRAY[''admin_fee'',''admin_fee_status'',''admin_fee_transaction_reference'',''admin_fee_paid_at'']::text[]) ORDER BY q.created_at DESC)';
begin
  select pg_get_functiondef('public.ops_list_customer_requests()'::regprocedure)
  into v_definition;
  if position(v_old in v_definition)=0 then
    raise exception 'Redaction preflight failed: exact production request-list aggregation differs; inspect and adapt rather than continue';
  end if;
  v_definition := replace(v_definition,v_old,v_new);
  v_definition := replace(v_definition,'SET search_path TO ''public'', ''pg_temp''','SET search_path TO ''''');
  execute v_definition;
end;
$redact$;

-- Add only the missing Operations quotation permission. Do not alter other roles.
insert into public.admin_role_permissions(role,permission)
select 'operations_admin','quotations.manage_operational'
where not exists (
  select 1 from public.admin_role_permissions
  where role='operations_admin' and permission='quotations.manage_operational'
);

commit;
