# Unified Permission Authorisation — Backend Dependency Audit

Date: 2026-11-24
Environment: Isolated test only
Supabase project: `gqnidjifiobhqhnxjlow`
Repository: `wariwo23/frosttech-test-preview`
Branch: `command-center-shell-stage1`

## Audit scope

Read-only inspection of test database SECURITY DEFINER functions, grants, test role permissions, Edge Function deployments and frontend workspace gates. This audit did not alter code, database, RLS, grants, accounts, records, or Edge Functions.

## Confirmed permission-first backend procedures

The following database procedures enforce `admin_has_permission(...)` internally:

- Operations: customer request listing/review, order and order-item listing, operational quotation listing, delivery listing/scheduling/status changes, delivery contact logs.
- Finance: `finance_get_summary`, `finance_list_payments`, `finance_list_quotations`, `finance_list_direct_quotation_activity`, `finance_list_my_cost_submissions`, and `finance_list_quotations_for_costing`.
- Supplier: application listing requires `supplier_applications.read`; application decision requires `supplier_applications.review`.
- Supplier settlement: preparation/submission and disbursement record/verification use specific settlement permissions.
- Tax: assessment, remittance, certificate, supplier tax-profile and remittance-decision procedures use explicit tax permissions.

The inspected functions are SECURITY DEFINER with an empty search path. Authenticated EXECUTE is granted where the function itself performs the permission check; anonymous EXECUTE was false for these interactive procedures.

## High-priority mismatches

### 1. Direct quotation workflow still uses role-only authorisation

The deployed test Edge Functions were read directly from the isolated test project:

| Edge Function | Deployed version | Current gate |
|---|---:|---|
| `create-direct-quotation` | 19 | `admin_get_my_role()` must return Super Admin or Operations Admin |
| `issue-direct-quotation` | 24 | `admin_get_my_role()` must return Super Admin or Operations Admin |
| `direct-quotation-bank-workflow` | 8 | Role allowlist; send instructions = Super Admin/Operations; confirm or retry password email = Super Admin/Finance |

The issue function and draft create/update database RPCs additionally check `admin_accounts` directly for permanent Super Admin or Operations Admin rows. These checks do not recognise an isolated test permission grant. The Edge Functions pass the authenticated user's ID into service-role database RPCs, so a future permission-first correction must retain trusted identity binding and must not let a caller choose another actor ID.

The bank confirmation database RPC also checks `admin_accounts` directly for Super Admin/Finance and is callable only through the service-role Edge Function. Its current hardcoded quotation ID, test customer and development-only data restrictions must remain in place during test work.

**Required design:** define and enforce exact procedure permissions at the authenticated Edge Function boundary and preserve an independent database-side trusted-actor validation for service-role calls. Do not simply remove the actor check or trust a frontend permission flag.

### 2. Direct quotation count RPC

`frosttech_admin_count_direct_quotations()` checks active `admin_accounts` role in Super Admin/Operations rather than `admin_has_permission`. It is authenticated-executable. Its actual frontend caller and intended permission must be traced before any correction.

### 3. Workspace entry gates remain role-based

The following frontends still use role as their workspace entry test, even though their procedures use explicit permissions:

- `finance-admin-test.html`: entry accepts Finance Admin or Super Admin. Finance procedures themselves check specific permissions. Super Admin preview is intentionally read-only and must be preserved.
- `tax-admin-test.html`: entry accepts Finance Admin or Super Admin. Action visibility checks individual tax permissions; VAT/tax settings and tax-rule administration remain Super Administrator-only.
- `departmental-admin-test.html`: Operations dashboard entry accepts Operations Admin or Super Admin; Operations RPCs independently check specific permissions.
- `admin-independent-quotations-test.html`: workspace and bank action controls use role lists. The bank workflow Edge Function and database procedures also use role checks.

**Required design:** workspace visibility should be based on the permissions needed for that workspace's read operations; each action should independently use its own exact permission. Retain explicit Super Administrator-only procedures and the existing read-only Super Admin Finance preview.

## Supplier workflow distinction

The Supplier Applications page now:
- obtains the role through `admin_get_my_role()`;
- relies on `admin_list_supplier_applications` for `supplier_applications.read`;
- displays decision controls only when `supplier_applications.review` is true;
- leaves Super Administrator override handling intact.

The underlying review RPC remains the final authority. This is a valid separation between read permission and decision permission.

## Tax administration distinction

The tax-rule creation/activation/deactivation and VAT settings RPCs remain Super Administrator-only by design. Finance tax assessment/remittance/profile/certificate procedures use granular permissions. An older `frosttech_create_tax_rule` overload delegates to the newer guarded overload; it does not bypass the Super Administrator check. Do not drop or rewrite it without checking frontend compatibility and exact function grants.

## Preserved security boundaries

- Existing customer, guest and supplier RLS policies were not modified.
- Supplier-cost and direct-order supplier sourcing procedures remain Super Administrator-only.
- Supplier settlement approval/rejection remains Super Administrator-only.
- Employee appointment, operator assignment and administrative access management remain Super Administrator-only.
- The isolated Finance test grant remains active.
- The isolated test Super Administrator remains active.
- The departmental appointment hold remains enabled.
- Test grants remain in the isolated test database and do not transfer to production.

## Proposed correction sequence (not yet implemented)

1. Create a procedure-permission map for direct quotations, Finance, Tax, Operations and Supplier workflows. Confirm each permission name against the actual function and role-permission records.
2. Correct direct quotation Edge Function gates and database-side trusted-actor validation together. Preserve the test-only quotation/customer/data restrictions, idempotency, service-role-only RPC grants, and existing workflow semantics.
3. Correct frontend workspace entry gates to use the corresponding read permissions, and action controls to use their exact permissions.
4. Review `frosttech_admin_count_direct_quotations()` caller and replace role-only access only after its correct read permission is confirmed.
5. Run isolated test cases: valid permission grant succeeds regardless of role label; missing permission is denied; inactive profile/grant is denied; Super Admin-only action remains denied to departmental roles; direct URL and direct RPC calls are denied without permission.
6. Re-run supplier/customer/guest, settlement and quotation regression checks. No production promotion until separately reviewed and approved.

## Not performed

- No code or database implementation in this audit pass.
- No migrations, RLS policy edits, grants or permission assignments.
- No employee/operator appointments or invitations.
- No email sent, payment, settlement disbursement, or bank confirmation.
- No production repository or production Supabase project access.
- No live browser sign-in or end-to-end workflow execution.
