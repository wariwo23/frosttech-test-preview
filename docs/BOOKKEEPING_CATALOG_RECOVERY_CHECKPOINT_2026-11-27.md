# FrostTech Bookkeeping Recovery — Catalog Checkpoint
Date: 27 November 2026
Scope: read-only extraction from isolated test project `gqnidjifiobhqhnxjlow`.
Status: recovery evidence only. No database objects or financial rows were changed.

## Objects confirmed

All 12 live bookkeeping tables were returned from PostgreSQL catalogs and owned by `postgres`:
- `ft_bookkeeping_accounts`
- `ft_bookkeeping_audit_log`
- `ft_bookkeeping_bank_accounts`
- `ft_bookkeeping_bank_transactions`
- `ft_bookkeeping_documents`
- `ft_bookkeeping_expenses`
- `ft_bookkeeping_fixed_assets`
- `ft_bookkeeping_journal_lines`
- `ft_bookkeeping_journals`
- `ft_bookkeeping_periods`
- `ft_bookkeeping_reconciliations`
- `ft_bookkeeping_shareholder_loans`

The catalogue query captured column order, data types, nullability, defaults, identity/generated attributes, constraints, indexes, RLS enable/force flags, and policies. The first response was truncated by the connector output limit; therefore this is not yet a complete table-by-table DDL export. Remaining object definitions must be extracted in smaller batches before generating executable migration SQL.

## Identity dependencies

- `ft_bookkeeping_audit_log.id` is a bigint identity column backed by owned sequence `public.ft_bookkeeping_audit_log_id_seq`.
- `ft_bookkeeping_journals.entry_number` is a bigint identity column backed by owned sequence `public.ft_bookkeeping_journals_entry_number_seq`.
- Preserve identity semantics and sequence ownership; do not replace with an unowned serial default.

## Journal integrity triggers

Two non-internal triggers are present:

```sql
CREATE TRIGGER ft_bookkeeping_journal_line_guard
BEFORE INSERT OR DELETE OR UPDATE ON public.ft_bookkeeping_journal_lines
FOR EACH ROW EXECUTE FUNCTION public.ft_bookkeeping_guard_journal_line();

CREATE TRIGGER ft_bookkeeping_journal_guard
BEFORE INSERT OR UPDATE ON public.ft_bookkeeping_journals
FOR EACH ROW EXECUTE FUNCTION public.ft_bookkeeping_guard_journal();
```

### Exact function: `ft_bookkeeping_guard_journal_line()`

```sql
CREATE OR REPLACE FUNCTION public.ft_bookkeeping_guard_journal_line()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
declare
  v_journal_id uuid;
  v_status text;
begin
  v_journal_id := case when tg_op = 'DELETE' then old.journal_id else new.journal_id end;
  select status into v_status from public.ft_bookkeeping_journals where id = v_journal_id;

  if v_status is distinct from 'draft' and not public.is_super_admin() then
    raise exception 'Journal lines are locked after submission. Return a submitted journal through the controlled review process before correction.';
  end if;
  if v_status in ('approved','posted') then
    raise exception 'Approved and posted journal lines are immutable.';
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$function$;
```

### Exact function: `ft_bookkeeping_guard_journal()`

```sql
CREATE OR REPLACE FUNCTION public.ft_bookkeeping_guard_journal()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
declare
  v_debits numeric(18,2);
  v_credits numeric(18,2);
  v_lines integer;
  v_period_start date;
  v_period_end date;
  v_period_status text;
begin
  if tg_op = 'UPDATE' then
    if old.status = 'posted' then
      raise exception 'Posted journal entries are immutable. Use a separately approved reversal or adjustment entry.';
    end if;
    if old.status in ('submitted','approved') and not public.is_super_admin() then
      raise exception 'Submitted or approved journal entries cannot be changed by Finance Admin.';
    end if;
  end if;

  if new.status in ('approved','posted') and not public.is_super_admin() then
    raise exception 'Only the Super Administrator may approve or post journal entries.';
  end if;

  if tg_op = 'UPDATE' and old.status = 'submitted' and new.status not in ('submitted','approved','rejected') then
    raise exception 'A submitted journal can only remain submitted, be approved or be rejected.';
  end if;
  if tg_op = 'UPDATE' and old.status = 'approved' and new.status not in ('approved','posted') then
    raise exception 'An approved journal can only remain approved or be posted.';
  end if;

  if new.status = 'posted' then
    select count(*), coalesce(sum(debit),0), coalesce(sum(credit),0)
      into v_lines, v_debits, v_credits
    from public.ft_bookkeeping_journal_lines
    where journal_id = new.id;

    if v_lines < 2 or v_debits <= 0 or v_debits <> v_credits then
      raise exception 'Journal entry cannot be posted: at least two lines and equal non-zero debits and credits are required.';
    end if;

    if new.period_id is null then
      raise exception 'A journal must be assigned to an accounting period before posting.';
    end if;

    select start_date, end_date, status
      into v_period_start, v_period_end, v_period_status
    from public.ft_bookkeeping_periods where id = new.period_id;

    if not found or new.entry_date < v_period_start or new.entry_date > v_period_end then
      raise exception 'Journal date must fall within its assigned accounting period.';
    end if;
    if v_period_status <> 'open' then
      raise exception 'Journal entry cannot be posted into a closed accounting period.';
    end if;
    new.posted_by := auth.uid();
    new.posted_at := now();
  end if;

  if new.status = 'approved' and (tg_op = 'INSERT' or old.status <> 'approved') then
    new.approved_by := auth.uid();
    new.approved_at := now();
  end if;

  new.updated_at := now();
  return new;
end;
$function$;
```

Both functions are invoker-security (not SECURITY DEFINER), have empty search_path, and their execute ACL is limited to postgres and service_role. Do not grant direct execution to anon/authenticated. Trigger execution does not require a browser EXECUTE grant.

## Critical test-only grant issue

The live test catalogue shows authenticated granted every table privilege on the bookkeeping tables, including DELETE, TRUNCATE, TRIGGER, REFERENCES and broad INSERT/UPDATE, even where RLS policies appear more restrictive. RLS does not replace SQL privilege checks and does not protect against all privileged operations such as TRUNCATE. These grants are not acceptable as a production template.

The test role grants also include anon USAGE on both identity sequences. The production candidate must use explicit least-privilege grants and revoke inappropriate anon/authenticated sequence access. Final grants must be determined against verified frontend/RPC callers, not guessed.

## Current blockers before an executable migration can be generated

1. The initial 12-table catalogue response exceeded the connector output limit. Re-query columns/constraints/indexes/policies in small table batches and store the complete result.
2. Extract the full definitions, ACLs, volatility, security mode, configuration and dependencies for every RPC used by the Finance frontend/Edge Functions. The two trigger functions above are not the whole workflow.
3. Capture every trigger attached to the audit and tax objects that bookkeeping depends on, including the audit capture path.
4. Compare each dependency with production: `is_super_admin()`, `admin_has_permission(text)`, `auth.uid()`, role permission keys, and existing `frosttech_tax_settings`.
5. Generate a production-specific migration and rollback only after all preceding checks. Rehearse in a disposable production-equivalent schema; do not apply to production as part of this recovery.

## Release safety

This checkpoint is an evidence document, not runnable SQL. No production migration, storage change, permission change, or financial-record import was performed.
