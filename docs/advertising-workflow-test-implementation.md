# FrostTech Advertising Workflow — Isolated Test Implementation

Date: 26 November 2026  
Environment: `gqnidjifiobhqhnxjlow` / `command-center-shell-stage1`  
Production environment was not modified.

## Implemented database stages

1. `isolated_advertising_workflow_foundation_test`
   - Advertiser, document, campaign submission, package, order, order-item, payment, terms acceptance and enquiry tables.
   - Owner-only read policies, public active-package read, advertiser campaign read paths.
   - Permission-gated campaign review function.
2. `isolated_advertiser_review_and_private_documents_test`
   - Advertiser registration and document registration functions.
   - CAC/document review, advertiser approval/rejection and pending-document removal functions.
   - CAC approval guard.
   - Private `advertiser-documents` Storage bucket with owner upload/read and authorised reviewer read.
3. `isolated_advertising_admin_read_access_test`
   - Permission-gated read paths for advertiser, document, campaign, order and order-item review queues.
4. `seed_existing_advertising_packages_test`
   - Nine approved FrostTech test packages: ₦10,000, ₦15,000, ₦18,000, ₦25,000, ₦27,000, ₦32,000, ₦45,000, ₦48,000 and ₦80,000.
5. `fix_advertising_review_audit_target_test`
   - Corrects the campaign decision audit target to the advertiser's linked Auth user, rather than the advertiser table's own UUID.

## Edge Functions deployed to test only

- `review-advertisement-test` — authenticated, requires `advertisements.review`, calls the transactional review RPC.
- `create-advertising-order` — creates a Development/Test order for an approved advertiser and records terms acceptance.
- `initialize-advertising-payment-test` — dedicated Test Mode Paystack initialization.
- `verify-advertising-payment` — validates the exact Test Mode reference, amount, currency and order before marking paid.
- `advertising-test-preflight` — checks the dedicated Test Mode secret and test preview callback URL.

All functions require JWT verification. No production Edge Function was replaced.

## Test frontend pages

- `advertiser-login-test.html`
- `advertiser-reset-password-test.html`
- `advertiser-portal-test.html`
- `advertising-campaigns-test.html`
- `advertising-terms-test.html`
- `advertisers-communications-test.html`

The department command center now links the Advertisers & Communications administrator to the test review workspace.

## Authority boundaries

- Advertiser approval requires CAC registration number and an accepted CAC certificate.
- Document review and advertiser review require their respective permissions.
- Campaign review requires a verified successful Development/Test payment and a paid Development/Test order.
- Campaign approval activates the item and starts the paid duration.
- Campaign rejection records a reason and does not automatically refund.
- Advertisers & Communications cannot change package prices, payment records, payment status, or production campaign records.
- Public advertisement feed remains production-only; test campaigns are not made publicly live by this implementation.
- Private advertiser documents remain private; the reviewer receives only a short-lived signed link.

## Verification still required

- Confirm Test Mode environment secret and callback readiness through the advertiser test preflight while signed in as an approved test advertiser.
- Run an end-to-end test using an explicitly designated test advertiser account and Paystack test credentials.
- Verify the four roles with real test identities: advertiser, Advertisers & Communications administrator, unrelated department administrator and Super Administrator.
- Confirm audit log rows, document access boundaries, paid campaign rejection, successful approval and expiry behavior.
- Test email/notification delivery separately; no notification sender was deployed in this stage.

## Change boundary

This stage did not replace legacy RLS policies in production, alter production package pricing, change production payment configuration, or deploy any test Edge Function to production. Existing test advertiser and document records were preserved.

## Verification snapshot

- Nine active package rows are present at the nine approved prices.
- All nine advertising tables have RLS enabled.
- Advertiser and reviewer functions are SECURITY DEFINER with an empty search path; anonymous execution is revoked and authenticated execution is granted.
- The private advertiser document bucket is confirmed private, limited to 10 MB PDF/JPEG/PNG uploads.
- Super Administrator permission simulation: advertiser and campaign review permissions allowed.
- Operations Administrator permission simulation: advertiser and campaign review permissions denied.
- Test project currently has zero advertiser, document, campaign, order and payment rows; no real payment or approval test has been fabricated.
- Five test Edge Functions are active with JWT verification enabled.
- The preflight function is configured to expect the test preview callback path, not the production site.

## Payment and email notification readiness — 26 November 2026

### Payment
- The advertiser checkout page calls the test-only order, Paystack initialisation and Paystack verification functions.
- Initialisation requires `PAYSTACK_TEST_SECRET_KEY` and `ADVERTISING_PAYSTACK_CALLBACK_URL`; there is no production-key fallback.
- The preflight validates that the callback is HTTPS and points specifically to `/frosttech-test-preview/advertising-campaigns-test.html`.
- The verification function checks the exact reference, successful Paystack status, NGN currency, amount equality, advertiser ownership and Development/Test environment before marking an order paid.
- Payment verification does not publish a campaign.

### Notifications
- Added `advertising_notifications_test`, a private queue table with deduplication, status, provider ID, error tracking and a five-attempt ceiling.
- Database triggers enqueue email notifications after advertiser approval/rejection, successful verified advertising payment, and campaign approval/rejection.
- Added `dispatch-advertising-notification-test` (JWT required), restricted to the isolated test project and authorised Advertisers & Communications/Super Administrator permissions.
- Added `admin_list_advertising_notifications_test_v1()` and an Email Notifications tab in the departmental review workspace. Dispatch and retries are explicit administrator actions; a queued notification is not represented as delivered.
- The queue table has RLS enabled, no client table grants and no direct client policies. The administrator reads it through the permission-checking RPC.
- Revoked anonymous and authenticated EXECUTE from the CAC approval trigger function; its only purpose is to run as a trigger.

### Configuration boundary
- The code checks for the dedicated Paystack and Brevo configuration at runtime without returning secret values.
- The connected project tools do not expose Edge Function secret values or a secret-management action in this workflow. Therefore the presence and correctness of `PAYSTACK_TEST_SECRET_KEY`, `ADVERTISING_PAYSTACK_CALLBACK_URL`, `BREVO_API_KEY` and `EMAIL_FROM` have not been independently confirmed here.
- The workflow is implementation-ready but must report `not ready` until those runtime checks pass. No real charge or customer email is claimed.

## Next legacy-policy work — dependency order

Migration 00 and Migration 01 are already present in the isolated test database and were re-verified on 26 November:
- role constraints include `advertisers_admin` and `advertisers_communications`;
- protected `admin_get_my_role()` and `admin_appoint_departmental_admin(uuid,text)` are SECURITY DEFINER with an empty search path, authenticated-only execution, and no anonymous execution;
- the Advertisers & Communications permission rows exist.

The next legacy-policy stage is the Operations & Customer quotation/order boundary. The current test inventory includes the legacy `admin_quotation_items_admin_manage` policy using `is_admin()`, a Super-Admin-only `Admins manage direct quotations` policy, customer-owned read policies, and permission-guarded operational quotation RPCs. The child and parent quotation policies must be assessed together; do not grant Operations direct item writes in isolation. Preserve customer-owned reads, immutable issued quotation snapshots, and Finance's separate financial-read boundary. The policy replacement migration will be prepared only after the current quotation-page and Edge Function callers are reconciled.
