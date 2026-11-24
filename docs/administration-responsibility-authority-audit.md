# FrostTech Administration Architecture — Responsibility and Authority Audit

Date: 2026-11-24  
Status: Read-only audit and implementation blueprint  
Environment: Isolated test only  
Repository: `wariwo23/frosttech-test-preview`  
Branch: `command-center-shell-stage1`  
Test Supabase project: `gqnidjifiobhqhnxjlow`

## 1. Governing architecture

FrostTech will have one Administration Landing Page with two separate entry paths:

1. **Super Administrator sign-in** — opens the exclusive Super Administrator Command Center.
2. **Departmental Administrator sign-in** — authenticates the administrator and routes them directly to the mini Command Center for their assigned department.

The Super Administrator Command Center is the central authority and must show the complete FrostTech responsibility overview. It is not a shared departmental dashboard.

A departmental administrator must never need to enter the Super Administrator Command Center to perform their assigned work. The Super Administrator may open any department from the central Command Center without another sign-in.

Within either level, selecting a responsibility opens only that responsibility workspace. The other responsibility cards/navigation must be hidden until the user returns to the relevant Command Center.

## 2. Four departments already defined by the existing system

The isolated test database already defines four departmental roles and the employee-department appointment mapping. Preserve these exact role identities; do not create replacement roles merely to regroup the user interface.

| Department | Existing administrator role | Responsibility grouping |
|---|---|---|
| Operations | `operations_admin` | Customer requests, standard quotations, direct quotations, orders, order items, delivery scheduling/progress and customer contact records |
| Supplier Management | `supplier_admin` | Supplier applications, supplier verification/review, supplier quotations and supplier account workflows |
| Finance & Tax | `finance_admin` | Financial reporting, payment visibility/verification where authorised, financial quotation visibility, cost submissions, supplier settlement preparation/execution, tax assessments, remittances, supplier tax profiles and certificates |
| Catalogue & Product Management | `catalogue_admin` | Product catalogue, product details, images, selling prices, stock and product activation/deactivation |

The four existing departments are therefore Operations, Supplier Management, Finance, and Catalogue. The eight current Command Center navigation headings are not eight independent appointment roles.

## 3. Responsibility allocation and protected boundaries

### A. Operations

Departmental responsibilities:
- Customer quote requests and request review.
- Standard customer quotations and operational quotation visibility.
- Independent/direct customer quotations.
- Orders and order items.
- Delivery scheduling, status updates and customer contact logs.

Permission boundaries:
- Operations procedures continue to enforce their exact permissions, including `customer_requests.manage`, `quotations.read_operational`, `orders.manage` and `deliveries.manage`.
- Operations must not receive supplier commercial quote costs, supplier margins, Finance-only quotation information, or payment-verification permissions merely because it handles customer requests.
- Finance-only direct-quotation payment verification remains separately permission-gated.

### B. Supplier Management

Departmental responsibilities:
- Supplier application listing and review.
- Supplier verification and supplier account workflows.
- Supplier quotation review and selection, where the existing supplier workflow authorises it.

Permission boundaries:
- Supplier application read and review remain separate permissions.
- Super Administrator override of a previous supplier decision remains exclusive to the Super Administrator.
- Supplier-cost records, internal pricing and direct-order supplier costing remain Super Administrator-only.
- Operations access to customer requests must not expose supplier quote costs or supplier margins.

### C. Finance & Tax

Departmental responsibilities:
- Financial summaries and reporting.
- Payment history, reconciliation and payment verification only where the exact permission is granted.
- Financial quotation visibility.
- Submission of actual quotation costs for Super Administrator review.
- Supplier settlement preparation, submission and other explicitly permitted execution steps.
- Tax assessments and reconciliation.
- Tax remittances and evidence.
- Supplier tax profile submission/verification and tax certificates, according to the specific permission.

Super Administrator-only Finance/Tax authority:
- Review/approval/rejection of quotation-cost submissions and approval snapshots/audit.
- Supplier settlement approval/rejection.
- Creation, activation and deactivation of tax rules.
- VAT/tax settings, system-wide tax rates and effective dates.
- Any other function explicitly protected by the existing Super Administrator-only RPC.

A Finance permission to prepare or execute a settlement must not be interpreted as authority to approve/reject that settlement. Tax assessment permissions must not be interpreted as authority to change tax rates or effective dates.

### D. Catalogue & Product Management

Departmental responsibilities:
- Product catalogue maintenance.
- Product details, descriptions, images and categories.
- Selling prices and stock levels.
- Product activation/deactivation.

Protected boundary:
- Supplier-cost values and supplier-cost RPCs remain Super Administrator-only.
- The test database currently has the Catalogue role permission rows but does not have the corresponding `catalogue_*` RPC set found in the production Catalogue page. Its product table policy also remains Super Administrator-only. Do not grant direct table write access or expose supplier costs to make the page appear functional. Port and review the dedicated RPC workflow before enabling Catalogue Admin write actions in test.

## 4. Responsibilities retained by the Super Administrator

These are central governance and reserved responsibilities, not a fifth departmental role.

The Super Administrator must have a complete overview and authorised access to:

- All four departments and all their permitted operational workspaces.
- Supplier matters, including oversight, decision overrides and supplier account maintenance.
- Customer matters, including customer requests, customer-facing quotation/order oversight and system-wide customer administration.
- Standard quotations and direct/independent quotations.
- Financial oversight, payment records, receipts, fee reconciliation and financial audit.
- Quotation-cost approval/rejection and immutable cost approval records.
- Supplier-cost management and direct-order supplier sourcing/costing.
- Supplier settlement approval/rejection and reserved disbursement oversight.
- Tax rules, tax rates, VAT configuration and effective dates.
- Advertiser verification, CAC review and advertising campaign approval.
- Notification Centre and restricted notification recovery.
- Employee onboarding, administrator/operator appointments, department assignments, suspension/reactivation/removal, role and permission governance.
- System-wide security, activity/audit oversight and print audit.
- Marketplace-wide configuration and consolidated business/department reporting.

No departmental grouping, title, or convenience link transfers any of these reserved powers to a departmental administrator.

## 5. Customer, advertiser and communications allocation

- Customer request handling and customer quotation/order operations belong in Operations.
- Super Administrator retains marketplace-wide customer oversight and any customer-account action that has not been explicitly delegated through a verified permission and backend procedure.
- Advertiser verification, CAC review and campaign decisions remain Super Administrator-only in the current reviewed production workflow. The production review page uses the existing `is_admin()` guard; no equivalent advertiser tables/review workflow or dedicated advertiser permission set is present in the isolated test database.
- Notification recovery and the current central notification workflow remain Super Administrator-only unless a separate permission design is reviewed and approved.
- These responsibilities must remain visible in the Super Administrator overview even when they are not assigned to a departmental mini Command Center.

## 6. Sign-in and workspace behaviour

### Administration Landing Page

Show two independent sign-in entrances:
- Super Administrator
- Departmental Administrator

The Super Administrator route must accept only the server-verified `super_admin` identity and open the main Command Center.

The departmental route must use the authenticated role returned by `admin_get_my_role()`, not a user-selected department, and route only to one of:
- `operations_admin` → Operations mini Command Center
- `supplier_admin` → Supplier Management mini Command Center
- `finance_admin` → Finance & Tax mini Command Center
- `catalogue_admin` → Catalogue mini Command Center

A department selector must never grant or imply access.

### Super Administrator navigation

- Main overview shows all four departments plus all reserved Super Administrator responsibilities.
- Opening one department/responsibility hides the other responsibility navigation.
- The Super Administrator can move between departments without another sign-in.
- Every workspace retains its own server-side authorization and protected action checks.
- Return links take the Super Administrator back to the main Command Center.

### Departmental navigation

- Departmental administrators enter their own mini Command Center directly after sign-in.
- Each mini Command Center shows all authorised responsibilities within that department.
- Opening one responsibility hides the other departmental responsibilities.
- Return links return to that department's mini Command Center.
- Departmental administrators cannot enter the Super Administrator Command Center or another department by changing a URL or selecting a different department.

## 7. Read-only findings from the current isolated test branch/database

1. The test database already has four departmental roles and 30 role-permission rows across those four roles.
2. The permanent test Super Administrator and Operations Administrator accounts are active. A temporary isolated Finance test grant is also present. There is no active Supplier Administrator or Catalogue Administrator appointment in the current test inventory.
3. The test employee table currently has no employee records.
4. The departmental appointment hold is enabled. It must remain enabled; this audit did not release it, create employees, send invitations, or appoint operators.
5. The test Command Center currently displays eight navigation groups. Its current test login page sends all recognised administrator roles to the main Command Center; this must be corrected so only Super Administrator enters the main Command Center.
6. The test repository does not yet contain a dedicated departmental sign-in page or a complete mini Command Center for every one of the four departments.
7. The test repository has a Supplier Applications review page, but the full Supplier Administration workflow (including supplier quotations) is not yet integrated as a complete mini Command Center.
8. The test repository has Finance and Tax workspaces, but the Finance page currently includes a separate login form. The Super Administrator's existing authenticated session must be reused when opening Finance from the main Command Center; no second sign-in should be required.
9. The test repository does not yet contain the Catalogue Admin page. The isolated test database does not currently expose the production Catalogue RPC set.
10. The production frontend contains additional Super Administrator responsibilities that are not all present in the test repository, including advertiser/campaign review, supplier-cost management, direct-order sourcing, and the full central administration dashboard. These must be carried into the test responsibility overview without changing production.
11. The test database contains no advertiser review tables/workflow equivalent to the production advertiser review. The advertiser responsibility must not be dropped or silently delegated during the test port.

## 8. Existing work that must not be repeated or weakened

- Operations request/quotation/order/delivery dependency and integrity work has already been applied and metadata-checked in the isolated test project.
- Finance and Tax permission-first workspace checks have already been implemented in the isolated test project.
- Direct quotation procedure permissions have already been unified in the isolated test project. Preserve the exact permission split between operational quotation actions and payment-read/payment-verification actions.
- Supplier application read/review permissions and Super Administrator override remain separate.
- Supplier-cost RPCs remain Super Administrator-only.
- Customer, guest and supplier RLS policies remain unchanged unless a separate, dependency-complete review and explicit approval authorise a change.
- Existing appointment hold and Super Administrator protection remain unchanged.

## 9. Implementation sequence

1. Build the Administration Landing Page with separate Super Administrator and Departmental Administrator entry paths.
2. Restrict the main Command Center to the server-verified Super Administrator only.
3. Replace the eight top-level department headings with the four existing departments while retaining the already-tested single-responsibility navigation behaviour.
4. Add a complete Super Administrator responsibility overview, including reserved duties that do not belong to departmental administrators.
5. Build/port the four departmental mini Command Centers using the existing production workflows and test-only Supabase configuration.
6. Reuse the Super Administrator session when entering any department from the main Command Center; do not require another sign-in.
7. Port missing test-only workspace dependencies in separate reviewed steps. Do not create fake controls or point to missing RPCs.
8. Verify each page and direct URL against its exact permission. Test forbidden direct RPC/RLS access as well as hidden UI.
9. Test with existing authorised test identities only. Do not release the appointment hold or create new administrator accounts without separate explicit approval.
10. Keep all work in `frosttech-test-preview` / `command-center-shell-stage1`. No production repository, database, Edge Function, payment configuration, account, or deployment changes.

## 10. Non-actions in this audit

This document records findings and a proposed implementation map only. It is not executable SQL and does not change the live application.

No production code or production database was changed. No test database migration, permission row, RLS policy, function grant, Auth setting, account, employee record, appointment, invitation, payment, quotation, supplier record, advertiser record, or notification was created, altered, or deleted during this audit.
