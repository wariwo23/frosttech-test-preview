-- FrostTech isolated test environment only.
-- Supplier quotation review functions with explicit field allow-list and permission checks.

create or replace function public.admin_list_supplier_quotes()
returns table (
  id uuid,
  request_id uuid,
  request_number text,
  request_title text,
  request_quantity integer,
  supplier_id uuid,
  supplier_name text,
  product_id uuid,
  product_name text,
  quantity integer,
  supplier_unit_price numeric,
  supplier_total numeric,
  delivery_cost numeric,
  notes text,
  valid_until timestamptz,
  status text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null
     or not coalesce(public.admin_has_permission('supplier_quotes.manage'), false) then
    raise exception 'Access denied: supplier quotation permission is required.'
      using errcode = '42501';
  end if;

  return query
  select sq.id, sq.request_id, qr.request_number, qr.title, qr.quantity,
         sq.supplier_id, s.business_name, sq.product_id, p.name,
         sq.quantity, sq.supplier_unit_price, sq.supplier_total,
         sq.delivery_cost, sq.notes, sq.valid_until, sq.status,
         sq.created_at, sq.updated_at
  from public.supplier_quotes as sq
  left join public.quote_requests as qr on qr.id = sq.request_id
  left join public.suppliers as s on s.id = sq.supplier_id
  left join public.products as p on p.id = sq.product_id
  order by sq.created_at desc, sq.id;
end;
$function$;

create or replace function public.admin_select_supplier_quote(p_quote_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_request_id uuid;
  v_status text;
  v_rejected_count integer := 0;
begin
  if auth.uid() is null
     or not coalesce(public.admin_has_permission('supplier_quotes.manage'), false) then
    raise exception 'Access denied: supplier quotation permission is required.'
      using errcode = '42501';
  end if;
  if p_quote_id is null then raise exception 'A supplier quotation ID is required.'; end if;

  select sq.request_id, sq.status into v_request_id, v_status
  from public.supplier_quotes as sq where sq.id = p_quote_id for update;
  if not found then raise exception 'Supplier quotation was not found.'; end if;
  if v_request_id is null then
    raise exception 'This quotation is not linked to a customer request and cannot be selected.';
  end if;
  if v_status <> 'submitted' then raise exception 'Only a submitted supplier quotation can be selected.'; end if;

  perform sq.id from public.supplier_quotes as sq
  where sq.request_id = v_request_id order by sq.id for update;

  if exists (
    select 1 from public.supplier_quotes as sq
    where sq.request_id = v_request_id and sq.status = 'selected' and sq.id <> p_quote_id
  ) then
    raise exception 'Another supplier quotation is already selected for this request. Super Administrator review is required before replacing it.';
  end if;

  update public.supplier_quotes as sq
  set status = 'rejected', updated_at = pg_catalog.now()
  where sq.request_id = v_request_id and sq.id <> p_quote_id and sq.status = 'submitted';
  get diagnostics v_rejected_count = row_count;

  update public.supplier_quotes as sq
  set status = 'selected', customer_quote_status = 'draft', updated_at = pg_catalog.now()
  where sq.id = p_quote_id and sq.status = 'submitted';
  if not found then
    raise exception 'The quotation status changed before selection could be completed. Refresh and review again.';
  end if;

  insert into public.admin_activity_log (actor_user_id, action, details)
  values (auth.uid(), 'supplier_quote_selected',
    pg_catalog.jsonb_build_object('quote_id', p_quote_id, 'request_id', v_request_id,
      'other_submitted_quotes_rejected', v_rejected_count, 'environment', 'isolated_test'));

  return pg_catalog.jsonb_build_object('success', true, 'quote_id', p_quote_id,
    'request_id', v_request_id, 'other_submitted_quotes_rejected', v_rejected_count);
end;
$function$;

create or replace function public.admin_reject_supplier_quote(p_quote_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_request_id uuid;
  v_status text;
begin
  if auth.uid() is null
     or not coalesce(public.admin_has_permission('supplier_quotes.manage'), false) then
    raise exception 'Access denied: supplier quotation permission is required.'
      using errcode = '42501';
  end if;
  if p_quote_id is null then raise exception 'A supplier quotation ID is required.'; end if;

  select sq.request_id, sq.status into v_request_id, v_status
  from public.supplier_quotes as sq where sq.id = p_quote_id for update;
  if not found then raise exception 'Supplier quotation was not found.'; end if;
  if v_status <> 'submitted' then raise exception 'Only a submitted supplier quotation can be rejected.'; end if;

  update public.supplier_quotes as sq
  set status = 'rejected', updated_at = pg_catalog.now()
  where sq.id = p_quote_id and sq.status = 'submitted';
  if not found then
    raise exception 'The quotation status changed before rejection could be completed. Refresh and review again.';
  end if;

  insert into public.admin_activity_log (actor_user_id, action, details)
  values (auth.uid(), 'supplier_quote_rejected',
    pg_catalog.jsonb_build_object('quote_id', p_quote_id, 'request_id', v_request_id,
      'environment', 'isolated_test'));

  return pg_catalog.jsonb_build_object('success', true, 'quote_id', p_quote_id, 'request_id', v_request_id);
end;
$function$;

revoke all on function public.admin_list_supplier_quotes() from public, anon;
revoke all on function public.admin_select_supplier_quote(uuid) from public, anon;
revoke all on function public.admin_reject_supplier_quote(uuid) from public, anon;
grant execute on function public.admin_list_supplier_quotes() to authenticated;
grant execute on function public.admin_select_supplier_quote(uuid) to authenticated;
grant execute on function public.admin_reject_supplier_quote(uuid) to authenticated;
