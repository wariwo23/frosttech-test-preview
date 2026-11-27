# Bookkeeping Migration — No-Cost Static Validation
Date: 27 November 2026
Environment: repository review plus read-only catalog queries against existing test and production projects.
Status: static validation only. No DDL was executed; no project branch, new project, or paid resource was created.

## Cost constraint respected
A temporary Supabase development branch was not created because Supabase requested cost confirmation. The user's instruction is to use a no-cost method. No charge was approved or incurred.

## Tools available
- The existing test Supabase project is already populated with all 12 bookkeeping tables, so the candidate's deliberate "stop if target table exists" guard prevents replaying it there.
- Local runtime does not have `psql`, `postgres`, `docker`, or the Python `pglast` SQL parser available.
- Consequently, this stage uses static source checks and read-only catalog inspection only. It does not claim a live migration rehearsal or syntax-execution pass.

## Static structure checks
Candidate migration currently contains:
- 12 `CREATE TABLE` statements.
- 12 RLS enablement statements.
- 31 policies.
- 2 journal trigger functions and 2 triggers.
- Identity definitions for audit log id and journal entry number.
- A target-existence guard that prevents overwriting any existing target table.
- No anonymous grants.
- No production helper-function replacement and no test-record import.

## Correction made: privilege minimization
The first candidate draft granted INSERT/UPDATE on many tables that the inspected current UI does not write. The grant block has now been narrowed to the actual observed caller paths:
- SELECT: accounts, periods, journals, journal lines, expenses, shareholder loans.
- INSERT: journals and journal lines.
- UPDATE: journals only.
- No authenticated DELETE, TRUNCATE, TRIGGER, REFERENCES or direct audit-log write grants.
- No authenticated grants on future/unverified workflow tables.
This is materially safer and matches the inspected `bookkeeping-admin-test.html` behavior. The associated RLS policies remain in place as row-level controls.

## Existing test catalog index comparison
Read-only catalog inspection of all four batches found only the expected primary-key and unique indexes:
- accounts: PK and unique code
- audit log: PK
- bank accounts: PK
- bank transactions: PK
- documents: PK
- expenses: PK
- fixed assets: PK
- journal lines: PK
- journals: PK and unique entry_number
- periods: PK and unique (start_date,end_date)
- reconciliations: PK
- shareholder loans: PK

No additional non-constraint indexes were returned by the test catalog query.

## Work completed after the initial static checkpoint

- Added append-only audit capture for journal header and journal-line INSERT/UPDATE/DELETE operations, including old/new snapshots, actor ID and timestamp.
- Added a trigger that rejects audit-log UPDATE and DELETE.
- Added authenticated read-only audit-log access under the existing bookkeeping.read permission.
- Added audit-event display to the test bookkeeping page.
- Added separate frontend checks for bookkeeping.reports.read and bookkeeping.documents.manage. Reports are hidden without report permission. Document-management status is displayed, but document-upload controls remain unimplemented.
- Updated rollback to remove audit triggers/functions, while retaining the guard that refuses to drop tables containing data.
- Tightened the migration's audit log SELECT grant to authenticated users only.

Audit coverage is currently journal headers and journal lines only. Other mutable bookkeeping registers still need equivalent audit coverage before the entire module can be called fully audited.

## Important unresolved technical blockers
1. **No executable rehearsal yet.** Static validation cannot prove that PostgreSQL will accept every statement or that all RLS policies behave as intended. Do not represent this as a passed database test.
2. **Audit trail scope.** Journal header and journal-line changes are captured by the candidate. Expenses, bank transactions, documents, periods, chart of accounts, fixed assets, reconciliations and shareholder-loan changes are not yet covered.
3. **UI/permission alignment.** Report-read and document-management permission checks are now present. Document upload is not implemented on this page; Super Admin-only register maintenance is enforced in RLS but needs end-to-end execution testing.
4. **Journal workflow verification.** Static review of the reconstructed guard is not a substitute for exercising draft -> submitted -> approved -> posted, rejected, and immutable states under Finance and Super Admin identities.
5. **Financial report correctness.** Reports are calculated in the browser. Period handling and completeness need review before relying on them for company accounts.
6. **Opening records not seeded.** The ₦100,000 interest-free shareholder loan, ₦10,000 legal-search expense and ₦90,000 bank ledger baseline remain separate from schema creation. Do not seed until source statement and journal states are reconciled.

## Production decision
The candidate is a substantially narrowed and statically reviewed schema package, but remains **not approved for production execution**. No production DDL, permissions, storage or financial records were changed. The next safe no-cost work is to finish the audit mechanism and UI/permission compatibility in source code, then run a rehearsal only if an existing free, disposable PostgreSQL environment is available.
