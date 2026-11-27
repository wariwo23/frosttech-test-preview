# FrostTech Super Administrator and Departmental Responsibility Coverage Audit

Date: 2026-11-25
Status: Read-only source comparison; implementation sequence approved for isolated test branch
Repository: `wariwo23/frosttech-test-preview`
Branch: `command-center-shell-stage1`
Production repository: `wariwo23/frosttech-frontend` (read-only comparison only)
Production Supabase: not modified
Test Supabase: isolated project only; no schema, permission, account or data changes in this audit

## 1. Governing rule

The Super Administrator Command Center must expose every FrostTech-wide responsibility and every reserved Super Administrator decision. Four departmental mini Command Centers must independently expose all responsibilities assigned to their department. Department heads must not need to enter the Super Administrator Command Center to do their work.

The Super Administrator remains the highest authority and alone appoints administrators/operators, assigns departments, governs system-wide roles/access, and controls other explicitly reserved functions. A departmental page must not expose another department's responsibilities or reserved Super Administrator actions.

Preserve all existing accounts, records, authentication, payment, supplier, customer, advertiser, notification, storage, database, RLS and Edge Function behaviour. Supplier-cost RPCs and direct-order supplier costing remain Super Administrator-only. Supplier settlement approval/rejection remains Super Administrator-only. Tax-rule and VAT configuration/effective dates remain Super Administrator-only. Existing customer, guest and supplier RLS policies must not be casually changed.

## 2. Production responsibility inventory observed

The production Administration Dashboard (`admin.html`) exposes or links to:
- Marketplace Summary.
- Financial Dashboard and production payment/income, recognised orders, accepted quotation estimates, production expenses, inventory valuation and reconciliation integrity.
- Product Management.
- Admin-Direct Quotations and saved direct quotations.
- Customer Quote Requests.
- Notification Centre and controlled notification recovery.
- Saved Supplier Quotations.
- Supplier Management and supplier application/account status.
- Advertiser Verification, private CAC/supporting-document review and Advertising Campaign Review.
- Payment Records.
- Employee and Administrator Management.
- Supplier Account Maintenance.
- Direct Order Sourcing and Costing.
- Print approval, authorisation and audit.
- Department and Operator Management and Administrator Activity Log.

Other production departmental workspaces observed:
- Operations: customer requests, operational quotations, orders, order items, delivery management and contact history; independent/direct quotation workspace.
- Supplier: supplier applications/review and supplier quotations/selection.
- Finance: financial reconciliation, payment records, financial quotation review and cost submissions, direct-quotation ledger; tax and supplier-settlement responsibilities are also represented by separate administrative workflows.
- Catalogue: product creation, product details, image/category data, selling-price updates, stock updates and product activation/deactivation.
- Super Administrator-only supplier cost management and direct-order supplier sourcing/costing.

The production inventory is the baseline to preserve. It is not permission to broaden any departmental role.

## 3. Super Administrator Command Center coverage

The current test Command Center has all six agreed top-level groups:
1. Operations & Customer Matters.
2. Supplier & Catalogue Management.
3. Finance, Payments & Tax.
4. Advertisers & Communications.
5. People, Roles & Access Governance.
6. Security, Audit & Marketplace Oversight.

Current responsibility registry includes customer matters, standard/direct quotations, orders/delivery, supplier applications, supplier quotations, supplier costs/direct sourcing, catalogue/products/prices/stock, finance/payment/reconciliation, quotation-cost decisions, supplier settlement decisions, tax operations and reserved tax configuration, advertiser/CAC/campaigns, notifications/email/recovery, employee onboarding, appointments/operators, roles/permissions, security, activity/print audit and marketplace reporting.

### Super Administrator gaps in the isolated test build

| Responsibility | Current test status |
|---|---|
| Customer requests, quotations, orders and delivery | Connected to Operations test workspace |
| Customer account administration | Listed; dedicated test workspace pending |
| Independent/direct quotations | Existing test workflow linked |
| Supplier applications and review | Test workspace linked |
| Supplier account oversight/maintenance | Listed; dedicated workspace pending |
| Supplier quotation review/selection | Listed; dedicated workspace pending |
| Supplier costs and direct-order sourcing | Correctly reserved; dedicated test integration pending |
| Product catalogue management | Listed; dedicated test page and RPC integration pending |
| Financial reporting/payment records | Finance test workspace linked |
| Payment verification/reconciliation | Partly represented; complete action and evidence coverage needs verification |
| Quotation-cost approval/rejection | Correctly reserved; dedicated Super Admin decision workspace pending |
| Supplier settlement approval/rejection | Dedicated Super Admin test workspace linked |
| Supplier disbursement oversight | Evidence and independent-verification workflows exist in Finance test page; end-to-end review still required |
| Tax assessments/remittances/profiles/certificates | Tax test workspace linked |
| Tax rules, VAT, rates and effective dates | Correctly reserved to Super Administrator in test |
| Advertiser accounts, CAC and campaign review | Listed; test database/workspace integration pending |
| Notification Centre and recovery | Listed; test database/workspace integration pending |
| Employee onboarding and department/operator appointments | Test workspaces linked |
| Role/permission and security governance | Partly represented; full control and audit verification pending |
| Administrative activity and print audit | Activity log linked; print approval/audit integration pending |
| Consolidated marketplace reporting | Listed; report integration pending |
| Financial expenses, receipts, refunds and complete reconciliation | Existing production scope identified; test integration needs completion/verification |

A visible responsibility with a null/pending link is not complete. It must remain visibly marked as pending and must not present a fake action as operational.

## 4. Departmental mini Command Center coverage

### A. Operations (`operations_admin`)

Responsibilities to capture:
- Customer quote requests and request triage/review.
- Standard customer-request quotations and operational quotation visibility.
- Independent/direct customer quotations.
- Orders and order items.
- Fulfilment and delivery scheduling/status/progress.
- Delivery contact history, follow-ups and customer communications recorded against deliveries.

Current test mini-center:
- Customer Requests, Orders & Deliveries → `departmental-admin-test.html`.
- Standard & Direct Quotations → `admin-independent-quotations-test.html`.
- Customer Account Oversight → currently pending; no dedicated departmental account-management workspace is ported.

The Operations data page has five operational record modules: requests, quotations, orders, order items and deliveries. Delivery contact history is loaded through the protected Operations RPC. Do not grant Operations supplier quote costs/margins, Finance-only quotation data, payment verification or supplier-cost access merely because Operations handles customer work.

### B. Supplier Management (`supplier_admin`)

Responsibilities to capture:
- Supplier application queue and application details.
- Supplier verification, review decisions and reasons.
- Supplier quotation review, comparison and selection.
- Supplier account status and authorised maintenance.
- Supplier communication/decision notification status where included in the existing supplier workflow.

Current test mini-center:
- Supplier Applications & Verification → `supplier-applications-test.html`.
- Supplier Quotations → pending; no complete dedicated test workspace.
- Supplier Account Maintenance → pending; no complete dedicated test workspace.

Supplier application read and review remain separate permissions. Super Administrator override of a previous supplier decision remains exclusive. Supplier costs, internal pricing, margins and direct-order supplier costing remain Super Administrator-only. Do not expose supplier costs to Supplier Admin.

### C. Finance & Tax (`finance_admin`)

Responsibilities to capture:
- Financial reporting and reconciliation.
- Payment records and status visibility; verification only where the exact permission and procedure allow it.
- Receipts, fee reconciliation, refunds and financial exceptions where the existing workflow provides them.
- Financial quotation review and actual-cost submissions.
- Direct-quotation financial ledger and payment attempts without supplier costs/margins.
- Supplier settlement preparation/submission and separately permitted execution/evidence tasks.
- Manual disbursement evidence and independent verification, where permitted.
- Tax assessments, remittances/evidence, supplier tax profiles and certificates under granular permissions.

Current test mini-center:
- Financial Reporting & Payments → `finance-admin-test.html`.
- Tax Assessments, Remittances & Certificates → `tax-admin-test.html`.
- Supplier Settlement Preparation & Execution → `finance-admin-test.html`.

Reserved Super Administrator authority:
- Approve/reject quotation-cost submissions and create protected approval snapshots.
- Approve/reject supplier settlements; this is separate from disbursement.
- Configure/activate/deactivate tax rules, VAT settings, system-wide tax rates and effective dates.
- Any other procedure explicitly restricted to Super Administrator.

Finance submission or execution permission must never be treated as settlement approval permission. Tax assessment permissions must never be treated as tax-rate configuration permission. Finance Super Administrator preview must remain read-only.

### D. Catalogue & Product Management (`catalogue_admin`)

Responsibilities to capture:
- Product creation and editing.
- Product names, descriptions, categories, brands/models, SKU and units.
- Product images and image storage workflow.
- Selling-price updates.
- Stock quantity and minimum-stock updates.
- Product activation/deactivation and catalogue publication/visibility.

Current test mini-center:
- Product Catalogue → pending; no dedicated test catalogue page/RPC integration is present.
- Supplier Costs → correctly reserved and disabled for Catalogue Admin.

The isolated test database has Catalogue permission rows but the corresponding production `catalogue_*` RPC workflow has not been ported. Its product table policy is Super Administrator-only. Do not grant direct table write access or expose supplier costs to make the Catalogue workspace appear functional. Port and review the dedicated protected RPC workflow before enabling write actions.

## 5. Important test-build structural findings

- The test department mini-center currently contains a static `functionsByDepartment` list. It is a navigation/permission view, not proof that every listed responsibility has a complete backend workspace.
- Operations has an existing page with five record modules; its additional customer-account tile is pending.
- Supplier has an applications page; supplier quotations and account maintenance remain pending.
- Finance has a substantive page plus tax and settlement workflows, but complete production parity and end-to-end evidence flows remain to be verified.
- Catalogue has no dedicated test product-management page/RPC integration yet.
- The Super Administrator registry includes several responsibilities with pending links. Those must not be counted as complete merely because their headings exist.
- Existing four roles remain the only departmental appointment roles. Do not create additional role identities to represent the six Super Admin groups or individual responsibility tiles.

## 6. Approved isolated-test implementation sequence

1. **Freeze and validate the responsibility register** against the production source and existing database permission/RPC design.
2. **Super Administrator completion:** connect or port the missing Super Admin-only and oversight workspaces in small, isolated stages: catalogue and supplier-cost/direct sourcing; supplier accounts/quotes; quotation-cost decisions; advertiser/CAC/campaign review; notification/recovery; financial expenses/receipts/refunds/reconciliation; print audit; consolidated reports and customer-account oversight.
3. **Operations mini-center:** verify all operational pages and protected actions; identify whether customer account administration is explicitly delegated or remains Super Admin-only. Do not assume delegation.
4. **Supplier mini-center:** integrate supplier application review, supplier quotation comparison/selection, account maintenance and notification status with separate exact permissions.
5. **Finance mini-center:** verify financial reporting, payment permissions, cost submission, settlement preparation/execution/evidence, and tax operational permissions; keep all reserved approvals/configuration Super Admin-only.
6. **Catalogue mini-center:** port the production Catalogue RPC workflow to isolated test only after reviewing its exact authorization, image storage, product fields and supplier-cost separation.
7. **Security and regression audit:** verify direct URL and direct RPC denial, inactive account denial, permission-specific visibility, Super Admin preview behaviour, and no cross-department leakage.
8. **User browser verification:** user tests each department head's sign-in and every responsibility tile on the isolated test site.
9. Production remains untouched until a separate production-readiness review and explicit deployment approval.

## 7. Non-negotiable regression checks

- Permanent Super Administrator remains highest authority.
- Departmental admins independently sign in and land directly in their own mini Command Center.
- Departmental admins cannot change department by URL or open another department's mini-center.
- Super Administrator can open each department without another sign-in and return to the central Command Center.
- No departmental administrator can appoint/remove administrators or operators, assign departments, change system-wide roles, or configure system-wide tax rates/effective dates.
- Supplier-cost data/RPCs and direct-order supplier costing remain Super Administrator-only.
- Supplier settlement approval/rejection remains Super Administrator-only.
- Quotation-cost approval/rejection remains Super Administrator-only.
- Tax rule activation/deactivation and VAT/system-wide tax configuration remain Super Administrator-only.
- Customer, guest and supplier RLS policies are preserved unless a separately reviewed and explicitly approved migration is required.
- Preserve all existing working auth, password reset, notification, advertiser/CAC, payment, quotation, supplier and customer workflows.
- Never mark a responsibility complete based only on a heading or disabled placeholder tile.

## 8. Change record for this audit

This document records the source comparison and implementation plan. No application code, database schema, RLS policy, grants, role permissions, account, record, storage policy, Edge Function or production setting was changed as part of the audit.


## 9. Implementation checkpoint — direct-order sourcing workspace (2026-11-25)

A first Super Administrator workspace integration was completed in the isolated test repository only.

- Added `direct-order-sourcing-test.html`, adapted from the existing production Direct Order Sourcing page.
- The test page uses the isolated `supabase-test.js` client and contains no production Supabase project reference or production publishable key.
- It calls the existing test database procedures:
  - `frosttech_super_admin_list_direct_order_sourcing()`
  - `frosttech_super_admin_assign_direct_order_item_supplier(...)`
  - `frosttech_super_admin_record_direct_order_item_cost(...)`
- The database procedure definitions were inspected read-only. Each checks `auth.uid()` and `public.is_super_admin()`; assignment is limited to paid/processing/pre-delivery orders and active, verified, approved suppliers; supplier reassignment clears the previous cost and records audit history; cost entry requires an assigned approved supplier and a paid order.
- The page preserves the existing FrostTech confirmation modal and sourcing audit display, and adds a return link to the test Super Administrator Command Center.
- The Super Administrator responsibility registry now links Direct-Order Sourcing to this test workspace.
- Catalogue supplier-cost records remain explicitly pending because the corresponding `admin_list_product_supplier_costs`, `admin_save_product_supplier_cost`, `admin_select_product_supplier` and supporting test procedures are not present in the isolated test database. No direct table-write workaround was introduced.
- The Catalogue product-management workspace remains pending because the `catalogue_*` procedures used by the production Catalogue page are not present in the test database. The existing product table's Super Administrator-only write policy was not changed.
- Supplier quotation review and supplier account maintenance remain pending because the matching test workspace/procedure set has not yet been verified.

Test-repository commits:
- Add test-only Direct Order Sourcing page: `8f6b39e117a23be1d1432dbff3b1eb67cdd2150e`
- Connect Super Admin responsibility tile: `830e38f7eafcda7219747c0ea6c25637b31d2336`

Verification performed: source re-fetch, isolated client/reference checks, protected RPC name checks, and read-only inspection of the three RPC definitions and execute grants. No live browser session or sourcing mutation was executed.

No production repository, production Supabase project, database schema, RLS policy, grant, role permission, account, record, storage setting, or Edge Function was changed.
