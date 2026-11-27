# FrostTech Finance workspace integration — isolated test

**Environment:** isolated test project only  
**Repository:** `wariwo23/frosttech-test-preview`  
**Branch:** `command-center-shell-stage1`  
**Test Supabase ref:** `gqnidjifiobhqhnxjlow`  
**Date:** 2026-11-23

## Changes completed

1. Added `finance-admin-test.html`, adapted from the existing production Finance page.
   - Loads `supabase-test.js` and the isolated test publishable key only.
   - Contains no production project URL or production publishable key.
   - Retains the existing Finance sign-in, role check, reporting period, reconciliation summary, payment list, quotation review, own cost submissions, direct-quotation ledger, cost-submission form, branded confirmation modal, and password reset flow.
   - Password reset returns to the isolated test admin login page.
   - Logout returns to the isolated test admin login page.
   - Super Admin preview remains read-only; Finance Admin cost submission is available only after the backend permission check.
   - No cost approval/rejection button has been added; approval remains Super Admin-only and is not performed from the Finance page.

2. Connected the Command Center Finance & Payments entries:
   - Financial Reporting now checks `financial_reports.read`.
   - Payments & Reconciliation now checks `payments.read`.
   - Both authorised entries open `finance-admin-test.html`.
   - Existing Supplier Settlement and Tax entries retain their separate permissions and routes.
   - Super Admin remains able to preview the Finance workspace.

## Static integration checks

Passed:
- Test Finance page loads `supabase-test.js`.
- No production project ref or production publishable key appears in the test page.
- Finance and Payments navigation entries use the expected permission names.
- Both navigation entries point to the isolated Finance page.
- Password reset and logout return to test login, not production pages.
- Expected Finance RPC names are present in the page.

## Database checks

Previously verified after the isolated Finance migration:
- Finance summary, payment list, quotation list, own cost-submission list and quotation-costing list RPCs exist and return the expected JSON container types for Super Admin.
- Direct quotation activity RPC exists and returned a JSON array for Super Admin.
- Operations Admin lacks Finance report, payment-read and cost-submission permissions.
- Operations Admin calls to Finance reporting, cost submission and cost review were rejected by server-side permission checks.
- Cost submissions, snapshots and approval audit are protected by their intended RLS policies.
- Cost snapshot and approval audit immutability triggers and cost self-approval guard are enabled.
- No test Finance Admin account is currently active, so its positive-path login and data access remain untested.

## Security advisor review

The isolated test project's security advisor currently reports:
- 21 RLS-enabled tables without policies. Several are intentionally RPC-only/private operational tables and must be reviewed individually; no blanket policies were added.
- 56 authenticated-callable SECURITY DEFINER functions. The Finance RPCs exposed to authenticated users perform explicit permission checks, and private cost implementation helpers remain in the private schema. The warning is not itself proof of an exploitable flaw; review each function's auth checks, grants and search_path before wider rollout.
- Leaked-password protection remains disabled in the isolated test project's Auth settings. No Auth setting was changed.

## Not done

- No Finance Admin account created or appointed.
- No invitation sent.
- No real cost submission, approval, rejection, payment, receipt, settlement or customer record created or changed.
- No manual payment-verification action added.
- No production code, database, Auth settings or deployment changed.
- No claim of browser end-to-end testing: the page and navigation were statically verified and backend RPC/permission behavior was tested through database calls.

## Next test step

Open the isolated Command Center as the existing Super Admin test account and launch Financial Reporting or Payments & Reconciliation. Confirm the sign-in page, read-only Super Admin preview, reporting panels and refresh behavior in a browser. A separate active Finance Admin test identity is required before positive Finance Admin access and cost-submission UI can be exercised.
