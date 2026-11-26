# Supplier & Catalogue security audit — 26 November 2026

## Scope and safety

Read-only comparison of the isolated test database and production database. No database changes were made in this audit.

## Confirmed critical findings

### 1. Product supplier cost is directly selectable

Both test and production have `products.supplier_cost`. Both databases currently grant column SELECT on this field to `anon` and `authenticated`. The products table also has public SELECT policies for active products. Therefore active product rows can expose supplier cost through direct Data API queries. RLS filters rows; it does not hide individual columns.

Both databases also retain broad table grants on `products`, including anon/authenticated INSERT, UPDATE, DELETE and TRUNCATE. TRUNCATE is not protected by RLS. This is part of the separately prepared broad-grant security correction and must be handled in a dependency-aware package, not ignored.

### 2. Supplier quotation reader returns financial cost fields in test

Test `admin_list_supplier_quotes()` returns `supplier_unit_price`, `supplier_total`, and `delivery_cost` in its result signature and body. It is SECURITY DEFINER and checks `supplier_quotes.manage`. Test Supplier role currently lacks that permission, but Super Admin can bypass the permission function.

Production `admin_list_supplier_quotes()` has a different return contract (`SETOF supplier_quotes`) and checks `supplier_quotes.manage`. Production Supplier role currently has that permission. Because the function is SECURITY DEFINER and returns the full table row, this is a potential supplier-cost disclosure path to Supplier Admin; it must be tested under a real Supplier Admin JWT, not assumed safe from the table's RLS policy.

Production `admin_select_supplier_quote()` and `admin_reject_supplier_quote()` also authorize through `supplier_quotes.manage`. The selection function must be reviewed against the governance rule that final cost-based supplier selection belongs only to Super Admin. Do not assume its name alone defines whether it is final supplier selection; inspect its exact writes and downstream triggers.

### 3. Super Admin-only supplier cost functions in production

Production has dedicated functions:
- `admin_list_product_supplier_costs(uuid)`
- `admin_save_product_supplier_cost(uuid,uuid,numeric)`
- `admin_select_product_supplier(uuid,uuid)`

They explicitly require Super Admin and are separate from catalogue editing. Preserve this boundary.

### 4. Catalogue operational functions

Production has permission-gated catalogue functions for:
- product listing and creation;
- product details;
- selling-price updates;
- stock updates;
- activation/deactivation.

The normal listing function returns a JSON projection and does not contain `supplier_cost`. However, `catalogue_create_product` references supplier cost internally; inspect its exact signature/body and ensure the catalogue role cannot set or retrieve a hidden cost through its parameters or result.

### 5. Role permission drift

Test Supplier role has application read/review/verification permissions but does not have `supplier_quotes.manage`. Production Supplier role does have `supplier_quotes.manage`. Test and production Catalogue role currently have the same four catalogue permissions: `catalogue.manage`, `products.manage`, `selling_prices.manage`, `stock.manage`.

Do not simply copy the test mapping or production mapping. The consolidated Supplier & Catalogue department needs separate capability flags inside the role or carefully scoped permissions so that supplier application review and non-financial catalogue operations do not inherit financial supplier-cost access.

## Required corrections before release

1. Remove direct Data API access to `products.supplier_cost` for anon and authenticated. Because table-level grants override the practical protection expected from a column-level revoke, first inventory every frontend/RPC dependency, then replace broad table grants with explicit safe-column grants or move private costs into a dedicated Super-Admin-only table/view.
2. Reconcile product supplier cost duplication between `products.supplier_cost` and `product_supplier_costs.supplier_cost`. Identify canonical storage and triggers before retiring either field.
3. Replace or split `admin_list_supplier_quotes()` with a safe non-financial operational projection for departmental review, and retain a distinct Super-Admin-only cost view.
4. Restrict final cost-based supplier selection and supplier-cost maintenance to Super Admin. Review `admin_select_supplier_quote()` separately from product supplier assignment.
5. Verify supplier quote ownership policies still let each supplier see only its own submissions and do not expose competing suppliers' quotes.
6. Remove anon/authenticated broad INSERT/UPDATE/DELETE/TRUNCATE grants from products and other affected tables in the separately ordered grant-hardening package, after checking all frontend direct writes and service-role workflows.
7. Verify Storage supplier application documents and decision records remain private and appropriately permission-gated.

## Release status

**Not approved for production integration yet.** Supplier-cost exposure is a release blocker. No changes were made to either database. The findings are recorded for the master production integration register.
