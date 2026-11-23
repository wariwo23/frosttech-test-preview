-- REVIEW-ONLY DRAFT — DO NOT APPLY YET
-- FrostTech Administration Command Center: Operations workspace
-- Repository: wariwo23/frosttech-test-preview
-- Branch: command-center-shell-stage1
-- Target project when separately approved: gqnidjifiobhqhnxjlow (isolated test ONLY)
--
-- Prepared from read-only inspection of the existing production Operations RPCs
-- and table metadata. No production object or data is modified by saving this file.
--
-- Scope:
--   * Recreate the ten existing Operations RPCs with their permission checks.
--   * Add only the missing quotation and delivery-contact-log schema dependencies
--     in the isolated test project.
--   * Add the four existing Operations permission rows for operations_admin.
--   * Preserve existing orders/order_items/deliveries RLS and table policies.
--   * Do not create users, employees, invitations, orders, quotations, or sample data.
--
-- Security choices:
--   * All Operations RPCs require auth.uid() and admin_has_permission().
--   * SECURITY DEFINER functions use an empty search_path and schema-qualified
--     application/auth objects.
--   * Direct access to delivery_customer_contact_logs remains revoked.
--   * Sensitive supplier costs and margins are removed from Operations results.
--
-- PRE-FLIGHT: This draft expects the existing isolated-test admin_accounts,
-- admin_role_permissions, admin_activity_log, profiles, products, customers,
-- orders, order_items, deliveries, and permission helper functions.
-- It intentionally does not alter those existing objects.

begin;

-- ---------------------------------------------------------------------------
-- 1. Preconditions: fail closed if expected isolated-test dependencies differ.
-- ---------------------------------------------------------------------------
do $preflight$
begin
  if to_regclass('public.admin_accounts') is null
     or to_regclass('public.admin_role_permissions') is null
     or to_regclass('public.admin_activity_log') is null
     or to_regclass('public.profiles') is null
     or to_regclass('public.products') is null
     or to_regclass('public.customers') is null
     or to_regclass('public.orders') is null
     or to_regclass('public.order_items') is null
     or to_regclass('public.deliveries') is null then
    raise exception 'Operations migration preflight failed: a required existing test table is missing';
  end if;

  if to_regprocedure('public.admin_has_permission(text)') is null
     or to_regprocedure('public.is_super_admin()') is null then
    raise exception 'Operations migration preflight failed: existing admin permission helpers are missing';
  end if;

  if to_regclass('public.quote_requests') is not null
     or to_regclass('public.admin_quotations') is not null
     or to_regclass('public.delivery_customer_contact_logs') is not null then
    raise exception 'Operations migration draft expects the three missing test dependencies to be absent; inspect before adapting';
  end if;
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- 2. Missing request/quotation schema dependencies.
--    These reproduce the inspected production columns and key constraints.
-- ---------------------------------------------------------------------------
create table public.quote_requests (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid null references public.profiles(id),
  product_id uuid null references public.products(id),
  request_number text null unique,
  title text not null,
  description text null,
  quantity integer not null default 1,
  preferred_brand text null,
  budget numeric null,
  delivery_address text null,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  admin_fee numeric null,
  admin_fee_status text not null default 'pending',
  admin_fee_transaction_reference text null,
  admin_fee_paid_at timestamptz null,
  customer_name text null,
  customer_email text null,
  customer_phone text null,
  installation_kit_quantity integer not null default 0,
  installation_service boolean not null default false,
  outdoor_bracket_quantity integer not null default 0,
  environment text not null default 'development',
  constraint quote_requests_environment_check
    check (environment in ('development','production'))
);

comment on table public.quote_requests is
  'Isolated-test mirror of the production customer request table; no production records copied.';

alter table public.quote_requests enable row level security;

-- Customer/guest submission and authorised admin request review retain the
-- production access model. Departmental access is permission-based.
create policy "Admins can view quote requests"
  on public.quote_requests for select to authenticated
  using (public.frosttech_can_manage_customer_requests_v1());

create policy "Admins can update quote requests"
  on public.quote_requests for update to authenticated
  using (public.frosttech_can_manage_customer_requests_v1())
  with check (public.frosttech_can_manage_customer_requests_v1());

create policy "Customers can insert their own quote requests"
  on public.quote_requests for insert to authenticated
  with check (
    customer_id = (select auth.uid())
    and exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid())
        and p.role = 'customer'
        and p.is_active is true
    )
  );

create policy "Guests can submit unlinked quote requests"
  on public.quote_requests for insert to anon
  with check (customer_id is null);

grant select, insert, update on public.quote_requests to authenticated;
grant insert on public.quote_requests to anon;

create table public.admin_quotations (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.quote_requests(id) on delete cascade,
  customer_id uuid null,
  quotation_number text not null unique,
  product_description text not null,
  quantity integer not null default 1,
  unit_price numeric not null,
  delivery_cost numeric not null default 0,
  additional_charges numeric not null default 0,
  discount numeric not null default 0,
  subtotal numeric null,
  total_amount numeric null,
  validity_date date null,
  notes text null,
  status text not null default 'draft',
  created_by uuid null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  customer_decision text null,
  decline_reason text null,
  terms_accepted_at timestamptz null,
  decline_comments text null,
  customer_decision_at timestamptz null,
  prepayment_terms_accepted_at timestamptz null,
  order_payment_terms_accepted_at timestamptz null,
  version_group_id uuid not null default gen_random_uuid(),
  version_number integer not null default 1,
  supersedes_quotation_id uuid null,
  quotation_scope_snapshot jsonb not null
    default '{"state":"draft","snapshot_version":2}'::jsonb,
  submitted_scope_snapshot jsonb null,
  approved_scope_snapshot jsonb null,
  constraint admin_quotations_additional_charges_check check (additional_charges >= 0),
  constraint admin_quotations_approved_snapshot_object
    check (approved_scope_snapshot is null or jsonb_typeof(approved_scope_snapshot) = 'object'),
  constraint admin_quotations_delivery_cost_check check (delivery_cost >= 0),
  constraint admin_quotations_discount_check check (discount >= 0),
  constraint admin_quotations_quantity_check check (quantity > 0),
  constraint admin_quotations_scope_snapshot_object
    check (jsonb_typeof(quotation_scope_snapshot) = 'object'),
  constraint admin_quotations_status_check
    check (status in ('draft','submitted','accepted','rejected','expired')),
  constraint admin_quotations_submitted_snapshot_object
    check (submitted_scope_snapshot is null or jsonb_typeof(submitted_scope_snapshot) = 'object'),
  constraint admin_quotations_unit_price_check check (unit_price >= 0),
  constraint admin_quotations_version_number_positive check (version_number > 0),
  constraint admin_quotations_supersedes_fk
    foreign key (supersedes_quotation_id)
    references public.admin_quotations(id) on delete restrict
);

comment on table public.admin_quotations is
  'Isolated-test mirror of the production quotation header table; no production records copied.';

alter table public.admin_quotations enable row level security;

create policy "Admins manage direct quotations"
  on public.admin_quotations for all to authenticated
  using (public.is_super_admin())
  with check (public.is_super_admin());

create policy "department_finance_quotations_read"
  on public.admin_quotations for select to authenticated
  using (public.admin_has_permission('quotations.read_financial'));

grant select, insert, update, delete on public.admin_quotations to authenticated;

-- Helper used by the existing production quote_requests RLS model.
create or replace function public.frosttech_can_manage_customer_requests_v1()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select coalesce(public.admin_has_permission('customer_requests.manage'), false);
$function$;

revoke all on function public.frosttech_can_manage_customer_requests_v1() from public, anon;
grant execute on function public.frosttech_can_manage_customer_requests_v1() to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Missing delivery customer-contact log dependency.
--    Intentionally RPC-only: no direct client table privileges or policies.
-- ---------------------------------------------------------------------------
create table public.delivery_customer_contact_logs (
  id uuid primary key default gen_random_uuid(),
  delivery_id uuid not null references public.deliveries(id) on delete cascade,
  order_id uuid not null references public.orders(id) on delete cascade,
  contact_method text not null,
  contact_summary text not null,
  contact_outcome text null,
  next_follow_up_at timestamptz null,
  contacted_at timestamptz not null default now(),
  contacted_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  constraint delivery_customer_contact_logs_contact_method_check
    check (contact_method in ('phone','whatsapp','email','sms','other'))
);

alter table public.delivery_customer_contact_logs enable row level security;
revoke all on table public.delivery_customer_contact_logs from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. Operations role permissions already present in production.
--    Add only missing rows; do not alter other roles or existing permissions.
-- ---------------------------------------------------------------------------
insert into public.admin_role_permissions(role, permission)
select 'operations_admin', v.permission
from (values
  ('customer_requests.manage'),
  ('quotations.read_operational'),
  ('orders.manage'),
  ('deliveries.manage')
) as v(permission)
where not exists (
  select 1 from public.admin_role_permissions rp
  where rp.role = 'operations_admin' and rp.permission = v.permission
);

-- ---------------------------------------------------------------------------
-- 5. The ten recovered Operations RPCs.
-- ---------------------------------------------------------------------------

create or replace function public.ops_list_customer_requests()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  result jsonb;
begin
  if auth.uid() is null
     or not public.admin_has_permission('customer_requests.manage') then
    raise exception 'Access denied';
  end if;

  select coalesce(
    jsonb_agg(to_jsonb(q) order by q.created_at desc),
    '[]'::jsonb
  )
  into result
  from (
    select *
    from public.quote_requests
    order by created_at desc
    limit 500
  ) q;

  return result;
end;
$function$;

create or replace function public.ops_mark_request_reviewing(p_request_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_updated_id uuid;
begin
  if auth.uid() is null
     or not public.admin_has_permission('customer_requests.manage') then
    raise exception 'Access denied';
  end if;

  if p_request_id is null then
    raise exception 'Customer request ID is required';
  end if;

  update public.quote_requests
  set status = 'reviewing', updated_at = now()
  where id = p_request_id
    and status in ('pending', 'reviewing')
  returning id into v_updated_id;

  if v_updated_id is null then
    return false;
  end if;

  insert into public.admin_activity_log(actor_user_id, action, target_user_id, details)
  values (
    auth.uid(), 'customer_request_marked_reviewing', null,
    jsonb_build_object('request_id', v_updated_id)
  );

  return true;
end;
$function$;

create or replace function public.ops_list_quotations()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  result jsonb;
begin
  if auth.uid() is null
     or not public.admin_has_permission('quotations.read_operational') then
    raise exception 'Access denied';
  end if;

  select coalesce(
    jsonb_agg(
      (
        to_jsonb(q)
        - array[
          'notes',
          'supplier_cost',
          'supplier_unit_cost',
          'supplier_margin',
          'frosttech_margin',
          'cost_price',
          'unit_cost',
          'purchase_price',
          'profit'
        ]::text[]
      )
      order by q.created_at desc
    ),
    '[]'::jsonb
  )
  into result
  from (
    select *
    from public.admin_quotations
    order by created_at desc
    limit 500
  ) q;

  return result;
end;
$function$;

create or replace function public.ops_list_orders()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  result jsonb;
begin
  if auth.uid() is null
     or not public.admin_has_permission('orders.manage') then
    raise exception 'Access denied';
  end if;

  select coalesce(
    jsonb_agg(
      to_jsonb(o) - array['supplier_cost','frosttech_margin']
      order by o.created_at desc
    ),
    '[]'::jsonb
  )
  into result
  from (
    select *
    from public.orders
    order by created_at desc
    limit 500
  ) o;

  return result;
end;
$function$;

create or replace function public.ops_list_order_items()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  result jsonb;
begin
  if auth.uid() is null
     or not public.admin_has_permission('orders.manage') then
    raise exception 'Access denied';
  end if;

  select coalesce(
    jsonb_agg(to_jsonb(i) - 'supplier_unit_cost' order by i.created_at desc),
    '[]'::jsonb
  )
  into result
  from (
    select *
    from public.order_items
    order by created_at desc
    limit 1000
  ) i;

  return result;
end;
$function$;

create or replace function public.ops_list_deliveries()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  result jsonb;
begin
  if auth.uid() is null
     or not public.admin_has_permission('deliveries.manage') then
    raise exception 'Access denied';
  end if;

  select coalesce(
    jsonb_agg(
      to_jsonb(d) - array['supplier_cost','supplier_unit_cost','frosttech_margin']
    ),
    '[]'::jsonb
  )
  into result
  from public.deliveries d;

  return result;
end;
$function$;

create or replace function public.ops_schedule_delivery(
  p_delivery_id uuid,
  p_scheduled_delivery_at timestamptz,
  p_delivery_window_end_at timestamptz default null,
  p_assigned_to text default null,
  p_driver_phone text default null,
  p_delivery_address text default null,
  p_tracking_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_delivery public.deliveries%rowtype;
  v_new_status text;
begin
  if auth.uid() is null
     or not public.admin_has_permission('deliveries.manage') then
    raise exception 'Access denied';
  end if;

  if p_delivery_window_end_at is not null
     and p_scheduled_delivery_at is not null
     and p_delivery_window_end_at < p_scheduled_delivery_at then
    raise exception 'Delivery window end cannot be earlier than its start';
  end if;

  select * into v_delivery
  from public.deliveries
  where id = p_delivery_id
  for update;

  if not found then
    raise exception 'Delivery record not found';
  end if;

  if v_delivery.status in ('delivered','cancelled') then
    raise exception 'This delivery can no longer be scheduled or reassigned';
  end if;

  v_new_status := v_delivery.status;

  if nullif(trim(p_assigned_to), '') is not null
     and v_delivery.status in ('pending','failed') then
    v_new_status := 'assigned';
  end if;

  update public.deliveries
  set
    scheduled_delivery_at = p_scheduled_delivery_at,
    delivery_window_end_at = p_delivery_window_end_at,
    assigned_to = coalesce(nullif(trim(p_assigned_to), ''), assigned_to),
    driver_phone = coalesce(nullif(trim(p_driver_phone), ''), driver_phone),
    delivery_address = coalesce(nullif(trim(p_delivery_address), ''), delivery_address),
    tracking_note = coalesce(nullif(trim(p_tracking_note), ''), tracking_note),
    status = v_new_status,
    assigned_at = case
      when nullif(trim(p_assigned_to), '') is not null
       and (
         v_delivery.assigned_to is distinct from nullif(trim(p_assigned_to), '')
         or v_delivery.status in ('pending','failed')
       )
      then now()
      else assigned_at
    end,
    updated_at = now()
  where id = p_delivery_id;

  insert into public.admin_activity_log(actor_user_id, action, details)
  values (
    auth.uid(), 'delivery_scheduled_or_assigned',
    jsonb_build_object(
      'delivery_id', p_delivery_id,
      'scheduled_delivery_at', p_scheduled_delivery_at,
      'delivery_window_end_at', p_delivery_window_end_at,
      'assigned_to', p_assigned_to
    )
  );

  return jsonb_build_object('success', true, 'delivery_id', p_delivery_id, 'status', v_new_status);
end;
$function$;

create or replace function public.ops_update_delivery_status(
  p_delivery_id uuid,
  p_new_status text,
  p_tracking_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_current_status text;
  v_order_id uuid;
  v_order_status text;
  v_target_order_status text;
  v_allowed boolean := false;
begin
  if auth.uid() is null
     or not public.admin_has_permission('deliveries.manage') then
    raise exception 'Access denied';
  end if;

  if p_new_status not in (
    'pending','assigned','picked_up','in_transit','delivered','failed','cancelled'
  ) then
    raise exception 'Invalid delivery status';
  end if;

  select status, order_id
  into v_current_status, v_order_id
  from public.deliveries
  where id = p_delivery_id
  for update;

  if not found then
    raise exception 'Delivery record not found';
  end if;

  v_allowed := case v_current_status
    when 'pending' then p_new_status in ('assigned','cancelled')
    when 'assigned' then p_new_status in ('picked_up','failed','cancelled')
    when 'picked_up' then p_new_status in ('in_transit','failed')
    when 'in_transit' then p_new_status in ('delivered','failed')
    when 'failed' then p_new_status in ('assigned','cancelled')
    else false
  end;

  if not v_allowed then
    raise exception 'Delivery status change from % to % is not permitted',
      v_current_status, p_new_status;
  end if;

  update public.deliveries
  set
    status = p_new_status,
    tracking_note = coalesce(nullif(trim(p_tracking_note), ''), tracking_note),
    delivered_at = case when p_new_status = 'delivered' then now() else delivered_at end,
    updated_at = now()
  where id = p_delivery_id;

  v_target_order_status := case p_new_status
    when 'assigned' then 'ready_for_delivery'
    when 'picked_up' then 'out_for_delivery'
    when 'in_transit' then 'out_for_delivery'
    when 'delivered' then 'delivered'
    else null
  end;

  if v_target_order_status is not null then
    update public.orders
    set status = v_target_order_status, updated_at = now()
    where id = v_order_id
      and status in ('paid','processing','ready_for_delivery','out_for_delivery');
  end if;

  select status into v_order_status
  from public.orders
  where id = v_order_id;

  insert into public.admin_activity_log(actor_user_id, action, target_user_id, details)
  values (
    auth.uid(), 'delivery_status_updated', null,
    jsonb_build_object(
      'delivery_id', p_delivery_id,
      'old_status', v_current_status,
      'new_status', p_new_status,
      'tracking_note', coalesce(nullif(trim(p_tracking_note), ''), ''),
      'order_status_after_sync', v_order_status
    )
  );

  return jsonb_build_object(
    'success', true, 'delivery_id', p_delivery_id,
    'old_status', v_current_status, 'new_status', p_new_status
  );
end;
$function$;

create or replace function public.ops_log_delivery_customer_contact(
  p_delivery_id uuid,
  p_contact_method text,
  p_contact_summary text,
  p_contact_outcome text default null,
  p_next_follow_up_at timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_order_id uuid;
  v_log_id uuid;
begin
  if auth.uid() is null
     or not public.admin_has_permission('deliveries.manage') then
    raise exception 'Access denied';
  end if;

  if p_contact_method not in ('phone','whatsapp','email','sms','other') then
    raise exception 'Invalid contact method';
  end if;

  if nullif(trim(p_contact_summary), '') is null then
    raise exception 'Contact summary is required';
  end if;

  select order_id into v_order_id
  from public.deliveries
  where id = p_delivery_id;

  if not found then
    raise exception 'Delivery record not found';
  end if;

  insert into public.delivery_customer_contact_logs(
    delivery_id, order_id, contact_method, contact_summary,
    contact_outcome, next_follow_up_at, contacted_by
  )
  values (
    p_delivery_id, v_order_id, p_contact_method, trim(p_contact_summary),
    p_contact_outcome, p_next_follow_up_at, auth.uid()
  )
  returning id into v_log_id;

  insert into public.admin_activity_log(actor_user_id, action, details)
  values (
    auth.uid(), 'delivery_customer_contact_recorded',
    jsonb_build_object(
      'delivery_id', p_delivery_id,
      'contact_log_id', v_log_id,
      'contact_method', p_contact_method,
      'next_follow_up_at', p_next_follow_up_at
    )
  );

  return v_log_id;
end;
$function$;

create or replace function public.ops_list_delivery_contact_logs(p_delivery_id uuid)
returns table (
  contact_log_id uuid,
  contact_method text,
  contact_summary text,
  contact_outcome text,
  next_follow_up_at timestamptz,
  contacted_at timestamptz,
  contacted_by_name text
)
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null
     or not public.admin_has_permission('deliveries.manage') then
    raise exception 'Access denied';
  end if;

  if not exists (
    select 1 from public.deliveries where id = p_delivery_id
  ) then
    raise exception 'Delivery record not found';
  end if;

  return query
  select l.id, l.contact_method, l.contact_summary, l.contact_outcome,
         l.next_follow_up_at, l.contacted_at, p.full_name
  from public.delivery_customer_contact_logs l
  left join public.profiles p on p.id = l.contacted_by
  where l.delivery_id = p_delivery_id
  order by l.contacted_at desc;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 6. Explicit function privileges: authenticated only; never anon/PUBLIC.
-- ---------------------------------------------------------------------------
revoke all on function public.ops_list_customer_requests() from public, anon, authenticated;
revoke all on function public.ops_mark_request_reviewing(uuid) from public, anon, authenticated;
revoke all on function public.ops_list_quotations() from public, anon, authenticated;
revoke all on function public.ops_list_orders() from public, anon, authenticated;
revoke all on function public.ops_list_order_items() from public, anon, authenticated;
revoke all on function public.ops_list_deliveries() from public, anon, authenticated;
revoke all on function public.ops_schedule_delivery(uuid,timestamptz,timestamptz,text,text,text,text) from public, anon, authenticated;
revoke all on function public.ops_update_delivery_status(uuid,text,text) from public, anon, authenticated;
revoke all on function public.ops_log_delivery_customer_contact(uuid,text,text,text,timestamptz) from public, anon, authenticated;
revoke all on function public.ops_list_delivery_contact_logs(uuid) from public, anon, authenticated;

grant execute on function public.ops_list_customer_requests() to authenticated;
grant execute on function public.ops_mark_request_reviewing(uuid) to authenticated;
grant execute on function public.ops_list_quotations() to authenticated;
grant execute on function public.ops_list_orders() to authenticated;
grant execute on function public.ops_list_order_items() to authenticated;
grant execute on function public.ops_list_deliveries() to authenticated;
grant execute on function public.ops_schedule_delivery(uuid,timestamptz,timestamptz,text,text,text,text) to authenticated;
grant execute on function public.ops_update_delivery_status(uuid,text,text) to authenticated;
grant execute on function public.ops_log_delivery_customer_contact(uuid,text,text,text,timestamptz) to authenticated;
grant execute on function public.ops_list_delivery_contact_logs(uuid) to authenticated;

commit;

-- ---------------------------------------------------------------------------
-- 7. Post-apply test plan (NOT executed by this draft).
-- ---------------------------------------------------------------------------
-- [ ] Confirm all ten RPC signatures match departmental-admin.html.
-- [ ] Confirm anon cannot execute any Operations RPC.
-- [ ] Confirm authenticated customer/supplier accounts cannot execute Operations RPCs.
-- [ ] Confirm Operations Admin can read permitted request/quotation/order/delivery data.
-- [ ] Confirm Operations Admin cannot directly SELECT admin_quotations or contact logs.
-- [ ] Confirm Operations RPC payloads omit supplier_cost, supplier_unit_cost,
--     frosttech_margin and private quotation cost/profit keys.
-- [ ] Confirm Operations Admin cannot read payments, supplier costs or financial quotations.
-- [ ] Confirm invalid delivery transitions and invalid schedule windows are rejected.
-- [ ] Confirm unpaid/cancelled/completed orders are not overwritten by delivery sync.
-- [ ] Confirm activity records use auth.uid(), not client-supplied actor IDs.
-- [ ] Confirm Super Admin retains access and all existing test accounts/records remain intact.
-- [ ] Run Supabase Security Advisor on the isolated test project after applying.
--
-- This file is a draft only. No SQL in this file has been applied.
