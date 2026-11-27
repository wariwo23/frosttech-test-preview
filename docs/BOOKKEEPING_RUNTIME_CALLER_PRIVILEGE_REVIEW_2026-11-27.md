# Bookkeeping Runtime Caller and Privilege Review
Date: 27 November 2026
Environment: isolated test repository branch `command-center-shell-stage1` and test Supabase project `gqnidjifiobhqhnxjlow`.
Status: compatibility evidence; no production changes.

## Frontend file inspected

`bookkeeping-admin-test.html` was inspected in full. Its direct database operations establish the current test UI's actual access needs.

### Direct reads

The page directly SELECTs:
- `ft_bookkeeping_accounts`: id, code, name, account_type, is_active
- `ft_bookkeeping_periods`: id, period_name, start_date, end_date, status
- `ft_bookkeeping_journals`: id, entry_number, entry_date, description, source_reference, status, created_at
- `ft_bookkeeping_journal_lines`: journal_id, account_id, line_description, debit, credit
- `ft_bookkeeping_expenses`: expense_date, payee, description, amount, status, payment_method
- `ft_bookkeeping_shareholder_loans`: lender_name, principal_amount, interest_rate, amount_repaid, repayment_terms, status, agreement_date, created_at (used for ordering)

The page calculates trial balance, profit and loss, balance sheet and bank movement client-side from posted journal entries and account types. It does not call a dedicated bookkeeping reporting RPC in this version.

### Direct writes

Finance preparer path:
1. INSERT a draft into `ft_bookkeeping_journals`, setting prepared_by to the authenticated user.
2. INSERT balanced lines into `ft_bookkeeping_journal_lines`.
3. UPDATE the journal status to submitted and set submitted_at.

Super Administrator path:
- UPDATE `ft_bookkeeping_journals.status` to approved.
- UPDATE `ft_bookkeeping_journals.status` to posted.

The trigger function is the decisive server-side enforcement for approval/posting and immutable posted journals. RLS policies separately constrain who can issue those updates. The UI does not directly write to accounts, periods, expenses, fixed assets, bank accounts, bank transactions, reconciliations, shareholder loans, or audit_log.

### Runtime role checks

The page calls:
- `admin_get_my_role()`
- `admin_has_permission('bookkeeping.read')`
- `admin_has_permission('bookkeeping.prepare')`

Super Admin is permitted by the page's role check. Departmental access requires the matching permission checks. The database RLS policies also use `is_super_admin()` and `admin_has_permission(text)`; these are critical dependencies and must be verified against production definitions and grants before migration.

## Minimum privilege direction (not final SQL)

Based only on this inspected page, a production grant matrix should start with:
- SELECT on the six directly-read tables for authenticated users, with RLS restricting records to authorized Finance and Super Admin.
- INSERT on journals and journal_lines for authenticated preparers, with RLS checks and the journal guard enforcing workflow.
- UPDATE on journals for the controlled submit/approve/post workflow, with RLS and trigger checks retained.
- No authenticated DELETE, TRUNCATE, TRIGGER or REFERENCES grants.
- No broad direct-write grants on read-only register tables.
- No direct authenticated writes to audit_log; audit writes should be made only through the verified audit capture path.
- Sequence access must be derived from identity behavior and actual caller behavior; do not grant broad sequence privileges by default.

This is a starting least-privilege assessment, not an approved final grant script. It does not yet account for future UI versions, server-side functions, or other consumers.

## Confirmed identity metadata

- `ft_bookkeeping_audit_log.id`: GENERATED ALWAYS AS IDENTITY, sequence `public.ft_bookkeeping_audit_log_id_seq`.
- `ft_bookkeeping_journals.entry_number`: GENERATED ALWAYS AS IDENTITY, sequence `public.ft_bookkeeping_journals_entry_number_seq`.
- Both sequences are owned by postgres, increment 1, start 1, cache 1, no cycle.
- Test sequence last_value at inspection: audit log 7; journal entry number 4. These are test state only and must never be copied as production sequence values.

## Material findings / release blockers

1. The test grants authenticated ALL table privileges on every bookkeeping table, including DELETE, TRUNCATE, TRIGGER and REFERENCES. This is excessive and must not be replicated.
2. The current bookkeeping frontend uses direct PostgREST table access rather than an all-RPC architecture. A production migration must preserve those exact callers or refactor the frontend and database together; do not revoke INSERT/UPDATE without a compatible frontend change.
3. The current UI's report calculations are client-side and use posted journal rows. They need a separate correctness review before production use (especially period selection, comparative periods, cash-flow completeness and auditability).
4. Expenses and shareholder loans are read-only in this page. The ₦10,000 legal-search expense row still requires explicit status/journal reconciliation before any posting; the ₦100,000 shareholder financing remains an interest-free liability, not equity.
5. Approval/posting controls are hidden in the UI for non-Super Admin, but UI hiding is not security. RLS and trigger enforcement remain mandatory.
6. The test environment's identity sequence values are not production seeds. Sequence ownership/identity mode must be preserved, but production sequence state must be initialized from the production table's own values if these objects are ever installed there.
7. GitHub code search did not return indexed matches for the table/function identifiers on the test branch. The repository tree was therefore used to locate and inspect the actual `bookkeeping-admin-test.html` page.

## Next bounded recovery steps

- Capture the complete dependency definitions and ACLs for `is_super_admin()`, `admin_has_permission(text)`, `admin_get_my_role()`, and any audit capture functions used by bookkeeping.
- Inspect all triggers on the wider tax/finance tables that write to bookkeeping audit records.
- Compare the required bookkeeping permission keys and helper-function definitions with production without modifying production.
- Then draft a production-specific migration and non-destructive rollback package. Do not execute it in production.
