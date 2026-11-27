# FrostTech Bookkeeping Source Recovery — Detailed Catalog
Date: 27 November 2026
Environment: isolated test Supabase project `gqnidjifiobhqhnxjlow`
Status: source-recovery evidence only; not a production migration.

## Purpose and production alignment

This is a bounded continuation of the production integration register. It records actual live PostgreSQL definitions for the 12 bookkeeping tables in smaller, non-truncated batches. The intent is to reconstruct the missing migration source and then prepare a production-specific, reversible migration. No production objects or records were changed.

## Recovered table definitions

All 12 tables are ordinary permanent tables, owned by `postgres`, with RLS enabled (not FORCE RLS).

### `ft_bookkeeping_accounts`
- `id uuid NOT NULL DEFAULT gen_random_uuid()`
- `code text NOT NULL`; `name text NOT NULL`; `account_type text NOT NULL`
- `parent_id uuid`; `is_active boolean NOT NULL DEFAULT true`
- `created_at timestamptz NOT NULL DEFAULT now()`; `created_by uuid`
- PK `id`; unique `code`; FK `created_by -> auth.users(id)`; self-FK `parent_id -> accounts(id)`
- Check account_type in asset, liability, equity, income, expense.
- Unique code index and PK index.

### `ft_bookkeeping_audit_log`
- `id bigint NOT NULL` (identity sequence described below)
- `table_name text NOT NULL`; `record_id uuid`; `action text NOT NULL`; `actor_id uuid`
- `details jsonb NOT NULL DEFAULT '{}'`; `created_at timestamptz NOT NULL DEFAULT now()`
- PK id; FK actor_id -> auth.users(id); PK index.
- No extra default was exposed for id; identity metadata/sequence ownership is authoritative.

### `ft_bookkeeping_bank_accounts`
- `id uuid NOT NULL DEFAULT gen_random_uuid()`
- `account_name text NOT NULL`; `bank_name text NOT NULL`; `account_number_last4 text`
- `currency char(3) NOT NULL DEFAULT 'NGN'`; `ledger_account_id uuid`
- `is_active boolean NOT NULL DEFAULT true`; `created_at timestamptz NOT NULL DEFAULT now()`
- PK id; FK ledger_account_id -> accounts(id).

### `ft_bookkeeping_bank_transactions`
- `id uuid NOT NULL DEFAULT gen_random_uuid()`; `bank_account_id uuid NOT NULL`
- `transaction_date date NOT NULL`; `description text NOT NULL`; `reference text`
- `debit numeric(18,2) NOT NULL DEFAULT 0`; `credit numeric(18,2) NOT NULL DEFAULT 0`
- `source text NOT NULL DEFAULT 'manual'`; `matched_journal_line_id uuid`
- `created_by uuid`; `created_at timestamptz NOT NULL DEFAULT now()`
- PK id; FK bank_account_id -> bank_accounts(id), matched_journal_line_id -> journal_lines(id), created_by -> auth.users(id).
- Checks: exactly one of debit/credit is positive; each nonnegative; source in manual, statement_import.

### `ft_bookkeeping_documents`
- `id uuid NOT NULL DEFAULT gen_random_uuid()`; `document_type text NOT NULL`; `document_name text NOT NULL`
- `storage_path text`; `external_reference text`; `document_date date`; `related_table text`; `related_record_id uuid`; `notes text`; `uploaded_by uuid`
- `created_at timestamptz NOT NULL DEFAULT now()`
- PK id; FK uploaded_by -> auth.users(id); check storage_path or external_reference must be present.

### `ft_bookkeeping_expenses`
- `id uuid NOT NULL DEFAULT gen_random_uuid()`; `expense_date date NOT NULL`; `payee text NOT NULL`; `description text NOT NULL`
- `account_id uuid NOT NULL`; `amount numeric(18,2) NOT NULL`; `payment_method text`
- `bank_transaction_id uuid`; `journal_id uuid`; `status text NOT NULL DEFAULT 'draft'`
- `prepared_by uuid`; `approved_by uuid`; `approved_at timestamptz`; `created_at timestamptz NOT NULL DEFAULT now()`
- PK id; FKs account_id -> accounts, bank_transaction_id -> bank_transactions, journal_id -> journals, prepared_by/approved_by -> auth.users.
- Checks amount > 0; status in draft, submitted, approved, rejected.

### `ft_bookkeeping_fixed_assets`
- `id uuid NOT NULL DEFAULT gen_random_uuid()`; `asset_name text NOT NULL`; `acquisition_date date NOT NULL`
- `cost numeric(18,2) NOT NULL`; `useful_life_months integer`; `residual_value numeric(18,2) NOT NULL DEFAULT 0`
- `depreciation_method text NOT NULL DEFAULT 'straight_line'`; `accumulated_depreciation numeric(18,2) NOT NULL DEFAULT 0`
- `status text NOT NULL DEFAULT 'active'`; `journal_id uuid`; `supporting_document_id uuid`; `created_at timestamptz NOT NULL DEFAULT now()`
- PK id; FK journal_id -> journals(id).
- Checks: cost > 0; residual_value >= 0 and <= cost; accumulated_depreciation >= 0 and <= cost-residual_value; useful_life_months > 0; status in active, disposed, written_off.

### `ft_bookkeeping_journal_lines`
- `id uuid NOT NULL DEFAULT gen_random_uuid()`; `journal_id uuid NOT NULL`; `account_id uuid NOT NULL`
- `line_description text`; `debit numeric(18,2) NOT NULL DEFAULT 0`; `credit numeric(18,2) NOT NULL DEFAULT 0`
- `created_at timestamptz NOT NULL DEFAULT now()`
- PK id; FK account_id -> accounts(id) ON DELETE RESTRICT; FK journal_id -> journals(id) ON DELETE RESTRICT.
- Checks: exactly one of debit/credit is positive; both nonnegative.
- BEFORE INSERT/UPDATE/DELETE trigger `ft_bookkeeping_journal_line_guard` calls `ft_bookkeeping_guard_journal_line()`.

### `ft_bookkeeping_journals`
- `id uuid NOT NULL DEFAULT gen_random_uuid()`; `entry_number bigint NOT NULL` (identity sequence described below)
- `entry_date date NOT NULL`; `description text NOT NULL`; `source_type text NOT NULL DEFAULT 'manual'`; `source_reference text`
- `period_id uuid`; `status text NOT NULL DEFAULT 'draft'`; `prepared_by uuid`; `submitted_at timestamptz`
- `approved_by uuid`; `approved_at timestamptz`; `posted_by uuid`; `posted_at timestamptz`
- `created_at timestamptz NOT NULL DEFAULT now()`; `updated_at timestamptz NOT NULL DEFAULT now()`
- PK id; unique entry_number; FKs period_id -> periods(id), prepared_by/approved_by/posted_by -> auth.users.
- Check status in draft, submitted, approved, posted, rejected.
- BEFORE INSERT/UPDATE trigger `ft_bookkeeping_journal_guard` calls `ft_bookkeeping_guard_journal()`.

### `ft_bookkeeping_periods`
- `id uuid NOT NULL DEFAULT gen_random_uuid()`; `period_name text NOT NULL`; `start_date date NOT NULL`; `end_date date NOT NULL`
- `status text NOT NULL DEFAULT 'open'`; `closed_at timestamptz`; `closed_by uuid`; `created_at timestamptz NOT NULL DEFAULT now()`
- PK id; unique (start_date,end_date); FK closed_by -> auth.users; checks end_date >= start_date and status in open, closed.

### `ft_bookkeeping_reconciliations`
- `id uuid NOT NULL DEFAULT gen_random_uuid()`; `bank_account_id uuid NOT NULL`; `period_start date NOT NULL`; `period_end date NOT NULL`
- `statement_closing_balance numeric(18,2) NOT NULL`; `ledger_closing_balance numeric(18,2) NOT NULL`
- `difference numeric(18,2) DEFAULT (statement_closing_balance - ledger_closing_balance)`
- `status text NOT NULL DEFAULT 'draft'`; `prepared_by uuid`; `approved_by uuid`; `approved_at timestamptz`
- `supporting_document_id uuid`; `created_at timestamptz NOT NULL DEFAULT now()`
- PK id; FKs bank_account_id -> bank_accounts(id), prepared_by/approved_by -> auth.users.
- Checks period_end >= period_start; status in draft, submitted, approved.

### `ft_bookkeeping_shareholder_loans`
- `id uuid NOT NULL DEFAULT gen_random_uuid()`; `lender_name text NOT NULL`; `principal_amount numeric(18,2) NOT NULL`
- `interest_rate numeric(7,4) NOT NULL DEFAULT 0`; `repayment_terms text NOT NULL`; `agreement_date date`
- `amount_repaid numeric(18,2) NOT NULL DEFAULT 0`; `status text NOT NULL DEFAULT 'outstanding'`
- `journal_id uuid`; `supporting_document_id uuid`; `created_by uuid`; `created_at timestamptz NOT NULL DEFAULT now()`
- PK id; FKs journal_id -> journals(id), created_by -> auth.users.
- Checks principal_amount > 0; interest_rate >= 0; amount_repaid >= 0 and <= principal_amount; status in outstanding, partially_repaid, repaid.

## Identity sequences

- `public.ft_bookkeeping_audit_log_id_seq` is owned by `ft_bookkeeping_audit_log.id`.
- `public.ft_bookkeeping_journals_entry_number_seq` is owned by `ft_bookkeeping_journals.entry_number`.
- Preserve identity generation, ownership, sequence state and grants. Do not replace with plain serial defaults.

## RLS policies recovered

All policies target role `authenticated`. Their predicates use `is_super_admin()` and/or `admin_has_permission(...)`.

| Table | Policy | Command | Predicate |
|---|---|---|---|
| accounts | accounts_read | SELECT | Super Admin OR `bookkeeping.read` |
| accounts | accounts_write | ALL | Super Admin |
| audit_log | audit_read | SELECT | Super Admin OR `bookkeeping.read` |
| bank_accounts | bank_accounts_read | SELECT | Super Admin OR `bookkeeping.read` |
| bank_accounts | bank_accounts_write | ALL | Super Admin |
| bank_transactions | bank_tx_prepare | INSERT | Super Admin OR `bookkeeping.prepare` |
| bank_transactions | bank_tx_read | SELECT | Super Admin OR `bookkeeping.read` |
| bank_transactions | bank_tx_update | UPDATE | Super Admin |
| documents | documents_insert | INSERT | Super Admin OR `bookkeeping.documents.manage` |
| documents | documents_read | SELECT | Super Admin OR `bookkeeping.read` |
| documents | documents_update | UPDATE | Super Admin |
| expenses | expenses_insert | INSERT | Super Admin OR `bookkeeping.prepare` |
| expenses | expenses_read | SELECT | Super Admin OR `bookkeeping.read` |
| expenses | expenses_update | UPDATE | Super Admin OR prepare permission; check restricts non-Super Admin to draft/submitted/rejected |
| fixed_assets | assets_prepare | INSERT | Super Admin OR `bookkeeping.prepare` |
| fixed_assets | assets_read | SELECT | Super Admin OR `bookkeeping.read` |
| fixed_assets | assets_update | UPDATE | Super Admin |
| journal_lines | lines_insert | INSERT | Super Admin OR `bookkeeping.prepare` |
| journal_lines | lines_read | SELECT | Super Admin OR `bookkeeping.read` |
| journal_lines | lines_update | UPDATE | Super Admin OR prepare permission and parent journal remains draft |
| journals | journals_insert | INSERT | Super Admin OR `bookkeeping.prepare` |
| journals | journals_read | SELECT | Super Admin OR `bookkeeping.read` |
| journals | journals_update | UPDATE | Super Admin OR prepare permission; using only draft, check allows draft/submitted |
| periods | periods_prepare | INSERT | Super Admin OR `bookkeeping.prepare` |
| periods | periods_read | SELECT | Super Admin OR `bookkeeping.read` |
| periods | periods_update | UPDATE | Super Admin |
| reconciliations | reconciliations_insert | INSERT | Super Admin OR `bookkeeping.prepare` |
| reconciliations | reconciliations_read | SELECT | Super Admin OR `bookkeeping.read` |
| reconciliations | reconciliations_update | UPDATE | Super Admin OR prepare permission; check permits draft/submitted |
| shareholder_loans | loans_read | SELECT | Super Admin OR `bookkeeping.read` |
| shareholder_loans | loans_write | ALL | Super Admin |

Important: RLS policies are not substitutes for table-level GRANT privileges. Test currently grants authenticated broad table privileges including DELETE, TRUNCATE, TRIGGER and REFERENCES. Production must explicitly revoke excess grants and grant only operations needed by verified RPC/function paths and approved frontend reads.

## Journal trigger safeguards

The live function definitions were recovered exactly in the prior checkpoint. Key protections:
- Submitted/approved journals cannot be altered by Finance Admin.
- Only Super Admin can approve or post.
- Posted journals are immutable; correction requires a separately approved reversal/adjustment.
- Posting requires at least two lines, balanced non-zero debits/credits, an assigned period, journal date within period, and an open period.
- Journal-line mutation is blocked once the journal is no longer draft, subject to the Super Admin path and explicit approved/posted immutability check.
- Both functions are invoker-security and set an empty search_path; do not grant browser users direct EXECUTE on trigger helpers.

## Remaining release blockers

1. This catalogue records table/constraint/index and RLS state, but the exact full original migration source files are still missing from the repository. A reconstructed SQL file must be clearly marked reconstructed, not presented as recovered original source.
2. Need inspect actual identity generation metadata and current sequence values, plus all function/trigger dependencies and grants, before writing DDL.
3. Need inspect full policies on production for similarly named tables/functions, and compare permission keys. Do not overwrite production role mapping.
4. Need inspect bookkeeping UI/Edge Function callers to establish minimum table grants and required RPCs.
5. Need reconcile the bookkeeping audit-log insert path and audit capture function; the earlier identity metadata confirms the audit id sequence is owned by the identity column.
6. Need confirm status transitions for expense, reconciliation, period and shareholder-loan workflows; direct table writes should not bypass required approval workflow.
7. Need prepare and rehearse a production-specific rollback that does not delete financial data. For financial tables, rollback should normally disable/revoke newly added access or detach new objects rather than drop tables containing records.

## Production release status

No production migration, grants, storage changes, or financial record imports were performed in this stage. This report is not executable SQL and does not authorize production deployment.
