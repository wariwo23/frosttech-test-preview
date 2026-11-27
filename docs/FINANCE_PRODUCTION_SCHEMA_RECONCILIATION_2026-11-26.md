# FrostTech Finance Production Schema Reconciliation
Date: 26 November 2026
Scope: production project nftxptjpgidcsgtaltjn compared with isolated test project gqnidjifiobhqhnxjlow.

## Verified live database findings
- Production public finance-related base tables matching bookkeeping, journal, tax, settlement and disbursement names: only `frosttech_tax_settings`.
- Isolated test contains the bookkeeping, tax and supplier settlement table families:
  - `ft_bookkeeping_accounts`, `ft_bookkeeping_audit_log`, `ft_bookkeeping_bank_accounts`, `ft_bookkeeping_bank_transactions`, `ft_bookkeeping_documents`, `ft_bookkeeping_expenses`, `ft_bookkeeping_fixed_assets`, `ft_bookkeeping_journal_lines`, `ft_bookkeeping_journals`, `ft_bookkeeping_periods`, `ft_bookkeeping_reconciliations`, `ft_bookkeeping_shareholder_loans`.
  - `frosttech_tax_assessments`, `frosttech_tax_audit_log`, `frosttech_tax_certificates`, `frosttech_tax_remittances`, `frosttech_tax_rules`, `frosttech_supplier_tax_profiles`.
  - `frosttech_supplier_settlements`, `frosttech_supplier_settlement_items`, `frosttech_supplier_settlement_audit`, `frosttech_supplier_disbursements`.
- This confirms Finance schema parity has not been reached. No Finance schema or financial rows were copied into production during this reconciliation.
- Test schema has relational constraints and workflow state fields (including journal status, approval/posting actors, shareholder-loan interest rate and repayment fields, tax rule snapshots, WHT snapshots, settlement approval/rejection trail and idempotent disbursement references). Those dependencies must be migrated as a complete ordered package.
- Attempted retrieval of three previously cited bookkeeping migration paths from the test repository returned GitHub 404. Those paths are therefore not verified source artifacts and must not be used as a migration source until recovered from the actual repository history or regenerated from live test schema and function definitions.

## Accounting records that must be reconciled, not blindly copied
- Shareholder financing: NGN 100,000 received 20 November 2026; interest-free shareholder loan, liability, not paid-up share capital.
- Legal search expense: NGN 10,000.
- Resulting bank ledger balance: NGN 90,000.
- Previously noted test journal workflow includes two balanced journal entries; expense approval/posting status needs reconciliation against source evidence before production posting.
- Bank statement is the source document. Preserve its attachment/document reference and audit trail.
- Do not duplicate existing production entries. Before importing, query production for matching transaction references, dates, descriptions and amounts.

## Required migration order
1. Capture production backup/recovery point and exact schema/migration baseline.
2. Recover authoritative test migration SQL or regenerate a reviewed schema-only migration from live test definitions.
3. Migrate enums/types, base tables, constraints, indexes and foreign keys in dependency order.
4. Migrate triggers and helper functions; verify SECURITY DEFINER search_path and role checks.
5. Enable RLS and recreate table policies; remove broad direct writes and TRUNCATE grants.
6. Add RPCs and grants only after confirming every referenced table/function exists.
7. Integrate Finance frontend and document storage policies.
8. Import only verified opening records with stable idempotency keys and supporting-document references.
9. Verify journal balancing, loan classification, expense status, bank reconciliation, audit trail, Finance-vs-Super-Admin separation and rollback.
10. Only then mark Finance package ready for production.

## Authority boundaries
- Finance may prepare bookkeeping, assess taxes under approved rules, prepare settlement packs and reconcile payments.
- Super Administrator retains tax-rule configuration authority and final supplier settlement approval.
- Supplier costs and settlement data must not be exposed to customers, suppliers or unrelated departmental roles.
- Tax/WHT rates must use approved effective-dated rules; do not hardcode a rate into settlement migrations.

## Release status
BLOCKED from production schema application pending authoritative migration source recovery, full dependency review, backup confirmation, and isolated rehearsal of the exact production candidate. Production was not modified by this reconciliation.
