# Finance Schema Reconstruction — Live Definition Audit
Date: 26 November 2026
Source: isolated test Supabase project gqnidjifiobhqhnxjlow
Target: production project nftxptjpgidcsgtaltjn
Status: source audit in progress; no production DDL applied.

## Live structures confirmed
The isolated test database contains the bookkeeping, tax and supplier settlement families:
- ft_bookkeeping_accounts
- ft_bookkeeping_audit_log
- ft_bookkeeping_bank_accounts
- ft_bookkeeping_bank_transactions
- ft_bookkeeping_documents
- ft_bookkeeping_expenses
- ft_bookkeeping_fixed_assets
- ft_bookkeeping_journal_lines
- ft_bookkeeping_journals
- ft_bookkeeping_periods
- ft_bookkeeping_reconciliations
- ft_bookkeeping_shareholder_loans
- frosttech_tax_rules, frosttech_tax_assessments, frosttech_tax_audit_log, frosttech_tax_certificates, frosttech_tax_remittances, frosttech_supplier_tax_profiles
- frosttech_supplier_settlements, frosttech_supplier_settlement_items, frosttech_supplier_settlement_audit, frosttech_supplier_disbursements

## Critical definition details
- Tables use RLS. RLS is enabled but not FORCE RLS on the captured set.
- Settlement tables contain WHT calculation snapshots and constraints; settlement net payable must equal gross entitlement less WHT amount.
- Settlement approval cannot be performed by the same user who prepared it.
- Rejection requires actor, timestamp and a reason of at least five characters.
- Settlement status transitions include draft, submitted, approved, rejected, processing, partially_paid, paid, failed and cancelled.
- Disbursement records enforce idempotency keys, NGN currency, positive amount, unique payment/provider references and verification evidence for successful status.
- Tax assessments are unique per transaction type/id, direction and tax type; rate constrained to 0–100%; tax rule snapshots are retained.
- Tax rules are effective-dated, distinguish VAT/WHT, and store calculation basis, entity type and residency status.
- Test Finance tables grant authenticated SELECT at table level but no direct authenticated INSERT and no anon SELECT/INSERT/TRUNCATE in the sampled privilege check. RLS policies therefore remain the effective read boundary; grants and policies must be migrated together.
- A bookkeeping audit-log primary key uses bigint without a default in the captured column definition. Verify whether the sequence/identity mechanism exists before recreating this table; a naive DDL reconstruction would break audit inserts.
- A generated DDL draft must preserve column identity/generated flags, ownership, sequence/default dependencies, constraint validation state, indexes, triggers, function dependencies, policy expressions and function EXECUTE grants. Do not use a simplified table-only export.

## Required next source-recovery tasks
1. Extract each table definition with identity/generated attributes and sequence ownership.
2. Extract all functions called by triggers and RPCs, not only functions whose names contain bookkeeping/tax/settlement.
3. Extract trigger functions, trigger definitions and exact grants.
4. Extract all policies, including helper-function definitions and role membership/permission dependencies.
5. Extract Storage policies and bucket configuration for tax certificates, evidence and bookkeeping documents.
6. Compare all dependencies with production, especially suppliers, orders/order_items, profiles, admin_accounts, admin_role_permissions and tax_settings.
7. Produce separate ordered migrations: schema/types; constraints/indexes; functions/triggers; RLS/policies/grants; storage; RPC/frontend compatibility.
8. Rehearse the exact candidate against an isolated production-equivalent schema before production backup and deployment.

## Financial record controls
Do not import test finance rows wholesale. Reconcile the opening evidence against production:
- NGN 100,000 interest-free shareholder loan received 20 November 2026 (liability, not share capital).
- NGN 10,000 legal search expense.
- NGN 90,000 resulting bank ledger balance.
- Bank statement is source evidence. Legal search expense approval/posting status must be confirmed before posting.
Use stable idempotency references and check production for existing entries before import.

## Release decision
Finance schema migration remains blocked pending complete extraction of transitive functions, trigger logic, sequence/default dependencies, exact grants and storage rules. Production remains unchanged by this audit.
