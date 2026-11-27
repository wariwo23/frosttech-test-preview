# Direct Quotation — Unified Permission Implementation (Isolated Test)

Date: 2026-11-24
Environment: isolated FrostTech test only
Supabase project: `gqnidjifiobhqhnxjlow`
Repository: `wariwo23/frosttech-test-preview`
Branch: `command-center-shell-stage1`

## Implemented

### Database

Migration `20261124160000_unified_direct_quotation_permissions_test.sql` was applied to the isolated test database and committed to the test branch.

- Added `frosttech_admin_actor_has_permission(actor, permission)`, a SECURITY DEFINER helper with an empty search path.
- Helper validates the actor's active profile, active permanent administrator account and exact role permission, or active, non-revoked isolated test grant and exact role permission.
- Helper EXECUTE is revoked from PUBLIC, anon and authenticated; only service_role can execute it. It is used by service-role-only direct quotation RPCs after their Edge Functions authenticate the bearer token and obtain the verified actor ID.
- Direct quotation draft creation, update and issue now require `quotations.read_operational`.
- Simulated bank-credit confirmation now requires `payments.verify`.
- `frosttech_admin_count_direct_quotations()` now uses the authenticated caller's `admin_has_permission('quotations.read_operational')` rather than checking a hardcoded administrator role.
- Existing own-draft restrictions, test quotation ID restrictions, development environment checks, idempotency, pricing/fee calculations, and service-role-only RPC grants were retained.

### Edge Functions deployed to isolated test project

| Function | Previous version | New version | JWT |
|---|---:|---:|---|
| `create-direct-quotation` | 19 | 20 | Required |
| `issue-direct-quotation` | 24 | 25 | Required |
| `direct-quotation-bank-workflow` | 8 | 9 | Required |

Procedure permissions are now checked using `admin_has_permission`:

- Create/list/read/update draft and issue quotation: `quotations.read_operational`
- Send bank instructions: `quotations.read_operational`
- Read bank payment status: `payments.read`
- Confirm simulated bank payment and retry password email: `payments.verify`

The Edge Functions still verify the bearer session using Supabase Auth, enforce the isolated project/environment and designated test quotation/customer restrictions, and pass only the verified user ID to the database RPC. No caller-supplied actor ID is trusted.

### Frontend

`admin-independent-quotations-test.html` now:
- checks central account status plus the exact procedure permissions;
- allows a user with operational quotation permission to prepare/send quotation instructions;
- allows a user with payment-read permission to read payment status;
- allows a user with payment-verification permission to confirm or retry the simulated test payment workflow;
- no longer uses administrator role names to gate those procedures;
- disables payment-status refresh for users without `payments.read`.

## Verification

### Permission matrix — read-only database calls

| Test identity | Permission checked | Result |
|---|---|---|
| Finance test grant | `payments.verify` | Allowed |
| Finance test grant | `quotations.read_operational` | Denied |
| Operations test admin | `quotations.read_operational` | Allowed |
| Operations test admin | `payments.verify` | Denied |
| Test Super Administrator | `payments.verify` | Allowed |
| Old inactive/ungranted test identity | `payments.verify` | Denied |

This confirms that access follows the procedure permission rather than the environment's profile role label.

### Database grants

- Helper: anon=false, authenticated=false, service_role=true.
- Four privileged direct quotation/payment RPCs: anon=false, authenticated=false, service_role=true.
- Direct quotation count RPC: anon=false, authenticated=true, service_role=true; its function checks authenticated identity and the operational quotation permission.
- Central helper and all updated function definitions were re-read after migration.

### Edge deployment verification

All three deployed functions were fetched again:
- versions 20, 25 and 9 were active;
- `verify_jwt=true` remained enabled;
- all three call `admin_has_permission`;
- none retains the old `admin_get_my_role()` role-list gate.

### Existing test quotation state

The designated development quotation `FT-DQ-2026-0000002` was inspected after implementation. It already had one synthetic fee-payment record, one synthetic bank-confirmation record and one protected document, with status submitted / fee paid. This was pre-existing test data. This implementation did not create or change those records. It represents a simulated test flow only, not a real bank credit or real funds transfer.

## Security advisor observation

The post-migration security advisor still reports the project's existing SECURITY DEFINER/RLS informational and warning findings, including a pre-existing anonymous-executable tax trigger function. The new helper and the updated service-role-only quotation RPCs do not appear as anonymous-executable findings. No broad RLS, function-grant or trigger changes were made as part of this task. The existing findings require a separate dependency review; do not blanket revoke them.

## Not yet verified

- No interactive browser login or live end-to-end quotation workflow was executed.
- No new quotation was created or issued.
- No new bank confirmation, payment, email, or password release was triggered.
- No production repository, production Supabase project, or production Edge Function was changed.
- Finance, Tax and Operations workspace entry pages still need their separate permission-first frontend corrections and tests.

## Commits

- Isolated migration file: `ea8e1d69c40054b76b96b9c5fff88d99bc1db30e`
- Quotation workspace permission gates: `10e03740dddd4d00ff28142dd612ea6d0289db75`
- Remaining quotation UI role gate removed: `ed6f857bb761e49820affb73f8dd32fc16ab952b`
- Payment-status refresh permission correction: `507d7ded2f62529b2d7983c0ba0e558178bf6c9e`
