# FrostTech Command Center — Appointment Hold Safeguard

**Environment:** Isolated test Supabase project `gqnidjifiobhqhnxjlow` and test frontend repository `wariwo23/frosttech-test-preview`, branch `command-center-shell-stage1`.

**Status:** Implemented in test only. Production was not changed.

## Safeguard behaviour

- A central `departmental_appointments` control is created with `is_on_hold = true`.
- Only the active Super Administrator can read or change the hold through the dedicated RPCs.
- Releasing the hold requires a reason of at least 12 characters and writes an administrative audit entry.
- Releasing the hold does not appoint or activate anyone automatically.
- Employee planning records remain separate from employment activation.
- Employee invitation and account setup remain separate onboarding steps and are not blocked by the appointment hold.
- Employee transition to `active` is blocked while the hold is on.
- New departmental administrator appointments and reactivation of departmental administrator access are blocked while the hold is on.
- Existing Super Administrator and departmental administrator records are preserved. Suspension and removal remain available.
- Table triggers provide a second backend enforcement layer in addition to explicit checks in the employee activation and appointment RPCs.
- The control table has RLS enabled and no direct privileges for public, anon, or authenticated clients.

## Test database checks

| Check | Result |
|---|---|
| Hold state | ON |
| Hold reason | Appointments are on hold until FrostTech officially launches. |
| Employee records | 0 |
| Administrator accounts | 2 |
| Existing accounts | 1 active Super Admin; 1 active Operations Admin |
| Database guard triggers | 2 present |
| Appointment RPC checks hold | Confirmed |
| Employment activation RPC checks hold | Confirmed |
| Hold control RLS | Enabled |
| Hold status/set RPC execution | Authenticated role permitted; RPC enforces Super Admin |
| Internal hold-state helper | Execute revoked from authenticated |
| Trigger function direct execute | Execute revoked from public, anon, authenticated |

No employee records, invitations, staff accounts, or administrator appointments were created. No emails were sent. The hold was not released.

## Test frontend updates

- `employee-management-test.html`: shows hold status and disables employment activation while held.
- `department-operator-management-test.html`: shows the hold, provides Super Admin-only release/re-enable controls, requires a launch reason, disables appointment and reactivation controls while held.
- `admin-management-test.html`: displays the current hold status alongside the read-only audit log.

## Migration

`supabase/migrations/20261123190000_command_center_appointment_hold_draft.sql`

The test database migration history records version `20261123190000` as `command_center_appointment_hold_draft`.

## Remaining validation

There are no employee records in the test database, so an end-to-end employee activation or departmental appointment attempt could not be exercised without creating test identities and records. That has deliberately not been done. The backend guards, RPC definitions, grants, hold state, and trigger presence were inspected. A Super Admin browser smoke test of the three updated pages remains the next validation step.

**Production:** untouched. No production migration, deployment, staff appointment, invitation, or email action was performed.
