# FrostTech Finance Integration — Trigger, Grants and Storage Dependency Audit
Date: 26 November 2026
Source project: gqnidjifiobhqhnxjlow (isolated test)
Target project: nftxptjpgidcsgtaltjn (production)
Status: review-only. No production database changes.

## Trigger functions recovered
The live test schema uses a shared SECURITY DEFINER trigger function:
- public.frosttech_capture_financial_audit()
  - search_path is set to empty.
  - Captures old/new row images.
  - Redacts supplier tax_identifier from audit snapshots.
  - Routes tax-rule, tax-assessment, tax-remittance, tax-certificate and supplier-tax-profile changes to frosttech_tax_audit_log.
  - Routes supplier settlement, settlement item and disbursement changes to frosttech_supplier_settlement_audit.
  - Depends on both audit tables existing before trigger installation.
- public.frosttech_reject_audit_mutation()
  - SECURITY DEFINER with empty search_path.
  - Rejects UPDATE/DELETE and TRUNCATE against append-only supplier settlement audit records.

Observed trigger installations include financial audit capture on supplier disbursements, settlement items, settlements and tax assessments; append-only mutation guards on supplier settlement audit. The full trigger inventory and remaining tables must be cross-checked before migration assembly.

## Table grants
The test environment grants authenticated SELECT on the reviewed Finance tables; writes are mediated through privileged functions/service role and RLS policies rather than broad authenticated table writes. Service role has backend privileges. Production migration must reproduce only the necessary privileges and preserve the separation between browser roles and service-role execution.
A sampled privilege result is not a substitute for the full grant matrix. Extract and review every table, sequence, function and schema grant before deployment.

## Storage dependencies recovered
Test storage.objects policies reference these private buckets:
- frosttech-tax-documents
  - Finance insert/read gated by tax.remittances.manage OR tax.certificates.manage.
- supplier-disbursement-evidence
  - Insert/read gated by supplier_settlements.execute.
  - Upload paths enforce settlement UUID folder and uploader UID folder.
- advertiser-documents (existing unrelated workflow; preserve current ownership and reviewer access).
- direct-quotation-documents (service-role-only; preserve).
These are not all Finance buckets. Check storage.buckets metadata, file-size/MIME restrictions, bucket privacy, object ownership and any existing production bucket name collisions before creating buckets or policies.

## Important authorization conflict to resolve
The test storage policy for supplier-disbursement-evidence requires supplier_settlements.execute, while the approved responsibility model reserves final settlement authorization/approval to Super Administrator and Finance prepares the settlement. Production permission matrix must not accidentally grant execution authority to the Finance or supplier department. Reconcile the intended upload actor (Finance preparing evidence versus Super Admin executing payment) before translating this policy. Do not grant execute permission merely to make uploads work.

## Type and sequence findings
- No custom Finance enum type was surfaced by the name-filtered type query; the inspected tables use their declared column types/check constraints.
- The only sequences surfaced by the sequence query were unrelated direct-quotation/receipt sequences. The bookkeeping audit bigint identifier did not expose an obvious serial sequence/default. Verify the actual insert path and key generation before production recreation; do not invent a sequence.
- Preserve existing production frosttech_tax_settings rather than dropping/recreating it. Compare columns, constraints, policies and data with the test version and merge only missing capabilities.

## Production migration packaging order
1. Dependency objects and exact table/column definitions (including identity/generated flags).
2. Base tables and constraints, respecting cross-table dependencies.
3. Indexes and unique/idempotency constraints.
4. Trigger helper functions and every transitive helper function.
5. Audit tables before audit triggers.
6. Triggers and append-only audit guards.
7. RLS policies and exact grants, including function EXECUTE grants.
8. Private storage buckets, MIME/size restrictions and object policies.
9. RPCs and frontend compatibility.
10. Data reconciliation/import using idempotency checks and verified source documents.

## Outstanding blockers
- Full transitive helper-function inventory and grants are not yet fully extracted.
- Exact bucket metadata and production collisions not yet reconciled.
- The supplier evidence upload actor/permission boundary requires an explicit policy decision consistent with Super Admin final settlement authority.
- No production-equivalent rehearsal or backup/recovery checkpoint has been recorded in this stage.

## Accounting import guard
Opening figures remain: NGN 100,000 interest-free shareholder loan (liability), NGN 10,000 legal search expense, NGN 90,000 bank balance. Do not import until source document reference, existing production duplicates and expense approval/posting status are checked.
