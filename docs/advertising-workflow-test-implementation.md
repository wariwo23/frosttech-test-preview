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
