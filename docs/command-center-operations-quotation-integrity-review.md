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


## Trigger, constraint, and index definitions captured

A read-only production metadata pass retrieved the trigger definitions and exact trigger-function bodies for the dependency tables.

### Preserved trigger behaviour

- Supplier quote pricing trigger validates quantity and non-negative supplier unit/delivery costs, calculates supplier total, and deliberately resets FrostTech margin/customer total fields rather than exposing a customer price from supplier submission.
- Alternative proposal preparation requires the immutable original-request snapshot, rejects unsupported/protected payload keys, verifies supplier proposal linkage to the supplier's submitted quote for the same request, requires explicit product linkage, and computes a differences object.
- Alternative proposal and decision records, request snapshots, and integrity audit entries are append-only.
- Cross-quotation acceptance serializes on the parent request and prevents acceptance of competing FrostTech/alternative quotation paths; an accepted alternative must be represented in the quotation items.
- Quotation item scope is immutable once the parent quotation is no longer draft.
- Integrity audit enrichment verifies the proposal/request pair and records the proposal differences.

All retrieved trigger functions use an empty search_path; SECURITY DEFINER functions explicitly qualify referenced public objects. These function bodies must be carried forward faithfully and reviewed for grants/ownership before execution.

### Constraints and indexes

The captured production definitions include:
- Supplier quote status check and supplier/request/product foreign keys.
- Alternative proposal proposer-type, linkage, payload-object, reason-length, version and uniqueness constraints.
- One decision per proposal and at most one accepted alternative decision per request (partial unique index).
- Composite proposal/request foreign keys on decisions and integrity audit.
- Original snapshot one-row-per-request primary key and permitted capture-type values.
- Quotation item type, quantity, unit-price, line-total, description, unit, sort-order and JSON-object checks; quotation/product/replacement/source-proposal foreign keys.
- Supporting request, supplier, proposal, audit chronology, quotation-order and source-proposal indexes.

### Companion migration safety gate

The migration must reproduce the dependency schema and trigger graph in dependency order, with exact FK/index/check definitions, and then apply restrictive grants/RLS. It must not grant direct INSERT/UPDATE/DELETE on integrity or quotation dependency tables to anon or authenticated clients. Supplier self-service policies must remain limited to a supplier's own verified and active supplier account; Super Admin-only management remains intact. No Operations permission may expose supplier quote costs, supplier margin fields, or Finance-only quotation information.

The isolated test supplier table differs from production; migration preflight must stop rather than alter an existing object if its shape is unexpected. Existing draft SQL remains blocked pending companion migration and complete static review.

This was a metadata/function-definition inspection only. No production data rows were read and no database writes or deployments were performed.


## Migration static review — newly identified blockers

The current Operations SQL draft was re-opened and statically inspected against the metadata gathered so far. It remains **not safe to apply**.

1. **Helper creation order:** the draft creates policies on `quote_requests` that call `frosttech_can_manage_customer_requests_v1()` before the helper function is defined later in the file. PostgreSQL policy creation requires the referenced function to exist at policy creation time. The helper must be created and permission-checked before those policies.
2. **Direct table grants:** the draft grants broad direct `SELECT, INSERT, UPDATE` to authenticated and `INSERT` to anon on `quote_requests`. This has not been demonstrated to match production table grants and is broader than the intended RPC-mediated Operations access. It must not be carried forward without an exact grant comparison and a documented need.
3. **Quotation table privileges:** the draft grants direct `SELECT, INSERT, UPDATE, DELETE` on `admin_quotations` to authenticated, relying only on RLS to narrow access. This must be checked against production grants and existing frontend RPC dependencies; do not assume an RLS policy alone is the complete privilege boundary.
4. **Production integrity trigger omissions:** the draft still does not create the original-request snapshot capture, original-field immutability, request deletion guard, environment-classification guard, quotation version-scope guard, cross-quotation acceptance guard, or automatic quotation-number trigger and their required dependencies.
5. **Supplier/proposal dependency omissions:** the draft does not yet create supplier quote, alternative proposal, alternative decision, quotation item, snapshot, and integrity-audit tables with the verified constraints/indexes/triggers/policies. The production supplier-quote pricing trigger and alternative-payload preparation function are not optional if the workflow is represented in the test mirror.
6. **Test supplier table:** the existing isolated test `suppliers` table is confirmed present with its own column shape. The migration must reference it only after checking all required columns and foreign-key compatibility; it must not recreate or reshape it.
7. **RPC fidelity:** the current Operations RPC bodies were previously identified as approximations in places. Before application, each function must be compared line-by-line with the exact production function definition and the test frontend call signatures. No simplified substitute is acceptable for live customer/order/delivery workflows.

### Decision

Do not apply the current Operations draft and do not create the companion migration as executable DDL yet. First retrieve exact production table grants, complete remaining table/trigger/function dependencies (including the request and quotation guards), and compare all ten RPC bodies and frontend signatures. Then prepare a corrected, ordered companion migration and a corrected Operations migration as one review package.

This static review did not execute the migration or change any database object. Production and isolated test databases remain unchanged.


## Production table-grant comparison — correction and precise interpretation

A separate, single-query read-only inspection of `information_schema.role_table_grants` captured the effective role grants for the relevant production tables. This clarifies the earlier static-review warning:

- Production `quote_requests` has broad base table privileges for anon/authenticated in several operations, but **neither anon nor authenticated has INSERT** in the captured grants. RLS policies and triggers are essential to constrain the remaining operations.
- Production `admin_quotations` and `admin_quotation_items` show broad base table privileges for anon/authenticated, again relying on RLS and integrity triggers to restrict effective access. Therefore, the previous statement that broad authenticated table privileges on `admin_quotations` were necessarily broader than production was too strong; the grant list does not support that conclusion.
- Production `supplier_quotes` grants authenticated table privileges, while RLS limits supplier access to the supplier's own eligible record and Super Admin policy controls management. No anon table grants were returned for supplier quotes.
- Production `alternative_proposals`, `alternative_proposal_decisions`, and `quote_request_original_snapshots` grant table privileges to service_role/postgres, not anon/authenticated in the captured results.
- Production `quote_request_integrity_audit` includes authenticated SELECT, but RLS still scopes reads to request managers; mutation privileges are not granted to authenticated in the captured results.
- Existing production orders/order_items/deliveries show broad base grants too, with RLS policies providing the effective restrictions. Do not treat the presence of a base grant as proof that a user can perform the action.

**Required correction to migration review:** do not simply revoke all broad table grants or blindly copy grants. The corrected migration must reproduce the exact production grant + RLS + trigger combination where applicable, while ensuring the test environment does not broaden effective access. The specific confirmed overgrant in the earlier draft remains `quote_requests INSERT` for anon/authenticated because production's captured grants do not include that privilege. All privilege decisions must be evaluated together with policies, helper functions, triggers and frontend usage.

No data rows were read. This was a metadata-only production inspection.


## Exact Operations RPC comparison — completed

A fresh read-only retrieval of the live production definitions was compared against all ten function definitions in `20261123150000_command_center_operations_workspace_draft.sql`.

### Results

- All ten Operations function bodies are equivalent to the production bodies after ignoring whitespace and formatting.
- Parameter names and order match the frontend call contract. Return types also match, including the table-shaped result from `ops_list_delivery_contact_logs`.
- The live `departmental-admin.html` frontend uses the same five list RPC names through its module map and calls the five action/history RPCs with the matching named arguments.
- The frontend source inspected was production branch `main`, file blob `da61e462290d7bb3b654b45df1a44bc8f3fa8a9a`.

### Deliberate execution-context difference

The draft sets each Operations function to `SET search_path = ''`; production currently uses `SET search_path TO 'public', 'pg_temp'`. This is a deliberate hardening difference, not an exact definition copy. The draft bodies schema-qualify application objects used by these functions, but this must remain part of the static review and must not be changed casually.

### Schema comparison update

The draft's column inventories for `quote_requests` (24 columns) and `admin_quotations` (31 columns) match the live production column names. This does not make the schema complete: production triggers and their dependencies remain absent from the draft.

A fresh production trigger inventory confirms the draft omits:

- `quote_requests`: original-request snapshot capture, original-field immutability, delete prevention, and private environment-classification guard (insert and update).
- `admin_quotations`: quotation scope/version immutability, cross-quotation acceptance guard, and automatic quotation-number assignment.

The draft still creates the `quote_requests` policies before creating `frosttech_can_manage_customer_requests_v1()`. This ordering must be corrected because the policy references a helper that does not yet exist at that point in the migration.

The draft also grants `INSERT` on `quote_requests` to both `anon` and `authenticated`. The captured production table grants do not include `INSERT` for either role. These grants must be removed unless a separately verified and approved requirement establishes otherwise. Do not infer that other broad table grants are wrong: production `admin_quotations` relies on the combined grant, RLS, and trigger model, so grants must be compared as a complete security boundary.

### Decision

The ten RPC bodies are no longer a blocker. The migration remains **BLOCKED / DO NOT APPLY** because the integrity trigger graph, dependent tables/functions, policies/grants, helper creation order, and test-side supplier dependencies still need a complete reconciled migration. No migration was applied and no production object was changed.


## Migration block resolution — review package prepared

**Companion migration draft:** `supabase/migrations/20261123160000_command_center_quotation_integrity_dependencies_draft.sql`

**Operations migration corrections:** `supabase/migrations/20261123150000_command_center_operations_workspace_draft.sql`

### Blockers closed in the SQL drafts

1. The Operations helper `frosttech_can_manage_customer_requests_v1()` is now created, restricted and granted to authenticated before any `quote_requests` policy references it.
2. Direct INSERT grants on `quote_requests` to anon/authenticated have been removed. This matches the captured production role grants; the existing customer/guest RLS insert policies are retained but do not themselves confer table privileges.
3. Production quotation version uniqueness and lookup indexes are included: unique `(version_group_id, version_number)`, plus customer, request and superseded-quotation indexes.
4. The companion migration recreates the captured production integrity dependency graph:
   - supplier quote table, pricing trigger and verified-active supplier / Super Admin RLS;
   - immutable original request payload helper and one-time snapshot capture;
   - original request field immutability, deletion prevention and trusted environment-classification guard;
   - append-only snapshots, proposal, decision and integrity audit records;
   - alternative proposal payload validation, supplier-quote linkage and difference calculation;
   - quotation line items and post-submission item immutability;
   - quotation version scope guard, approved-snapshot immutability, automatic quotation numbering and cross-acceptance guard;
   - required foreign keys, checks, unique constraints, partial unique index and supporting indexes.
5. The existing isolated-test `suppliers` table is not altered. The companion preflight requires its reviewed `id`, `user_id`, `is_verified` and `is_active` columns and fails closed if they differ.
6. RLS and grants are intentionally restrictive for the dependency tables. Alternative proposal/decision/snapshot tables remain RPC-mediated; supplier quotes remain limited to the supplier's own eligible row and Super Admin; the integrity audit remains request-manager read-only; quotation item management remains Super Admin-only with scoped read access.

### Production comparison status

- All ten Operations RPC bodies, names, argument order and return types were previously compared with production and the departmental-admin frontend; all ten matched.
- The quote request and quotation column inventories match production. Generated quotation subtotal and total expressions were checked against production metadata.
- The production quotation version-group uniqueness and lookup indexes were added after the first comparison.
- The deliberate empty `search_path` hardening in the Operations RPCs remains documented; all referenced application objects are schema-qualified.
- Existing Operations role permissions are added only if missing; no other role permission rows are rewritten.

### Scope boundary that remains explicit

The companion migration restores the **schema and integrity protections needed by the Operations quotation/request workspace**. It does not port the full customer/supplier alternative-proposal RPC suite or supplier portal frontend into the test environment. Those are separate workflow integrations and must be audited before any claim that the complete customer/supplier alternative-proposal journey is available in test. No customer, supplier or advertiser RLS policies outside this reviewed dependency set are changed.

### Current decision

The previously identified **static migration blockers have been addressed in the review-only SQL drafts**. This is not yet a runtime validation: the isolated test schema has not been changed, neither migration has been applied, and the SQL has not been executed against a scratch database. Therefore the package is **READY FOR THE NEXT REVIEW GATE, NOT CLEARED FOR APPLICATION**.

Before any isolated-test application, perform a final file-to-file dependency/order and SQL syntax review, then obtain explicit approval to apply both drafts together to `gqnidjifiobhqhnxjlow`. Run the post-apply RPC, RLS, trigger, grant and negative-access tests before treating the Operations workspace as verified. Production remains untouched.
