# Operations production compatibility — status 26 November 2026

## Work completed in this pass

Read-only inspection of the production database confirmed:

- `admin_create_direct_quotation_revision_v2(uuid)` contains the existing revision safeguards: only declined/rejected/expired quotations may be revised; quotations with orders cannot be revised; private pricing snapshot must exist; additional charges must be safely itemised; revision must originate from latest version; items and private pricing snapshot are copied into a new draft version.
- `admin_replace_direct_quotation_items_v2(uuid,jsonb)` validates item fields/totals, enforces the accepted alternative proposal, and rejects unaccepted proposal links.
- `admin_submit_direct_quotation(uuid)` validates ownership/request state, blocks overlapping active/accepted quotations, validates item totals and accepted alternatives, preserves paid consultation-fee state, and records the immutable submission snapshot.
- All three functions currently use the broad legacy `public.is_admin()` authorization predicate.
- Production `ops_list_customer_requests()` currently returns the entire `quote_requests` row, including the four Finance-only consultation-fee fields.
- Production `admin_role_permissions_role_check` currently permits the five roles `super_admin`, `operations_admin`, `supplier_admin`, `finance_admin`, and `catalogue_admin`. The consolidated advertiser role is a separate role-constraint stage and is not changed here.

## Prepared release candidates

Two SQL candidates have been committed under `supabase/release-candidates/`:

1. `20261126_operations_authorization_and_redaction_production_candidate.sql`
2. `20261126_operations_authorization_and_redaction_rollback_candidate.sql`

The forward candidate uses the live function definitions as its source at execution time, changes only the three legacy authorization predicates to `admin_has_permission('quotations.manage_operational')`, applies explicit fee-field redaction to the Operations request list, and adds only the missing Operations permission mapping. It does not rewrite quotation business rules or change the existing function signatures.

The rollback restores the three legacy authorization predicates and removes the added permission mapping. It intentionally keeps the fee-field redaction because exposing Finance-only fee details to Operations is not an acceptable rollback state.

## Validation and release gates still outstanding

- These candidates have been committed to the isolated test repository only; they have **not** been applied to production or test databases.
- Execute in an isolated production-schema clone or controlled disposable clone and validate the exact live function body formatting, function grants, trigger behavior and migration transaction before release.
- Confirm the Operations role's permission mapping and Super Admin bypass in the target production authorization schema.
- Run regression tests for revision eligibility, latest-version enforcement, order-linked revision rejection, private pricing snapshot copying, item totals, accepted alternative linkage, acceptance conflicts, immutable snapshots, and customer ownership.
- Confirm Operations cannot read consultation-fee amount/status/reference/paid timestamp while Finance and Super Admin retain their authorized views.
- Reconcile the editor frontend with the RPC contracts, including a proper submitted-version revision workflow. The current test editor's draft workflow alone is not sufficient.
- Complete the remaining frontend and Edge Function compatibility review before production release.

## Release decision

**Not approved for production application yet.** The candidates are prepared; compatibility testing and the remaining authorization/frontend regression gates must pass first. No production database, frontend, Edge Function, payment, or live customer workflow was changed in this pass.
