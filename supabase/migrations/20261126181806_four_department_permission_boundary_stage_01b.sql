delete from public.admin_role_permissions
where (role='supplier_admin' and permission='supplier_quotes.manage')
   or (role='finance_admin' and permission='supplier_settlements.execute');