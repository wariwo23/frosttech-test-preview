-- FrostTech isolated-test only: additive departmental permission reconciliation.
-- Production project nftxptjpgidcsgtaltjn is explicitly excluded.
-- Preserve all existing tax, settlement, legacy supplier and Operations permissions.
-- No accounts, roles, employee records, or existing permission rows are removed or changed.

insert into public.admin_role_permissions (role, permission)
values
  ('supplier_admin', 'supplier_applications.manage'),
  ('supplier_admin', 'supplier_verification.manage'),
  ('supplier_admin', 'supplier_quotes.manage'),
  ('finance_admin', 'financial_reports.read'),
  ('finance_admin', 'orders.read_financial'),
  ('finance_admin', 'payments.read'),
  ('finance_admin', 'payments.verify'),
  ('finance_admin', 'quotations.read_financial'),
  ('finance_admin', 'quotations.costs.submit'),
  ('catalogue_admin', 'catalogue.manage'),
  ('catalogue_admin', 'products.manage'),
  ('catalogue_admin', 'selling_prices.manage'),
  ('catalogue_admin', 'stock.manage')
on conflict (role, permission) do nothing;
