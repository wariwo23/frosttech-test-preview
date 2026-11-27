-- FrostTech Command Center: Finance workspace dependencies
-- ISOLATED TEST DATABASE ONLY.
-- Draft migration for review. Do not apply to production.
-- Reconciled against production function definitions, table metadata, RLS policies,
-- constraints, indexes, triggers and grants on 2026-11-23.
--
-- Preserves the finance workflow:
--   * Finance operators may read authorised financial reports and submit actual costs.
--   * Only the active Super Administrator may approve/reject cost submissions.
--   * Submitter self-approval is blocked.
--   * Approved snapshots and audit history are immutable.
--   * Cost approval does not alter the customer's quotation price/payment state.
--   * Payment reconciliation is production Paystack/NGN/receipt matched only.

begin;

-- The isolated test private schema is deliberately closed by default.
-- Grant namespace lookup only; individual private functions remain separately ACL-controlled.
grant usage on schema private to authenticated;

do $preflight$
begin
  if to_regclass('public.admin_quotations') is null
     or to_regclass('public.payments') is null
     or to_regclass('public.payment_receipts') is null
     or to_regclass('public.admin_accounts') is null
     or to_regclass('public.profiles') is null
     or to_regprocedure('public.admin_has_permission(text)') is null then
    raise exception 'Finance migration preflight failed: required test dependencies are missing.';
  end if;
  if not exists (select 1 from pg_namespace where nspname = 'private') then
    raise exception 'Finance migration preflight failed: private schema is missing.';
  end if;
end;
$preflight$;

-- Define the private Super Admin predicate before policies reference it.
create or replace function private.is_active_super_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.admin_accounts aa
    join public.profiles p on p.id = aa.user_id
    where aa.user_id = (select auth.uid())
      and aa.role = 'super_admin'
      and aa.is_active is true
      and p.role = 'admin'
      and p.is_active is true
  );
$function$;
revoke all on function private.is_active_super_admin() from public, anon;
grant execute on function private.is_active_super_admin() to authenticated, service_role;

-- Receipt voids are required for reconciliation to exclude voided receipts.
create table if not exists public.payment_receipt_voids (
  id uuid primary key default gen_random_uuid(),
  receipt_id uuid not null references public.payment_receipts(id) on delete restrict,
  reason text not null check (length(trim(reason)) >= 5),
  voided_by uuid not null references auth.users(id) on delete restrict,
  voided_at timestamptz not null default now(),
  constraint payment_receipt_voids_receipt_id_key unique (receipt_id)
);
alter table public.payment_receipt_voids enable row level security;
revoke all on public.payment_receipt_voids from public, anon, authenticated;
grant all on public.payment_receipt_voids to service_role;
drop policy if exists frosttech_service_manage_receipt_voids on public.payment_receipt_voids;
create policy frosttech_service_manage_receipt_voids
  on public.payment_receipt_voids for all to service_role
  using (true) with check (true);

create or replace function public.frosttech_prevent_receipt_void_changes()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  raise exception 'Receipt void records are append-only and cannot be changed or deleted.';
end;
$function$;
revoke all on function public.frosttech_prevent_receipt_void_changes() from public, anon, authenticated;
drop trigger if exists frosttech_receipt_void_immutable_trigger on public.payment_receipt_voids;
create trigger frosttech_receipt_void_immutable_trigger
before delete or update on public.payment_receipt_voids
for each row execute function public.frosttech_prevent_receipt_void_changes();

-- Cost submission records are visible to their submitter and Super Admin only.
create table if not exists public.quotation_cost_submissions (
  id uuid primary key default gen_random_uuid(),
  quotation_id uuid not null references public.admin_quotations(id) on delete restrict,
  submitted_by uuid not null references auth.users(id) on delete restrict,
  status text not null default 'pending_approval'
    check (status in ('pending_approval','approved','rejected')),
  actual_cost_subtotal numeric(14,2) not null
    check (actual_cost_subtotal > 0 and actual_cost_subtotal::text not in ('NaN','Infinity','-Infinity')),
  markup_rate numeric(8,4) not null
    check (markup_rate >= 0 and markup_rate::text not in ('NaN','Infinity','-Infinity')),
  markup_amount numeric(14,2) not null
    check (markup_amount >= 0 and markup_amount::text not in ('NaN','Infinity','-Infinity')),
  discount_amount numeric(14,2) not null default 0
    check (discount_amount >= 0 and discount_amount::text not in ('NaN','Infinity','-Infinity')),
  delivery_customer_charge numeric(14,2) not null default 0
    check (delivery_customer_charge >= 0 and delivery_customer_charge::text not in ('NaN','Infinity','-Infinity')),
  actual_delivery_cost numeric(14,2)
    check (actual_delivery_cost is null or (actual_delivery_cost >= 0 and actual_delivery_cost::text not in ('NaN','Infinity','-Infinity'))),
  selling_value_before_delivery numeric(14,2) not null
    check (selling_value_before_delivery >= 0 and selling_value_before_delivery::text not in ('NaN','Infinity','-Infinity')),
  breakdown jsonb not null default '{}'::jsonb check (jsonb_typeof(breakdown) = 'object'),
  notes text,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  review_notes text,
  submitted_at timestamptz not null default now(),
  constraint quotation_cost_discount_cap check (discount_amount <= actual_cost_subtotal + markup_amount),
  constraint quotation_cost_review_state check (
    (status = 'pending_approval' and reviewed_by is null and reviewed_at is null)
    or (status in ('approved','rejected') and reviewed_by is not null and reviewed_at is not null)
  )
);
create index if not exists quotation_cost_submission_quotation_idx
  on public.quotation_cost_submissions(quotation_id);
create index if not exists quotation_cost_submission_user_idx
  on public.quotation_cost_submissions(submitted_by);
create unique index if not exists quotation_cost_one_pending_idx
  on public.quotation_cost_submissions(quotation_id) where status = 'pending_approval';
alter table public.quotation_cost_submissions enable row level security;
revoke all on public.quotation_cost_submissions from public, anon;
grant select on public.quotation_cost_submissions to authenticated;
grant all on public.quotation_cost_submissions to service_role;
drop policy if exists quotation_cost_submission_select on public.quotation_cost_submissions;
create policy quotation_cost_submission_select
  on public.quotation_cost_submissions for select to authenticated
  using (
    private.is_active_super_admin()
    or (submitted_by = (select auth.uid())
        and public.admin_has_permission('quotations.costs.submit'))
  );

-- Immutable approved financial snapshots.
create table if not exists public.quotation_cost_snapshots (
  id uuid primary key default gen_random_uuid(),
  submission_id uuid not null references public.quotation_cost_submissions(id) on delete restrict,
  quotation_id uuid not null references public.admin_quotations(id) on delete restrict,
  version_number integer not null check (version_number > 0),
  actual_cost_subtotal numeric(14,2) not null,
  markup_rate numeric(8,4) not null,
  markup_amount numeric(14,2) not null,
  discount_amount numeric(14,2) not null,
  delivery_customer_charge numeric(14,2) not null,
  actual_delivery_cost numeric(14,2),
  selling_value_before_delivery numeric(14,2) not null,
  captured_by uuid not null references auth.users(id) on delete restrict,
  captured_at timestamptz not null default now(),
  constraint quotation_cost_snapshots_quotation_version_key unique (quotation_id,version_number),
  constraint quotation_cost_snapshots_submission_key unique (submission_id)
);
create index if not exists quotation_cost_snapshot_quotation_idx
  on public.quotation_cost_snapshots(quotation_id);
alter table public.quotation_cost_snapshots enable row level security;
revoke all on public.quotation_cost_snapshots from public, anon;
grant select on public.quotation_cost_snapshots to authenticated;
grant all on public.quotation_cost_snapshots to service_role;
drop policy if exists quotation_cost_snapshot_select on public.quotation_cost_snapshots;
create policy quotation_cost_snapshot_select
  on public.quotation_cost_snapshots for select to authenticated
  using (
    private.is_active_super_admin()
    or public.admin_has_permission('quotations.read_financial')
  );

-- Append-only approval/rejection history. Only Super Admin can read it.
create table if not exists public.quotation_cost_approval_audit (
  id uuid primary key default gen_random_uuid(),
  submission_id uuid not null references public.quotation_cost_submissions(id) on delete restrict,
  action text not null check (action in ('submitted','approved','rejected')),
  previous_values jsonb,
  new_values jsonb not null,
  changed_by uuid references auth.users(id) on delete set null,
  changed_at timestamptz not null default now()
);
create index if not exists quotation_cost_audit_date_idx
  on public.quotation_cost_approval_audit(changed_at);
create index if not exists quotation_cost_audit_submission_idx
  on public.quotation_cost_approval_audit(submission_id);
alter table public.quotation_cost_approval_audit enable row level security;
revoke all on public.quotation_cost_approval_audit from public, anon;
grant select on public.quotation_cost_approval_audit to authenticated;
grant all on public.quotation_cost_approval_audit to service_role;
drop policy if exists quotation_cost_audit_select on public.quotation_cost_approval_audit;
create policy quotation_cost_audit_select
  on public.quotation_cost_approval_audit for select to authenticated
  using (private.is_active_super_admin());

-- Production-equivalent private authorisation and immutable-record guards.
create or replace function private.is_active_super_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.admin_accounts aa
    join public.profiles p on p.id = aa.user_id
    where aa.user_id = (select auth.uid())
      and aa.role = 'super_admin'
      and aa.is_active is true
      and p.role = 'admin'
      and p.is_active is true
  );
$function$;
revoke all on function private.is_active_super_admin() from public, anon;
grant execute on function private.is_active_super_admin() to authenticated, service_role;

create or replace function private.prevent_quotation_financial_mutation()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  raise exception 'Approved financial snapshots and audit history cannot be changed or deleted.';
end;
$function$;
revoke all on function private.prevent_quotation_financial_mutation() from public, anon, authenticated;

create or replace function private.prevent_quotation_cost_self_approval()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if new.status = 'approved'
     and new.submitted_by is not null
     and new.reviewed_by = new.submitted_by then
    raise exception 'A quotation cost submission cannot be approved by its submitter.';
  end if;
  return new;
end;
$function$;
revoke all on function private.prevent_quotation_cost_self_approval() from public, anon, authenticated;

drop trigger if exists quotation_cost_audit_immutable on public.quotation_cost_approval_audit;
create trigger quotation_cost_audit_immutable
before delete or update on public.quotation_cost_approval_audit
for each row execute function private.prevent_quotation_financial_mutation();

drop trigger if exists quotation_cost_snapshot_immutable on public.quotation_cost_snapshots;
create trigger quotation_cost_snapshot_immutable
before delete or update on public.quotation_cost_snapshots
for each row execute function private.prevent_quotation_financial_mutation();

drop trigger if exists quotation_cost_self_approval_guard on public.quotation_cost_submissions;
create trigger quotation_cost_self_approval_guard
before insert or update on public.quotation_cost_submissions
for each row execute function private.prevent_quotation_cost_self_approval();

-- Finance reporting RPCs: production-only Paystack/NGN reconciliation.
create or replace function public.finance_get_summary(p_start_date date, p_end_date date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare v jsonb;
begin
  if auth.uid() is null or not public.admin_has_permission('financial_reports.read') then
    raise exception 'Finance reporting permission required';
  end if;
  if p_start_date is null or p_end_date is null or p_end_date < p_start_date then
    raise exception 'Invalid reporting period';
  end if;
  with bounds as (
    select p_start_date::timestamp at time zone 'Africa/Lagos' as starts_at,
           (p_end_date + 1)::timestamp at time zone 'Africa/Lagos' as ends_at
  ),
  verified as (
    select p.id,p.amount,p.paid_at,p.order_id
    from public.payments p
    join public.payment_receipts r
      on r.payment_reference=p.transaction_reference
     and r.order_id=p.order_id::text
     and r.amount_received=p.amount
     and r.receipt_type='final_order_payment'
     and r.environment='production'
     and r.payment_status='successful'
     and r.currency='NGN'
     and r.payment_method='paystack'
    cross join bounds b
    where p.environment='production'
      and p.status='successful'
      and p.currency='NGN'
      and p.payment_method='paystack'
      and p.paid_at >= b.starts_at and p.paid_at < b.ends_at
      and not exists(select 1 from public.payment_receipt_voids x where x.receipt_id=r.id)
  ),
  successful as (
    select count(*) as row_count,coalesce(sum(p.amount),0)::numeric as amount
    from public.payments p cross join bounds b
    where p.environment='production' and p.status='successful'
      and p.currency='NGN' and p.paid_at >= b.starts_at and p.paid_at < b.ends_at
  ),
  receipt_totals as (
    select count(*) as row_count,coalesce(sum(r.amount_received),0)::numeric as amount
    from public.payment_receipts r cross join bounds b
    where r.receipt_type='final_order_payment' and r.environment='production'
      and r.payment_status='successful' and r.currency='NGN'
      and r.payment_method='paystack' and r.paid_at >= b.starts_at and r.paid_at < b.ends_at
      and not exists(select 1 from public.payment_receipt_voids x where x.receipt_id=r.id)
  ),
  verified_totals as (
    select count(*) as row_count,coalesce(sum(amount),0)::numeric as amount from verified
  ),
  fees as (
    select coalesce(sum(r.amount_received),0)::numeric as amount,count(*) as row_count
    from public.payment_receipts r cross join bounds b
    where r.receipt_type='quotation_admin_fee' and r.environment='production'
      and r.payment_status='successful' and r.currency='NGN'
      and r.payment_method='paystack' and r.paid_at >= b.starts_at and r.paid_at < b.ends_at
      and not exists(select 1 from public.payment_receipt_voids x where x.receipt_id=r.id)
  )
  select jsonb_build_object(
    'period',jsonb_build_object('start',p_start_date,'end',p_end_date,'timezone','Africa/Lagos'),
    'successful_payment_rows',s.row_count,
    'successful_payment_amount',s.amount,
    'verified_payment_rows',vt.row_count,
    'verified_payment_amount',vt.amount,
    'successful_receipt_rows',rt.row_count,
    'successful_receipt_amount',rt.amount,
    'quotation_admin_fee_receipts',f.row_count,
    'quotation_admin_fee_amount',f.amount,
    'unverified_successful_payment_rows',greatest(s.row_count-vt.row_count,0),
    'reconciliation_status',case when s.row_count=vt.row_count and s.amount=vt.amount then 'matched' else 'reconciliation_required' end
  ) into v
  from successful s cross join verified_totals vt cross join receipt_totals rt cross join fees f;
  return v;
end;
$function$;

create or replace function public.finance_list_payments(p_start_date date, p_end_date date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare v jsonb;
begin
  if auth.uid() is null or not public.admin_has_permission('payments.read') then
    raise exception 'Payment-read permission required';
  end if;
  if p_start_date is null or p_end_date is null or p_end_date < p_start_date then
    raise exception 'Invalid reporting period';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'payment_id',p.id,'order_id',p.order_id,'amount',p.amount,
    'currency',p.currency,'payment_method',p.payment_method,
    'reference',p.transaction_reference,'status',p.status,
    'environment',p.environment,'paid_at',p.paid_at,
    'receipt_verified',exists(
      select 1 from public.payment_receipts r
      where r.payment_reference=p.transaction_reference
        and r.order_id=p.order_id::text and r.amount_received=p.amount
        and r.receipt_type='final_order_payment' and r.environment='production'
        and r.payment_status='successful' and r.currency='NGN'
        and r.payment_method='paystack'
        and not exists(select 1 from public.payment_receipt_voids x where x.receipt_id=r.id)
    )
  ) order by p.created_at desc),'[]'::jsonb) into v
  from public.payments p
  where p.environment='production'
    and p.created_at >= p_start_date::timestamp at time zone 'Africa/Lagos'
    and p.created_at < (p_end_date+1)::timestamp at time zone 'Africa/Lagos';
  return v;
end;
$function$;

create or replace function public.finance_list_quotations(p_start_date date, p_end_date date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare v jsonb;
begin
  if auth.uid() is null or not public.admin_has_permission('quotations.read_financial') then
    raise exception 'Financial quotation-read permission required';
  end if;
  if p_start_date is null or p_end_date is null or p_end_date < p_start_date then
    raise exception 'Invalid reporting period';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',q.id,'quotation_number',q.quotation_number,'product_description',q.product_description,
    'quantity',q.quantity,'unit_price',q.unit_price,'subtotal',q.subtotal,
    'additional_charges',q.additional_charges,'discount',q.discount,
    'delivery_cost',q.delivery_cost,'total_amount',q.total_amount,
    'status',q.status,'created_at',q.created_at,'customer_decision',q.customer_decision,
    'latest_cost_snapshot',case when s.id is null then null else jsonb_build_object(
      'actual_cost_subtotal',s.actual_cost_subtotal,'markup_amount',s.markup_amount,
      'discount_amount',s.discount_amount,'delivery_customer_charge',s.delivery_customer_charge,
      'actual_delivery_cost',s.actual_delivery_cost,'captured_at',s.captured_at
    ) end
  ) order by q.created_at desc),'[]'::jsonb) into v
  from public.admin_quotations q
  left join lateral (
    select cs.* from public.quotation_cost_snapshots cs
    where cs.quotation_id=q.id order by cs.version_number desc,cs.captured_at desc limit 1
  ) s on true
  where q.created_at >= p_start_date::timestamp at time zone 'Africa/Lagos'
    and q.created_at < (p_end_date+1)::timestamp at time zone 'Africa/Lagos';
  return v;
end;
$function$;

create or replace function public.finance_list_my_cost_submissions()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare v jsonb;
begin
  if auth.uid() is null or not public.admin_has_permission('quotations.costs.submit') then
    raise exception 'Quotation cost-submission permission required';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',s.id,'quotation_id',s.quotation_id,'status',s.status,
    'actual_cost_subtotal',s.actual_cost_subtotal,'markup_rate',s.markup_rate,
    'markup_amount',s.markup_amount,'discount_amount',s.discount_amount,
    'delivery_customer_charge',s.delivery_customer_charge,
    'actual_delivery_cost',s.actual_delivery_cost,'notes',s.notes,
    'created_at',s.submitted_at,'reviewed_at',s.reviewed_at,'review_notes',s.review_notes
  ) order by s.submitted_at desc),'[]'::jsonb)
  into v
  from public.quotation_cost_submissions s
  where s.submitted_by = auth.uid();
  return v;
end;
$function$;

create or replace function public.finance_list_quotations_for_costing()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare v_result jsonb;
begin
  if (select auth.uid()) is null
     or not public.admin_has_permission('quotations.costs.submit') then
    raise exception 'Quotation cost-submission permission required';
  end if;
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id',q.id,'quotation_number',q.quotation_number,
      'product_description',q.product_description,'quantity',q.quantity,
      'status',q.status,'subtotal',q.subtotal,
      'additional_charges',q.additional_charges,'discount',q.discount,
      'delivery_cost',q.delivery_cost,'total_amount',q.total_amount,
      'created_at',q.created_at,
      'pending_cost_submission',exists(
        select 1 from public.quotation_cost_submissions s
        where s.quotation_id=q.id and s.status='pending_approval'
      )
    ) order by q.created_at desc
  ),'[]'::jsonb)
  into v_result
  from public.admin_quotations q
  where q.status in ('draft','submitted');
  return v_result;
end;
$function$;

-- Private cost submission and Super Admin-only review implementation.
create or replace function private.submit_quotation_cost_internal(
  p_quotation_id uuid,
  p_actual_cost_subtotal numeric,
  p_markup_rate numeric,
  p_discount_amount numeric,
  p_delivery_customer_charge numeric,
  p_actual_delivery_cost numeric,
  p_breakdown jsonb,
  p_notes text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_quotation public.admin_quotations%rowtype;
  v_submission_id uuid;
  v_submission public.quotation_cost_submissions%rowtype;
  v_delivery_customer_charge numeric(14,2);
begin
  if auth.uid() is null then raise exception 'Authentication required.'; end if;
  if not public.admin_has_permission('quotations.costs.submit') then
    raise exception 'You do not have permission to submit quotation costs.';
  end if;
  if p_actual_cost_subtotal is null or p_actual_cost_subtotal <= 0
     or p_actual_cost_subtotal::text in ('NaN','Infinity','-Infinity') then
    raise exception 'Invalid actual cost subtotal.';
  end if;
  if p_markup_rate is distinct from 0 or p_discount_amount is distinct from 0 then
    raise exception 'Markup and discount adjustments are not accepted in internal cost submissions.';
  end if;
  if p_actual_delivery_cost is not null and
     (p_actual_delivery_cost < 0 or p_actual_delivery_cost::text in ('NaN','Infinity','-Infinity')) then
    raise exception 'Invalid actual delivery cost.';
  end if;
  if p_breakdown is null or jsonb_typeof(p_breakdown) <> 'object' then
    raise exception 'Cost breakdown must be a JSON object.';
  end if;
  select * into v_quotation from public.admin_quotations
  where id=p_quotation_id for update;
  if not found then raise exception 'Quotation not found.'; end if;
  if v_quotation.status not in ('draft','submitted') then
    raise exception 'Cost submission is only allowed for draft or submitted quotations.';
  end if;
  if exists(select 1 from public.quotation_cost_submissions
            where quotation_id=p_quotation_id and status='pending_approval') then
    raise exception 'A pending cost submission already exists for this quotation.';
  end if;
  v_delivery_customer_charge := coalesce(v_quotation.delivery_cost,0);
  insert into public.quotation_cost_submissions (
    quotation_id,submitted_by,actual_cost_subtotal,markup_rate,markup_amount,
    discount_amount,delivery_customer_charge,actual_delivery_cost,
    selling_value_before_delivery,breakdown,notes
  ) values (
    p_quotation_id,auth.uid(),p_actual_cost_subtotal,0,0,0,
    v_delivery_customer_charge,p_actual_delivery_cost,p_actual_cost_subtotal,
    p_breakdown,p_notes
  ) returning id into v_submission_id;
  select * into v_submission from public.quotation_cost_submissions where id=v_submission_id;
  insert into public.quotation_cost_approval_audit
    (submission_id,action,previous_values,new_values,changed_by)
  values (v_submission_id,'submitted',null,to_jsonb(v_submission),auth.uid());
  return v_submission_id;
end;
$function$;

create or replace function private.review_quotation_cost_internal(
  p_submission_id uuid,p_decision text,p_review_notes text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_submission public.quotation_cost_submissions%rowtype;
  v_quotation public.admin_quotations%rowtype;
  v_old_values jsonb;
  v_new_values jsonb;
  v_quotation_old_values jsonb;
  v_quotation_new_values jsonb;
  v_snapshot_id uuid;
  v_version integer;
  v_subtotal numeric;
  v_total numeric;
  v_self_approved boolean := false;
begin
  if auth.uid() is null then raise exception 'Authentication required.'; end if;
  if not private.is_active_super_admin() then
    raise exception 'Only the active Super Administrator can review quotation costs.';
  end if;
  if p_decision is null or p_decision not in ('approve','reject') then
    raise exception 'Decision must be approve or reject.';
  end if;
  if p_review_notes is not null and length(p_review_notes)>5000 then
    raise exception 'Review notes are too long.';
  end if;
  if p_decision='reject' and nullif(trim(p_review_notes),'') is null then
    raise exception 'A reason is required when rejecting a submission.';
  end if;
  select * into v_submission from public.quotation_cost_submissions
  where id=p_submission_id for update;
  if not found then raise exception 'Cost submission not found.'; end if;
  if v_submission.status <> 'pending_approval' then
    raise exception 'This submission has already been reviewed.';
  end if;
  v_self_approved := (p_decision='approve' and v_submission.submitted_by=auth.uid());
  if v_self_approved then raise exception 'You cannot approve your own quotation cost submission.'; end if;
  v_old_values := to_jsonb(v_submission);
  if p_decision='approve' then
    select * into v_quotation from public.admin_quotations
    where id=v_submission.quotation_id for update;
    if not found then raise exception 'Original quotation not found.'; end if;
    if v_quotation.status not in ('draft','submitted') then
      raise exception 'Quotation status no longer permits approval.';
    end if;
    v_quotation_old_values := to_jsonb(v_quotation);
    v_subtotal := round(v_submission.actual_cost_subtotal+v_submission.markup_amount,2);
    if round(v_subtotal-v_submission.discount_amount,2) <>
       round(v_submission.selling_value_before_delivery,2) then
      raise exception 'Financial consistency check failed. Selling value does not match subtotal minus discount.';
    end if;
    v_total := round(v_subtotal+v_submission.delivery_customer_charge+
                     v_quotation.additional_charges-v_submission.discount_amount,2);
    select coalesce(max(version_number),0)+1 into v_version
    from public.quotation_cost_snapshots where quotation_id=v_submission.quotation_id;
    insert into public.quotation_cost_snapshots (
      submission_id,quotation_id,version_number,actual_cost_subtotal,markup_rate,
      markup_amount,discount_amount,delivery_customer_charge,actual_delivery_cost,
      selling_value_before_delivery,captured_by
    ) values (
      v_submission.id,v_submission.quotation_id,v_version,v_submission.actual_cost_subtotal,
      v_submission.markup_rate,v_submission.markup_amount,v_submission.discount_amount,
      v_submission.delivery_customer_charge,v_submission.actual_delivery_cost,
      v_submission.selling_value_before_delivery,auth.uid()
    ) returning id into v_snapshot_id;
    -- Deliberately do not update admin_quotations or customer/payment fields.
    v_quotation_new_values := to_jsonb(v_quotation);
    update public.quotation_cost_submissions
    set status='approved',reviewed_by=auth.uid(),reviewed_at=now(),review_notes=p_review_notes
    where id=p_submission_id returning * into v_submission;
  else
    update public.quotation_cost_submissions
    set status='rejected',reviewed_by=auth.uid(),reviewed_at=now(),review_notes=p_review_notes
    where id=p_submission_id returning * into v_submission;
  end if;
  v_new_values := jsonb_build_object(
    'submission',to_jsonb(v_submission),'snapshot_id',v_snapshot_id,
    'quotation_before',v_quotation_old_values,'quotation_after',v_quotation_new_values,
    'self_approved',v_self_approved
  );
  insert into public.quotation_cost_approval_audit
    (submission_id,action,previous_values,new_values,changed_by)
  values (
    p_submission_id,case when p_decision='approve' then 'approved' else 'rejected' end,
    v_old_values,v_new_values,auth.uid()
  );
  return v_snapshot_id;
end;
$function$;

create or replace function public.submit_quotation_cost(
  p_quotation_id uuid,p_actual_cost_subtotal numeric,p_markup_rate numeric,
  p_discount_amount numeric default 0,p_delivery_customer_charge numeric default 0,
  p_actual_delivery_cost numeric default null,p_breakdown jsonb default '{}'::jsonb,
  p_notes text default null
)
returns uuid
language sql
set search_path = ''
as $function$
  select private.submit_quotation_cost_internal(
    p_quotation_id,p_actual_cost_subtotal,p_markup_rate,p_discount_amount,
    p_delivery_customer_charge,p_actual_delivery_cost,p_breakdown,p_notes
  );
$function$;

create or replace function public.review_quotation_cost(
  p_submission_id uuid,p_decision text,p_review_notes text default null
)
returns uuid
language sql
set search_path = ''
as $function$
  select private.review_quotation_cost_internal(p_submission_id,p_decision,p_review_notes);
$function$;

-- Keep SECURITY DEFINER helpers non-public; callable wrappers enforce permissions internally.
revoke all on function private.submit_quotation_cost_internal(uuid,numeric,numeric,numeric,numeric,numeric,jsonb,text) from public,anon;
grant execute on function private.submit_quotation_cost_internal(uuid,numeric,numeric,numeric,numeric,numeric,jsonb,text) to authenticated,service_role;
revoke all on function private.review_quotation_cost_internal(uuid,text,text) from public,anon;
grant execute on function private.review_quotation_cost_internal(uuid,text,text) to authenticated,service_role;

revoke all on function public.finance_get_summary(date,date) from public,anon;
revoke all on function public.finance_list_payments(date,date) from public,anon;
revoke all on function public.finance_list_quotations(date,date) from public,anon;
revoke all on function public.finance_list_my_cost_submissions() from public,anon;
revoke all on function public.finance_list_quotations_for_costing() from public,anon;
revoke all on function public.submit_quotation_cost(uuid,numeric,numeric,numeric,numeric,numeric,jsonb,text) from public,anon;
revoke all on function public.review_quotation_cost(uuid,text,text) from public,anon;
grant execute on function public.finance_get_summary(date,date) to authenticated,service_role;
grant execute on function public.finance_list_payments(date,date) to authenticated,service_role;
grant execute on function public.finance_list_quotations(date,date) to authenticated,service_role;
grant execute on function public.finance_list_my_cost_submissions() to authenticated,service_role;
grant execute on function public.finance_list_quotations_for_costing() to authenticated,service_role;
grant execute on function public.submit_quotation_cost(uuid,numeric,numeric,numeric,numeric,numeric,jsonb,text) to authenticated,service_role;
grant execute on function public.review_quotation_cost(uuid,text,text) to authenticated,service_role;

-- Finance payment visibility remains permission-based, not a broad role grant.
drop policy if exists department_finance_payments_read on public.payments;
create policy department_finance_payments_read
  on public.payments for select to authenticated
  using (public.admin_has_permission('payments.read'));

commit;
