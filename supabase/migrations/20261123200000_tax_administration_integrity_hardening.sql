-- FrostTech Tax Administration hardening: isolated test environment only.
-- Adds supplier entity/residency matching, safe WHT settlement basis rules,
-- VAT settings controls, and source-record validation for tax assessments.

begin;

-- 1) Tax rules must be able to target verified supplier entity and residency.
alter table public.frosttech_tax_rules
  add column if not exists entity_type text not null default 'any',
  add column if not exists residency_status text not null default 'any';

alter table public.frosttech_tax_rules
  drop constraint if exists frosttech_tax_rules_entity_type_check;
alter table public.frosttech_tax_rules
  add constraint frosttech_tax_rules_entity_type_check
  check (entity_type in ('any','individual','company','partnership','other'));

alter table public.frosttech_tax_rules
  drop constraint if exists frosttech_tax_rules_residency_status_check;
alter table public.frosttech_tax_rules
  add constraint frosttech_tax_rules_residency_status_check
  check (residency_status in ('any','resident','non_resident'));

-- Prevent overlapping active rules, including wildcard scopes.
create or replace function public.frosttech_guard_tax_rule_overlap()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.is_active then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtext(new.tax_type || '|' || new.transaction_category || '|' ||
        new.tax_classification),
      0
    );

    if exists (
      select 1 from public.frosttech_tax_rules r
      where r.id <> coalesce(new.id,'00000000-0000-0000-0000-000000000000'::uuid)
        and r.is_active
        and r.tax_type = new.tax_type
        and r.transaction_category = new.transaction_category
        and r.tax_classification = new.tax_classification
        and (r.direction = 'both' or new.direction = 'both' or r.direction = new.direction)
        and (r.entity_type = 'any' or new.entity_type = 'any' or r.entity_type = new.entity_type)
        and (r.residency_status = 'any' or new.residency_status = 'any'
             or r.residency_status = new.residency_status)
        and tstzrange(r.effective_from,coalesce(r.effective_until,'infinity'::timestamptz),'[)')
            && tstzrange(new.effective_from,coalesce(new.effective_until,'infinity'::timestamptz),'[)')
    ) then
      raise exception 'An active tax rule already overlaps this tax, supplier classification, entity, residency, direction and effective period';
    end if;
  end if;
  return new;
end;
$function$;

drop trigger if exists frosttech_tax_rule_overlap_guard on public.frosttech_tax_rules;
create trigger frosttech_tax_rule_overlap_guard
before insert or update of tax_type,direction,transaction_category,tax_classification,
  entity_type,residency_status,effective_from,effective_until,is_active
on public.frosttech_tax_rules
for each row execute function public.frosttech_guard_tax_rule_overlap();

-- New explicit rule-creation signature. Old callers remain supported below.
create or replace function public.frosttech_create_tax_rule(
  p_tax_type text,
  p_direction text,
  p_transaction_category text,
  p_tax_classification text,
  p_entity_type text,
  p_residency_status text,
  p_rate numeric,
  p_calculation_basis text,
  p_vat_mode text,
  p_legal_reference text,
  p_effective_from timestamptz,
  p_effective_until timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_id uuid;
begin
  if auth.uid() is null or not public.is_super_admin() then
    raise exception 'Only the Super Admin may create tax rules';
  end if;
  if p_tax_type is null or p_tax_type not in ('VAT','WHT')
     or p_direction is null or p_direction not in ('inbound','outbound','both')
     or nullif(trim(coalesce(p_transaction_category,'')),'') is null
     or nullif(trim(coalesce(p_tax_classification,'')),'') is null
     or p_entity_type is null or p_entity_type not in ('any','individual','company','partnership','other')
     or p_residency_status is null or p_residency_status not in ('any','resident','non_resident')
     or p_rate is null or p_rate < 0 or p_rate > 100
     or p_calculation_basis not in ('taxable_base','gross_amount','net_amount')
     or p_effective_from is null
     or (p_effective_until is not null and p_effective_until <= p_effective_from) then
    raise exception 'Invalid tax rule details';
  end if;
  if p_tax_type = 'VAT' and (p_vat_mode is null or p_vat_mode not in ('inclusive','exclusive')
     or p_entity_type <> 'any' or p_residency_status <> 'any') then
    raise exception 'VAT rules require a VAT mode and an unsegmented supplier scope';
  end if;
  if p_tax_type = 'WHT' and p_vat_mode is not null then
    raise exception 'WHT rules must not have a VAT mode';
  end if;
  if length(trim(coalesce(p_legal_reference,''))) < 3 then
    raise exception 'A legal reference or approved tax authority basis is required';
  end if;

  insert into public.frosttech_tax_rules(
    tax_type,direction,transaction_category,tax_classification,
    entity_type,residency_status,rate,calculation_basis,vat_mode,
    legal_reference,effective_from,effective_until,is_active,created_by
  ) values (
    p_tax_type,p_direction,trim(p_transaction_category),trim(p_tax_classification),
    p_entity_type,p_residency_status,p_rate,p_calculation_basis,p_vat_mode,
    trim(p_legal_reference),p_effective_from,p_effective_until,false,auth.uid()
  ) returning id into v_id;

  insert into public.admin_activity_log(actor_user_id,action,target_user_id,details)
  values(auth.uid(),'tax_rule_created',null,
    jsonb_build_object(
      'tax_rule_id',v_id,'tax_type',p_tax_type,'direction',p_direction,
      'category',p_transaction_category,'classification',p_tax_classification,
      'entity_type',p_entity_type,'residency_status',p_residency_status,
      'rate',p_rate,'effective_from',p_effective_from,
      'effective_until',p_effective_until,'created_inactive',true,
      'environment','isolated_test'
    ));
  return v_id;
end;
$function$;

-- Preserve the existing RPC signature for any existing caller.
create or replace function public.frosttech_create_tax_rule(
  p_tax_type text,
  p_direction text,
  p_transaction_category text,
  p_tax_classification text,
  p_rate numeric,
  p_calculation_basis text,
  p_vat_mode text,
  p_legal_reference text,
  p_effective_from timestamptz,
  p_effective_until timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
begin
  return public.frosttech_create_tax_rule(
    p_tax_type,p_direction,p_transaction_category,p_tax_classification,
    'any','any',p_rate,p_calculation_basis,p_vat_mode,p_legal_reference,
    p_effective_from,p_effective_until
  );
end;
$function$;

revoke all on function public.frosttech_create_tax_rule(text,text,text,text,text,text,numeric,text,text,text,timestamptz,timestamptz) from public, anon;
grant execute on function public.frosttech_create_tax_rule(text,text,text,text,text,text,numeric,text,text,text,timestamptz,timestamptz) to authenticated;
revoke all on function public.frosttech_create_tax_rule(text,text,text,text,numeric,text,text,text,timestamptz,timestamptz) from public, anon;
grant execute on function public.frosttech_create_tax_rule(text,text,text,text,numeric,text,text,text,timestamptz,timestamptz) to authenticated;

-- 2) VAT settings become Super Admin managed only; no direct API table access.
revoke all on table public.frosttech_tax_settings from public, anon, authenticated;

create or replace function public.frosttech_admin_get_tax_settings()
returns table (
  vat_enabled boolean,
  vat_rate numeric,
  vat_mode text,
  effective_at timestamptz,
  updated_by uuid,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null or not public.is_super_admin() then
    raise exception 'Only the Super Admin may view tax settings';
  end if;
  return query
  select s.vat_enabled,s.vat_rate,s.vat_mode,s.effective_at,s.updated_by,s.updated_at
  from public.frosttech_tax_settings s where s.id=1;
end;
$function$;

create or replace function public.frosttech_admin_update_tax_settings(
  p_vat_enabled boolean,
  p_vat_rate numeric,
  p_vat_mode text,
  p_effective_at timestamptz,
  p_reason text
)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null or not public.is_super_admin() then
    raise exception 'Only the Super Admin may change tax settings';
  end if;
  if length(trim(coalesce(p_reason,''))) < 12 then
    raise exception 'A reason of at least 12 characters is required';
  end if;

  if p_vat_enabled is true then
    if p_vat_rate is null or p_vat_rate <= 0 or p_vat_rate > 100
       or p_vat_mode is null or p_vat_mode not in ('inclusive','exclusive') or p_effective_at is null then
      raise exception 'Enabled VAT requires a valid rate, mode and effective date';
    end if;
    if exists (
      select 1 from public.frosttech_tax_rules r
      where r.tax_type='VAT' and r.is_active
        and (r.rate <> p_vat_rate or r.vat_mode <> p_vat_mode
             or r.effective_from < p_effective_at)
    ) then
      raise exception 'VAT settings conflict with an active VAT rule; reconcile or deactivate the rule first';
    end if;
  else
    if p_vat_rate is not null or p_vat_mode is distinct from 'not_configured' or p_effective_at is not null then
      raise exception 'Disabled VAT must have no rate or effective date and use not_configured mode';
    end if;
    if exists (select 1 from public.frosttech_tax_rules r where r.tax_type='VAT' and r.is_active) then
      raise exception 'Deactivate active VAT rules before disabling VAT settings';
    end if;
  end if;

  update public.frosttech_tax_settings
  set vat_enabled=p_vat_enabled,vat_rate=p_vat_rate,vat_mode=p_vat_mode,
      effective_at=p_effective_at,updated_by=auth.uid(),updated_at=now()
  where id=1;

  insert into public.admin_activity_log(actor_user_id,action,target_user_id,details)
  values(auth.uid(),'tax_settings_updated',null,
    jsonb_build_object(
      'vat_enabled',p_vat_enabled,'vat_rate',p_vat_rate,
      'vat_mode',p_vat_mode,'effective_at',p_effective_at,
      'reason',trim(p_reason),'environment','isolated_test'
    ));
  return 'updated';
end;
$function$;

revoke all on function public.frosttech_admin_get_tax_settings() from public, anon;
grant execute on function public.frosttech_admin_get_tax_settings() to authenticated;
revoke all on function public.frosttech_admin_update_tax_settings(boolean,numeric,text,timestamptz,text) from public, anon;
grant execute on function public.frosttech_admin_update_tax_settings(boolean,numeric,text,timestamptz,text) to authenticated;

-- VAT activation must agree with the singleton VAT settings.
create or replace function public.frosttech_activate_tax_rule(p_tax_rule_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_rule public.frosttech_tax_rules%rowtype;
  v_settings public.frosttech_tax_settings%rowtype;
begin
  if auth.uid() is null or not public.is_super_admin() then
    raise exception 'Only the Super Admin may activate tax rules';
  end if;
  select * into v_rule from public.frosttech_tax_rules where id=p_tax_rule_id for update;
  if not found then raise exception 'Tax rule not found'; end if;
  if nullif(trim(coalesce(v_rule.legal_reference,'')),'') is null then
    raise exception 'Tax rule cannot be activated without a legal reference';
  end if;
  if v_rule.effective_until is not null and v_rule.effective_until<=v_rule.effective_from then
    raise exception 'Tax rule effective dates are invalid';
  end if;
  if v_rule.tax_type='VAT' then
    select * into v_settings from public.frosttech_tax_settings where id=1;
    if not found or not v_settings.vat_enabled
       or v_settings.vat_rate is distinct from v_rule.rate
       or v_settings.vat_mode is distinct from v_rule.vat_mode
       or v_settings.effective_at is null
       or v_rule.effective_from < v_settings.effective_at then
      raise exception 'VAT rule must match enabled VAT settings and their effective date';
    end if;
  end if;
  update public.frosttech_tax_rules set is_active=true,updated_at=now() where id=p_tax_rule_id;
  insert into public.admin_activity_log(actor_user_id,action,target_user_id,details)
  values(auth.uid(),'tax_rule_activated',null,
    jsonb_build_object('tax_rule_id',p_tax_rule_id,'rate',v_rule.rate,
      'effective_from',v_rule.effective_from,'effective_until',v_rule.effective_until,
      'environment','isolated_test'));
  return 'active';
end;
$function$;

-- 3) Supplier settlement amounts represent gross entitlement before withholding.
-- A net_amount rule would require a gross-up and a different settlement model;
-- fail closed instead of silently applying the wrong formula.
alter table public.frosttech_supplier_settlements
  drop constraint if exists frosttech_settlement_wht_basis_ck;
alter table public.frosttech_supplier_settlements
  add constraint frosttech_settlement_wht_basis_ck
  check (coalesce(tax_rule_snapshot->>'calculation_basis' in ('taxable_base','gross_amount'),false));

create or replace function public.frosttech_prepare_supplier_settlement(
  p_supplier_id uuid,
  p_order_item_ids uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := auth.uid();
  v_supplier public.suppliers%rowtype;
  v_profile public.frosttech_supplier_tax_profiles%rowtype;
  v_rule public.frosttech_tax_rules%rowtype;
  v_gross numeric(14,2);
  v_wht numeric(14,2);
  v_settlement_id uuid;
  v_count integer;
begin
  if v_actor is null or not public.admin_has_permission('supplier_settlements.prepare') then
    raise exception 'Finance settlement preparation permission is required';
  end if;
  if p_supplier_id is null or p_order_item_ids is null
     or cardinality(p_order_item_ids)=0
     or array_position(p_order_item_ids,null) is not null
     or cardinality(p_order_item_ids)>200 then
    raise exception 'Select between 1 and 200 valid order items';
  end if;
  if cardinality(p_order_item_ids) <>
     (select count(distinct x) from unnest(p_order_item_ids) as x) then
    raise exception 'Duplicate order items are not permitted';
  end if;

  select * into v_supplier from public.suppliers
  where id=p_supplier_id and is_active is true
    and is_verified is true and review_status='approved'
  for update;
  if not found then raise exception 'Supplier must be active, verified and approved'; end if;

  select * into v_profile from public.frosttech_supplier_tax_profiles
  where supplier_id=p_supplier_id and verification_status='verified'
  for update;
  if not found then
    raise exception 'Supplier tax profile must be verified before settlement preparation';
  end if;

  perform 1
  from public.order_items oi
  join public.orders o on o.id=oi.order_id
  join public.products p on p.id=oi.product_id
  join public.frosttech_order_item_supplier_assignments a on a.order_item_id=oi.id
  where oi.id=any(p_order_item_ids)
    and a.order_id=o.id and a.supplier_id=p_supplier_id
    and a.status='confirmed' and a.supplier_unit_cost>0
    and o.status in ('paid','processing','ready_for_delivery','out_for_delivery','delivered','completed')
    and lower(trim(p.category)) in ('air conditioners','refrigeration parts','hvac accessories')
  for update of oi,o,a;
  get diagnostics v_count = row_count;
  if v_count <> cardinality(p_order_item_ids) then
    raise exception 'Every item must have a confirmed matching supplier assignment, an eligible paid order and a verifiable catalogue product category';
  end if;

  select round(sum(oi.quantity*a.supplier_unit_cost),2) into v_gross
  from public.order_items oi
  join public.frosttech_order_item_supplier_assignments a on a.order_item_id=oi.id
  where oi.id=any(p_order_item_ids) and a.supplier_id=p_supplier_id and a.status='confirmed';
  if v_gross is null or v_gross<=0 then
    raise exception 'Supplier entitlement could not be calculated';
  end if;

  select * into v_rule
  from public.frosttech_tax_rules
  where tax_type='WHT'
    and direction in ('outbound','both')
    and transaction_category='supplier_settlement'
    and tax_classification=v_profile.tax_classification
    and entity_type in (v_profile.entity_type,'any')
    and residency_status in (v_profile.residency_status,'any')
    and is_active is true
    and effective_from<=now()
    and (effective_until is null or effective_until>now())
  order by (entity_type=v_profile.entity_type) desc,
           (residency_status=v_profile.residency_status) desc,
           effective_from desc
  limit 1 for share;

  if not found then
    raise exception 'No effective WHT rule matches this verified supplier classification, entity type and residency status';
  end if;
  if v_rule.calculation_basis not in ('taxable_base','gross_amount') then
    raise exception 'This WHT rule uses a net-amount gross-up basis, which is not supported by the current supplier settlement model. Create a gross-basis supplier settlement rule instead.';
  end if;

  v_wht := round(v_gross*v_rule.rate/100,2);

  insert into public.frosttech_supplier_settlements(
    supplier_id,currency,gross_entitlement,wht_base,wht_rate,wht_amount,
    net_payable,tax_rule_snapshot,status,prepared_by,prepared_at
  ) values (
    p_supplier_id,'NGN',v_gross,v_gross,v_rule.rate,v_wht,
    v_gross-v_wht,
    jsonb_build_object(
      'tax_rule_id',v_rule.id,'tax_type',v_rule.tax_type,
      'direction',v_rule.direction,'transaction_category',v_rule.transaction_category,
      'tax_classification',v_rule.tax_classification,
      'entity_type',v_rule.entity_type,'residency_status',v_rule.residency_status,
      'rate',v_rule.rate,'calculation_basis',v_rule.calculation_basis,
      'legal_reference',v_rule.legal_reference,'effective_from',v_rule.effective_from,
      'effective_until',v_rule.effective_until,
      'supplier_entity_type',v_profile.entity_type,
      'supplier_residency_status',v_profile.residency_status,
      'supplier_tax_classification',v_profile.tax_classification
    ),
    'draft',v_actor,now()
  ) returning id into v_settlement_id;

  insert into public.frosttech_supplier_settlement_items(
    settlement_id,source_type,order_item_id,description,quantity,
    unit_cost,line_total,supplier_assignment_snapshot
  )
  select v_settlement_id,'order_item',oi.id,oi.product_name,oi.quantity,
    a.supplier_unit_cost,round(oi.quantity*a.supplier_unit_cost,2),
    jsonb_build_object(
      'supplier_id',a.supplier_id,'supplier_unit_cost',a.supplier_unit_cost,
      'assignment_source',a.assignment_source,'source_record_id',a.source_record_id,
      'verified_by',a.verified_by,'verified_at',a.verified_at,
      'order_id',oi.order_id,'product_id',oi.product_id,'product_category',p.category
    )
  from public.order_items oi
  join public.products p on p.id=oi.product_id
  join public.frosttech_order_item_supplier_assignments a on a.order_item_id=oi.id
  where oi.id=any(p_order_item_ids) and a.supplier_id=p_supplier_id and a.status='confirmed';

  insert into public.admin_activity_log(actor_user_id,action,target_user_id,details)
  values(v_actor,'supplier_settlement_prepared',null,
    jsonb_build_object('settlement_id',v_settlement_id,'supplier_id',p_supplier_id,
      'order_item_ids',to_jsonb(p_order_item_ids),'gross_entitlement',v_gross,
      'wht_rate',v_rule.rate,'wht_amount',v_wht,'net_payable',v_gross-v_wht,
      'tax_rule_id',v_rule.id,'entity_type',v_profile.entity_type,
      'residency_status',v_profile.residency_status,'environment','isolated_test'));
  return v_settlement_id;
end;
$function$;

revoke all on function public.frosttech_prepare_supplier_settlement(uuid,uuid[]) from public, anon;
grant execute on function public.frosttech_prepare_supplier_settlement(uuid,uuid[]) to authenticated;

-- 4) Tax assessments may only reference verified source records.
-- Current supported source types are orders and successful payments.
-- Supplier settlements use their dedicated WHT settlement/remittance linkage.
create or replace function public.frosttech_create_tax_assessment(
  p_transaction_type text,
  p_transaction_id uuid,
  p_direction text,
  p_tax_type text,
  p_transaction_category text,
  p_tax_classification text,
  p_base_amount numeric
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := auth.uid();
  v_rule public.frosttech_tax_rules%rowtype;
  v_existing public.frosttech_tax_assessments%rowtype;
  v_settings public.frosttech_tax_settings%rowtype;
  v_source_amount numeric(14,2);
  v_tax numeric(14,2);
  v_gross numeric(14,2);
  v_net numeric(14,2);
  v_id uuid;
begin
  if v_actor is null or not public.admin_has_permission('tax.assessments.manage') then
    raise exception 'Finance tax assessment permission is required';
  end if;
  if nullif(trim(coalesce(p_transaction_type,'')),'') is null
     or p_transaction_id is null
     or p_direction not in ('inbound','outbound') or p_direction is null
     or p_tax_type not in ('VAT','WHT') or p_tax_type is null
     or nullif(trim(coalesce(p_transaction_category,'')),'') is null
     or nullif(trim(coalesce(p_tax_classification,'')),'') is null
     or p_base_amount is null or p_base_amount<=0 then
    raise exception 'Invalid tax assessment details';
  end if;

  if lower(trim(p_transaction_type))='order' then
    select customer_total into v_source_amount
    from public.orders
    where id=p_transaction_id
      and status in ('paid','processing','ready_for_delivery','out_for_delivery','delivered','completed');
  elsif lower(trim(p_transaction_type))='payment' then
    select amount into v_source_amount
    from public.payments
    where id=p_transaction_id and status='successful' and paid_at is not null;
  else
    raise exception 'Unsupported tax source type. Only verified orders and successful payments are currently supported; supplier settlements use their dedicated WHT remittance linkage.';
  end if;

  if v_source_amount is null or v_source_amount<=0 then
    raise exception 'The referenced paid order or successful payment does not exist or is not eligible for tax assessment';
  end if;
  if round(p_base_amount,2)>round(v_source_amount,2) then
    raise exception 'Taxable base cannot exceed the verified source transaction amount';
  end if;

  select * into v_existing
  from public.frosttech_tax_assessments
  where transaction_type=trim(p_transaction_type)
    and transaction_id=p_transaction_id
    and direction=p_direction and tax_type=p_tax_type;
  if found then
    if v_existing.taxable_base<>round(p_base_amount,2) then
      raise exception 'This transaction already has a tax assessment with a different base amount';
    end if;
    return v_existing.id;
  end if;

  select * into v_rule
  from public.frosttech_tax_rules
  where tax_type=p_tax_type
    and direction in (p_direction,'both')
    and transaction_category=trim(p_transaction_category)
    and tax_classification=trim(p_tax_classification)
    and is_active and effective_from<=now()
    and (effective_until is null or effective_until>now())
  order by (direction=p_direction) desc,effective_from desc
  limit 1;
  if not found then raise exception 'No active tax rule matches this transaction'; end if;

  if p_tax_type='VAT' then
    select * into v_settings from public.frosttech_tax_settings where id=1;
    if not found or not v_settings.vat_enabled
       or v_settings.vat_rate is distinct from v_rule.rate
       or v_settings.vat_mode is distinct from v_rule.vat_mode
       or v_settings.effective_at is null or v_settings.effective_at>now()
       or v_rule.effective_from<v_settings.effective_at then
      raise exception 'VAT assessment blocked: the active rule does not match enabled VAT settings and their effective date';
    end if;
  end if;

  if p_tax_type='WHT' then
    if v_rule.calculation_basis='net_amount' then
      if v_rule.rate>=100 then raise exception 'WHT rate must be below 100 percent for net-basis gross-up'; end if;
      v_net:=round(p_base_amount,2);
      v_tax:=round(p_base_amount*v_rule.rate/(100-v_rule.rate),2);
      v_gross:=round(v_net+v_tax,2);
    else
      v_gross:=round(p_base_amount,2);
      v_tax:=round(p_base_amount*v_rule.rate/100,2);
      v_net:=round(v_gross-v_tax,2);
    end if;
  elsif v_rule.vat_mode='inclusive' then
    v_gross:=round(p_base_amount,2);
    v_tax:=round(p_base_amount*v_rule.rate/(100+v_rule.rate),2);
    v_net:=round(v_gross-v_tax,2);
  else
    if v_rule.calculation_basis='gross_amount' then
      v_gross:=round(p_base_amount,2);
      v_net:=round(p_base_amount/(1+v_rule.rate/100),2);
      v_tax:=round(v_gross-v_net,2);
    else
      v_net:=round(p_base_amount,2);
      v_tax:=round(p_base_amount*v_rule.rate/100,2);
      v_gross:=round(v_net+v_tax,2);
    end if;
  end if;

  insert into public.frosttech_tax_assessments(
    transaction_type,transaction_id,direction,tax_type,tax_rule_id,
    taxable_base,applied_rate,tax_amount,gross_amount,net_amount,currency,
    rule_snapshot,assessment_status,assessed_by
  ) values (
    trim(p_transaction_type),p_transaction_id,p_direction,p_tax_type,v_rule.id,
    round(p_base_amount,2),v_rule.rate,v_tax,v_gross,v_net,'NGN',
    jsonb_build_object('tax_rule_id',v_rule.id,'tax_type',v_rule.tax_type,
      'direction',v_rule.direction,'transaction_category',v_rule.transaction_category,
      'tax_classification',v_rule.tax_classification,'entity_type',v_rule.entity_type,
      'residency_status',v_rule.residency_status,'rate',v_rule.rate,
      'calculation_basis',v_rule.calculation_basis,'vat_mode',v_rule.vat_mode,
      'legal_reference',v_rule.legal_reference,'effective_from',v_rule.effective_from,
      'effective_until',v_rule.effective_until,'source_amount',v_source_amount),
    'assessed',v_actor
  ) returning id into v_id;

  insert into public.admin_activity_log(actor_user_id,action,target_user_id,details)
  values(v_actor,'tax_assessment_created',null,
    jsonb_build_object('assessment_id',v_id,'transaction_type',p_transaction_type,
      'transaction_id',p_transaction_id,'direction',p_direction,
      'tax_type',p_tax_type,'taxable_base',p_base_amount,'rate',v_rule.rate,
      'tax_amount',v_tax,'gross_amount',v_gross,'net_amount',v_net,
      'environment','isolated_test'));
  return v_id;
end;
$function$;

revoke all on function public.frosttech_create_tax_assessment(text,uuid,text,text,text,text,numeric) from public, anon;
grant execute on function public.frosttech_create_tax_assessment(text,uuid,text,text,text,text,numeric) to authenticated;

commit;
