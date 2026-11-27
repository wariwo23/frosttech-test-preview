# Bookkeeping Migration Candidate — Review and Release Gate
Date: 27 November 2026
Branch: `command-center-shell-stage1`
Target: production Supabase project `nftxptjpgidcsgtaltjn`
Current status: migration and rollback files prepared; NOT applied to either database.

## Files prepared

- `supabase/migrations/20261127190000_create_bookkeeping_core_production_candidate.sql`
- `supabase/rollback/20261127190000_create_bookkeeping_core_production_candidate_rollback.sql`

The migration is reconstructed from the live isolated-test table catalog and checked against the production authorization helpers and existing production permission rows. It is deliberately a new-schema migration because none of the 12 bookkeeping tables currently exist in production.

## What the candidate contains

1. Twelve bookkeeping tables in dependency order.
2. UUID defaults and both GENERATED ALWAYS identity columns.
3. Primary keys, unique constraints, foreign keys and validated checks.
4. Journal and journal-line guard triggers.
5. RLS on every table and policies tied to production's existing `is_super_admin()` and `admin_has_permission(text)` helpers.
6. Explicit grants for authenticated reads and only the current UI's insert/update workflows. No anonymous access and no authenticated DELETE, TRUNCATE, TRIGGER or REFERENCES grants.
7. No test-only grant fallback, no changes to existing production auth helpers, no tax settings changes, no test financial record import.

## Additional hardening applied

The recovered test journal-line guard checked only the destination journal during UPDATE. That left a Super Admin edge case where a line could be moved out of an approved/posted journal into a draft journal. The candidate was hardened to check both the old and new parent journals, and to reject any mutation involving approved or posted journals. This is an intentional security improvement over the test definition.

## Rollback behavior

The rollback first counts rows in all 12 bookkeeping tables. If any row exists, it raises an exception and refuses to drop the tables. This is intentional: financial records must never be discarded by a routine rollback. If production records exist, use a forward repair or access-disable procedure instead.

## Pre-deployment blockers still to close

1. **Migration rehearsal:** the existing test project already contains all 12 tables, so this candidate has not been applied there. Rehearse in a disposable isolated Supabase project or a database clone, not by dropping/recreating the existing test ledger.
2. **Bookkeeping audit trail:** the recovered audit_log table has no confirmed automatic audit-capture trigger in the inspected bookkeeping objects, and the current bookkeeping UI does not write to it. Do not describe it as a functioning audit trail until its write path, append-only enforcement, and actor capture are implemented and verified.
3. **UI/permission alignment:** the current test bookkeeping page writes directly to PostgREST tables. Before production release, patch the UI to align expense/document/period/asset controls with their dedicated permission boundaries. The present page does not currently check `bookkeeping.documents.manage` or `bookkeeping.reports.read` as distinct gates.
4. **Accounting reports:** current UI computes reports client-side from posted journal data. This migration does not add server-side report RPCs or validate financial statement completeness.
5. **Opening financial records:** no records are seeded. The ₦100,000 interest-free shareholder loan and ₦10,000 legal-search expense, with the ₦90,000 bank ledger balance, must be reconciled to the supporting bank statement and approved journal state before any separately authorized production import or entry. The shareholder loan remains a liability, not share capital.
6. **Backup and production approval:** take/verify a production backup and confirm restore capability immediately before deployment. Production deployment remains a separate explicit action.

## Static review observations

- The table dependency order is correct: periods precede journals; journals precede journal lines; journal lines precede bank transactions; all other foreign-key parents precede dependents.
- The two identity columns are GENERATED ALWAYS and are not seeded with test sequence values.
- No migration statement alters or drops existing production tables, policies, helper functions, storage buckets, or tax settings.
- The migration contains a guard that stops if any target bookkeeping table already exists, avoiding accidental partial overwrite.
- The rollback is guarded by non-empty-table checks and must not be run against an environment containing records.

## Deployment decision

**Not yet production-deployable.** The schema candidate is prepared, but a disposable-environment rehearsal and the audit/UI release blockers above must be resolved first. No production changes have been made.
