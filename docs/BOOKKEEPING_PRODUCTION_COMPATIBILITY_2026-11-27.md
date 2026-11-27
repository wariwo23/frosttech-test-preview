# Bookkeeping Production Compatibility Findings
Date: 27 November 2026
Compared environments:
- Test: `gqnidjifiobhqhnxjlow`
- Production: `nftxptjpgidcsgtaltjn`
Status: read-only comparison; no production writes.

## Production object presence

The 12 `ft_bookkeeping_*` tables recovered in the test environment are not present in production. The production query returned no matching bookkeeping table names. Therefore this is a new schema integration into production, not an in-place table upgrade. Existing production finance/tax tables and settings must remain untouched.

## Authorization helper comparison

Production definitions were inspected for:
- `is_super_admin()`
- `admin_has_permission(text)`
- `admin_get_my_role()`

All three are SECURITY DEFINER, STABLE, and set an empty search_path. Their production definitions use the production `admin_accounts`, `profiles`, and `admin_role_permissions` tables.

Critical difference:
- Test `admin_get_my_role()` has an additional fallback to `isolated_test_admin_grants`.
- Test `admin_has_permission(text)` has an additional permission branch via `isolated_test_admin_grants`.
- Production helpers do not contain this test-only branch.
- Production `admin_get_my_role()` already recognizes the consolidated `supplier_catalogue_admin` role as well as legacy roles. The test version inspected here does not include that consolidated role in its main role allowlist.
- Do not copy test helper definitions into production. Preserve the existing production definitions and use production role/permission tables only.

## Production bookkeeping permission rows

Production already contains these role-permission mappings:
- finance_admin: `bookkeeping.read`
- finance_admin: `bookkeeping.prepare`
- finance_admin: `bookkeeping.documents.manage`
- finance_admin: `bookkeeping.reports.read`

No new production permission insert is required for these four keys unless a later caller audit reveals a missing key. The bookkeeping page inspected in test uses the first two permissions and Super Admin bypass; it does not currently check `bookkeeping.reports.read` or `bookkeeping.documents.manage` before showing the relevant page controls. That UI/permission mismatch should be corrected as part of compatibility patching, not by broadening the role grants.

## Production Super Admin boundary

Production `is_super_admin()` checks an active Super Admin account and active profile. Production `admin_has_permission(text)` grants Super Admin bypass and otherwise uses the role-permission table. This is consistent with the intended production authority model. No changes to these helpers are proposed.

## Release implications

1. Add the bookkeeping schema as a new, separately ordered production migration after role/permission and helper-function reconciliation.
2. Do not create/replace the existing production helper functions.
3. Do not create or depend on `isolated_test_admin_grants` in production.
4. Keep Finance Admin preparation/read permissions as currently configured; Super Admin alone retains approval, posting, account/period/loan administration.
5. Use a production-specific minimal grant set; never reproduce test's authenticated ALL table grants.
6. The production migration should create the schema and required indexes/constraints/triggers/policies but should not import test financial records automatically.
7. Existing production tax settings, tax objects, payment records, supplier settlements and other finance workflows are outside the scope of this bookkeeping schema creation and must remain unchanged.

## Status

This comparison is evidence for the production migration design. It does not constitute approval to apply the migration or modify production.
