-- Reconcile the isolated-test appointment hold audit and standardise future
-- direct-quotation activity labels without rewriting historical records.
create or replace function public.frosttech_normalize_test_activity_environment()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.action in (
    'direct_quotation_draft_created',
    'direct_quotation_issued',
    'direct_quotation_bank_instructions_emailed',
    'direct_quotation_bank_fee_confirmed',
    'direct_quotation_password_emailed_after_bank_confirmation'
  ) then
    new.details := coalesce(new.details, '{}'::jsonb);
    if new.details ->> 'environment' is distinct from 'isolated_test' then
      new.details := new.details
        - 'environment'
        || jsonb_build_object(
          'source_environment', new.details -> 'environment',
          'environment', 'isolated_test'
        );
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_frosttech_normalize_test_activity_environment
  on public.admin_activity_log;
create trigger trg_frosttech_normalize_test_activity_environment
before insert on public.admin_activity_log
for each row
execute function public.frosttech_normalize_test_activity_environment();

-- The original hold activation has no actor attribution. Record a transparent
-- reconciliation entry using the control row's timestamp, without inventing an actor.
insert into public.admin_activity_log(actor_user_id, action, target_user_id, details, created_at)
select
  null,
  'departmental_appointment_hold_baseline_reconciled',
  null,
  jsonb_build_object(
    'environment', 'isolated_test',
    'record_type', 'audit_reconciliation',
    'hold_status', 'active',
    'effective_hold_since', c.updated_at,
    'original_actor_attribution', 'unavailable',
    'note', 'Baseline reconstructed from the appointment control row. This entry does not claim a user action.'
  ),
  c.updated_at
from public.frosttech_appointment_controls c
where c.control_key = 'departmental_appointments'
  and c.is_on_hold is true
  and not exists (
    select 1
    from public.admin_activity_log a
    where a.action = 'departmental_appointment_hold_baseline_reconciled'
      and a.details ->> 'environment' = 'isolated_test'
  );
