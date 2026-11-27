# Unified Permission Authorisation — Isolated Test Results

Date: 2026-11-24
Environment: Isolated FrostTech test project only
Supabase project: `gqnidjifiobhqhnxjlow`
Repository: `wariwo23/frosttech-test-preview`
Branch: `command-center-shell-stage1`

## Scope completed

Applied a focused first correction pass to align the test frontend with the central database authorisation model. No production repository, production database, production account, or production configuration was changed.

### Frontend changes

1. `test-admin-login.html`
   - Removed the incorrect requirement that `profiles.role` equal `admin`.
   - Uses `admin_get_my_role()` as the central role/active-account check. The database function verifies the active profile and permanent administrator account or valid isolated-test grant.
   - Expanded the safe same-origin return-page allowlist to include the existing protected test workspaces. Each destination still performs its own authorisation check; this does not grant access.

2. `supplier-applications-test.html`
   - Removed the incorrect `profiles.role = 'admin'` prerequisite.
   - Uses `admin_get_my_role()` for role verification.
   - Checks `admin_has_permission('supplier_applications.review')` before displaying supplier decision controls. The database RPC continues to enforce the permission and Super Administrator override rules.

3. `admin-command-center-test.html`
   - Removed role-based fallback scopes that could show a department despite its required permission being absent.
   - Navigation now depends on explicit permission checks, with the existing Super Administrator override retained.
   - The Quotations & Deliveries entry accepts either operational or financial quotation-read permission.
   - Permission enumeration supports modules with one permission or multiple alternative permissions.

## Database review

Read-only inspection confirmed:

- `admin_get_my_role()` and `admin_has_permission(text)` are SECURITY DEFINER functions with an empty search path.
- Supplier application list and review RPCs independently enforce `supplier_applications.read` and `supplier_applications.review`.
- Operations workspace RPCs independently enforce the corresponding `customer_requests.manage`, `orders.manage`, `quotations.read_operational`, and `deliveries.manage` permissions.
- Supplier settlement recording and verification independently enforce `supplier_settlements.execute`.
- Settlement approval/rejection, tax-rule activation, employee onboarding and departmental appointment controls remain Super Administrator-only.
- The Finance test grant remains active, the test Super Administrator remains active, and the appointment hold remains enabled.
- Existing customer, supplier, order, and settlement RLS policies were inspected but not modified.

## Verification performed

- Re-fetched all three changed frontend files from the test branch after the writes.
- Confirmed the legacy profile-role guards are absent from login and supplier application verification.
- Confirmed the supplier review button condition uses the explicit review permission.
- Confirmed Command Center role-scope fallbacks are absent, permission arrays are enumerated, and both quotation permissions are mapped.
- Read-only test database state check returned:
  - Active Finance test grant: 1
  - Expected Operations, Supplier and Finance permission rows: 13
  - Appointment hold: enabled
  - Active test Super Administrator: 1

## Important limits / remaining work

This is a focused first correction pass, not certification of every FrostTech administrative procedure. No live browser sign-in or end-to-end RPC execution was performed in this pass. The following require a separate dependency review and targeted tests before production consideration:

- Finance and Tax workspace procedure-by-procedure checks, including the Super Administrator-only tax settings read.
- Independent quotation frontend and Edge Function authorisation, including bank preparation and confirmation permissions.
- Remaining admin RPCs that still use role-only checks, including direct quotation counts, reviewed against their actual callers and data scope.
- RLS policies that currently use `is_super_admin()`, preserving customer, guest, supplier, and supplier-cost boundaries.
- Trigger/internal/service-role-only SECURITY DEFINER functions, which must not be mistaken for interactive administrator procedures.

No database migration was applied, no permissions were added or removed, no employee/operator was appointed, no invitation or email was sent, no settlement/disbursement was recorded, and no payment was made.

## Commits

- Login central role check: `558c0f1c88bed18fd94fed5d1eb03393bc413716`
- Supplier central role check: `1a31f4f474c6029fa29af2c19d165beeff62e32a`
- Command Center explicit permission checks: `e4892a62bb5c89d182f249a47c226d69e2f8a083`
- Login safe return destinations: `2997b2dac36e18078cec6ed321a11faa8a2a1109`
- Supplier review control permission gate: `6640ad3bad7d89bd56af0a872a4d1c4fd2fac863`
