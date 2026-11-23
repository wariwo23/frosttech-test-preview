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
