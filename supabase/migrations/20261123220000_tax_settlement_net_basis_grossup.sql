begin;

alter table public.frosttech_supplier_settlements
  drop constraint if exists frosttech_settlement_wht_basis_ck;
alter table public.frosttech_supplier_settlements
  add constraint frosttech_settlement_wht_basis_ck
  check (coalesce(tax_rule_snapshot->>'calculation_basis' in
    ('taxable_base','gross_amount','net_amount'),false));

create or replace function public.frosttech_prepare_supplier_settlement(
  p_supplier_id uuid,p_order_item_ids uuid[]
)
returns uuid language plpgsql security definer set search_path=''
as $function$
declare
  v_actor uuid:=auth.uid();
  v_supplier public.suppliers%rowtype;
  v_profile public.frosttech_supplier_tax_profiles%rowtype;
  v_rule public.frosttech_tax_rules%rowtype;
  v_item_total numeric(14,2);
  v_wht_base numeric(14,2);
  v_wht numeric(14,2);
  v_gross_entitlement numeric(14,2);
  v_net_payable numeric(14,2);
  v_settlement_id uuid;
  v_count integer;
begin
  if v_actor is null or not public.admin_has_permission('supplier_settlements.prepare') then
    raise exception 'Finance settlement preparation permission is required';
  end if;
  if p_supplier_id is null or p_order_item_ids is null or cardinality(p_order_item_ids)=0
     or array_position(p_order_item_ids,null) is not null or cardinality(p_order_item_ids)>200 then
    raise exception 'Select between 1 and 200 valid order items';
  end if;
  if cardinality(p_order_item_ids)<>(select count(distinct x) from unnest(p_order_item_ids) as x) then
    raise exception 'Duplicate order items are not permitted';
  end if;

  select * into v_supplier from public.suppliers
  where id=p_supplier_id and is_active is true and is_verified is true and review_status='approved'
  for update;
  if not found then raise exception 'Supplier must be active, verified and approved'; end if;

  select * into v_profile from public.frosttech_supplier_tax_profiles
  where supplier_id=p_supplier_id and verification_status='verified'
  for update;
  if not found then raise exception 'Supplier tax profile must be verified before settlement preparation'; end if;

  perform 1
  from public.order_items oi
  join public.orders o on o.id=oi.order_id
  join public.products p on p.id=oi.product_id
  join public.frosttech_order_item_supplier_assignments a on a.order_item_id=oi.id
  where oi.id=any(p_order_item_ids) and a.order_id=o.id
    and a.supplier_id=p_supplier_id and a.status='confirmed' and a.supplier_unit_cost>0
    and o.status in ('paid','processing','ready_for_delivery','out_for_delivery','delivered','completed')
    and lower(trim(p.category)) in ('air conditioners','refrigeration parts','hvac accessories')
  for update of oi,o,a;
  get diagnostics v_count=row_count;
  if v_count<>cardinality(p_order_item_ids) then
    raise exception 'Every item must have a confirmed matching supplier assignment, an eligible paid order and a verifiable catalogue product category';
  end if;

  select round(sum(oi.quantity*a.supplier_unit_cost),2) into v_item_total
  from public.order_items oi
  join public.frosttech_order_item_supplier_assignments a on a.order_item_id=oi.id
  where oi.id=any(p_order_item_ids) and a.supplier_id=p_supplier_id and a.status='confirmed';
  if v_item_total is null or v_item_total<=0 then raise exception 'Supplier entitlement could not be calculated'; end if;

  select * into v_rule from public.frosttech_tax_rules
  where tax_type='WHT' and direction in ('outbound','both')
    and transaction_category='supplier_settlement'
    and tax_classification=v_profile.tax_classification
    and entity_type in (v_profile.entity_type,'any')
    and residency_status in (v_profile.residency_status,'any')
    and is_active is true and effective_from<=now()
    and (effective_until is null or effective_until>now())
  order by (entity_type=v_profile.entity_type) desc,
           (residency_status=v_profile.residency_status) desc,effective_from desc
  limit 1 for share;
  if not found then
    raise exception 'No effective WHT rule matches this verified supplier classification, entity type and residency status';
  end if;

  v_wht_base:=v_item_total;
  if v_rule.calculation_basis='net_amount' then
    if v_rule.rate>=100 then raise exception 'Net-basis WHT rate must be below 100 percent'; end if;
    v_wht:=round(v_wht_base*v_rule.rate/(100-v_rule.rate),2);
    v_gross_entitlement:=round(v_wht_base+v_wht,2);
    v_net_payable:=v_wht_base;
  else
    v_wht:=round(v_wht_base*v_rule.rate/100,2);
    v_gross_entitlement:=v_item_total;
    v_net_payable:=round(v_gross_entitlement-v_wht,2);
  end if;

  insert into public.frosttech_supplier_settlements(
    supplier_id,currency,gross_entitlement,wht_base,wht_rate,wht_amount,
    net_payable,tax_rule_snapshot,status,prepared_by,prepared_at
  ) values (
    p_supplier_id,'NGN',v_gross_entitlement,v_wht_base,v_rule.rate,v_wht,
    v_net_payable,
    jsonb_build_object('tax_rule_id',v_rule.id,'tax_type',v_rule.tax_type,
      'direction',v_rule.direction,'transaction_category',v_rule.transaction_category,
      'tax_classification',v_rule.tax_classification,'entity_type',v_rule.entity_type,
      'residency_status',v_rule.residency_status,'rate',v_rule.rate,
      'calculation_basis',v_rule.calculation_basis,'legal_reference',v_rule.legal_reference,
      'effective_from',v_rule.effective_from,'effective_until',v_rule.effective_until,
      'supplier_entity_type',v_profile.entity_type,
      'supplier_residency_status',v_profile.residency_status,
      'supplier_tax_classification',v_profile.tax_classification),
    'draft',v_actor,now()
  ) returning id into v_settlement_id;

  insert into public.frosttech_supplier_settlement_items(
    settlement_id,source_type,order_item_id,description,quantity,unit_cost,line_total,supplier_assignment_snapshot
  )
  select v_settlement_id,'order_item',oi.id,oi.product_name,oi.quantity,
    a.supplier_unit_cost,round(oi.quantity*a.supplier_unit_cost,2),
    jsonb_build_object('supplier_id',a.supplier_id,'supplier_unit_cost',a.supplier_unit_cost,
      'assignment_source',a.assignment_source,'source_record_id',a.source_record_id,
      'verified_by',a.verified_by,'verified_at',a.verified_at,
      'order_id',oi.order_id,'product_id',oi.product_id,'product_category',p.category)
  from public.order_items oi
  join public.products p on p.id=oi.product_id
  join public.frosttech_order_item_supplier_assignments a on a.order_item_id=oi.id
  where oi.id=any(p_order_item_ids) and a.supplier_id=p_supplier_id and a.status='confirmed';

  insert into public.admin_activity_log(actor_user_id,action,target_user_id,details)
  values(v_actor,'supplier_settlement_prepared',null,
    jsonb_build_object('settlement_id',v_settlement_id,'supplier_id',p_supplier_id,
      'order_item_ids',to_jsonb(p_order_item_ids),'item_net_or_gross_total',v_item_total,
      'gross_entitlement',v_gross_entitlement,'wht_rate',v_rule.rate,
      'wht_amount',v_wht,'net_payable',v_net_payable,
      'calculation_basis',v_rule.calculation_basis,'environment','isolated_test'));
  return v_settlement_id;
end;
$function$;

create or replace function public.frosttech_submit_supplier_settlement(p_settlement_id uuid)
returns uuid language plpgsql security definer set search_path=''
as $function$
declare
  v_actor uuid:=auth.uid();
  v_settlement public.frosttech_supplier_settlements%rowtype;
  v_supplier public.suppliers%rowtype;
  v_item_count integer;
  v_valid_count integer;
  v_items_total numeric(14,2);
  v_expected_items_total numeric(14,2);
  v_expected_wht numeric(14,2);
  v_basis text;
begin
  if v_actor is null or not public.admin_has_permission('supplier_settlements.prepare') then
    raise exception 'Finance settlement preparation permission is required';
  end if;
  if p_settlement_id is null then raise exception 'Settlement ID is required'; end if;
  select * into v_settlement from public.frosttech_supplier_settlements
  where id=p_settlement_id for update;
  if not found then raise exception 'Settlement not found'; end if;
  if v_settlement.status<>'draft' then raise exception 'Only draft settlements can be submitted'; end if;
  select * into v_supplier from public.suppliers
  where id=v_settlement.supplier_id and is_active is true
    and is_verified is true and review_status='approved' for update;
  if not found then raise exception 'Supplier is no longer eligible'; end if;

  select count(*),coalesce(sum(line_total),0) into v_item_count,v_items_total
  from public.frosttech_supplier_settlement_items where settlement_id=p_settlement_id;
  if v_item_count=0 then raise exception 'Settlement has no line items'; end if;

  select count(*) into v_valid_count
  from public.frosttech_supplier_settlement_items si
  join public.order_items oi on oi.id=si.order_item_id
  join public.orders o on o.id=oi.order_id
  join public.products p on p.id=oi.product_id
  join public.frosttech_order_item_supplier_assignments a on a.order_item_id=oi.id
  where si.settlement_id=p_settlement_id and si.source_type='order_item'
    and oi.order_id=a.order_id and a.supplier_id=v_settlement.supplier_id
    and a.status='confirmed' and a.supplier_unit_cost=si.unit_cost
    and si.quantity=oi.quantity and si.line_total=round(oi.quantity*a.supplier_unit_cost,2)
    and o.status in ('paid','processing','ready_for_delivery','out_for_delivery','delivered','completed')
    and lower(trim(p.category)) in ('air conditioners','refrigeration parts','hvac accessories');
  if v_valid_count<>v_item_count then
    raise exception 'One or more settlement lines no longer have a valid paid order and confirmed supplier assignment';
  end if;

  v_basis:=v_settlement.tax_rule_snapshot->>'calculation_basis';
  if v_basis='net_amount' then
    v_expected_items_total:=v_settlement.wht_base;
    if v_settlement.wht_rate>=100 then raise exception 'Net-basis WHT rate must be below 100 percent'; end if;
    v_expected_wht:=round(v_settlement.wht_base*v_settlement.wht_rate/(100-v_settlement.wht_rate),2);
  elsif v_basis in ('taxable_base','gross_amount') then
    v_expected_items_total:=v_settlement.gross_entitlement;
    v_expected_wht:=round(v_settlement.wht_base*v_settlement.wht_rate/100,2);
  else
    raise exception 'Settlement tax calculation basis is missing or unsupported';
  end if;
  if round(v_items_total,2)<>round(v_expected_items_total,2) then
    raise exception 'Settlement line totals do not match the verified tax calculation basis';
  end if;
  if v_settlement.wht_amount<>v_expected_wht
     or v_settlement.net_payable<>v_settlement.gross_entitlement-v_settlement.wht_amount then
    raise exception 'Settlement tax calculations failed validation';
  end if;

  if exists (
    select 1 from public.frosttech_supplier_settlement_items si
    join public.frosttech_supplier_settlements other on other.id<>p_settlement_id
    join public.frosttech_supplier_settlement_items oi
      on oi.settlement_id=other.id and oi.order_item_id=si.order_item_id
    where si.settlement_id=p_settlement_id
  ) then raise exception 'An order item is already claimed by another settlement'; end if;

  update public.frosttech_supplier_settlements
  set status='submitted',submitted_at=now(),updated_at=now() where id=p_settlement_id;
  insert into public.admin_activity_log(actor_user_id,action,target_user_id,details)
  values(v_actor,'supplier_settlement_submitted',null,
    jsonb_build_object('settlement_id',p_settlement_id,'settlement_number',v_settlement.settlement_number,
      'supplier_id',v_settlement.supplier_id,'gross_entitlement',v_settlement.gross_entitlement,
      'wht_amount',v_settlement.wht_amount,'net_payable',v_settlement.net_payable,
      'line_count',v_item_count,'calculation_basis',v_basis,'environment','isolated_test'));
  return p_settlement_id;
end;
$function$;

create or replace function public.frosttech_approve_supplier_settlement(p_settlement_id uuid)
returns uuid language plpgsql security definer set search_path=''
as $function$
declare
  v_actor uuid:=auth.uid();
  v_settlement public.frosttech_supplier_settlements%rowtype;
  v_preparer_active boolean;
  v_item_count integer;
  v_valid_count integer;
  v_items_total numeric(14,2);
  v_expected_items_total numeric(14,2);
  v_expected_wht numeric(14,2);
  v_basis text;
begin
  if v_actor is null or not public.is_super_admin() then
    raise exception 'Only an active Super Administrator may approve supplier settlements';
  end if;
  if p_settlement_id is null then raise exception 'Settlement ID is required'; end if;
  select * into v_settlement from public.frosttech_supplier_settlements
  where id=p_settlement_id for update;
  if not found then raise exception 'Settlement not found'; end if;
  if v_settlement.status<>'submitted' then raise exception 'Only submitted settlements can be approved'; end if;
  if v_settlement.prepared_by=v_actor then
    raise exception 'The settlement preparer cannot approve their own settlement';
  end if;
  select exists(
    select 1 from public.admin_accounts aa join public.profiles p on p.id=aa.user_id
    where aa.user_id=v_settlement.prepared_by and aa.is_active is true and p.is_active is true
  ) into v_preparer_active;
  if not v_preparer_active then raise exception 'Settlement preparer is no longer an active administrator'; end if;
  if not exists(select 1 from public.suppliers s where s.id=v_settlement.supplier_id
    and s.is_active is true and s.is_verified is true and s.review_status='approved') then
    raise exception 'Supplier is no longer eligible';
  end if;

  select count(*),coalesce(sum(line_total),0) into v_item_count,v_items_total
  from public.frosttech_supplier_settlement_items where settlement_id=p_settlement_id;
  if v_item_count=0 then raise exception 'Settlement has no line items'; end if;
  select count(*) into v_valid_count
  from public.frosttech_supplier_settlement_items si
  join public.order_items oi on oi.id=si.order_item_id
  join public.orders o on o.id=oi.order_id
  join public.products p on p.id=oi.product_id
  join public.frosttech_order_item_supplier_assignments a on a.order_item_id=oi.id
  where si.settlement_id=p_settlement_id and si.source_type='order_item'
    and oi.order_id=a.order_id and a.supplier_id=v_settlement.supplier_id
    and a.status='confirmed' and a.supplier_unit_cost=si.unit_cost
    and oi.quantity=si.quantity and si.line_total=round(oi.quantity*a.supplier_unit_cost,2)
    and o.status in ('paid','processing','ready_for_delivery','out_for_delivery','delivered','completed')
    and lower(trim(p.category)) in ('air conditioners','refrigeration parts','hvac accessories');
  if v_valid_count<>v_item_count then
    raise exception 'Settlement lines failed final validation';
  end if;

  v_basis:=v_settlement.tax_rule_snapshot->>'calculation_basis';
  if v_basis='net_amount' then
    v_expected_items_total:=v_settlement.wht_base;
    if v_settlement.wht_rate>=100 then raise exception 'Net-basis WHT rate must be below 100 percent'; end if;
    v_expected_wht:=round(v_settlement.wht_base*v_settlement.wht_rate/(100-v_settlement.wht_rate),2);
  elsif v_basis in ('taxable_base','gross_amount') then
    v_expected_items_total:=v_settlement.gross_entitlement;
    v_expected_wht:=round(v_settlement.wht_base*v_settlement.wht_rate/100,2);
  else
    raise exception 'Settlement tax calculation basis is missing or unsupported';
  end if;
  if round(v_items_total,2)<>round(v_expected_items_total,2)
     or v_settlement.wht_amount<>v_expected_wht
     or v_settlement.net_payable<>v_settlement.gross_entitlement-v_settlement.wht_amount then
    raise exception 'Settlement lines or tax calculations failed final validation';
  end if;

  if exists(
    select 1 from public.frosttech_supplier_settlement_items si
    join public.frosttech_supplier_settlement_items other_si
      on other_si.order_item_id=si.order_item_id and other_si.settlement_id<>si.settlement_id
    join public.frosttech_supplier_settlements other_s on other_s.id=other_si.settlement_id
    where si.settlement_id=p_settlement_id and other_s.status not in ('rejected','cancelled')
  ) then raise exception 'An order item is already included in another active settlement'; end if;

  update public.frosttech_supplier_settlements
  set status='approved',approved_by=v_actor,approved_at=now(),updated_at=now()
  where id=p_settlement_id;
  insert into public.admin_activity_log(actor_user_id,action,target_user_id,details)
  values(v_actor,'supplier_settlement_approved',null,
    jsonb_build_object('settlement_id',p_settlement_id,'settlement_number',v_settlement.settlement_number,
      'supplier_id',v_settlement.supplier_id,'gross_entitlement',v_settlement.gross_entitlement,
      'wht_amount',v_settlement.wht_amount,'net_payable',v_settlement.net_payable,
      'prepared_by',v_settlement.prepared_by,'calculation_basis',v_basis,'environment','isolated_test'));
  return p_settlement_id;
end;
$function$;

revoke all on function public.frosttech_prepare_supplier_settlement(uuid,uuid[]) from public,anon;
grant execute on function public.frosttech_prepare_supplier_settlement(uuid,uuid[]) to authenticated;
revoke all on function public.frosttech_submit_supplier_settlement(uuid) from public,anon;
grant execute on function public.frosttech_submit_supplier_settlement(uuid) to authenticated;
revoke all on function public.frosttech_approve_supplier_settlement(uuid) from public,anon;
grant execute on function public.frosttech_approve_supplier_settlement(uuid) to authenticated;

commit;