# FrostTech Operations Workspace — Quotation Integrity Dependency Review

**Status:** Read-only dependency review complete; implementation migration remains blocked.
**Target:** Isolated test project only — `gqnidjifiobhqhnxjlow`
**Repository:** `wariwo23/frosttech-test-preview`
**Branch:** `command-center-shell-stage1`
**Production writes:** None. **Test writes:** None.

## Why the Operations migration is not yet safe to apply

The production Operations RPCs read and update `quote_requests` and read `admin_quotations`. Those two tables are not stand-alone objects. Production protects the underlying quotation lifecycle with database triggers, snapshot tables, integrity auditing, alternative-proposal decisions, quotation items, and server-controlled environment classification.

Creating only the two table shells would omit controls that are part of the existing workflow. The current Operations migration is therefore deliberately marked **BLOCKED**.

## Verified production dependencies

### Customer request integrity

Production `quote_requests` has:
- A submitted-original snapshot captured by `frosttech_capture_quote_request_original_v1()`.
- A protected original-payload builder, `frosttech_request_original_payload_v1(quote_requests)`.
- An update guard, `frosttech_guard_quote_request_original_v1()`, which rejects changes to original customer/request fields.
- A delete guard, `frosttech_block_quote_request_delete_v1()`.
- An environment-classification trigger using `private.frosttech_guard_environment_classification_v1()`.
- Snapshot storage in `quote_request_original_snapshots`.
- Integrity events in `quote_request_integrity_audit`.

The snapshot/audit tables have their own foreign keys, JSON-object checks, capture-type checks and read policies. They must not be replaced by weaker ad hoc tables.

### Quotation integrity

Production `admin_quotations` has:
- Generated `subtotal` and `total_amount` columns.
- `frosttech_guard_quotation_version_scope_v2()`, protecting submitted quotation versions and approved snapshots.
- `frosttech_guard_cross_quotation_acceptance_v1()`, preventing conflicting acceptance across quotation versions and accepted alternatives.
- `admin_quotation_assign_number()`, assigning a quotation number when absent.
- Scope/version constraints and foreign keys.

The cross-acceptance guard also references:
- `alternative_proposal_decisions`
- `alternative_proposals`
- `admin_quotation_items`

The alternative decision and quotation-item tables in turn reference additional workflow tables, including supplier/proposal records. These are not optional if the production acceptance guard is reproduced faithfully.

### Environment classification

Production restricts environment classification changes to trusted server-role requests. A test migration must preserve that rule and must not permit a client-side role to mark a test request/order as production.

## Required next preparation

1. Map the full alternative-proposal dependency chain, including `alternative_proposals`, `alternative_proposal_decisions`, `admin_quotation_items`, supplier quote/supplier references, and customer-ownership helper dependencies.
2. Inspect the complete production trigger and policy definitions for those dependencies.
3. Inspect the isolated test project's corresponding supplier, quotation, private-schema and helper objects to determine what already exists.
4. Prepare a companion **test-only** migration that creates only genuinely missing dependencies, preserving the production integrity rules and existing RLS boundaries.
5. Cross-check all ten Operations RPC signatures against the live test frontend before applying anything.
6. Present the combined migration set for user review. Applying it requires a separate explicit approval.

## Safety boundary

This document is a review record, not executable SQL. It does not create, alter, or delete any database object. No test data or production data was changed. No employee/admin account, invitation, payment, quotation or customer workflow was actioned.


## Additional read-only findings

### Ownership helper

`frosttech_customer_owns_quote_request_v1(request_id)` verifies that:
- The request belongs to `auth.uid()`.
- The matching profile has role `customer`.
- The profile is active.

This helper is used by customer-facing read policies for original snapshots, alternative proposals, and alternative decisions. It is a workflow dependency and should be retained in the test mirror if those policies are recreated.

### Production row-level policies

The inspected production read policies are:
- `alternative_proposals`: customer who owns the request, the proposal's submitting user, or an authorised customer-request manager.
- `alternative_proposal_decisions`: request-owning customer or authorised customer-request manager.
- `quote_request_original_snapshots`: request-owning customer or authorised customer-request manager.
- `quote_request_integrity_audit`: authorised customer-request manager only.
- `admin_quotation_items`: Super Admin manage policy; customer/manager read policy scoped through the parent quotation.

These are deliberately distinct access rules. Do not replace them with a blanket authenticated policy. The Operations list RPC should expose only the fields needed by Operations and must not confer direct table access.

### Cross-acceptance rule

The production cross-quotation guard runs on both quotation and alternative-decision changes. It serialises acceptance on the parent customer request, rejects acceptance of a second quotation version, and rejects accepting an alternative proposal when a quotation is already accepted (and vice versa). A quotation that incorporates an accepted alternative must contain the matching proposal reference in its quotation items.

### Remaining mapping before companion SQL is complete

The exact production columns and constraints for the four dependency tables have been inspected. The alternative proposal table also references supplier and supplier-quote records, and the quotation item table references proposal IDs. The companion migration must therefore map the exact test prerequisites for `suppliers`, `supplier_quotes`, `alternative_proposals`, and the corresponding functions/triggers before writing executable DDL.

No test-side dependency exists yet; the test project returned no matching integrity tables or helper functions in the read-only check. No production or test data was modified.


## Supplier and alternative-proposal dependency map — completed read-only pass

### Isolated test project inventory

The isolated test database currently has the `suppliers` table, but the following production workflow dependencies were not found there:
- `supplier_quotes`
- `alternative_proposals`
- `alternative_proposal_decisions`
- `admin_quotation_items`
- `quote_request_original_snapshots`
- `quote_request_integrity_audit`

The test project also has no matching production integrity trigger/helper functions. This confirms the companion dependency migration must build a coherent workflow layer, not just add a few foreign keys.

### Supplier quote relationship

Production `supplier_quotes` references:
- `quote_requests` (request)
- `suppliers` (supplier)
- `products` (optional catalogue product)

Its pricing trigger calculates supplier total from unit price × quantity and deliberately resets FrostTech margin and customer total fields. The table has supplier-owned read/insert policies for active, verified suppliers and a Super Admin manage policy. It must not be replaced with a broader authenticated policy.

Production `suppliers` also has a guard that prevents disabling, un-verifying, or un-approving a supplier while selected supplier-cost records still depend on that supplier. The test project has the suppliers table but does not have the related quotation/proposal dependency layer; the selected-supplier guard must only be carried over if its `product_supplier_costs` dependency and exact test schema are verified.

### Alternative proposal validation

The production insert trigger for `alternative_proposals`:
- Requires an original-request snapshot to exist.
- Removes protected customer identity, budget and delivery-address fields from the comparison baseline.
- Rejects unsupported fields in the proposed payload.
- For supplier proposals, verifies the linked supplier quote belongs to the same request and supplier and is still submitted.
- Requires the proposed product reference to match the linked supplier quote.
- Builds a complete proposed payload and a field-by-field differences object.

Alternative proposals and decisions are append-only: updates and deletes are rejected. The customer decision table permits only authenticated-customer or verified-guest-OTP decision channels, with mutually consistent actor fields.

### Quotation item integrity

Production `admin_quotation_items` references the quotation header, optional catalogue product, source alternative proposal, and optional replaced item. It enforces item type, non-empty description/unit, positive quantity, non-negative unit/line price, JSON object specifications, and non-negative sort order.

A trigger prevents items belonging to submitted quotations from being changed, deleted, or moved to another quotation. Direct table management is Super Admin-only; read access is separately scoped to the owning customer or authorised request manager.

### Production supplier quote policies

- Supplier SELECT and INSERT are limited to the supplier's own row when the supplier is active and verified.
- Super Admin has full supplier-quote management.
- Supplier profile reads are own-row or admin; supplier writes/deletes are admin-only.
- The test mirror must retain these boundaries and must not give Operations Admin supplier commercial quote visibility merely because Operations can view customer requests.

### Current readiness

The dependency graph and key integrity logic are now mapped. The next companion migration can be drafted, but it must explicitly identify which supplier-side schema objects are required and which are deliberately excluded from Operations scope. The Operations workspace itself should not receive any new supplier pricing or cost privileges.

**Still not authorised:** applying SQL to the test database, deploying functions, sending invitations, changing accounts, or modifying production.


## Exact schema inventory captured for companion migration

A further read-only metadata pass captured the production column inventory for the dependency tables:

- `supplier_quotes`: request, supplier and product references; quantity; supplier unit/total prices; delivery cost; validity/status; margin percentage/amount; customer total and customer quote status.
- `alternative_proposals`: request/proposer/supplier references; version; reason; proposed payload; commercial terms; differences; supplier quote and resulting admin quotation references.
- `alternative_proposal_decisions`: proposal/request references; decision and reason; actor/time; decision channel; normalised guest email.
- `admin_quotation_items`: quotation and optional product references; item type, description, specifications, unit, quantity, unit price, line total, sort order, source proposal and replaced-item references.
- `quote_request_original_snapshots`: request key, original JSON payload, payload hash, capture type and capture timestamp.
- `quote_request_integrity_audit`: request/proposal references, actor type/id, event type/details and timestamp.

The production policy inventory confirms:
- Supplier quote SELECT/INSERT is limited to the supplier's own record when the supplier is active and verified.
- Super Admin alone has full supplier quote management.
- Alternative proposal reads are scoped to the request-owning customer, submitting proposer, or request manager.
- Alternative decision and original-snapshot reads are scoped to the owning customer or request manager.
- Integrity audit reads are request-manager-only.
- Quotation-item management is Super Admin-only; read access is separately scoped through the parent quotation.

## Important drafting constraint

The test supplier table is structurally different from production in some areas, and the isolated test database has no supplier quote or alternative-proposal tables. The companion migration must not overwrite or casually reshape the existing test supplier table. Before writing executable DDL, the remaining exact production constraints, indexes, trigger bodies, trigger ordering, and referenced helper/function definitions must be retrieved and cross-checked against test-side dependencies. In particular, supplier quote price/margin trigger logic and append-only proposal/decision guards must be preserved.

This is still a metadata-only review. No data rows were read, and no database object was changed.
