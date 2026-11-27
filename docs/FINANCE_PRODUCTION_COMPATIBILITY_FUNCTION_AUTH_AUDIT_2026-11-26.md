# FrostTech Finance — Production Compatibility and Function Authorization Audit
Date: 26 November 2026
Source: isolated test project gqnidjifiobhqhnxjlow
Target: production project nftxptjpgidcsgtaltjn
Status: audit evidence only; no production changes.

## Storage bucket comparison
Test buckets:
- advertiser-documents (private, 10 MiB, PDF/JPEG/PNG)
- direct-quotation-documents (private, 10 MiB, PDF)
- frosttech-tax-documents (private, 10 MiB, PDF/JPEG/PNG)
- payment-receipts (private, 10 MiB, PDF)
- supplier-disbursement-evidence (private, 10 MiB, PDF/JPEG/PNG)

Production buckets:
- advertiser-documents (private, 10 MiB, PDF/JPEG/PNG)
- payment-receipts (private, 10 MiB, PDF)
- product-images (public, unrestricted in the inspected bucket metadata)

Consequences:
- Do not recreate advertiser-documents or payment-receipts.
- direct-quotation-documents exists in test but was not present in the earlier production bucket inventory; recheck current production before considering any creation.
- frosttech-tax-documents and supplier-disbursement-evidence are absent in production and require production-specific private bucket creation plus reviewed storage policies.
- Preserve public product-images exactly; do not widen the privacy of financial or advertiser documents.

## Function execution grants
The live test function privilege check shows:
- Finance RPCs are executable by authenticated users, but their bodies check role/permission or Super Admin status.
- The online provider disbursement verification RPC is service_role-only.
- Journal guard trigger functions are not executable by anon/authenticated and are available to service_role.
- A trigger guard helper, frosttech_guard_duplicate_tax_source(), currently reports EXECUTE to anon and authenticated. Since it is trigger-only, direct invocation should be revoked from browser roles unless an independently verified caller requires it.
- Several SECURITY DEFINER RPCs require full review of their internal authorization, not just their EXECUTE grant. Reproduce grants only after checking every function body and transitive helper.

## Production tax settings compatibility
Production already has frosttech_tax_settings with the columns used by the test tax workflow:
id, vat_enabled, vat_rate, vat_mode, effective_at, updated_by, created_at, updated_at.
The Finance migration must preserve its current row and settings. Do not recreate or reset this table. Add only separately verified missing columns/constraints/indexes if any are demonstrated by comparison.

## Critical test-environment literals
Recovered SECURITY DEFINER function bodies include hard-coded 'isolated_test' environment values in admin_activity_log details for tax rule activation, tax settings updates and settlement approval. Before production deployment:
- remove test-environment labels from production function bodies or replace them with an authoritative environment marker;
- retain audit event names, actors, amounts, effective dates, reasons and decision evidence;
- verify production function names/signatures and all called helpers exist.
Do not copy those definitions verbatim.

## Settlement approval and disbursement
The settlement approval function is Super Admin-only and checks:
- preparer and approver are different users;
- preparer remains an active administrator;
- supplier remains approved and verified;
- settlement items match confirmed supplier assignments and eligible order status;
- tax calculation basis and WHT amount/net payable reconcile;
- order items are not already included in another active settlement.
Online disbursement verification requires service_role and validates provider reference, amount, NGN currency and settlement state.
These protections are mandatory dependencies of the production candidate.

## Release blockers now narrowed
1. Finish extraction of every transitive helper and function EXECUTE grant; specifically classify trigger-only functions and revoke browser EXECUTE where unnecessary.
2. Rebuild production-specific function bodies to remove isolated_test labels and align production permission names/roles.
3. Reconcile storage bucket and object policies, retaining existing bucket IDs and privacy.
4. Generate identity/sequence-preserving DDL and exact rollback; the audit log ID generation path still needs confirmation.
5. Rehearse on a production-equivalent isolated schema, run authorization and workflow tests, then take a verified production recovery point.
6. Import the three opening accounting figures only after source evidence, expense approval state and duplicate checks.

## No production mutation
This audit only read live metadata and function definitions. No production schema, permissions, storage buckets or accounting records were changed.
