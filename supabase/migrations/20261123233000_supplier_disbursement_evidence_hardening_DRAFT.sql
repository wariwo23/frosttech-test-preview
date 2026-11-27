-- DRAFT ONLY — do not apply until reviewed and explicitly approved.
-- Isolated-test supplier disbursement evidence hardening.
-- Creates a private evidence bucket and enforces object existence/ownership
-- in both the record and manual-verification RPCs.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'supplier-disbursement-evidence',
  'supplier-disbursement-evidence',
  false,
  10485760,
  array['application/pdf','image/jpeg','image/png']::text[]
)
on conflict (id) do update
set public = false,
    file_size_limit = 10485760,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists supplier_disbursement_evidence_insert on storage.objects;
create policy supplier_disbursement_evidence_insert
on storage.objects for insert to authenticated
with check (
  bucket_id = 'supplier-disbursement-evidence'
  and public.admin_has_permission('supplier_settlements.execute')
  and (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  and (storage.foldername(name))[2] = auth.uid()::text
);

drop policy if exists supplier_disbursement_evidence_read on storage.objects;
create policy supplier_disbursement_evidence_read
on storage.objects for select to authenticated
using (
  bucket_id = 'supplier-disbursement-evidence'
  and public.admin_has_permission('supplier_settlements.execute')
);

-- No authenticated UPDATE or DELETE policy is intentionally created.
-- Object path format: <settlement_uuid>/<uploader_auth_uid>/<unique_filename>.

create or replace function public.frosttech_record_supplier_disbursement(
  p_settlement_id uuid,
  p_payment_method text,
  p_amount numeric,
  p_idempotency_key text,
  p_payment_reference text default null,
  p_provider_reference text default null,
  p_evidence_path text default null
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor uuid := auth.uid();
  v_settlement public.frosttech_supplier_settlements%rowtype;
  v_reserved numeric(14,2);
  v_disbursement_id uuid;
begin
  if v_actor is null or not public.admin_has_permission('supplier_settlements.execute') then
    raise exception 'Finance settlement execution permission is required';
  end if;
  if p_settlement_id is null
     or p_payment_method not in ('manual_bank_transfer','online_payment')
     or p_payment_method is null
     or p_amount is null or p_amount<=0
     or p_amount<>round(p_amount,2)
     or length(trim(coalesce(p_idempotency_key,'')))<12
     or length(p_idempotency_key)>200 then
    raise exception 'Invalid disbursement details';
  end if;
  if p_payment_method='manual_bank_transfer' then
    if length(trim(coalesce(p_payment_reference,'')))<3
       or length(trim(coalesce(p_evidence_path,'')))<3
       or p_provider_reference is not null then
      raise exception 'Manual bank transfer requires a bank reference and evidence path';
    end if;
  else
    if length(trim(coalesce(p_provider_reference,'')))<3
       or p_payment_reference is not null
       or p_evidence_path is not null then
      raise exception 'Online payment requires a provider reference; verification is performed separately';
    end if;
  end if;

  select * into v_settlement
  from public.frosttech_supplier_settlements
  where id=p_settlement_id
  for update;
  if not found then raise exception 'Settlement not found'; end if;

  -- Idempotency is checked before status validation so retries remain safe after payment.
  select id into v_disbursement_id
  from public.frosttech_supplier_disbursements
  where idempotency_key=trim(p_idempotency_key);
  if v_disbursement_id is not null then
    return v_disbursement_id;
  end if;

  if v_settlement.status not in ('approved','processing','partially_paid') then
    raise exception 'Only approved settlements may receive disbursement records';
  end if;

  if p_payment_method='manual_bank_transfer' then
    if (storage.foldername(trim(p_evidence_path)))[1] <> p_settlement_id::text
       or (storage.foldername(trim(p_evidence_path)))[2] <> v_actor::text
       or position('/' in trim(p_evidence_path)) = 0
       or exists (
         select 1 from public.frosttech_supplier_disbursements d
         where d.evidence_path = trim(p_evidence_path)
       )
       or not exists (
         select 1
         from storage.objects o
         where o.bucket_id='supplier-disbursement-evidence'
           and o.name=trim(p_evidence_path)
           and o.owner=v_actor
           and coalesce((o.metadata->>'size')::bigint,0) between 1 and 10485760
           and lower(coalesce(o.metadata->>'mimetype','')) in
             ('application/pdf','image/jpeg','image/png')
       ) then
      raise exception 'Evidence must be an existing supported file uploaded by you for this settlement';
    end if;
  end if;

  select coalesce(sum(amount),0) into v_reserved
  from public.frosttech_supplier_disbursements
  where settlement_id=p_settlement_id
    and status in ('pending','processing','successful');
  if v_reserved+p_amount>v_settlement.net_payable then
    raise exception 'Disbursement would exceed the remaining approved net payable';
  end if;

  insert into public.frosttech_supplier_disbursements(
    settlement_id,payment_method,amount,currency,payment_reference,
    provider_reference,idempotency_key,status,evidence_path,initiated_by
  ) values (
    p_settlement_id,p_payment_method,round(p_amount,2),'NGN',
    nullif(trim(coalesce(p_payment_reference,'')),''),
    nullif(trim(coalesce(p_provider_reference,'')),''),
    trim(p_idempotency_key),'pending',
    case when p_payment_method='manual_bank_transfer' then trim(p_evidence_path) else null end,
    v_actor
  ) returning id into v_disbursement_id;

  update public.frosttech_supplier_settlements
  set status='processing',updated_at=now()
  where id=p_settlement_id and status in ('approved','partially_paid');

  insert into public.admin_activity_log(actor_user_id,action,target_user_id,details)
  values(v_actor,'supplier_disbursement_recorded',null,
    jsonb_build_object('settlement_id',p_settlement_id,
      'disbursement_id',v_disbursement_id,'payment_method',p_payment_method,
      'amount',round(p_amount,2),'status','pending'));
  return v_disbursement_id;
end;
$function$;

create or replace function public.frosttech_verify_manual_supplier_disbursement(
  p_disbursement_id uuid,
  p_decision text,
  p_verification_note text
)
returns text
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor uuid := auth.uid();
  v_disbursement public.frosttech_supplier_disbursements%rowtype;
  v_paid numeric(14,2);
  v_open_count integer;
  v_new_status text;
begin
  if v_actor is null or not public.admin_has_permission('supplier_settlements.execute') then
    raise exception 'Finance settlement verification permission is required';
  end if;
  if p_disbursement_id is null
     or p_decision not in ('successful','failed')
     or p_decision is null
     or length(trim(coalesce(p_verification_note,'')))<5 then
    raise exception 'A valid decision and verification note are required';
  end if;

  select * into v_disbursement
  from public.frosttech_supplier_disbursements
  where id=p_disbursement_id
  for update;
  if not found then raise exception 'Disbursement not found'; end if;
  if v_disbursement.payment_method<>'manual_bank_transfer' then
    raise exception 'This workflow is only for manual bank transfers';
  end if;
  if v_disbursement.initiated_by=v_actor then
    raise exception 'The initiator cannot verify their own bank transfer';
  end if;
  if v_disbursement.status not in ('pending','processing') then
    if v_disbursement.status in ('successful','failed') then
      return v_disbursement.status;
    end if;
    raise exception 'Disbursement is not awaiting verification';
  end if;
  if length(trim(coalesce(v_disbursement.payment_reference,'')))<3
     or length(trim(coalesce(v_disbursement.evidence_path,'')))<3 then
    raise exception 'Bank reference and evidence path are required';
  end if;

  if (storage.foldername(v_disbursement.evidence_path))[1] <> v_disbursement.settlement_id::text
     or (storage.foldername(v_disbursement.evidence_path))[2] <> v_disbursement.initiated_by::text
     or not exists (
       select 1
       from storage.objects o
       where o.bucket_id='supplier-disbursement-evidence'
         and o.name=v_disbursement.evidence_path
         and o.owner=v_disbursement.initiated_by
         and coalesce((o.metadata->>'size')::bigint,0) between 1 and 10485760
         and lower(coalesce(o.metadata->>'mimetype','')) in
           ('application/pdf','image/jpeg','image/png')
     ) then
    raise exception 'The original bank-transfer evidence is missing or does not match this settlement';
  end if;

  update public.frosttech_supplier_disbursements
  set status=p_decision, verified_by=v_actor, verified_at=now(),
      failure_reason=case when p_decision='failed' then trim(p_verification_note) else null end,
      updated_at=now()
  where id=p_disbursement_id;

  select coalesce(sum(amount),0) into v_paid
  from public.frosttech_supplier_disbursements
  where settlement_id=v_disbursement.settlement_id and status='successful';
  select count(*) into v_open_count
  from public.frosttech_supplier_disbursements
  where settlement_id=v_disbursement.settlement_id and status in ('pending','processing');

  update public.frosttech_supplier_settlements
  set status=case
      when v_paid>=net_payable then 'paid'
      when v_paid>0 and v_open_count>0 then 'processing'
      when v_paid>0 then 'partially_paid'
      when v_open_count>0 then 'processing'
      else 'approved'
    end,
    updated_at=now()
  where id=v_disbursement.settlement_id;

  insert into public.admin_activity_log(actor_user_id,action,target_user_id,details)
  values(v_actor,'supplier_manual_disbursement_verified',null,
    jsonb_build_object('settlement_id',v_disbursement.settlement_id,
      'disbursement_id',p_disbursement_id,'decision',p_decision,
      'amount',v_disbursement.amount,'verification_note',trim(p_verification_note)));
  select status into v_new_status from public.frosttech_supplier_disbursements where id=p_disbursement_id;
  return v_new_status;
end;
$function$;

-- Keep the existing RPC grants unchanged; this migration does not grant new
-- function execution privileges or alter settlement/Finance permission mappings.
