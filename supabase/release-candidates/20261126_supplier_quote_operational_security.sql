-- SUPPLIER & CATALOGUE SECURITY — PRODUCTION RELEASE CANDIDATE ONLY.
-- NOT APPLIED TO TEST OR PRODUCTION.
-- Preserves legacy full-row supplier quote reader for Super Admin only.
-- Adds a non-financial operational projection for departmental review.
-- Makes final supplier quote selection Super Admin-only.

begin;

do $preflight$
begin
  if to_regclass('public.supplier_quotes') is null
     or to_regclass('public.admin_role_permissions') is null
     or to_regprocedure('public.admin_has_permission(text)') is null
     or to_regprocedure('public.is_super_admin()') is null
     or to_regprocedure('public.admin_list_supplier_quotes()') is null
     or to_regprocedure('public.admin_select_supplier_quote(uuid)') is null
     or to_regprocedure('public.admin_reject_supplier_quote(uuid)') is null then
    raise exception 'Supplier security preflight failed: expected production dependencies are missing';
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='supplier_quotes'
      and column_name='supplier_unit_price'
  ) or not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='supplier_quotes'
      and column_name='customer_total'
  ) then
    raise exception 'Supplier quote schema differs from audited production schema';
  end if;
end;
$preflight$;

-- New operational list: no supplier prices, supplier totals, delivery cost,
-- margin, customer total or other financial quotation values.
create or replace function public.admin_list_supplier_quotes_operational()
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_result jsonb;
begin
  if auth.uid() is null
     or not public.admin_has_permission('supplier_quotes.review_operational') then
    raise exception 'Supplier quotation review permission required';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',sq.id,
        'request_id',sq.request_id,
        'supplier_id',sq.supplier_id,
        'product_id',sq.product_id,
        'quantity',sq.quantity,
        'notes',sq.notes,
        'valid_until',sq.valid_until,
        'status',sq.status,
        'created_at',sq.created_at,
        'updated_at',sq.updated_at
      ) order by sq.created_at desc
    ),
    '[]'::jsonb
  )
  into v_result
  from public.supplier_quotes sq;

  return v_result;
end;
$function$;

-- Keep the legacy full-row API contract but reserve it for Super Admin.
create or replace function public.admin_list_supplier_quotes()
returns setof public.supplier_quotes
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if auth.uid() is null or not public.is_super_admin() then
    raise exception 'Super Administrator access required';
  end if;

  return query
  select sq.*
  from public.supplier_quotes sq
  order by sq.created_at desc;
end;
$function$;

-- Selecting a quote rejects competing offers and therefore constitutes final
-- supplier selection. Reserve it for Super Admin.
create or replace function public.admin_select_supplier_quote(p_quote_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
    v_request_id uuid;
    v_status text;
begin
    if auth.uid() is null or not public.is_super_admin() then
        raise exception 'Super Administrator access required';
    end if;

    select request_id, status
    into v_request_id, v_status
    from public.supplier_quotes
    where id = p_quote_id
    for update;

    if not found then
        raise exception 'Supplier quotation not found';
    end if;

    if v_status <> 'submitted' then
        raise exception 'Only a submitted supplier quotation can be selected.';
    end if;

    perform id
    from public.supplier_quotes
    where request_id = v_request_id
    order by id
    for update;

    select status into v_status
    from public.supplier_quotes
    where id = p_quote_id;

    if v_status <> 'submitted' then
        raise exception 'This supplier quotation has already been reviewed.';
    end if;

    update public.supplier_quotes
    set status = 'rejected', updated_at = now()
    where request_id = v_request_id
      and id <> p_quote_id
      and status = 'submitted';

    update public.supplier_quotes
    set status = 'selected',
        customer_quote_status = 'draft',
        updated_at = now()
    where id = p_quote_id;

    insert into public.admin_activity_log(actor_user_id,action,details)
    values(auth.uid(),'supplier_quote_selected',
      jsonb_build_object('quote_id',p_quote_id,'request_id',v_request_id));
end;
$function$;

-- Departmental reviewer may reject a submitted quote, but cannot select the
-- winning supplier or access its financial fields through the operational API.
create or replace function public.admin_reject_supplier_quote(p_quote_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
    v_status text;
begin
    if auth.uid() is null
       or not public.admin_has_permission('supplier_quotes.review_operational') then
        raise exception 'Supplier quotation review permission required';
    end if;

    select status into v_status
    from public.supplier_quotes
    where id = p_quote_id
    for update;

    if not found then
        raise exception 'Supplier quotation not found';
    end if;

    if v_status <> 'submitted' then
        raise exception 'Only a submitted supplier quotation can be rejected.';
    end if;

    update public.supplier_quotes
    set status='rejected',updated_at=now()
    where id=p_quote_id;

    insert into public.admin_activity_log(actor_user_id,action,details)
    values(auth.uid(),'supplier_quote_rejected',
      jsonb_build_object('quote_id',p_quote_id));
end;
$function$;

insert into public.admin_role_permissions(role,permission)
select 'supplier_admin','supplier_quotes.review_operational'
where not exists (
  select 1 from public.admin_role_permissions
  where role='supplier_admin' and permission='supplier_quotes.review_operational'
);

-- The old broad permission is no longer required for departmental review.
delete from public.admin_role_permissions
where role='supplier_admin' and permission='supplier_quotes.manage';

revoke all on function public.admin_list_supplier_quotes_operational() from public,anon;
grant execute on function public.admin_list_supplier_quotes_operational() to authenticated;

commit;
