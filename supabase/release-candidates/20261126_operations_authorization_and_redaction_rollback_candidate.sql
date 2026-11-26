-- PRODUCTION ROLLBACK CANDIDATE ONLY — NOT APPLIED.
-- Reverts only the three authorization predicates and removes the added
-- Operations permission. It deliberately retains Finance-field redaction.
begin;

do $rollback$
declare
  v_signature text;
  v_definition text;
  v_new text := 'public.admin_has_permission(''quotations.manage_operational'')';
  v_old text := 'public.is_admin()';
begin
  foreach v_signature in array array[
    'public.admin_create_direct_quotation_revision_v2(uuid)',
    'public.admin_replace_direct_quotation_items_v2(uuid,jsonb)',
    'public.admin_submit_direct_quotation(uuid)'
  ] loop
    if to_regprocedure(v_signature) is null then
      raise exception 'Rollback stopped: required function % missing',v_signature;
    end if;
    select pg_get_functiondef(to_regprocedure(v_signature)) into v_definition;
    if position(v_new in v_definition)=0 then
      raise exception 'Rollback stopped: expected migrated predicate absent in %',v_signature;
    end if;
    execute replace(v_definition,v_new,v_old);
  end loop;
end;
$rollback$;

delete from public.admin_role_permissions
where role='operations_admin'
  and permission='quotations.manage_operational';

commit;
