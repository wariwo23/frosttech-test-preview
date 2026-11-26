# FrostTech production integration reconciliation — 26 November 2026

## Purpose and safety boundary

This is a read-only reconciliation record for the approved production-integration programme. All database inspection in this review was read-only. Production database, production website, production authentication, payments and live customer workflows were not changed.

The only repository change made during this review is a correction to the isolated-test rollback SQL, so that rollback does not re-expose Finance-only consultation-fee fields.

## Confirmed Operations work already present in isolated test

The isolated test migration history records both earlier Operations foundation migrations as applied:

- `20261123123958 command_center_operations_workspace_draft`
- `20261123124051 command_center_quotation_integrity_dependencies_draft`

The test database currently contains the ten Operations RPC foundation and the integrity triggers/tables for:

- immutable original customer request snapshots and append-only integrity audit;
- quotation version numbering, immutable submitted versions and approved-snapshot protection;
- immutable submitted quotation items;
- cross-quotation acceptance conflict prevention;
- accepted alternative proposal linkage and append-only proposal/decision records;
- supplier quote pricing guardrails.

The Operations RPCs include customer request review/listing, quotation listing, orders/order-items listing, deliveries listing/scheduling/status updates, and delivery customer-contact logs. These are not new work and must be retained.

## 26 November standard-quotation addition

The isolated test migration history also records:

- `20261126202128 operations_standard_quotation_workspace_test`
- `20261126202148 operations_standard_quotation_draft_reader_test`

The associated test page is `operations-standard-quotations-test.html`. The added RPCs are:

- `ops_get_standard_quotation_draft_v1(uuid)`
- `ops_save_standard_quotation_draft_v1(...)`
- `ops_submit_standard_quotation_v1(uuid)`

The new RPCs use `quotations.manage_operational`, and the Operations role has that test permission. Finance does not receive that permission. Super Admin permission bypass remains in place.

The new submit RPC creates a submitted quotation snapshot containing the line items, financial totals, original request snapshot and accepted alternative proposal. It calculates the already-approved 2% consultation fee basis excluding delivery, preserves an already-paid fee state, and refuses unresolved payment-reference attempts. The existing test triggers continue to protect submitted quotation versions and their items.

The prior fee-basis smoke test passed with a subtotal of ₦1,000, delivery ₦100, discount ₦50 and consultation fee ₦19; the temporary transaction was rolled back. This was an RPC/database smoke test, not proof of full browser-to-customer payment/email integration.

## Corrections and gaps identified

1. **Rollback safety:** The first rollback draft restored an earlier `ops_list_customer_requests()` that returned all request columns, including Finance-only fee amount/status/reference/timestamp. That was unsafe. The rollback file was corrected on the test branch to retain those four fields' redaction. The corrected rollback has not been executed.
2. **Revision workflow:** The new editor only loads and saves drafts. It does not expose a submitted-quotation revision workflow. Production has legacy revision/replace/submit RPCs (`admin_create_direct_quotation_revision_v2`, `admin_replace_direct_quotation_items_v2`, `admin_submit_direct_quotation`) whose authorization still uses broad `is_admin()`. Their complete business logic must be preserved while aligning authorization to Operations + Super Admin. Do not replace them with simplified RPCs.
3. **Production fee redaction:** The production `ops_list_customer_requests()` currently returns full request rows. Production integration must apply explicit redaction of `admin_fee`, `admin_fee_status`, `admin_fee_transaction_reference` and `admin_fee_paid_at` to Operations output.
4. **Frontend completion:** The test editor has no submitted-version revision action. Its assumptions about returned JSON, catalogue fields, and item edit reconstruction still require compatibility review against the actual UI and RPC contracts before it can be promoted.
5. **Production mismatch:** Production and test migration histories/schemas differ substantially. Test migrations must not be replayed blindly or copied wholesale to production. Production's current role/permission mappings and legacy policies/functions require a production-specific dependency migration.
6. **Security review:** Recheck exact function grants, RLS policy interactions, trigger definitions, and the customer ownership / accepted-alternative constraints before approving the final Operations package.

## Current status

- Earlier Operations foundation in isolated test: **present and migration-history-confirmed**.
- Quotation integrity layer in isolated test: **present and trigger-confirmed**.
- Standard quotation draft/save/submit in isolated test: **present**.
- Consultation-fee separation from Operations request listing: **present in test RPC**.
- Safe rollback: **corrected in repository; not executed**.
- Submitted quotation revision compatibility: **outstanding**.
- Production-specific Operations authorization integration: **outstanding**.
- Production deployment: **not performed**.

## Next integration action

Complete the Operations compatibility patch by reconciling submitted-version revision with the existing production revision RPCs, preserving all snapshot/version/alternative/acceptance rules and replacing only the broad authorization checks with the intended permission boundary. Then reconcile the exact production request-list RPC redaction and dependent frontend/Edge Function contracts. Keep all changes isolated until the complete production migration and rollback package passes review.


## Follow-on schema and four-department authorization reconciliation

A direct live catalog check confirms that the isolated test database does not contain the production revision RPCs `admin_create_direct_quotation_revision_v2(uuid)`, `admin_replace_direct_quotation_items_v2(uuid,jsonb)`, or `admin_submit_direct_quotation(uuid)`, and does not contain `admin_quotation_pricing_snapshots`. Production contains all four. The test database does contain the request snapshots, quotations, quotation items and alternative-proposal tables. This is a material schema/function mismatch; the full revision function must not be copied alone because its private pricing-snapshot table and dependent constraints are absent.

The test database already contains the quotation integrity triggers for request snapshots, quotation version scope, immutable quotation items, cross-quotation acceptance, and append-only alternative proposals/decisions. These must be retained if the missing revision dependency package is later ported.

### Role permission drift confirmed

The live permission catalogs differ:

- Test has the consolidated `advertisers_admin` permission group and expanded Finance bookkeeping/tax/settlement permissions.
- Production currently has no `advertisers_admin` role permission group and still separates `supplier_admin` and `catalogue_admin`.
- Test Operations has `quotations.manage_operational`; production does not yet.
- Production Supplier currently has `supplier_quotes.manage`; test Supplier does not.
- Test Finance has broader bookkeeping/tax/settlement permissions than production.
- Test Advertisers has advertising review, advertiser/document management, communications and notifications permissions; production has not yet received this consolidated role group.

This confirms that the four-department role consolidation is not yet production-ready. Do not apply the test permission list wholesale: first define the consolidated department-to-permission matrix and explicitly preserve Super Admin-only actions, including supplier-cost disclosure/selection, final supplier settlement approval, tax-rule administration and advertiser package pricing.

### Next work sequence

1. Complete a production-to-test dependency manifest for the revision function and private pricing snapshot table, including grants, triggers, RLS and foreign keys; do not copy partial objects.
2. Complete the Supplier & Catalogue privilege boundary review, especially removing supplier cost, delivery cost and final supplier-selection capabilities from departmental supplier views.
3. Reconcile Finance bookkeeping/tax/settlement permissions against the existing production functions and data tables.
4. Reconcile Advertisers & Communications permissions and payment/notification Edge Function authorization.
5. Only then prepare the ordered four-department role constraint and protected role-lookup migration, with exact production rollback and post-migration role matrix assertions.
