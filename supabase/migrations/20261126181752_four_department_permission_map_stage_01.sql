insert into public.admin_role_permissions(role,permission) values
('advertisers_admin','advertisers.manage'),
('advertisers_admin','advertiser_documents.review'),
('advertisers_admin','advertisements.review'),
('advertisers_admin','communications.manage'),
('advertisers_admin','notifications.manage')
on conflict (role,permission) do nothing;