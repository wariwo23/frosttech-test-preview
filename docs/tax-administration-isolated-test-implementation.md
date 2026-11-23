# FrostTech Tax Administration — isolated test implementation report

Date: 23 November 2026  
Environment: `gqnidjifiobhqhnxjlow` / `frosttech-test-preview` only  
Branch: `command-center-shell-stage1`

## Scope completed

Implemented the approved Tax Administration corrections in the isolated test environment. Production code, production database, production tax settings, payment provider settings, and live records were not changed.

### Database migrations applied

- `tax_administration_integrity_hardening` — migration version `20261123142843`
- `tax_assessment_source_dedup_guard` — migration version `20261123142927`
- `tax_assessment_concurrency_guard` — migration version `20261123143050`
- `tax_settlement_net_basis_grossup` — migration version `20261123143142`

### 1. WHT settlement calculation

- Settlement preparation now matches WHT rules against tax classification, supplier entity type, and residency status.
- Exact entity/residency matches take priority over `any` fallback rules.
- Gross/taxable-base basis: WHT is deducted from the verified supplier item total.
- Net-amount basis: supplier item total is treated as the required net payment; WHT is grossed up as `net × rate / (100 − rate)`, gross entitlement becomes net plus WHT, and net payable remains the supplier item total.
- Net-basis rates of 100% or higher are rejected.
- Settlement submission and Super Admin approval independently revalidate line totals and the matching WHT formula.
- Existing separate-person preparation/submission and Super Admin approval controls remain in place.
- The tax rule snapshot records the classification, entity, residency, calculation basis, legal reference, and effective period.

### 2. Supplier profile and tax-rule matching

- Tax rules now include `entity_type` and `residency_status`, each with explicit `any` scope.
- The overlap guard includes both new dimensions and is attached to updates of those columns.
- The existing supplier profile verification and separation-of-duties controls are preserved.
- Supplier tax identifiers are masked in the new workspace list and remain redacted in the financial audit snapshot.

### 3. VAT settings security and consistency

- Direct API table grants to `anon` and `authenticated` were revoked for `frosttech_tax_settings`.
- Super Admin-only read and update RPCs were added.
- VAT enablement requires a rate, mode, and effective timestamp.
- VAT disablement requires a null rate/effective timestamp and `not_configured` mode.
- VAT rule activation and VAT assessments must agree with the enabled settings and effective date.
- No VAT rate was entered or activated.

### 4. Assessment source validation

- Assessment creation accepts only a verified paid order or successful payment record.
- Unsupported source types are rejected; supplier settlements continue through their dedicated settlement/remittance linkage.
- The requested tax base cannot exceed the verified source amount.
- A database trigger prevents the same underlying order being assessed once through an order record and again through one of its successful payment records.
- An advisory transaction lock serializes this cross-source duplicate check.

### 5. Tax Administration workspaces

Created `tax-admin-test.html` and connected all three Command Center entries:
- Tax Rules & Rates
- Assessments & Remittances
- Supplier Profiles & Certificates

The workspace includes permission-gated forms and lists for rule creation/activation/deactivation, VAT settings, tax assessments and reconciliation, remittance evidence upload and independent verification, supplier profile submission/verification, and certificate upload/recording. Tax documents are uploaded to the existing private `frosttech-tax-documents` bucket. Super Admin settings and rule controls are not exposed to Finance Admin.

## Verification completed

- All four migrations appear in the test database migration history.
- RLS remains enabled on all seven tax-related tables checked.
- Direct `anon` and `authenticated` table grants for `frosttech_tax_settings` are absent.
- Finance Admin retains the existing seven tax permissions; no permissions were removed.
- Test account inventory remains one active Super Admin and one active Operations Admin. No Finance Admin account was created.
- Tax rule, assessment, remittance, supplier tax profile, certificate, and tax audit tables remain empty.
- VAT settings remain disabled, with no configured rate and no effective date.
- Settlement basis constraint now accepts `taxable_base`, `gross_amount`, and `net_amount`.
- The assessment cross-source guard is attached to the assessment table.
- RPC execution grants deny `anon`; authenticated execution remains protected by each function's internal role/permission checks.
- A numeric formula check was run as a calculation check only; it did not create or modify financial records.

## Not performed

- No tax rates or legal references were configured or activated.
- No Finance Admin account was created, appointed, or invited.
- No supplier profiles, assessments, settlements, remittances, certificates, or audit business records were created.
- No emails, payment instructions, supplier transfers, or production actions were triggered.
- No production merge or deployment was performed.

## Remaining validation before production consideration

1. Sign in as an independently authorised Finance Admin in the isolated test environment and test only permitted Finance actions.
2. Verify that the Finance Admin cannot access Super Admin VAT settings or activate/deactivate tax rules.
3. Exercise supplier tax profile submit/verify with two distinct test identities, without using real supplier tax identifiers.
4. Run controlled test fixtures for gross-basis and net-basis settlement calculations, including submit and Super Admin approval; then roll back or clean up only those expressly created fixtures.
5. Exercise source validation, duplicate order/payment prevention, remittance evidence, separate-person remittance verification, and certificate lifecycle using isolated test fixtures.
6. Review tax treatment and legal references against current Nigerian tax advice before any rate is configured or activated.

## Safety note

The user-suggested 7.5% is not a universal WHT setting. No default rate is assumed. Actual treatment depends on the transaction and supplier characteristics and must be supported by a current legal basis and Super Admin approval.
