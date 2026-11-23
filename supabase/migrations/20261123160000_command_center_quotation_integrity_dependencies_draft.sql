-- APPROVED ISOLATED-TEST MIGRATION
-- FrostTech quotation-integrity dependency layer for the isolated Operations workspace.
-- Target: gqnidjifiobhqhnxjlow ONLY, after the Operations schema migration.
-- This file contains no production connection, data copy, or account changes.
--
-- Dependency order:
--   1) 20261123150000_command_center_operations_workspace_draft.sql
--   2) this integrity dependency draft
--
-- The existing isolated-test suppliers table is referenced but never altered.
-- All original-request, quotation-version, alternative-proposal and supplier-quote
-- integrity triggers are recreated from read-only production definitions.
-- This migration is approved for isolated-test application only. Never apply to production.

begin;

-- The isolated test project does not yet contain the non-exposed private
-- schema used by the production environment-classification trigger.
create schema private authorization postgres;
revoke all on schema private from public, anon, authenticated, service_role;

do $preflight$
begin
  if to_regclass('public.quote_requests') is null
     or to_regclass('public.admin_quotations') is null
     or to_regclass('public.suppliers') is null
     or to_regclass('public.products') is null
     or to_regclass('public.profiles') is null
     or to_regclass('auth.users') is null
     or to_regnamespace('private') is null then
    raise exception 'Integrity dependency preflight failed: required Operations/test prerequisites are missing';
  end if;
  if to_regclass('public.supplier_quotes') is not null
     or to_regclass('public.alternative_proposals') is not null
     or to_regclass('public.alternative_proposal_decisions') is not null
     or to_regclass('public.admin_quotation_items') is not null
     or to_regclass('public.quote_request_original_snapshots') is not null
     or to_regclass('public.quote_request_integrity_audit') is not null then
    raise exception 'Integrity dependency preflight failed: one or more dependency tables already exist; inspect before adapting';
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='suppliers' and column_name='id' and udt_name='uuid'
  ) or not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='suppliers' and column_name='user_id' and udt_name='uuid'
  ) or not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='suppliers' and column_name='is_verified' and udt_name='bool'
  ) or not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='suppliers' and column_name='is_active' and udt_name='bool'
  ) then
    raise exception 'Integrity dependency preflight failed: isolated suppliers table shape differs from reviewed prerequisites';
  end if;
end;
$preflight$;

-- Supplier quotation source. Existing test suppliers table is referenced only.
create table public.supplier_quotes (
  id uuid primary key default gen_random_uuid(),
  request_id uuid null references public.quote_requests(id) on delete cascade,
  supplier_id uuid null references public.suppliers(id) on delete set null,
  product_id uuid null references public.products(id) on delete set null,
  quantity integer not null default 1,
  supplier_unit_price numeric not null default 0,
  supplier_total numeric not null default 0,
  delivery_cost numeric not null default 0,
  notes text null,
  valid_until timestamptz null,
  status text not null default 'submitted',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  frosttech_margin_percent numeric null default 15,
  frosttech_margin_amount numeric null default 0,
  customer_total numeric null default 0,
  customer_quote_status text null default 'draft',
  constraint supplier_quotes_status_check
    check (status in ('draft','submitted','selected','rejected','expired'))
);
create index idx_quotes_request on public.supplier_quotes(request_id);
create index idx_quotes_supplier on public.supplier_quotes(supplier_id);
alter table public.supplier_quotes enable row level security;

-- Immutable original request snapshot and append-only integrity audit.
create table public.quote_request_original_snapshots (
  request_id uuid primary key references public.quote_requests(id) on delete restrict,
  original_payload jsonb not null,
  payload_hash text not null,
  capture_type text not null,
  captured_at timestamptz not null default now(),
  constraint quote_request_original_snapshots_original_payload_check
    check (jsonb_typeof(original_payload)='object'),
  constraint quote_request_original_snapshots_capture_type_check
    check (capture_type in ('submitted_original','rollout_baseline_unverified'))
);
create table public.quote_request_integrity_audit (
  id bigint generated always as identity primary key,
  request_id uuid not null references public.quote_requests(id) on delete restrict,
  proposal_id uuid null,
  actor_type text not null,
  actor_id uuid null,
  event_type text not null,
  event_details jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now(),
  constraint quote_request_integrity_audit_actor_type_check
    check (actor_type in ('customer','supplier','frosttech','system')),
  constraint quote_request_integrity_audit_event_details_check
    check (jsonb_typeof(event_details)='object')
);
create index quote_integrity_audit_request_idx
  on public.quote_request_integrity_audit(request_id, occurred_at desc);
alter table public.quote_request_original_snapshots enable row level security;
alter table public.quote_request_integrity_audit enable row level security;

-- Alternatives and their customer decisions.
create table public.alternative_proposals (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.quote_requests(id) on delete restrict,
  proposer_type text not null,
  proposer_user_id uuid not null references auth.users(id) on delete restrict,
  supplier_id uuid null references public.suppliers(id) on delete restrict,
  version_number integer not null,
  reason text not null,
  proposed_payload jsonb not null,
  commercial_terms jsonb not null default '{}'::jsonb,
  submitted_at timestamptz not null default now(),
  differences jsonb not null default '{}'::jsonb,
  supplier_quote_id uuid null references public.supplier_quotes(id) on delete restrict,
  admin_quotation_id uuid null references public.admin_quotations(id) on delete restrict,
  constraint alternative_proposals_proposer_type_check
    check (proposer_type in ('supplier','frosttech')),
  constraint alternative_proposals_reason_check
    check (length(btrim(reason)) >= 5),
  constraint alternative_proposals_version_number_check
    check (version_number > 0),
  constraint alternative_proposals_proposed_payload_check
    check (jsonb_typeof(proposed_payload)='object'),
  constraint alternative_proposals_commercial_terms_check
    check (jsonb_typeof(commercial_terms)='object'),
  constraint alternative_proposals_differences_check
    check (jsonb_typeof(differences)='object'),
  constraint alternative_proposals_actor_consistency
    check ((proposer_type='supplier' and supplier_id is not null)
        or (proposer_type='frosttech' and supplier_id is null)),
  constraint alternative_proposal_linkage_check
    check ((proposer_type='supplier' and supplier_id is not null
            and supplier_quote_id is not null and admin_quotation_id is null)
        or (proposer_type='frosttech' and supplier_id is null
            and supplier_quote_id is null and admin_quotation_id is not null)),
  constraint alternative_proposals_id_request_unique unique(id,request_id),
  constraint alternative_proposals_version_unique
    unique(request_id,proposer_type,proposer_user_id,version_number)
);
create index alternative_proposals_request_idx
  on public.alternative_proposals(request_id,submitted_at desc);
create index alternative_proposals_supplier_quote_idx
  on public.alternative_proposals(supplier_quote_id);
alter table public.alternative_proposals enable row level security;

create table public.alternative_proposal_decisions (
  id uuid primary key default gen_random_uuid(),
  proposal_id uuid not null,
  request_id uuid not null,
  decision text not null,
  decision_reason text null,
  decided_by uuid null references auth.users(id) on delete restrict,
  decided_at timestamptz not null default now(),
  decision_channel text not null default 'authenticated_customer',
  guest_email_normalized text null,
  constraint alternative_proposal_decisions_proposal_request_fk
    foreign key(proposal_id,request_id)
    references public.alternative_proposals(id,request_id) on delete restrict,
  constraint alternative_proposal_decisions_decision_check
    check (decision in ('accepted','rejected')),
  constraint alternative_proposal_decisions_decision_channel_check
    check (decision_channel in ('authenticated_customer','verified_guest_otp')),
  constraint alternative_decision_actor_channel_check
    check ((decision_channel='authenticated_customer' and decided_by is not null and guest_email_normalized is null)
        or (decision_channel='verified_guest_otp' and decided_by is null and guest_email_normalized is not null)),
  constraint alternative_decisions_one_per_proposal unique(proposal_id)
);
create unique index alternative_one_accepted_per_request
  on public.alternative_proposal_decisions(request_id) where decision='accepted';
alter table public.alternative_proposal_decisions enable row level security;

-- Structured quotation line items.
create table public.admin_quotation_items (
  id uuid primary key default gen_random_uuid(),
  quotation_id uuid not null references public.admin_quotations(id) on delete restrict,
  item_type text not null default 'product',
  product_id uuid null references public.products(id) on delete set null,
  description text not null,
  specifications jsonb not null default '{}'::jsonb,
  unit text not null default 'unit',
  quantity numeric not null default 1,
  unit_price numeric not null,
  line_total numeric not null,
  sort_order integer not null default 0,
  source_proposal_id uuid null references public.alternative_proposals(id) on delete restrict,
  replaces_item_id uuid null references public.admin_quotation_items(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint admin_quotation_items_type_check
    check (item_type in ('product','service','accessory','installation','delivery','other')),
  constraint admin_quotation_items_description_check check (length(btrim(description))>0),
  constraint admin_quotation_items_specifications_object check (jsonb_typeof(specifications)='object'),
  constraint admin_quotation_items_unit_check check (length(btrim(unit))>0),
  constraint admin_quotation_items_quantity_check check (quantity>0),
  constraint admin_quotation_items_unit_price_check check (unit_price>=0),
  constraint admin_quotation_items_line_total_check check (line_total>=0),
  constraint admin_quotation_items_sort_order_check check (sort_order>=0)
);
create index admin_quotation_items_quote_order_idx
  on public.admin_quotation_items(quotation_id,sort_order,created_at);
create index admin_quotation_items_source_proposal_idx
  on public.admin_quotation_items(source_proposal_id);
alter table public.admin_quotation_items enable row level security;

-- Composite integrity relationship added after both sides exist.
alter table public.quote_request_integrity_audit
  add constraint quote_integrity_audit_proposal_request_fk
  foreign key(proposal_id,request_id)
  references public.alternative_proposals(id,request_id) on delete restrict;

-- Production helper functions used by the production RLS boundaries.
create or replace function public.frosttech_customer_owns_quote_request_v1(p_request_id uuid)
returns boolean language sql stable security definer set search_path=''
as $function$
  select exists (
    select 1 from public.quote_requests q
    join public.profiles p on p.id=q.customer_id
    where q.id=p_request_id and q.customer_id=auth.uid()
      and p.role='customer' and p.is_active=true
  );
$function$;

create or replace function public.frosttech_request_original_payload_v1(p public.quote_requests)
returns jsonb language sql immutable set search_path=''
as $function$
  select jsonb_build_object(
    'customer_id',p.customer_id,'customer_name',p.customer_name,
    'customer_email',p.customer_email,'customer_phone',p.customer_phone,
    'product_id',p.product_id,'request_number',p.request_number,
    'title',p.title,'description',p.description,'quantity',p.quantity,
    'preferred_brand',p.preferred_brand,'budget',p.budget,
    'delivery_address',p.delivery_address,
    'installation_kit_quantity',p.installation_kit_quantity,
    'installation_service',p.installation_service,
    'outdoor_bracket_quantity',p.outdoor_bracket_quantity,
    'created_at',p.created_at
  );
$function$;

create or replace function public.frosttech_guard_integrity_append_only_v1()
returns trigger language plpgsql set search_path=''
as $function$
begin
  raise exception 'This integrity record is permanent and cannot be changed or deleted';
end;
$function$;

create or replace function public.frosttech_capture_quote_request_original_v1()
returns trigger language plpgsql security definer set search_path=''
as $function$
declare v_payload jsonb;
begin
  v_payload:=public.frosttech_request_original_payload_v1(new);
  insert into public.quote_request_original_snapshots(request_id,original_payload,payload_hash,capture_type)
  values(new.id,v_payload,md5(v_payload::text),'submitted_original')
  on conflict(request_id) do nothing;
  insert into public.quote_request_integrity_audit(request_id,actor_type,actor_id,event_type,event_details)
  values(new.id,'system',auth.uid(),'original_request_captured',
    jsonb_build_object('capture_type','submitted_original','payload_hash',md5(v_payload::text)));
  return new;
end;
$function$;

create or replace function public.frosttech_guard_quote_request_original_v1()
returns trigger language plpgsql set search_path=''
as $function$
begin
  if row(new.customer_id,new.product_id,new.request_number,new.title,new.description,
    new.quantity,new.preferred_brand,new.budget,new.delivery_address,
    new.customer_name,new.customer_email,new.customer_phone,
    new.installation_kit_quantity,new.installation_service,new.outdoor_bracket_quantity,new.created_at)
    is distinct from
    row(old.customer_id,old.product_id,old.request_number,old.title,old.description,
    old.quantity,old.preferred_brand,old.budget,old.delivery_address,
    old.customer_name,old.customer_email,old.customer_phone,
    old.installation_kit_quantity,old.installation_service,old.outdoor_bracket_quantity,old.created_at)
  then raise exception 'Original customer request details are immutable. Submit a separately identified alternative proposal instead.';
  end if;
  return new;
end;
$function$;

create or replace function public.frosttech_block_quote_request_delete_v1()
returns trigger language plpgsql set search_path=''
as $function$
begin
  raise exception 'Original customer requests cannot be deleted; preserve the request and its history.';
end;
$function$;

create or replace function private.frosttech_guard_environment_classification_v1()
returns trigger language plpgsql set search_path=''
as $function$
declare v_jwt_role text;
begin
  v_jwt_role:=coalesce(auth.jwt()->>'role','');
  if v_jwt_role<>'service_role' then
    if tg_op='INSERT' and new.environment is distinct from 'development' then
      raise exception 'Only a trusted server operation may assign production environment.';
    end if;
    if tg_op='UPDATE' and new.environment is distinct from old.environment then
      raise exception 'Only a trusted server operation may change environment classification.';
    end if;
  end if;
  return new;
end;
$function$;

create or replace function public.admin_quotation_assign_number()
returns trigger language plpgsql security definer set search_path=''
as $function$
begin
  if new.quotation_number is null or btrim(new.quotation_number)='' then
    new.quotation_number:='FT-Q-'||
      (extract(epoch from clock_timestamp())*1000)::bigint::text||'-'||
      upper(substr(replace(gen_random_uuid()::text,'-',''),1,4));
  end if;
  return new;
end;
$function$;

create or replace function public.frosttech_guard_quotation_version_scope_v2()
returns trigger language plpgsql security definer set search_path=''
as $function$
begin
  if tg_op='DELETE' then
    if old.status<>'draft' then
      raise exception 'Submitted quotation versions are permanent records and cannot be deleted';
    end if;
    return old;
  end if;
  if old.status<>'draft' and new.status='draft' then
    raise exception 'A submitted quotation version cannot be reopened as a draft. Create a new version.';
  end if;
  if old.status<>'draft' and (
    new.request_id is distinct from old.request_id or new.customer_id is distinct from old.customer_id
    or new.product_description is distinct from old.product_description
    or new.quantity is distinct from old.quantity or new.unit_price is distinct from old.unit_price
    or new.delivery_cost is distinct from old.delivery_cost
    or new.additional_charges is distinct from old.additional_charges
    or new.discount is distinct from old.discount or new.validity_date is distinct from old.validity_date
    or new.notes is distinct from old.notes or new.version_group_id is distinct from old.version_group_id
    or new.version_number is distinct from old.version_number
    or new.supersedes_quotation_id is distinct from old.supersedes_quotation_id
    or new.quotation_scope_snapshot is distinct from old.quotation_scope_snapshot
    or new.submitted_scope_snapshot is distinct from old.submitted_scope_snapshot
  ) then raise exception 'Submitted quotation versions are immutable. Create a new quotation version.';
  end if;
  if old.approved_scope_snapshot is not null
     and new.approved_scope_snapshot is distinct from old.approved_scope_snapshot then
    raise exception 'The customer-approved quotation snapshot is immutable.';
  end if;
  return new;
end;
$function$;

create or replace function public.frosttech_guard_cross_quotation_acceptance_v1()
returns trigger language plpgsql set search_path=''
as $function$
declare v_linked_proposal uuid;
begin
  if tg_table_name='admin_quotations' then
    if new.customer_decision is distinct from old.customer_decision
       and lower(coalesce(new.customer_decision,''))='accepted' then
      perform 1 from public.quote_requests where id=new.request_id for update;
      if exists(select 1 from public.admin_quotations q where q.request_id=new.request_id
        and q.id<>new.id and lower(coalesce(q.customer_decision,''))='accepted') then
        raise exception 'Another quotation version has already been accepted for this customer request.';
      end if;
      select d.proposal_id into v_linked_proposal
      from public.alternative_proposal_decisions d
      where d.request_id=new.request_id and d.decision='accepted';
      if v_linked_proposal is not null and not exists(
        select 1 from public.admin_quotation_items i
        where i.quotation_id=new.id and i.source_proposal_id=v_linked_proposal
      ) then
        raise exception 'The accepted alternative must be included in the quotation version before acceptance.';
      end if;
    end if;
    return new;
  end if;
  if tg_table_name='alternative_proposal_decisions' and new.decision='accepted' then
    perform 1 from public.quote_requests where id=new.request_id for update;
    if exists(select 1 from public.admin_quotations q where q.request_id=new.request_id
      and lower(coalesce(q.customer_decision,''))='accepted') then
      raise exception 'A FrostTech quotation has already been accepted for this request. A separate alternative cannot also be accepted.';
    end if;
  end if;
  return new;
end;
$function$;

create or replace function public.frosttech_guard_quotation_scope_immutable_v2()
returns trigger language plpgsql security definer set search_path=''
as $function$
begin
  if tg_op='DELETE' then
    if exists(select 1 from public.admin_quotations q where q.id=old.quotation_id and q.status<>'draft') then
      raise exception 'Submitted quotation items are immutable. Create a new quotation version.';
    end if;
    return old;
  end if;
  if exists(select 1 from public.admin_quotations q where q.id=new.quotation_id and q.status<>'draft') then
    raise exception 'Submitted quotation items are immutable. Create a new quotation version.';
  end if;
  if tg_op='UPDATE' and old.quotation_id is distinct from new.quotation_id
    and exists(select 1 from public.admin_quotations q where q.id=old.quotation_id and q.status<>'draft') then
    raise exception 'Submitted quotation items cannot be moved to another quotation.';
  end if;
  return new;
end;
$function$;

create or replace function public.calculate_frosttech_supplier_quote()
returns trigger language plpgsql set search_path=''
as $function$
begin
  if new.quantity is null or new.quantity<1 then raise exception 'Quantity must be at least 1'; end if;
  if new.supplier_unit_price is null or new.supplier_unit_price<0 then raise exception 'Supplier unit price cannot be negative'; end if;
  if new.delivery_cost is null or new.delivery_cost<0 then raise exception 'Delivery cost cannot be negative'; end if;
  new.supplier_total:=round(new.supplier_unit_price*new.quantity,2);
  new.frosttech_margin_percent:=0;
  new.frosttech_margin_amount:=0;
  new.customer_total:=null;
  return new;
end;
$function$;

create or replace function public.frosttech_prepare_alternative_payload_v1()
returns trigger language plpgsql security definer set search_path=''
as $function$
declare v_original jsonb; v_complete jsonb; v_linked_product_id uuid; v_submitted boolean;
begin
  select s.original_payload-array['customer_id','customer_name','customer_email','customer_phone','budget','delivery_address']::text[]
  into v_original from public.quote_request_original_snapshots s where s.request_id=new.request_id;
  if v_original is null then raise exception 'Original customer request snapshot is missing'; end if;
  if exists(select 1 from jsonb_object_keys(new.proposed_payload) as x(key)
    where x.key not in ('product_id','request_number','title','description','quantity',
      'preferred_brand','installation_kit_quantity','installation_service','outdoor_bracket_quantity')) then
    raise exception 'Alternative payload contains a protected or unsupported field';
  end if;
  if new.proposer_type='supplier' then
    select sq.product_id,(sq.status='submitted') into v_linked_product_id,v_submitted
    from public.supplier_quotes sq where sq.id=new.supplier_quote_id
      and sq.request_id=new.request_id and sq.supplier_id=new.supplier_id;
    if not found or v_submitted is distinct from true then
      raise exception 'Supplier alternative must reference the supplier''s submitted quotation for this request';
    end if;
    if not (new.proposed_payload?'product_id') then
      raise exception 'Supplier alternative must explicitly identify its catalogue product reference or mark it as unlisted';
    end if;
    if nullif(new.proposed_payload->>'product_id','')::uuid is distinct from v_linked_product_id then
      raise exception 'Alternative product reference must match the linked supplier quotation';
    end if;
  end if;
  v_complete:=v_original||new.proposed_payload;
  select coalesce(jsonb_object_agg(x.key,jsonb_build_object('original',v_original->x.key,'proposed',x.value)),'{}'::jsonb)
    into new.differences from jsonb_each(v_complete) as x(key,value)
    where v_original->x.key is distinct from x.value;
  new.proposed_payload:=v_complete;
  return new;
end;
$function$;

create or replace function public.frosttech_enrich_alternative_audit_v1()
returns trigger language plpgsql security definer set search_path=''
as $function$
declare v_differences jsonb;
begin
  if new.event_type='alternative_proposal_submitted' and new.proposal_id is not null then
    select a.differences into v_differences from public.alternative_proposals a
    where a.id=new.proposal_id and a.request_id=new.request_id;
    if v_differences is null then raise exception 'Alternative proposal audit reference could not be verified'; end if;
    new.event_details:=new.event_details||jsonb_build_object('differences',v_differences);
  end if;
  return new;
end;
$function$;

-- Recreate the production trigger graph.
create trigger frosttech_guard_quote_requests_environment_v1
before insert or update of environment on public.quote_requests
for each row execute function private.frosttech_guard_environment_classification_v1();
create trigger frosttech_capture_quote_request_original_v1
after insert on public.quote_requests
for each row execute function public.frosttech_capture_quote_request_original_v1();
create trigger frosttech_guard_quote_request_original_v1
before update on public.quote_requests
for each row execute function public.frosttech_guard_quote_request_original_v1();
create trigger frosttech_block_quote_request_delete_v1
before delete on public.quote_requests
for each row execute function public.frosttech_block_quote_request_delete_v1();
create trigger trg_admin_quotation_assign_number
before insert on public.admin_quotations
for each row execute function public.admin_quotation_assign_number();
create trigger admin_quotations_scope_immutable_v2
before update on public.admin_quotations
for each row execute function public.frosttech_guard_quotation_version_scope_v2();
create trigger frosttech_guard_admin_quote_acceptance_v1
before update of customer_decision on public.admin_quotations
for each row execute function public.frosttech_guard_cross_quotation_acceptance_v1();
create trigger frosttech_supplier_quote_pricing
before insert or update of quantity,supplier_unit_price,delivery_cost on public.supplier_quotes
for each row execute function public.calculate_frosttech_supplier_quote();
create trigger frosttech_prepare_alternative_payload_v1
before insert on public.alternative_proposals
for each row execute function public.frosttech_prepare_alternative_payload_v1();
create trigger alternative_proposals_append_only
before update or delete on public.alternative_proposals
for each row execute function public.frosttech_guard_integrity_append_only_v1();
create trigger alternative_decisions_append_only
before update or delete on public.alternative_proposal_decisions
for each row execute function public.frosttech_guard_integrity_append_only_v1();
create trigger frosttech_guard_alternative_acceptance_v1
before insert on public.alternative_proposal_decisions
for each row execute function public.frosttech_guard_cross_quotation_acceptance_v1();
create trigger frosttech_enrich_alternative_audit_v1
before insert on public.quote_request_integrity_audit
for each row execute function public.frosttech_enrich_alternative_audit_v1();
create trigger quote_request_integrity_audit_append_only
before update or delete on public.quote_request_integrity_audit
for each row execute function public.frosttech_guard_integrity_append_only_v1();
create trigger quote_request_snapshots_append_only
before update or delete on public.quote_request_original_snapshots
for each row execute function public.frosttech_guard_integrity_append_only_v1();
create trigger admin_quotation_items_scope_immutable_v2
before insert or update or delete on public.admin_quotation_items
for each row execute function public.frosttech_guard_quotation_scope_immutable_v2();

-- Preserve production RLS policy boundaries.
create policy supplier_quotes_select_own_approved on public.supplier_quotes
for select to authenticated using (
  exists(select 1 from public.suppliers s where s.id=supplier_quotes.supplier_id
    and s.user_id=(select auth.uid()) and s.is_verified=true and s.is_active=true)
);
create policy supplier_quotes_insert_own_approved on public.supplier_quotes
for insert to authenticated with check (
  exists(select 1 from public.suppliers s where s.id=supplier_quotes.supplier_id
    and s.user_id=(select auth.uid()) and s.is_verified=true and s.is_active=true)
);
create policy "Admins can manage supplier quotations" on public.supplier_quotes
for all to authenticated using (public.is_super_admin()) with check (public.is_super_admin());

create policy alternative_proposals_customer_supplier_manager_read on public.alternative_proposals
for select to authenticated using (
  public.frosttech_customer_owns_quote_request_v1(request_id)
  or proposer_user_id=auth.uid()
  or public.frosttech_can_manage_customer_requests_v1()
);
create policy alternative_decisions_customer_or_manager_read on public.alternative_proposal_decisions
for select to authenticated using (
  public.frosttech_customer_owns_quote_request_v1(request_id)
  or public.frosttech_can_manage_customer_requests_v1()
);
create policy quote_original_snapshot_customer_or_manager_read on public.quote_request_original_snapshots
for select to authenticated using (
  public.frosttech_customer_owns_quote_request_v1(request_id)
  or public.frosttech_can_manage_customer_requests_v1()
);
create policy quote_integrity_audit_manager_read on public.quote_request_integrity_audit
for select to authenticated using (public.frosttech_can_manage_customer_requests_v1());
create policy admin_quotation_items_admin_manage on public.admin_quotation_items
for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy admin_quotation_items_customer_read on public.admin_quotation_items
for select to authenticated using (
  exists(select 1 from public.admin_quotations q where q.id=admin_quotation_items.quotation_id
    and (q.customer_id=auth.uid() or public.frosttech_can_manage_customer_requests_v1()))
);

-- Explicit table grants follow the inspected production model.
-- No direct authenticated/anon access to alternative proposals, decisions or snapshots.
revoke all on public.supplier_quotes from public,anon;
revoke all on public.alternative_proposals,public.alternative_proposal_decisions,
  public.quote_request_original_snapshots from public,anon,authenticated;
revoke all on public.quote_request_integrity_audit from public,anon,authenticated;
revoke all on public.admin_quotation_items from public;
grant all privileges on public.supplier_quotes to authenticated;
grant select on public.quote_request_integrity_audit to authenticated;
grant all privileges on public.admin_quotation_items to anon,authenticated;

-- Trigger functions are not client RPC endpoints.
revoke all on function public.frosttech_capture_quote_request_original_v1() from public,anon,authenticated;
revoke all on function public.frosttech_guard_quote_request_original_v1() from public,anon,authenticated;
revoke all on function public.frosttech_block_quote_request_delete_v1() from public,anon,authenticated;
revoke all on function private.frosttech_guard_environment_classification_v1() from public,anon,authenticated;
revoke all on function public.admin_quotation_assign_number() from public,anon,authenticated;
revoke all on function public.frosttech_guard_quotation_version_scope_v2() from public,anon,authenticated;
revoke all on function public.frosttech_guard_cross_quotation_acceptance_v1() from public,anon,authenticated;
revoke all on function public.frosttech_guard_quotation_scope_immutable_v2() from public,anon,authenticated;
revoke all on function public.calculate_frosttech_supplier_quote() from public,anon,authenticated;
revoke all on function public.frosttech_prepare_alternative_payload_v1() from public,anon,authenticated;
revoke all on function public.frosttech_enrich_alternative_audit_v1() from public,anon,authenticated;
revoke all on function public.frosttech_guard_integrity_append_only_v1() from public,anon,authenticated;
revoke all on function public.frosttech_request_original_payload_v1(public.quote_requests) from public,anon,authenticated;
revoke all on function public.frosttech_customer_owns_quote_request_v1(uuid) from public,anon;
grant execute on function public.frosttech_customer_owns_quote_request_v1(uuid) to authenticated;

commit;
