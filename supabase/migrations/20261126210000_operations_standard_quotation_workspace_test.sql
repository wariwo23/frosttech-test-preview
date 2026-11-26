-- FrostTech Operations standard quotation workspace (isolated test only)
-- Generated from the exact definitions applied and inspected in the test project.
-- Do not apply to production without the approved migration/release gate.


insert into public.admin_role_permissions(role,permission)
select 'operations_admin','quotations.manage_operational'
where not exists (
 select 1 from public.admin_role_permissions
 where role='operations_admin' and permission='quotations.manage_operational'
);

revoke all on function public.ops_list_customer_requests() from public,anon;
grant execute on function public.ops_list_customer_requests() to authenticated;
revoke all on function public.ops_get_standard_quotation_draft_v1(uuid) from public,anon;
grant execute on function public.ops_get_standard_quotation_draft_v1(uuid) to authenticated;
revoke all on function public.ops_save_standard_quotation_draft_v1(uuid,uuid,text,integer,numeric,numeric,numeric,numeric,date,text,jsonb) from public,anon;
grant execute on function public.ops_save_standard_quotation_draft_v1(uuid,uuid,text,integer,numeric,numeric,numeric,numeric,date,text,jsonb) to authenticated;
revoke all on function public.ops_submit_standard_quotation_v1(uuid) from public,anon;
grant execute on function public.ops_submit_standard_quotation_v1(uuid) to authenticated;

CREATE OR REPLACE FUNCTION public.ops_get_standard_quotation_draft_v1(p_quotation_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_quote public.admin_quotations%rowtype;
  v_items jsonb;
begin
  if auth.uid() is null
     or not public.admin_has_permission('quotations.manage_operational') then
    raise exception 'Operations quotation permission is required';
  end if;

  select * into v_quote
  from public.admin_quotations
  where id=p_quotation_id and status='draft';
  if not found then raise exception 'Editable draft quotation not found'; end if;

  select coalesce(jsonb_agg(to_jsonb(i) order by i.sort_order,i.created_at),'[]'::jsonb)
  into v_items
  from public.admin_quotation_items i
  where i.quotation_id=v_quote.id;

  return jsonb_build_object(
    'quotation',jsonb_build_object(
      'id',v_quote.id,'request_id',v_quote.request_id,
      'product_description',v_quote.product_description,
      'quantity',v_quote.quantity,'unit_price',v_quote.unit_price,
      'delivery_cost',v_quote.delivery_cost,
      'additional_charges',v_quote.additional_charges,
      'discount',v_quote.discount,'validity_date',v_quote.validity_date,
      'notes',v_quote.notes,'status',v_quote.status,
      'quotation_number',v_quote.quotation_number
    ),
    'items',v_items
  );
end;
$function$


CREATE OR REPLACE FUNCTION public.ops_list_customer_requests()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result jsonb;
begin
  if auth.uid() is null
     or not public.admin_has_permission('customer_requests.manage') then
    raise exception 'Access denied';
  end if;
  select coalesce(
    jsonb_agg(
      to_jsonb(q) - array[
        'admin_fee','admin_fee_status',
        'admin_fee_transaction_reference','admin_fee_paid_at'
      ]::text[]
      order by q.created_at desc
    ),
    '[]'::jsonb
  )
  into result
  from (
    select * from public.quote_requests
    order by created_at desc
    limit 500
  ) q;
  return result;
end;
$function$


CREATE OR REPLACE FUNCTION public.ops_save_standard_quotation_draft_v1(p_request_id uuid, p_quotation_id uuid, p_product_description text, p_quantity integer, p_unit_price numeric, p_delivery_cost numeric, p_additional_charges numeric, p_discount numeric, p_validity_date date, p_notes text, p_items jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_request public.quote_requests%rowtype;
  v_quote public.admin_quotations%rowtype;
  v_count integer;
  v_items_total numeric;
  v_expected numeric;
  v_accepted_proposal uuid;
  v_proposal_payload jsonb;
  v_linked_count integer;
begin
  if auth.uid() is null
     or not public.admin_has_permission('quotations.manage_operational') then
    raise exception 'Operations quotation permission is required';
  end if;

  if nullif(btrim(coalesce(p_product_description,'')),'') is null
     or p_quantity is null or p_quantity<=0
     or p_unit_price is null or p_unit_price<0
     or coalesce(p_delivery_cost,0)<0
     or coalesce(p_additional_charges,0)<0
     or coalesce(p_discount,0)<0
     or coalesce(p_discount,0)>(p_quantity*p_unit_price)+coalesce(p_additional_charges,0)
     or jsonb_typeof(p_items)<>'array'
     or jsonb_array_length(p_items)=0 then
    raise exception 'Quotation details are incomplete or invalid';
  end if;

  select * into v_request
  from public.quote_requests
  where id=p_request_id
  for update;
  if not found then raise exception 'Customer request not found'; end if;
  if v_request.status not in ('pending','in_progress','quoted') then
    raise exception 'This customer request is not available for quotation preparation';
  end if;

  select d.proposal_id,p.proposed_payload
  into v_accepted_proposal,v_proposal_payload
  from public.alternative_proposal_decisions d
  join public.alternative_proposals p on p.id=d.proposal_id
  where d.request_id=v_request.id and d.decision='accepted';

  if exists (
    select 1
    from jsonb_to_recordset(p_items) as x(
      item_type text,product_id uuid,description text,specifications jsonb,
      unit text,quantity numeric,unit_price numeric,sort_order integer,
      source_proposal_id uuid,replaces_item_id uuid
    )
    where coalesce(btrim(x.description),'')=''
       or coalesce(btrim(x.unit),'')=''
       or x.item_type not in ('product','service','accessory','installation','delivery','other')
       or x.quantity is null or x.quantity<=0
       or x.unit_price is null or x.unit_price<0
       or coalesce(x.sort_order,0)<0
       or (x.specifications is not null and jsonb_typeof(x.specifications)<>'object')
  ) then
    raise exception 'One or more quotation items contain invalid details';
  end if;

  select count(*),coalesce(sum(round(x.quantity*x.unit_price,2)),0)
  into v_count,v_items_total
  from jsonb_to_recordset(p_items) as x(
    item_type text,product_id uuid,description text,specifications jsonb,
    unit text,quantity numeric,unit_price numeric,sort_order integer,
    source_proposal_id uuid,replaces_item_id uuid
  );

  v_expected:=round((p_quantity*p_unit_price)+coalesce(p_additional_charges,0),2);
  if v_count=0 or round(v_items_total,2)<>v_expected then
    raise exception 'Item breakdown total (%) must equal product subtotal plus additional charges (%)',v_items_total,v_expected;
  end if;

  if v_accepted_proposal is not null then
    select count(*) into v_linked_count
    from jsonb_to_recordset(p_items) as x(
      item_type text,product_id uuid,description text,specifications jsonb,
      unit text,quantity numeric,unit_price numeric,sort_order integer,
      source_proposal_id uuid,replaces_item_id uuid
    )
    where x.source_proposal_id=v_accepted_proposal
       or (
         x.source_proposal_id is null
         and lower(btrim(x.description)) in (
           lower(btrim(coalesce(v_proposal_payload->>'title',''))),
           lower(btrim(coalesce(v_proposal_payload->>'description','')))
         )
       );
    if v_linked_count<>1 then
      raise exception 'The customer-approved alternative must appear exactly once in the quotation items';
    end if;
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_items) as x(
      item_type text,product_id uuid,description text,specifications jsonb,
      unit text,quantity numeric,unit_price numeric,sort_order integer,
      source_proposal_id uuid,replaces_item_id uuid
    )
    where x.source_proposal_id is not null
      and not exists (
        select 1 from public.alternative_proposal_decisions d
        where d.proposal_id=x.source_proposal_id
          and d.request_id=v_request.id and d.decision='accepted'
      )
  ) then
    raise exception 'Only a customer-accepted alternative may be linked to a quotation item';
  end if;

  if p_quotation_id is null then
    if exists (
      select 1 from public.admin_quotations q
      where q.request_id=v_request.id
        and (
          q.status='accepted'
          or (q.status='submitted'
              and coalesce(q.customer_decision,'') not in ('declined','rejected'))
        )
    ) then
      raise exception 'Another quotation is awaiting a customer decision or has been accepted';
    end if;

    insert into public.admin_quotations(
      request_id,customer_id,product_description,quantity,unit_price,
      delivery_cost,additional_charges,discount,validity_date,notes,
      status,created_by,quotation_scope_snapshot
    )
    values(
      v_request.id,v_request.customer_id,btrim(p_product_description),
      p_quantity,p_unit_price,coalesce(p_delivery_cost,0),
      coalesce(p_additional_charges,0),coalesce(p_discount,0),
      p_validity_date,nullif(btrim(coalesce(p_notes,'')),''),
      'draft',auth.uid(),
      jsonb_build_object(
        'snapshot_version',2,'state','draft',
        'request_id',v_request.id,'captured_at',now()
      )
    )
    returning * into v_quote;
  else
    select * into v_quote
    from public.admin_quotations
    where id=p_quotation_id
    for update;

    if not found or v_quote.status<>'draft' then
      raise exception 'Only an existing draft quotation can be edited';
    end if;
    if v_quote.request_id<>v_request.id then
      raise exception 'The quotation does not belong to the selected request';
    end if;

    update public.admin_quotations
    set product_description=btrim(p_product_description),
        quantity=p_quantity,
        unit_price=p_unit_price,
        delivery_cost=coalesce(p_delivery_cost,0),
        additional_charges=coalesce(p_additional_charges,0),
        discount=coalesce(p_discount,0),
        validity_date=p_validity_date,
        notes=nullif(btrim(coalesce(p_notes,'')),''),
        updated_at=now()
    where id=v_quote.id
    returning * into v_quote;
  end if;

  delete from public.admin_quotation_items
  where quotation_id=v_quote.id;

  insert into public.admin_quotation_items(
    quotation_id,item_type,product_id,description,specifications,unit,
    quantity,unit_price,line_total,sort_order,source_proposal_id,replaces_item_id
  )
  select
    v_quote.id,x.item_type,x.product_id,btrim(x.description),
    coalesce(x.specifications,'{}'::jsonb),btrim(x.unit),x.quantity,
    x.unit_price,round(x.quantity*x.unit_price,2),coalesce(x.sort_order,0),
    x.source_proposal_id,x.replaces_item_id
  from jsonb_to_recordset(p_items) as x(
    item_type text,product_id uuid,description text,specifications jsonb,
    unit text,quantity numeric,unit_price numeric,sort_order integer,
    source_proposal_id uuid,replaces_item_id uuid
  )
  order by coalesce(x.sort_order,0);

  return jsonb_build_object(
    'success',true,'quotation_id',v_quote.id,
    'quotation_number',v_quote.quotation_number,
    'status',v_quote.status,'subtotal',v_quote.subtotal,
    'additional_charges',v_quote.additional_charges,
    'discount',v_quote.discount,'delivery_cost',v_quote.delivery_cost,
    'total_amount',v_quote.total_amount,'item_count',v_count
  );
end;
$function$


CREATE OR REPLACE FUNCTION public.ops_submit_standard_quotation_v1(p_quotation_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_quote public.admin_quotations%rowtype;
  v_request public.quote_requests%rowtype;
  v_subtotal numeric;
  v_additional numeric;
  v_discount numeric;
  v_delivery numeric;
  v_total numeric;
  v_fee_basis numeric;
  v_fee numeric;
  v_item_total numeric;
  v_item_count integer;
  v_is_fee_paid boolean;
  v_snapshot jsonb;
  v_accepted_proposal uuid;
begin
  if auth.uid() is null
     or not public.admin_has_permission('quotations.manage_operational') then
    raise exception 'Operations quotation permission is required';
  end if;

  select * into v_quote from public.admin_quotations
  where id=p_quotation_id for update;
  if not found then raise exception 'Quotation not found'; end if;
  if v_quote.status<>'draft' then raise exception 'Only a draft quotation can be submitted'; end if;

  select * into v_request from public.quote_requests
  where id=v_quote.request_id for update;
  if not found then raise exception 'Linked customer request not found'; end if;
  if v_quote.customer_id is distinct from v_request.customer_id then
    raise exception 'Quotation and request ownership do not match';
  end if;
  if v_request.status not in ('pending','in_progress','quoted') then
    raise exception 'This customer request is not in a state that allows a quotation';
  end if;

  if exists (
    select 1 from public.admin_quotations other_quote
    where other_quote.request_id=v_request.id and other_quote.id<>v_quote.id
      and (
        other_quote.status='accepted'
        or (other_quote.status='submitted'
            and coalesce(other_quote.customer_decision,'') not in ('declined','rejected'))
      )
  ) then
    raise exception 'Another quotation is awaiting a customer decision or has been accepted';
  end if;

  v_subtotal:=v_quote.subtotal;
  v_additional:=coalesce(v_quote.additional_charges,0);
  v_discount:=coalesce(v_quote.discount,0);
  v_delivery:=coalesce(v_quote.delivery_cost,0);
  if v_subtotal<=0 or v_additional<0 or v_discount<0
     or v_discount>v_subtotal+v_additional or v_delivery<0 then
    raise exception 'Quotation amounts are invalid';
  end if;

  v_total:=v_quote.total_amount;
  v_fee_basis:=v_subtotal+v_additional-v_discount;
  if v_fee_basis<=0 then
    raise exception 'Consultation-fee basis must be greater than zero';
  end if;

  select count(*),coalesce(sum(line_total),0)
  into v_item_count,v_item_total
  from public.admin_quotation_items where quotation_id=v_quote.id;
  if v_item_count=0 or round(v_item_total,2)<>round(v_subtotal+v_additional,2) then
    raise exception 'Quotation item breakdown does not match subtotal plus additional charges';
  end if;

  select d.proposal_id into v_accepted_proposal
  from public.alternative_proposal_decisions d
  where d.request_id=v_quote.request_id and d.decision='accepted';

  if v_accepted_proposal is not null and not exists (
    select 1 from public.admin_quotation_items i
    where i.quotation_id=v_quote.id and i.source_proposal_id=v_accepted_proposal
  ) then
    raise exception 'The customer-approved alternative must be included in the quotation version';
  end if;

  if exists (
    select 1 from public.admin_quotation_items i
    where i.quotation_id=v_quote.id and i.source_proposal_id is not null
      and not exists (
        select 1 from public.alternative_proposal_decisions d
        where d.proposal_id=i.source_proposal_id
          and d.request_id=v_quote.request_id and d.decision='accepted'
      )
  ) then
    raise exception 'Only customer-accepted alternative proposals may be included';
  end if;

  v_is_fee_paid:=lower(coalesce(v_request.admin_fee_status,''))='paid'
    and v_request.admin_fee_paid_at is not null;
  if not v_is_fee_paid
     and nullif(btrim(coalesce(v_request.admin_fee_transaction_reference,'')),'') is not null then
    raise exception 'A previous consultation-fee payment attempt must be reconciled before submitting a revised quotation';
  end if;

  if v_is_fee_paid then
    v_fee:=v_request.admin_fee;
    if v_fee is null or v_fee<=0 then
      raise exception 'Recorded consultation-fee payment requires Finance reconciliation';
    end if;
  else
    v_fee:=round(v_fee_basis*0.02,2);
  end if;

  v_snapshot:=jsonb_build_object(
    'snapshot_version',2,
    'quotation_id',v_quote.id,
    'quotation_number',v_quote.quotation_number,
    'version_group_id',v_quote.version_group_id,
    'version_number',v_quote.version_number,
    'supersedes_quotation_id',v_quote.supersedes_quotation_id,
    'request_id',v_quote.request_id,
    'customer_id',v_quote.customer_id,
    'items',(
      select coalesce(jsonb_agg(jsonb_build_object(
        'item_id',i.id,'item_type',i.item_type,'product_id',i.product_id,
        'description',i.description,'specifications',i.specifications,
        'unit',i.unit,'quantity',i.quantity,'unit_price',i.unit_price,
        'line_total',i.line_total,'source_proposal_id',i.source_proposal_id,
        'replaces_item_id',i.replaces_item_id
      ) order by i.sort_order,i.created_at),'[]'::jsonb)
      from public.admin_quotation_items i where i.quotation_id=v_quote.id
    ),
    'subtotal',v_subtotal,'additional_charges',v_additional,
    'discount',v_discount,'delivery_cost',v_delivery,'total_amount',v_total,
    'validity_date',v_quote.validity_date,'customer_notes',v_quote.notes,
    'original_request_snapshot',(
      select jsonb_build_object(
        'capture_type',s.capture_type,
        'payload_hash',s.payload_hash,
        'captured_at',s.captured_at,
        'original_payload',s.original_payload
      )
      from public.quote_request_original_snapshots s
      where s.request_id=v_quote.request_id
    ),
    'accepted_alternative',(
      select jsonb_build_object(
        'proposal_id',p.id,'proposer_type',p.proposer_type,
        'reason',p.reason,'proposed_payload',p.proposed_payload,
        'commercial_terms',p.commercial_terms,'decision',d.decision,
        'decided_at',d.decided_at
      )
      from public.alternative_proposals p
      join public.alternative_proposal_decisions d on d.proposal_id=p.id
      where p.id=v_accepted_proposal
    ),
    'captured_at',now()
  );

  update public.admin_quotations
  set quotation_scope_snapshot=v_snapshot,
      submitted_scope_snapshot=v_snapshot,
      status='submitted',updated_at=now()
  where id=v_quote.id returning * into v_quote;

  if v_is_fee_paid then
    update public.quote_requests
    set status='quoted',updated_at=now()
    where id=v_request.id;
  else
    update public.quote_requests
    set status='quoted',admin_fee=v_fee,admin_fee_status='pending',
        updated_at=now()
    where id=v_request.id;
  end if;

  return jsonb_build_object(
    'quotation_id',v_quote.id,'request_id',v_quote.request_id,
    'quotation_number',v_quote.quotation_number,
    'version_group_id',v_quote.version_group_id,
    'version_number',v_quote.version_number,
    'fee',v_fee,'fee_already_paid',v_is_fee_paid,
    'subtotal',v_subtotal,'total_amount',v_total,'status',v_quote.status
  );
end;
$function$

