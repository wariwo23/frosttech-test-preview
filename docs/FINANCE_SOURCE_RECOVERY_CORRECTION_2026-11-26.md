# FrostTech Finance Integration — Corrected Source Recovery and Release Status
Date: 26 November 2026
Branch: command-center-shell-stage1
Production project: nftxptjpgidcsgtaltjn
Isolated test project: gqnidjifiobhqhnxjlow

## Correction to prior report
The earlier statement that no authoritative Finance migration history could be found was incomplete. A live query of the isolated test database migration ledger confirms these applied migration records:
- 20261122060405 frosttech_finance_tax_settlement_foundation
- 20261122060914 frosttech_supplier_settlement_preparation
- 20261122060930 frosttech_supplier_settlement_submission
- 20261122061253 frosttech_supplier_settlement_approval
- 20261122062700 frosttech_tax_administration_workflows
- 20261122062753 frosttech_tax_profile_and_assessment_hardening
- 20261122062829 frosttech_tax_evidence_storage_and_validation
- 20261122062855 frosttech_tax_evidence_immutability_and_idempotency
- 20261123142843 tax_administration_integrity_hardening
- 20261123142927 tax_assessment_source_dedup_guard
- 20261123143050 tax_assessment_concurrency_guard
- 20261123143142 tax_settlement_net_basis_grossup
- 20261123143221 tax_assessment_source_normalization
- 20261126154754 create_isolated_bookkeeping_core
- 20261126154819 add_bookkeeping_posting_guardrails
- 20261126155520 harden_bookkeeping_journal_workflow

The corresponding three bookkeeping migration SQL files are NOT present in the checked branch's supabase/migrations directory listing. Their earlier guessed paths returned 404. Therefore the database ledger proves the migrations ran, but does not supply their original SQL source. Do not equate migration ledger presence with recoverable source code.

## Finance dependency source files recovered
The branch does contain:
- 20261123180000_command_center_finance_workspace_dependencies_draft.sql (32,478 bytes; draft, isolated-test only; this is financial quotation-cost workflow support, not the base bookkeeping schema).
- 20261123200000_tax_administration_integrity_hardening.sql (26,800 bytes; test-specific tax hardening).
- 20261123203000_tax_assessment_source_dedup_guard.sql.
- 20261123210000_tax_assessment_concurrency_guard.sql.
- 20261123220000_tax_settlement_net_basis_grossup.sql.
- 20261123223000_tax_assessment_source_normalization.sql.
- 20261123230000_isolated_test_finance_admin_access.sql.
- 20261123233000_supplier_disbursement_evidence_hardening_DRAFT.sql (explicitly draft only).

These files contain environment-specific references such as 'isolated_test', test role names/permissions and assumptions about test schema. They must not be applied verbatim to production.

## Live schema and policy findings
- Production currently has only frosttech_tax_settings among the bookkeeping/journal/tax-assessment/supplier-settlement table-name families.
- Test has the complete bookkeeping, tax and settlement table families.
- The test Finance policies include read/prepare boundaries and Super Admin-only write/approval boundaries for key accounting tables.
- Supplier settlement approval is explicitly Super Admin-only; Finance prepares and submits.
- Test migration ledger shows the bookkeeping core and two subsequent posting/journal hardening migrations were applied on 26 November.
- The full live function definitions and complete table constraints still need extraction into source-controlled, reviewed migration files. Do not reconstruct by guessing or use pg_dump assumptions.

## Opening accounting records
Preserve and reconcile, not blindly copy:
- Shareholder loan: NGN 100,000 received 20 November 2026, interest-free liability, not share capital.
- Legal search expense: NGN 10,000.
- Resulting bank ledger balance: NGN 90,000.
- The bank statement is the source evidence.
- The legal search expense's approval/posting state was previously unresolved. Verify before posting.
- Use stable idempotency references and check for existing production matches before importing.

## Next required work
1. Recover or reconstruct the exact three bookkeeping migration definitions from authoritative source/commit history; if unavailable, extract exact live test table DDL, indexes, constraints, triggers, functions, grants and policies into a reviewable source package.
2. Reconcile test and production enum/type dependencies and storage evidence policies.
3. Prepare production-specific migration and rollback, including explicit preservation of existing tax settings.
4. Rehearse against a production-equivalent isolated schema and verify role separation.
5. Back up production and confirm recovery point before any DDL.
6. Apply only after preflight and rollback review; import accounting records only after idempotency checks.
7. Verify balanced journals, loan classification, expense status, bank reconciliation, immutable audit history and Super Admin approval boundaries.

## Status
Finance production schema integration remains BLOCKED pending authoritative DDL recovery and production-specific rehearsal. No Finance schema or accounting rows were changed in production in this stage.
