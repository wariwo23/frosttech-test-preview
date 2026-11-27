-- Serialize quote decisions on the parent customer request before locking quote rows.
-- This avoids opposite-order row locks when two administrators decide on offers concurrently.
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

  select sq.request_id into v_request_id
  from public.supplier_quotes as sq where sq.id = p_quote_id;
  if not found then raise exception 'Supplier quotation was not found.'; end if;
  if v_request_id is null then
    raise exception 'This quotation is not linked to a customer request and cannot be selected.';
  end if;

  perform qr.id from public.quote_requests as qr
  where qr.id = v_request_id for update;
  if not found then raise exception 'The linked customer request was not found.'; end if;

  perform sq.id from public.supplier_quotes as sq
  where sq.request_id = v_request_id order by sq.id for update;

  select sq.status into v_status
  from public.supplier_quotes as sq where sq.id = p_quote_id;
  if v_status <> 'submitted' then
    raise exception 'Only a submitted supplier quotation can be selected.';
  end if;

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

  select sq.request_id into v_request_id
  from public.supplier_quotes as sq where sq.id = p_quote_id;
  if not found then raise exception 'Supplier quotation was not found.'; end if;

  if v_request_id is not null then
    perform qr.id from public.quote_requests as qr
    where qr.id = v_request_id for update;
    if not found then raise exception 'The linked customer request was not found.'; end if;
    perform sq.id from public.supplier_quotes as sq
    where sq.request_id = v_request_id order by sq.id for update;
  else
    perform sq.id from public.supplier_quotes as sq
    where sq.id = p_quote_id for update;
  end if;

  select sq.status into v_status
  from public.supplier_quotes as sq where sq.id = p_quote_id;
  if v_status <> 'submitted' then
    raise exception 'Only a submitted supplier quotation can be rejected.';
  end if;

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

revoke all on function public.admin_select_supplier_quote(uuid) from public, anon;
revoke all on function public.admin_reject_supplier_quote(uuid) from public, anon;
grant execute on function public.admin_select_supplier_quote(uuid) to authenticated;
grant execute on function public.admin_reject_supplier_quote(uuid) to authenticated;
