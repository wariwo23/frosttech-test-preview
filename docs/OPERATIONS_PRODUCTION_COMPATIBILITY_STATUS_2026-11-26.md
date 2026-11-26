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


## Frontend and function-contract audit — additional findings

The current `operations-standard-quotations-test.html` is a draft-only editor, not yet a complete revision-capable Operations workspace:

- It calls the three new draft/save/submit RPCs and the existing `ops_list_customer_requests()` and `ops_list_quotations()` readers.
- It has no action to create a revision from an eligible submitted quotation, despite the production revision RPC already existing.
- It reconstructs an edited quotation as a primary product plus additional rows. When it rebuilds item JSON it sets `source_proposal_id` and `replaces_item_id` to null. That can discard the link to a customer-accepted alternative or a replaced item when a draft is edited and saved. This must be fixed before the editor is considered production-compatible.
- The editor assumes the first item in the returned item list is the primary item. The API must guarantee stable ordering and the editor must preserve all item metadata, not just display fields.
- Catalogue lookup assumes `products(id,name,unit,selling_price,is_active)`; the production schema and its RLS/grants must be checked before using this direct client query in production.
- It checks `profiles.is_active` and then `admin_get_my_role()`; the RPC remains the authoritative role check, but the page must also verify that only Operations and Super Admin are admitted and that Super Admin preview remains read-only.

Production grant inspection confirmed that the three existing quotation revision/edit/submit RPCs currently allow EXECUTE to authenticated and deny anon/public. The authorization migration uses CREATE OR REPLACE and therefore intends to preserve those existing grants; this still requires a post-migration grant assertion in regression tests.

## Updated next actions

1. Extend the Operations editor with a revision action for only the existing function's eligible states; call `admin_create_direct_quotation_revision_v2`, then load the returned new draft ID.
2. Preserve `source_proposal_id` and `replaces_item_id` for every row during edit/save. Do not clear accepted-alternative linkage.
3. Ensure the draft reader returns a stable ordered item list and complete allowed operational metadata without exposing private supplier pricing.
4. Verify production catalogue read policy/columns and use a safe, permission-scoped catalogue reader if direct client access is not appropriate.
5. Add explicit role gating and post-migration function-grant assertions.
6. Validate the release candidate in a disposable production-schema clone before any production execution.
