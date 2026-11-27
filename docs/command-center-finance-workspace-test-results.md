# FrostTech Command Center — Finance workspace test results

**Environment:** isolated test Supabase project only  
**Test project ref:** `gqnidjifiobhqhnxjlow`  
**Test branch:** `command-center-shell-stage1`  
**Migration file:** `supabase/migrations/20261123180000_command_center_finance_workspace_dependencies_draft.sql`  
**Applied migration record:** `20261123133336 command_center_finance_workspace_dependencies_draft`  
**Test date:** 2026-11-23

## Scope and safety

- Applied the Finance dependency migration to the isolated test database only.
- Production Supabase project `nftxptjpgidcsgtaltjn` was not changed.
- No employee/operator account was created or appointed.
- No invitation or email was sent.
- No customer, quotation, cost submission, approval, payment, receipt, or settlement record was created or modified.
- Permission checks and RPC probes were executed inside rollback-only transactions where applicable.
- The first migration attempt stopped at its preflight check because it incorrectly used `to_regclass('private')` to test for a schema. No objects from that failed attempt were committed. The draft was corrected to check `pg_namespace`, and the Super Admin helper was moved before policies that reference it. The corrected migration then applied successfully.

## Schema and object verification

Verified present:
- `quotation_cost_submissions`
- `quotation_cost_snapshots`
- `quotation_cost_approval_audit`
- Existing `payment_receipt_voids`
- Finance RPCs: `finance_get_summary`, `finance_list_payments`, `finance_list_quotations`, `finance_list_my_cost_submissions`, `finance_list_quotations_for_costing`
- Cost RPCs: `submit_quotation_cost`, `review_quotation_cost`

Verified enabled triggers:
- Receipt void append-only guard.
- Cost submission self-approval guard.
- Approved cost snapshot immutability.
- Cost approval audit immutability.

Verified policies and privileges:
- Finance payment reads are scoped by `admin_has_permission('payments.read')`.
- Cost submissions are visible to the submitting authorised Finance operator and active Super Admin.
- Cost snapshots are visible to authorised financial readers and active Super Admin.
- Cost approval audit is Super Admin-only.
- Receipt void records are service-role-only; authenticated direct SELECT is denied.
- Authenticated access to the private schema is namespace USAGE only; individual private function execute grants remain separately controlled.

## Role and RPC tests

### Super Administrator

Test identity: `7fb39f06-ce75-437c-8676-7a6141cf9664`

- `admin_get_my_role()` returned `super_admin`.
- `private.is_active_super_admin()` returned true.
- Super Admin permission override returned true for financial reports, payment reads and cost submissions.
- Read-only Finance RPCs executed successfully:
  - `finance_get_summary` returned JSON object.
  - `finance_list_payments` returned JSON array.
  - `finance_list_quotations` returned JSON array.
  - `finance_list_my_cost_submissions` returned JSON array.
  - `finance_list_quotations_for_costing` returned JSON array.

### Operations Administrator negative tests

Test identity: `3f783825-9ee0-4e7f-b792-eddc29a8b772`

- `admin_get_my_role()` returned `operations_admin`.
- Finance report, payment-read and quotation-cost-submission permissions all returned false.
- Calling `finance_get_summary` was rejected with `Finance reporting permission required`.
- Calling `submit_quotation_cost` was rejected with `You do not have permission to submit quotation costs.`
- Calling `review_quotation_cost` was rejected with `Only the active Super Administrator can review quotation costs.`
- Direct RLS-visible row counts for submissions, snapshots and approval audit were all zero.

## Remaining limitations / next checks

- No active Finance Admin account exists in the isolated test database, so positive Finance Admin role testing has not yet been performed. The Finance Admin permission matrix is present, including the six production-aligned Finance permissions and the existing tax/settlement permissions.
- The test branch does not yet contain a Finance workspace frontend page. The production Finance page was audited read-only; no frontend was copied or modified in this stage.
- No real cost submission was created, so the complete submit → Super Admin review → immutable snapshot/audit lifecycle still requires a deliberately authorised test fixture and end-to-end test.
- Existing Finance interface does not provide a manual payment-verification action; the `payments.verify` permission remains unused by that page and has not been wired to a new action.
- WHT design remains a separate production-readiness requirement; no rate or tax logic was changed here.

**Result:** isolated Finance dependency migration applied; schema, key RPC availability, Super Admin read access, Operations Admin denial, and key RLS/trigger safeguards verified. Finance Admin positive-path and full cost lifecycle tests remain outstanding.
