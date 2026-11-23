# Supplier Disbursement Evidence Hardening — Isolated Test Results

Date: 23 November 2026
Environment: Isolated FrostTech test Supabase project only
Project ref: gqnidjifiobhqhnxjlow
Status: Backend migration applied; static security checks passed; end-to-end upload/verification test remains pending.

## Applied changes
- Created private bucket `supplier-disbursement-evidence`.
- Maximum object size: 10 MB.
- Allowed MIME types: PDF, JPEG, PNG.
- Added authenticated INSERT policy requiring `supplier_settlements.execute`, a UUID settlement folder, and uploader UID as the second path segment.
- Added authenticated SELECT policy requiring `supplier_settlements.execute`.
- Did not add authenticated UPDATE or DELETE policies.
- Replaced `frosttech_record_supplier_disbursement` so manual-transfer evidence must already exist in the dedicated bucket, belong to the initiating user, match the settlement path, be within size/MIME constraints, and not already be attached to another disbursement.
- Replaced `frosttech_verify_manual_supplier_disbursement` so it rechecks the same evidence object and ownership before accepting a verification decision.
- Preserved existing function EXECUTE grants; anon execution remains false and authenticated execution remains true, subject to the functions' internal permission checks.
- Preserved SECURITY DEFINER and empty search_path on both functions.

## Checks completed
- Bucket exists and is private.
- Bucket size/MIME restrictions match the intended configuration.
- Storage INSERT and SELECT policies exist for the dedicated bucket.
- Path parser returns settlement UUID and uploader UID folders as expected.
- Both RPCs remain SECURITY DEFINER with empty search_path.
- Anon cannot execute either RPC; authenticated can invoke them subject to internal permission checks.
- No evidence objects were uploaded.
- No supplier disbursement rows were created.
- No supplier settlement rows were changed.

## Outstanding end-to-end checks
The current test Finance workspace has no supplier-disbursement evidence uploader or disbursement execution UI. Therefore the following have not been exercised through an authenticated Finance session:
1. Upload a permitted PDF/JPG/PNG to the required path.
2. Confirm an unauthorised role cannot upload or read.
3. Confirm a Finance user cannot upload under another user's folder.
4. Confirm a wrong-settlement path, missing object, wrong owner, unsupported MIME type, oversized file, and reused evidence path are rejected by the recording RPC.
5. Confirm the verifier can read and verify another user's evidence but cannot verify their own transfer.
6. Confirm deletion/replacement of evidence is not available to authenticated users.

No production changes or deployments were made. Do not merge or deploy this work to production until the upload workflow is implemented and the outstanding tests pass.
