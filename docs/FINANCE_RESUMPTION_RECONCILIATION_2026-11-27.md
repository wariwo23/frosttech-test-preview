# FrostTech Finance — Resumption Reconciliation
Date: 27 November 2026
Scope: read-only comparison of production project `nftxptjpgidcsgtaltjn`, isolated test project `gqnidjifiobhqhnxjlow`, and their GitHub migration directories.
Status: audit update only. No database, storage, payment, or financial-row mutations were made.

## Confirmed production state

- Production's migration ledger currently ends at `20261126204816 production_four_department_roles_and_appointment`.
- The repository contains `20261126223000_production_finance_department_permissions.sql`, whose header says it was applied on 26 November. However, that version is **not** present in the production migration ledger returned on 27 November.
- A live read of `admin_role_permissions` confirms that all 14 Finance permission rows from that SQL file are already present in production. Do not replay or duplicate this permission insert. Reconcile the migration-history discrepancy separately; do not insert a fabricated migration-history row.
- The production public-schema inventory currently contains `frosttech_tax_settings` only among the audited Finance/tax/bookkeeping object families. The production bookkeeping tables, tax workflow tables, and supplier-settlement tables are not yet present.
- Preserve the existing production `frosttech_tax_settings` row, policy, and trigger. Do not recreate or reset it.

## Confirmed isolated test state

- The test migration ledger contains the three bookkeeping migrations:
  - `20261126154754 create_isolated_bookkeeping_core`
  - `20261126154819 add_bookkeeping_posting_guardrails`
  - `20261126155520 harden_bookkeeping_journal_workflow`
- The three corresponding SQL source files were not found in the inspected test branch's `supabase/migrations` directory, and code search did not return matching source. Their SQL cannot be reconstructed from the migration ledger alone.
- The test project contains the 12 `ft_bookkeeping_*` tables, with RLS enabled. The live catalog confirms a sequence for `ft_bookkeeping_audit_log.id` and a sequence for journal entry numbers; these dependencies must be preserved in any recovered DDL.
- The test project also contains tax and supplier-settlement workflow tables. These are test-only until separately reconciled and approved for production.

## Release decisions

1. No Finance migration is approved for production execution yet.
2. Do not copy the test database wholesale or apply test migrations by version alone.
3. Recover the three bookkeeping definitions from live PostgreSQL catalogs: columns/defaults/identity, sequences, constraints, indexes, ownership, RLS policies, grants, triggers, and dependent functions. Capture exact function definitions and transitive helper dependencies.
4. Compare the recovered definitions with production's existing tax-settings objects and current role/permission model before assembling a production-specific migration.
5. Generate a matching rollback and rehearse the candidate against a disposable production-equivalent schema before any production change.
6. Keep the opening accounting evidence separate from schema migration: the ₦100,000 shareholder loan, ₦10,000 legal search expense, and ₦90,000 bank balance must be imported only after source-document, duplicate, and expense-approval checks.

## Important distinction

A committed SQL file, a migration-ledger entry, and a live database object are three different forms of evidence. This reconciliation records all three separately. The Finance permission rows exist in production even though the corresponding committed migration version is absent from the production ledger. That mismatch must be reconciled without blindly replaying the SQL or fabricating migration history.
