begin;
create or replace function public.frosttech_guard_duplicate_tax_source()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_order_id uuid;
begin
  if new.tax_type not in ('VAT','WHT') then return new; end if;
  if lower(trim(new.transaction_type))='order' then
    v_order_id := new.transaction_id;
  elsif lower(trim(new.transaction_type))='payment' then
    select p.order_id into v_order_id from public.payments p
    where p.id=new.transaction_id and p.status='successful';
  else
    return new;
  end if;
  if v_order_id is not null then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtext('frosttech_tax_source:' || v_order_id::text),1
    );
  end if;
  if lower(trim(new.transaction_type))='order' then
    if exists (
      select 1 from public.payments p
      join public.frosttech_tax_assessments a
        on a.transaction_type='payment' and a.transaction_id=p.id
       and a.tax_type=new.tax_type and a.direction=new.direction
      where p.order_id=new.transaction_id and p.status='successful'
    ) then
      raise exception 'This paid order already has a matching tax assessment through a successful payment';
    end if;
  elsif lower(trim(new.transaction_type))='payment' and v_order_id is not null then
    if exists (
      select 1 from public.frosttech_tax_assessments a
      where a.transaction_type='order' and a.transaction_id=v_order_id
        and a.tax_type=new.tax_type and a.direction=new.direction
    ) then
      raise exception 'This payment order already has a matching tax assessment';
    end if;
  end if;
  return new;
end;
$function$;
commit;