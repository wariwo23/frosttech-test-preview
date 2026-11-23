begin;

create or replace function public.frosttech_guard_duplicate_tax_source()
returns trigger language plpgsql security definer set search_path=''
as $function$
declare v_order_id uuid; v_source_type text;
begin
  if new.tax_type not in ('VAT','WHT') then return new; end if;
  v_source_type:=lower(trim(new.transaction_type));
  if v_source_type='order' then
    v_order_id:=new.transaction_id;
  elsif v_source_type='payment' then
    select p.order_id into v_order_id from public.payments p
    where p.id=new.transaction_id and p.status='successful';
  else
    return new;
  end if;
  if v_order_id is not null then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtext('frosttech_tax_source:'||v_order_id::text),1
    );
  end if;
  if v_source_type='order' then
    if exists(
      select 1 from public.payments p
      join public.frosttech_tax_assessments a
        on lower(trim(a.transaction_type))='payment'
       and a.transaction_id=p.id and a.tax_type=new.tax_type and a.direction=new.direction
      where p.order_id=new.transaction_id and p.status='successful'
    ) then
      raise exception 'This paid order already has a matching tax assessment through a successful payment';
    end if;
  elsif v_source_type='payment' and v_order_id is not null then
    if exists(
      select 1 from public.frosttech_tax_assessments a
      where lower(trim(a.transaction_type))='order'
        and a.transaction_id=v_order_id and a.tax_type=new.tax_type and a.direction=new.direction
    ) then
      raise exception 'This payment order already has a matching tax assessment';
    end if;
  end if;
  return new;
end;
$function$;

create or replace function public.frosttech_create_tax_assessment(
  p_transaction_type text,p_transaction_id uuid,p_direction text,p_tax_type text,
  p_transaction_category text,p_tax_classification text,p_base_amount numeric
)
returns uuid language plpgsql security definer set search_path=''
as $function$
declare
  v_actor uuid:=auth.uid();
  v_source_type text:=lower(trim(coalesce(p_transaction_type,'')));
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
  if v_source_type not in ('order','payment') or p_transaction_id is null
     or p_direction not in ('inbound','outbound') or p_direction is null
     or p_tax_type not in ('VAT','WHT') or p_tax_type is null
     or nullif(trim(coalesce(p_transaction_category,'')),'') is null
     or nullif(trim(coalesce(p_tax_classification,'')),'') is null
     or p_base_amount is null or p_base_amount<=0 then
    raise exception 'Invalid tax assessment details';
  end if;

  if v_source_type='order' then
    select customer_total into v_source_amount from public.orders
    where id=p_transaction_id
      and status in ('paid','processing','ready_for_delivery','out_for_delivery','delivered','completed');
  else
    select amount into v_source_amount from public.payments
    where id=p_transaction_id and status='successful' and paid_at is not null;
  end if;
  if v_source_amount is null or v_source_amount<=0 then
    raise exception 'The referenced paid order or successful payment does not exist or is not eligible for tax assessment';
  end if;
  if round(p_base_amount,2)>round(v_source_amount,2) then
    raise exception 'Taxable base cannot exceed the verified source transaction amount';
  end if;

  select * into v_existing from public.frosttech_tax_assessments
  where lower(trim(transaction_type))=v_source_type
    and transaction_id=p_transaction_id and direction=p_direction and tax_type=p_tax_type;
  if found then
    if v_existing.taxable_base<>round(p_base_amount,2) then
      raise exception 'This transaction already has a tax assessment with a different base amount';
    end if;
    return v_existing.id;
  end if;

  select * into v_rule from public.frosttech_tax_rules
  where tax_type=p_tax_type and direction in (p_direction,'both')
    and transaction_category=trim(p_transaction_category)
    and tax_classification=trim(p_tax_classification)
    and is_active and effective_from<=now()
    and (effective_until is null or effective_until>now())
  order by (direction=p_direction) desc,effective_from desc limit 1;
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
    transaction_type,transaction_id,direction,tax_type,tax_rule_id,taxable_base,
    applied_rate,tax_amount,gross_amount,net_amount,currency,rule_snapshot,assessment_status,assessed_by
  ) values (
    v_source_type,p_transaction_id,p_direction,p_tax_type,v_rule.id,round(p_base_amount,2),
    v_rule.rate,v_tax,v_gross,v_net,'NGN',
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
    jsonb_build_object('assessment_id',v_id,'transaction_type',v_source_type,
      'transaction_id',p_transaction_id,'direction',p_direction,'tax_type',p_tax_type,
      'taxable_base',p_base_amount,'rate',v_rule.rate,'tax_amount',v_tax,
      'gross_amount',v_gross,'net_amount',v_net,'environment','isolated_test'));
  return v_id;
end;
$function$;

revoke all on function public.frosttech_create_tax_assessment(text,uuid,text,text,text,text,numeric) from public,anon;
grant execute on function public.frosttech_create_tax_assessment(text,uuid,text,text,text,text,numeric) to authenticated;

commit;