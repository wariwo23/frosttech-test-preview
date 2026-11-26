-- Supplier & Catalogue security rollback candidate. NOT APPLIED.
-- Keeps final supplier selection Super Admin-only and never restores cost access
-- to the departmental operational reader. A full rollback to previous insecure
-- supplier role behaviour is intentionally not provided.
begin;
drop function if exists public.admin_list_supplier_quotes_operational();
commit;
