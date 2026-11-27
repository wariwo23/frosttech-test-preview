# Finance, Tax and Operations — Unified Permission Frontend Corrections

Date: 2026-11-24
Environment: isolated FrostTech test only
Supabase project: `gqnidjifiobhqhnxjlow`
Repository: `wariwo23/frosttech-test-preview`
Branch: `command-center-shell-stage1`

## Scope

Updated the Finance, Tax, Operations and central Command Center frontend entry checks so authorised procedure permissions—not a fixed administrator role label—determine access. No database migration or permission assignment was made in this stage.

## Changes

### Finance Administration — `finance-admin-test.html`

- Removed the Finance Admin / Super Admin role allowlist as the entry criterion.
- Requires an active central administrator/test-grant identity from `admin_get_my_role()`.
- Verifies the workspace's required procedure permissions through `admin_has_permission()`: `financial_reports.read`, `payments.read`, `quotations.read_financial`, and `quotations.costs.submit`.
- Preserves Super Administrator read-only preview.
- Existing settlement workflow remains separately gated by its own `supplier_settlements.*` permissions.

### Tax Administration — `tax-admin-test.html`

- Removed the Finance Admin / Super Admin role allowlist.
- Entry now requires an active central identity and at least one applicable Tax procedure permission, with Super Administrator access retained.
- Loads only the data groups whose required permission sets are present.
- Tax assessment/remittance refresh also checks supplier-settlement read and audit-read permissions because that view reads those protected datasets.
- Tax rule activation/deactivation, VAT configuration, and viewing/updating VAT settings remain Super Administrator-only. Granular assessment, remittance, supplier-profile and certificate actions remain permission-gated.

### Operations — `departmental-admin-test.html`

- Removed the Operations Admin / Super Admin role allowlist.
- Requires the exact Operations permission set: `customer_requests.manage`, `deliveries.manage`, `orders.manage`, and `quotations.read_operational`.
- The workspace is shown only after those permissions have been confirmed (or for Super Administrator preview).
- Super Administrator preview remains read-only.
- Existing Operations RPC checks remain the final authority for each operation.

### Administration Command Center — `admin-command-center-test.html`

- Removed the fixed list of permitted role names at workspace entry.
- Requires a valid active identity from the central database function.
- Department navigation continues to use explicit permission checks, with Super Administrator override.
- Security administration remains Super Administrator-only.

## Test database permission matrix

Read-only actor-permission checks against the isolated test project returned:

| Identity | Permission | Result |
|---|---|---|
| Finance test grant | `financial_reports.read` | Allowed |
| Finance test grant | `payments.read` | Allowed |
| Finance test grant | `quotations.read_financial` | Allowed |
| Finance test grant | `quotations.costs.submit` | Allowed |
| Finance test grant | `tax.rules.read` | Allowed |
| Finance test grant | `tax.assessments.read` | Allowed |
| Finance test grant | `supplier_settlements.read` | Allowed |
| Operations test admin | `customer_requests.manage` | Allowed |
| Operations test admin | `orders.manage` | Allowed |
| Operations test admin | `quotations.read_operational` | Allowed |
| Operations test admin | `deliveries.manage` | Allowed |
| Operations test admin | `payments.verify` | Denied |
| Test Super Administrator | `tax.rules.read` | Allowed |
| Inactive/unauthorised test identity | `tax.rules.read` | Denied |

This verifies that procedure access follows the exact permission and not a profile role label. It was a database-level permission test, not a live browser workflow test.

## Re-fetch checks

All four changed HTML files were fetched again from the test branch. The legacy profile-role hard gate and fixed role allowlists are absent from their workspace entry logic. Central role/account validation and permission calls remain present.

## Preserved controls

- Finance Super Administrator preview remains read-only.
- Tax rule activation/deactivation and VAT settings remain Super Administrator-only.
- Operations Super Administrator preview remains read-only.
- Command Center security/employee/operator administration remains Super Administrator-only.
- Existing customer, guest, supplier and supplier-cost RLS policies were not changed.
- No database grants, permission rows, test grants or accounts were changed.
- No employee/operator appointments, invitations, emails, payment, settlement, or production changes occurred.

## Not yet verified

- No interactive browser login was run for Finance, Tax or Operations.
- No end-to-end form submission or workflow action was run.
- Direct RPC and RLS enforcement remain as previously audited; no RLS edits were needed for this frontend-only stage.
- Live Finance evidence upload/disbursement verification remains pending.
- Production remains untouched and requires its own separate audit and explicit approval.

## Commits

- Finance permission-first entry: `0a0c739f1860540163f8b7ae3e1e1002a3a4b286`
- Tax permission-first entry and conditional refresh: `6d87b432ead7eb14cced319e20766e5b5a4cdf17`
- Tax settlement-read dependency: `ae129605241ef0987d9a90090197b776a424adcf`
- Operations permission-first entry: `c01420a01d579b18d857b145c3fadc4e46b3a6f0`
- Operations permission-driven workspace: `9ef37531bf339592b03555e89642db1784630e31`
- Operations Super Administrator preview preservation: `5ab1282a9a6bc23a8b72b8fe49e705111cbe5015`
- Command Center role allowlist removal: `3a0d6673e49d3dd0ca1866a1f364d81f618e7ec4`
