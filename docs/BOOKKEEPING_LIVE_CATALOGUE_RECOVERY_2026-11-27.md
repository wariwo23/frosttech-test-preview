# FrostTech Bookkeeping — Live Catalogue Recovery Report
Date: 27 November 2026
Source: isolated test project `gqnidjifiobhqhnxjlow`
Target: production project `nftxptjpgidcsgtaltjn`
Status: read-only catalogue recovery. No database or financial rows changed.

## Recovery result

The three missing bookkeeping migration source files can be reconstructed from the live test PostgreSQL catalogue. The recovered object family consists of 12 tables:

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

The catalogue extraction captured each table's ordered columns, data types, defaults, nullability, constraints, foreign keys, RLS flags, policies, and indexes. The reconciliation table has a stored generated `difference` column. The audit-log ID is a bigint identity column; journal entry number is a bigint identity column. Their owned sequences are:

- `public.ft_bookkeeping_audit_log_id_seq`
- `public.ft_bookkeeping_journals_entry_number_seq`

Both identity sequences use increment 1, start 1, cache 1, and no cycle. Their exact owned-column relationships were confirmed using `pg_get_serial_sequence`.

## Guard functions and triggers

The recovered bookkeeping-specific functions are:

- `public.ft_bookkeeping_guard_journal()`
- `public.ft_bookkeeping_guard_journal_line()`

Both are trigger functions, PL/pgSQL, SECURITY INVOKER, with an empty search_path. Browser roles do not have EXECUTE; the inspected grants list postgres and service_role only.

Triggers:
- `ft_bookkeeping_journals`: BEFORE INSERT OR UPDATE invokes `ft_bookkeeping_guard_journal()`.
- `ft_bookkeeping_journal_lines`: BEFORE INSERT OR UPDATE OR DELETE invokes `ft_bookkeeping_guard_journal_line()`.

Journal safeguards recovered:
- Posted journals are immutable.
- Submitted/approved journals cannot be changed by Finance Admin.
- Only Super Admin can approve or post.
- Posting requires at least two lines, equal non-zero debits and credits, an assigned accounting period, entry date inside the period, and an open period.
- Approval/posting actor and timestamps are set by the trigger.

Journal-line safeguards recovered:
- Lines are locked after submission for non-Super Admin users.
- Approved and posted journal lines are immutable.

The test `admin_has_permission(text)` helper is NOT production-compatible: its test definition also consults `isolated_test_admin_grants`. Production's helper checks only active admin accounts, active profiles, and production `admin_role_permissions`. Production helper definitions were read and compared. The production helper must be retained and referenced; never copy the test helper body.

## Critical grant finding — do not copy test grants

All 12 test bookkeeping tables have RLS enabled, but RLS is not forced. The inspected table ACLs grant authenticated users the full table privilege set, including DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN, INSERT, UPDATE, and SELECT. RLS policies do not protect TRUNCATE. This means the test ACLs are materially over-broad and must NOT be reproduced in production.

The two identity sequences also expose SELECT, UPDATE, and USAGE to anon and authenticated in the test project. Do not reproduce these broad sequence grants. Production grants must be deliberately minimal and aligned with verified frontend/RPC callers. RLS and SQL grants must be designed together.

## RLS policy intent

The recovered policies consistently distinguish:
- read access: Super Admin or `bookkeeping.read`;
- preparation: Super Admin or `bookkeeping.prepare`;
- document upload: Super Admin or `bookkeeping.documents.manage`;
- account setup, bank-account setup, period closure, and shareholder-loan maintenance: Super Admin-only;
- journal approval and posting: Super Admin-only, enforced again by trigger logic.

The exact policy expressions, command types, and check expressions were captured in the recovery worksheet. Production policies must use the production `is_super_admin()` and `admin_has_permission(text)` helpers, not test-only authorization paths.

## Production compatibility observations

- Production does not contain the 12 bookkeeping tables. The prior live inventory showed only `frosttech_tax_settings` among the target Finance/bookkeeping table family.
- Production `frosttech_tax_settings` must remain untouched by this recovery.
- Production already has the production-compatible authorization helpers. The test `admin_has_permission` body contains a test-only grant-table branch; production's helper does not.
- Do not import test rows as part of schema recovery.
- The opening shareholder loan, legal search expense, and bank balance remain a separate evidence-led import task.

## Next safe work

1. Assemble a reconstructed source package from the catalogue evidence, preserving all 12 table definitions, identity/generated columns, FK order, constraints, indexes, triggers, and policies.
2. Produce a separate production grant plan that does not carry over test's broad authenticated/anon ACLs.
3. Verify every frontend/Edge Function caller and authorization helper before assigning grants.
4. Produce rollback SQL that drops only objects created by the candidate and does not touch production tax settings or existing marketplace objects.
5. Rehearse against a disposable production-equivalent schema. No production execution is authorized by this report.

## Evidence boundary

A live catalogue definition is authoritative for the current test schema, but it is not a substitute for the missing original migration history. The reconstructed package must be labelled as recovered-from-live-schema, include its provenance, and be reviewed against application callers before release.
