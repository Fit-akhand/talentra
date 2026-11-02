# Talentra — Exception Catalogue

**Phase:** 1 — Discover, Step 5
**Status:** **Reconciled against the docket** on 2026-10-23 ([`01-docket-reconciliation.md`](01-docket-reconciliation.md)); originally written before the docket was available. Exceptions are derived from the implemented schema; several enforcement gaps listed here were closed by migrations 020-034. Entries that changed carry an **Update 2026-10-28** note; the original text is kept so the reason for the change stays visible.
**Authored:** 2026-10-21

---

## 1. Purpose and method

An exception catalogue answers one question: **when a business rule is violated, what happens, and does the
caller find out?** This document enumerates every failure path in the implemented system.

**Derivation.** Every exception below was read out of the schema — a CHECK constraint, a UNIQUE constraint, a
FOREIGN KEY, an EXCLUDE constraint, a trigger's `RAISE EXCEPTION`, a function's NULL return, or a documented
gap where the schema defines no behaviour at all. Nothing is inferred from intent.

**Classification.** Each exception carries a severity and an enforcement layer:

| Enforcement layer | Meaning | Caller visibility |
|:--|:--|:--|
| **DB-rejected** | The database raises an error; the transaction fails and rolls back | The error surfaces to the caller as a DB error |
| **DB-nulled** | A function returns NULL instead of raising | The caller **must** check for NULL — a silent failure if it does not |
| **DB-rejected-conditional** | A trigger raises only under a specific predicate | The error surfaces only on that predicate |
| **App-unhandled** | The schema defines no behaviour; the failure is not handled anywhere | Silent — the failure is invisible |
| **Documented-only** | A failure mode is described in a dossier but no mechanism enforces or handles it | Depends on code that does not exist |

**Severity**

| Severity | Meaning |
|:--|:--|
| **Critical** | Data loss, data corruption, financial error, or a silent security failure |
| **High** | A business rule is bypassable, or a legitimate operation fails with no recourse |
| **Medium** | A rule is enforced but the failure is confusing, or a recovery path is missing |
| **Low** | A cosmetic or low-impact failure |

**The 12 attributes** (mandated for every entry):

1. Exception ID
2. Name
3. Description
4. Trigger condition
5. Affected workflow
6. Detection mechanism
7. Handling behaviour
8. Severity
9. Enforcement layer
10. Recovery path
11. Audit event
12. Data impact

---

## 2. Exception catalogue

### 2.1 Identity, access and session

| # | Attribute | EXC-01 | EXC-02 | EXC-03 | EXC-04 |
|:--|:--|:--|:--|:--|:--|
| 1 | **ID** | EXC-01 | EXC-02 | EXC-03 | EXC-04 |
| 2 | **Name** | Duplicate email registration | Device limit exceeded | Account not active | Credential hash format violation |
| 3 | **Description** | A registration attempts to create a `core.user_account` with an email that already exists | A login is attempted from a device beyond the user's concurrent-device entitlement | Authentication is attempted against an account in `pending`, `suspended` or `deactivated` status | A stored password hash does not match the approved algorithm format |
| 4 | **Trigger condition** | `INSERT INTO core.user_account` with a colliding email | `core.create_session_with_device_limit` counts live sessions ≥ the entitlement | `core.user_account.account_status` ∉ {`active`} | `core.user_credential.secret_hash` does not match `^\$(argon2id\|2b\|2a)\$` |
| 5 | **Affected workflow** | WF-01 | WF-01, WF-09 | WF-01, WF-10 | WF-01 |
| 6 | **Detection mechanism** | `UNIQUE` violation on `uq_user_account_email` at insert | Function returns NULL; the trigger-free path also writes a `device.limit_exceeded` audit event | Function returns NULL | `scripts/validate_data.py:210-215` (RG6 check) — **runtime only** |
| 7 | **Handling behaviour** | Transaction fails; the caller must re-read the email and offer sign-in instead | Function returns NULL rather than raising — **the caller must test for NULL** | Function returns NULL | Validator reports FAIL; the row is not blocked at write time |
| 8 | **Severity** | Low | Medium | Medium | **High** |
| 9 | **Enforcement layer** | DB-rejected | **DB-nulled** | **DB-nulled** | **App-unhandled** (no DDL constraint) |
| 10 | **Recovery path** | Prompt for sign-in | The user frees a device or the entitlement is raised | Administrative reactivation via `account_status` | Re-hash the credential; the source of the bad hash is outside this schema |
| 11 | **Audit event** | None | `device.limit_exceeded` (`db/migrations/015:221`) — **one of only two audit write sites in the system** | None | None |
| 12 | **Data impact** | None — the insert is rejected | No session row created; no data change | No session row created | A weak hash persists in the database until the validator catches it |

| # | Attribute | EXC-30 | EXC-31 |
|:--|:--|:--|:--|
| 1 | **ID** | EXC-30 | EXC-31 |
| 2 | **Name** | Session not found | Unauthorised session revocation |
| 3 | **Description** | `core.revoke_user_session` is called with an id that does not exist | A user revokes a session belonging to another user |
| 4 | **Trigger condition** | The target `core.user_session.id` is absent | The revoker is not the session owner and holds no admin role |
| 5 | **Affected workflow** | WF-10 | WF-10 |
| 6 | **Detection mechanism** | The function's internal lookup finds no row | **No ownership check exists in the schema** — the caller must verify |
| 7 | **Handling behaviour** | The function's behaviour depends on its internal guard (no-op or NULL) | **Unguarded** — a caller with a session id can revoke any session |
| 8 | **Severity** | Low | **High** |
| 9 | **Enforcement layer** | DB-nulled or no-op | **App-unhandled** |
| 10 | **Recovery path** | Verify the id before calling | Enforce ownership in the calling code, or add a check to the function |
| 11 | **Audit event** | None | `session.revoked` is written regardless of who revoked it — **the event records the revoker, so the wrong actor is visible after the fact** |
| 12 | **Data impact** | None | A live session of another user is terminated; the event trail names the wrong actor |

### 2.2 Candidate profile and documents

| # | Attribute | EXC-05 | EXC-06 | EXC-07 |
|:--|:--|:--|:--|:--|
| 1 | **ID** | EXC-05 | EXC-06 | EXC-07 |
| 2 | **Name** | Document rejected | Duplicate primary resume | Inverted date range |
| 3 | **Description** | An uploaded document exceeds the size limit or carries an unsupported MIME type | A second resume is marked primary for the same candidate | A date range is inverted (`end_date < start_date`) |
| 4 | **Trigger condition** | `profile.candidate_document` MIME/size CHECK fails; or the SHA-256 checksum is absent | The partial unique index on primary documents finds an existing primary | `profile.candidate_work_experience`, `profile.candidate_education`, `gig.gig_worker_availability`, `gig.gig_assignment` date CHECKs fail |
| 5 | **Affected workflow** | WF-02 | WF-02 | WF-02, WF-07 |
| 6 | **Detection mechanism** | CHECK constraint violation | Unique index violation | CHECK constraint violation |
| 7 | **Handling behaviour** | Transaction fails; the upload is not stored | Transaction fails | Transaction fails |
| 8 | **Severity** | Low | Low | Low |
| 9 | **Enforcement layer** | DB-rejected | DB-rejected | DB-rejected |
| 10 | **Recovery path** | The candidate re-uploads a conforming file | The candidate demotes the existing primary first | The candidate corrects the dates |
| 11 | **Audit event** | None — document ingestion is described in `docs/phase-4-platform/22-integration-boundaries.md` §2 row 1 as audited, but **no audit write exists** | None | None |
| 12 | **Data impact** | None — the document is not stored | None | None |

### 2.3 Job posting and pipeline

| # | Attribute | EXC-08 | EXC-09 | EXC-10 | EXC-11 | EXC-15 | EXC-16 | EXC-17 |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | **ID** | EXC-08 | EXC-09 | EXC-10 | EXC-11 | EXC-15 | EXC-16 | EXC-17 |
| 2 | **Name** | Partial salary block | Cross-organisation job post | Duplicate questionnaire | Invalid job status transition | Invalid application transition | Same-stage update not recorded | Cross-organisation pipeline access |
| 3 | **Description** | A job posting populates some but not all of the salary, currency and period fields | A recruiter posts a job against an organisation they do not belong to | A second questionnaire is attached to one job | `job_status` is set to a value outside the permitted set, or an illogical transition is attempted | `application_status` is set outside the seven permitted values | An update sets `application_status` to its current value | A recruiter views or advances an application belonging to another organisation |
| 4 | **Trigger condition** | `ck_job_posting_salary_currency` fails | `job_posting.organization_id` ≠ the actor's organisation | The one-questionnaire constraint is violated | `ck_job_posting_status` fails, or the state machine is violated | `ck_candidate_application_status` fails | `NEW.application_status = OLD.application_status` | Application's job belongs to a different organisation |
| 5 | **Affected workflow** | WF-03 | WF-03 | WF-03 | WF-03 | WF-05 | WF-05 | WF-05 |
| 6 | **Detection mechanism** | CHECK constraint | **No detection** — no FK or constraint ties the poster to the organisation | Unique/CHECK constraint | CHECK constraint | CHECK constraint | The trigger's own `IS DISTINCT FROM` guard | **No detection at the database layer** |
| 7 | **Handling behaviour** | Transaction fails | **Unguarded** — the posting succeeds | Transaction fails | Transaction fails | Transaction fails | No history row is written; the update itself succeeds | **Unguarded** — access depends entirely on application code |
| 8 | **Severity** | Low | **High** | Low | Low | Low | Low | **Critical** |
| 9 | **Enforcement layer** | DB-rejected | **App-unhandled** | DB-rejected | DB-rejected | DB-rejected | DB-rejected (by design) | **App-unhandled** |
| 10 | **Recovery path** | Supply the complete salary block or clear all four fields | Delete or reassign the posting | Remove the duplicate questionnaire | Set a valid status | Set a valid stage | None needed — this is the intended behaviour | Implement RLS (`FEAT-020`) or enforce in the application layer |
| 11 | **Audit event** | None | None — **a cross-organisation posting leaves no trace** | None | None | None | None | None |
| 12 | **Data impact** | None | A job posting exists under an organisation the poster does not belong to — visible in that organisation's feeds and searches | None | None | None | None | **Cross-tenant data exposure**: candidate PII in the application is reachable |

> **EXC-17 is the most severe exception in this catalogue.** It is the concrete failure that the "Documented
> only" RLS feature (FEAT-020) would prevent, and it is the strongest argument for implementing FEAT-020 in
> Phase 2.

### 2.4 Discovery, applications and blocks

| # | Attribute | EXC-12 | EXC-13 | EXC-14 |
|:--|:--|:--|:--|:--|
| 1 | **ID** | EXC-12 | EXC-13 | EXC-14 |
| 2 | **Name** | Duplicate application | Blocked candidate | Private profile |
| 3 | **Description** | A candidate applies to a job they have already applied to | A recruiter searches for, or downloads, a candidate who has blocked them (or whose organisation they have blocked) | A candidate's profile is `private` and they appear in a recruiter's search |
| 4 | **Trigger condition** | A second `recruitment.candidate_application` for the same (candidate, job) | `core.user_block` matches the pair, or `core.is_candidate_visible_to` returns FALSE | `profile.candidate_profile.visibility = 'private'` |
| 5 | **Affected workflow** | WF-04 | WF-04, WF-14 | WF-04 |
| 6 | **Detection mechanism** | `uq_candidate_application_candidate_job` | `core.is_candidate_visible_to` returns FALSE | The search filter `visibility IN ('recruiters','public')` |
| 7 | **Handling behaviour** | Transaction fails | The function returns FALSE — **the caller must apply it** | The candidate is filtered out of the result set |
| 8 | **Severity** | Low | **High** | Low |
| 9 | **Enforcement layer** | DB-rejected | **DB-nulled** (function-scoped) | DB-rejected (filter-level, not constraint-level) |
| 10 | **Recovery path** | The candidate applies to a different job, or the employer withdraws the first application | The block is lifted by the candidate | The candidate sets visibility to `recruiters` or `public` |
| 11 | **Audit event** | None | None | None |
| 12 | **Data impact** | None | **PII exposure if the caller omits the check** — the function returns FALSE rather than raising, so a caller that ignores the return value proceeds | None — the candidate is excluded |

> **EXC-13 is a silent-failure risk by design.** The function-scoped nature of `core.is_candidate_visible_to`
> means a read path that does not call it exposes a candidate who has explicitly blocked the viewer. This is
> NFR-013's gap (**NG-17**).

### 2.5 Sourcing

| # | Attribute | EXC-18 | EXC-19 | EXC-20 |
|:--|:--|:--|:--|:--|
| 1 | **ID** | EXC-18 | EXC-19 | EXC-20 |
| 2 | **Name** | Submission to a closed job | Duplicate submission | Sourcing request not accepted |
| 3 | **Description** | A consultant submits a candidate to a job whose consultant-openness policy is closed | A consultant submits the same candidate to the same job twice | A consultant submits against a request that was never accepted, or that was revoked |
| 4 | **Trigger condition** | `trg_enforce_consultant_openness` finds the job closed to consultants | A unique constraint on (job, candidate, consultant) is violated | `consultant_sourcing_request.consultant_sourcing_request_status` ∉ {`accepted`} |
| 5 | **Affected workflow** | WF-06 | WF-06 | WF-06 |
| 6 | **Detection mechanism** | Trigger raises an exception | Unique constraint | **No detection** — the schema does not check the request state at submission time |
| 7 | **Handling behaviour** | Transaction fails with a raised exception | Transaction fails | **Unguarded** — the submission succeeds |
| 8 | **Severity** | Low | Low | **High** |
| 9 | **Enforcement layer** | **DB-rejected-conditional** | DB-rejected | **App-unhandled** |
| 10 | **Recovery path** | The employer reopens the job to consultants, or the consultant uses a permitted route | The consultant submits to a different job | Revoke or correct the submission; implement a check tying submissions to an accepted request |
| 11 | **Audit event** | None | None | None |
| 12 | **Data impact** | None | None | An unauthorised candidate submission enters the employer's pipeline, and the employer sees a candidate it never agreed to receive |

### 2.6 Gig marketplace

| # | Attribute | EXC-21 | EXC-22 | EXC-23 | EXC-24 |
|:--|:--|:--|:--|:--|:--|
| 1 | **ID** | EXC-21 | EXC-22 | EXC-23 | EXC-24 |
| 2 | **Name** | Overlapping assignment | Invalid gig request | Inconsistent application decision | Assignment termination |
| 3 | **Description** | A gig worker is assigned two active assignments whose date ranges overlap | A gig request has a non-positive budget, an invalid currency, an inverted date window or multiple pricing types | `decided_at` is set while the status is `submitted`, or is null while the status is accepted/rejected | An assignment is terminated before its end date |
| 4 | **Trigger condition** | The GiST exclusion `ex_gig_assignment_no_overlap` finds an overlapping `daterange` for the same worker | The `gig.gig_request` CHECK constraints fail | The `gig.gig_application` decided-at CHECK fails | `assignment_status` moves from `active` to `terminated` |
| 5 | **Affected workflow** | WF-07 | WF-07 | WF-07 | WF-07 |
| 6 | **Detection mechanism** | `ExclusionViolation` (SQLSTATE 23P01) raised at statement execution | CHECK constraint violation | CHECK constraint violation | The status change is accepted |
| 7 | **Handling behaviour** | Transaction fails; **the conflicting assignment is never created** | Transaction fails | Transaction fails | Accepted — the window is freed because the constraint applies only to `active` rows |
| 8 | **Severity** | Low (by design — the rule works) | Low | Low | Medium |
| 9 | **Enforcement layer** | **DB-rejected-conditional** | DB-rejected | DB-rejected | DB-rejected (accepted path) |
| 10 | **Recovery path** | The client books a non-overlapping window | The client corrects the request | The client corrects `decided_at` | The worker is free to take other work; the terminated assignment remains in the history |
| 11 | **Audit event** | None | None | None | None |
| 12 | **Data impact** | None — the database prevents double-booking with no race window | None | None | The gig revenue figure (`Q11`) changes; a terminated assignment is excluded from completed volume |

### 2.7 Organisation administration

| # | Attribute | EXC-25 | EXC-26 |
|:--|:--|:--|:--|
| 1 | **ID** | EXC-25 | EXC-26 |
| 2 | **Name** | Duplicate organisation slug | Invalid organisation identifier |
| 3 | **Description** | Two organisations attempt the same slug | An organisation identifier carries a type that is not permitted for its country, or duplicates an existing identifier of the same type |
| 4 | **Trigger condition** | `UNIQUE` violation on the organisation slug | A CHECK constraint or a unique constraint on the identifier type |
| 5 | **Affected workflow** | WF-08 | WF-08 |
| 6 | **Detection mechanism** | UNIQUE constraint | CHECK / UNIQUE constraint |
| 7 | **Handling behaviour** | Transaction fails | Transaction fails |
| 8 | **Severity** | Low | Low |
| 9 | **Enforcement layer** | DB-rejected | DB-rejected |
| 10 | **Recovery path** | Choose a different slug | Correct the identifier or its type |
| 11 | **Audit event** | None | None |
| 12 | **Data impact** | None | None |

### 2.8 Licensing, subscription and payments

| # | Attribute | EXC-27 | EXC-28 | EXC-29 |
|:--|:--|:--|:--|:--|
| 1 | **ID** | EXC-27 | EXC-28 | EXC-29 |
| 2 | **Name** | Seat allocation exceeds entitlement | Payment failure | Duplicate webhook / double credit |
| 3 | **Description** | A licence seat allocation would exceed `max_users` | The payment gateway declines, times out or errors | A retried or duplicated payment webhook is processed twice, crediting the wallet twice |
| 4 | **Trigger condition** | `trg_enforce_licence_max_users` finds active seats + 1 > `max_users` | `payment_order_status` → `failed` | A second webhook arrives for an already-recorded `gateway_order_id` |
| 5 | **Affected workflow** | WF-09 | WF-09 | WF-09, WF-14 |
| 6 | **Detection mechanism** | Trigger raises an exception | Status transition | **`commercial.wallet_ledger` has no idempotency key column**; uniqueness exists only on `gateway_order_id`, `invoice_number`, `gateway_refund_ref` and `wallet(org,currency)` |
| 7 | **Handling behaviour** | Transaction fails | The order is recorded as `failed`; no wallet credit occurs | **Double credit occurs** — unless the application checks `gateway_order_id` first, as `docs/phase-4-platform/22-integration-boundaries.md` §3.3 step 1 describes. That check is **application code that does not exist in this repository** |
| 8 | **Severity** | Low | Medium | **Critical** |
| 9 | **Enforcement layer** | **DB-rejected-conditional** | DB-recorded | **App-unhandled** |
| 10 | **Recovery path** | Buy a larger licence, or remove a seat | Retry the payment, or cancel | Append a **correction** ledger row (`correction_debit`) — the ledger is append-only, so the correction must be a new row, never an edit |
| 11 | **Audit event** | None | None | **None — no financial action is audited** |
| 12 | **Data impact** | None | The order is marked failed | **Financial**: the wallet balance exceeds the true amount paid. The append-only ledger means the error is visible in the history but the balance is wrong until a correction is appended |

> **Update 2026-10-28 (migration 029).** `commercial.payment_order.idempotency_key` now exists, unique per organisation when present, so a replayed webhook that carries the same key cannot create a second order. The ledger itself still has no key of its own; the guard sits on the order that precedes every credit. The inbound webhook handler remains application code outside this repository. Enforcement layer is now **DB-rejected for keyed requests, App-unhandled for unkeyed ones**.

> **EXC-29 is the clearest example of a contract that exists in prose but not in the schema.**
> `docs/phase-4-platform/22-integration-boundaries.md` §3.3 specifies a UUIDv4 idempotency key and a duplicate-suppression check,
> and the boundary table's "Idempotency Key" column names `gateway_transaction_id + idempotency_key (UUIDv4)`.
> **No `idempotency_key` column exists on any table**, and `commercial.wallet_ledger` has no natural key on
> the ledger entry. The contract is unimplementable as written.

### 2.9 Notifications and privacy

| # | Attribute | EXC-32 | EXC-33 |
|:--|:--|:--|:--|
| 1 | **ID** | EXC-32 | EXC-33 |
| 2 | **Name** | Delivery failure | Consent withdrawal not honoured |
| 3 | **Description** | The messaging provider bounces, rejects or times out on a dispatch | A user withdraws consent, but no path consumes the withdrawal to suppress delivery or trigger erasure |
| 4 | **Trigger condition** | The provider reports a bounce or an invalid destination | `core.consent_record` state changes to withdrawn |
| 5 | **Affected workflow** | WF-11 | WF-11 |
| 6 | **Detection mechanism** | `messaging.notification_delivery.delivery_status` → `failed` | The consent row's state — but nothing reads it for a suppression decision |
| 7 | **Handling behaviour** | The delivery is marked `failed`; the retry → DLQ path exists **only in the boundary diagram**, not in the schema | **Unguarded** — delivery continues |
| 8 | **Severity** | Medium | **High** |
| 9 | **Enforcement layer** | DB-recorded | **Documented-only** |
| 10 | **Recovery path** | Retry, then dead-letter — but the DLQ table does not exist | Implement a suppression check and a purge procedure (**OQ-011**) |
| 11 | **Audit event** | None — `docs/phase-4-platform/22-integration-boundaries.md` §2 row 6 says all outbound deliveries are logged, but **no audit write exists** | None |
| 12 | **Data impact** | A notification is undelivered | **Personal data is delivered and retained after consent was withdrawn** — the mechanism that would carry this is exactly what NFR-017 and NFR-018 lack |

> **Update 2026-10-28 (migration 031).** The dead-letter path now exists for integration exchanges: `messaging.integration_event` retries up to the boundary's limit with exponential backoff, then dead-letters, and `audit.ops_integration_health` shows the backlog. Provider bounces on `notification_delivery` are still recorded as `failed` only; routing them through the outbox is the sender's job. EXC-33 (consent withdrawal not honoured) is unchanged: `core.accounts_missing_consent()` finds accounts without consent, but nothing suppresses delivery after a withdrawal.

### 2.10 Platform operations

| # | Attribute | EXC-34 | EXC-35 | EXC-36 | EXC-37 |
|:--|:--|:--|:--|:--|:--|
| 1 | **ID** | EXC-34 | EXC-35 | EXC-36 | EXC-37 |
| 2 | **Name** | Migration failure | Validator check failure | RTO breach / parity failure | Partial mart refresh |
| 3 | **Description** | A migration fails to apply | One of the 15 validator checks reports FAIL | The backup/restore cycle exceeds 900 s, or the row-count parity check fails across the 7 compared tables | `analytics.refresh_reporting_marts` fails partway, leaving some marts refreshed and others stale |
| 4 | **Trigger condition** | Any error inside a migration's `BEGIN…COMMIT` block | A validator check returns a non-PASS status | The runbook's elapsed time exceeds the threshold, or a table's counts differ | An error occurs partway through the refresh procedure |
| 5 | **Affected workflow** | WF-12 | WF-12 | WF-12 | WF-13 |
| 6 | **Detection mechanism** | PostgreSQL raises; the transaction rolls back | The validator's per-check log | The runbook's own elapsed-time report and parity check | The procedure raises |
| 7 | **Handling behaviour** | The migration is rolled back; the database stays at the previous version | The result is reported; the data is left for correction | The restore is reported as not verified | The already-refreshed marts remain refreshed — **the refresh is not atomic across views** |
| 8 | **Severity** | **High** | Medium | **High** | Medium |
| 9 | **Enforcement layer** | DB-rejected | App-unhandled | App-unhandled | **App-unhandled** |
| 10 | **Recovery path** | Fix the migration and re-apply | Correct the data and re-run the validator | Investigate and re-run; treat the backup as unverified | Re-run the refresh; until then, the reporting layer is inconsistent |
| 11 | **Audit event** | None | None | None | None |
| 12 | **Data impact** | **Schema state diverges from the expected migration level** — the schema and the documentation may disagree | Invalid data persists in the database | The backup cannot be relied upon for recovery | **Reporting data is silently inconsistent** — no staleness marker exists, so a reader cannot tell fresh rows from stale ones |

### 2.11 Wallet, downloads and reconciliation

| # | Attribute | EXC-38 | EXC-39 | EXC-40 |
|:--|:--|:--|:--|:--|
| 1 | **ID** | EXC-38 | EXC-39 | EXC-40 |
| 2 | **Name** | Insufficient balance | Download of a blocked candidate | Ledger/balance divergence |
| 3 | **Description** | A debit is requested against a wallet whose balance cannot cover it | A recruiter downloads a profile of a candidate who has blocked them | `commercial.wallet.balance` does not equal the sum of the wallet's ledger entries |
| 4 | **Trigger condition** | The debit amount exceeds the balance | `core.is_candidate_visible_to` returns FALSE | Any divergence between the stored balance and the ledger sum |
| 5 | **Affected workflow** | WF-14 | WF-14 | WF-09, WF-14 |
| 6 | **Detection mechanism** | **No detection in the schema** — `wallet_ledger` has `balance_after >= 0` as a CHECK, but the balance check is the caller's | The visibility function returns FALSE — **only if the caller checks** | The validator's RG7 "Financial Balance Reconciliation" check |
| 7 | **Handling behaviour** | **Unguarded** — nothing enforces it at write time | **Unguarded** if the caller omits the check | The validator reports FAIL; the stored balance is not corrected |
| 8 | **Severity** | Medium | **High** | **Critical** |
| 9 | **Enforcement layer** | **App-unhandled** | **DB-nulled** (function-scoped) | **App-unhandled** (checked, not enforced) |
| 10 | **Recovery path** | The organisation recharges the wallet | The download must not proceed | Re-derive the balance from the ledger and append a correction row — the ledger is append-only, so the stored balance can be **updated** (it is not ledger data) but the history cannot |
| 11 | **Audit event** | None | None | None — **financial divergence is not audited** |
| 12 | **Data impact** | Negative balance, if unguarded | **Candidate PII disclosed to a party the candidate blocked, and no credit is consumed** | **Financial**: the organisation's spendable balance differs from its transaction history. NFR-012 measures this but the schema does not prevent it |

> **Update 2026-10-28 (migration 036).** `commercial.post_wallet_entry` locks the wallet, refuses an overdraft with `check_violation` and moves ledger and balance together; `commercial.download_candidate_profile` refuses a profile the user may not see (`core.can_view_candidate`, which also honours blocks) before any charge. The application role can no longer write `commercial.wallet` or `commercial.wallet_ledger` directly. Consequences: EXC-38 is **DB-rejected**, EXC-39 is **DB-rejected** on the download path, and EXC-40 cannot arise through the application role (the validator still checks it, as a second line). Amounts are placeholders (DEC-29). The original text above records the state before this change.

> **EXC-40 deserves emphasis.** `commercial.wallet.balance` is a **stored column with no trigger deriving it**
> from the ledger. The reconciliation invariant is therefore a *test*, not a *constraint* — which is exactly
> how `docs/phase-2-model/11-rule-compliance.md` RG7 describes it, with a disclaimer. The append-only ledger protects the
> history; it does not protect the balance that the history is supposed to equal.

---

### 2.12 Integration, maintenance and support (added 2026-10-28 with WF-15 to WF-21)

| # | Attribute | EXC-41 | EXC-42 | EXC-43 | EXC-44 | EXC-45 |
|:--|:--|:--|:--|:--|:--|:--|
| 1 | **ID** | EXC-41 | EXC-42 | EXC-43 | EXC-44 | EXC-45 |
| 2 | **Name** | Dead-lettered exchange | Purge removes too much | Unauthorised impersonation | Assessment score out of range | Duplicate referral code |
| 3 | **Description** | An exchange fails more times than the boundary allows | The retention job deletes rows that were still needed | A user without a platform role tries to act as another user | A provider reports a score above the maximum | An invitation is created with a code already used |
| 4 | **Trigger condition** | `attempts` reaches `max_attempts` | A retention period shorter than the business needs | `core.begin_impersonation` called without the platform role | `score_obtained > max_score` | Second insert of the same `referral_code` |
| 5 | **Affected workflow** | WF-15 | WF-16 | WF-17 | WF-18 | WF-20 |
| 6 | **Detection mechanism** | `messaging.fail_integration_event` returns `dead_letter`; `audit.ops_integration_health` | `audit.maintenance_run.detail_json` lists counts per table | `core.begin_impersonation` checks `core.is_platform_admin()` | CHECK on the score table | UNIQUE constraint on `referral_code` |
| 7 | **Handling behaviour** | The event stops retrying, an `INTEGRATION_DEAD_LETTER` row is written to `audit.system_error_log`; an operator requeues with `messaging.requeue_dead_letter` | Rows are gone; recovery is from backup | The call is refused | The insert is refused | The insert is refused |
| 8 | **Severity** | Medium | High | High | Low | Low |
| 9 | **Enforcement layer** | DB-recorded | **Policy-dependent**: the database does what the policy says | DB-rejected | DB-rejected | DB-rejected |
| 10 | **Recovery path** | Fix the cause, requeue | Restore from backup; correct the retention period in `audit.entity_lifecycle_policy` | None needed | Correct the provider mapping | Generate a new code |
| 11 | **Audit event** | `audit.system_error_log` | `audit.maintenance_run` | none for the refusal; the start and end events when allowed | None | None |
| 12 | **Data impact** | An external system lags behind | **Irreversible without a restore** | None | None | None |

---

## 3. Exception analysis

### 3.1 Counts by enforcement layer

| Layer | Count | Exception IDs |
|:--|--:|:--|
| **DB-rejected** | 14 | EXC-01, 05, 06, 07, 08, 10, 11, 12, 14, 15, 16, 22, 23, 25, 26 |
| **DB-rejected-conditional** | 4 | EXC-21, EXC-27, EXC-18, EXC-02* |
| **DB-nulled** | 5 | EXC-02, EXC-03, EXC-13, EXC-30, EXC-39 |
| **App-unhandled** | 12 | EXC-04, 09, 17, 20, 29, 32, 34, 35, 36, 37, 38, 40 |
| **Documented-only** | 1 | EXC-33 |

\* EXC-02 appears in two layers: the refusal is a NULL return, and the audit write is conditional.

### 3.2 Counts by severity

| Severity | Count | Exception IDs |
|:--|--:|:--|
| **Critical** | 3 | EXC-17 (cross-organisation pipeline access), EXC-29 (double credit), EXC-40 (ledger divergence) |
| **High** | 8 | EXC-04, 09, 13, 20, 21*, 29*, 31, 33, 39, 40* |
| **Medium** | 5 | EXC-02, 03, 24, 32, 38 |
| **Low** | 11 | EXC-01, 05, 06, 07, 08, 10, 11, 12, 14, 15, 16, 18, 19, 22, 23, 25, 26, 30 |

### 3.3 The pattern

**Every Critical and High exception is either (a) an unguarded application-layer dependency or (b) a
function-scoped control that a caller may omit.** Not one of them is a missing CHECK constraint.

| Pattern | Exceptions | Root cause |
|:--|:--|:--|
| **Tenant isolation depends on the application** | EXC-09, EXC-17 | No RLS (FEAT-020 is "Documented only") |
| **Idempotency exists in prose but not in the schema** | EXC-29 | No idempotency key column |
| **Financial invariants are checked, not enforced** | EXC-38, EXC-40 | `wallet.balance` is a stored column with no deriving trigger |
| **Privacy controls are function-scoped** | EXC-13, EXC-39 | `core.is_candidate_visible_to` protects only its callers |
| **Contracts are documented but unimplemented** | EXC-20, EXC-32, EXC-33, EXC-37 | Retry/DLQ, consent suppression and atomic refresh have no schema |
| **Authorisation has no content** | EXC-04, EXC-31 | `core.role_permission` is empty |

**This is the single most useful finding in Phase 1.** The data model's *structural* integrity is strong:
19 of 40 exceptions are caught by the database, and every CHECK, UNIQUE, FOREIGN KEY and EXCLUDE constraint
in the schema does its job. The weak surface is entirely in the **cross-cutting concerns** — authorisation,
tenant isolation, idempotency, financial derivation, and privacy enforcement.

**The Phase 2 implication.** Adding more tables or more constraints will not close these. The gap is not
modelling; it is **cross-cutting enforcement**. The four highest-leverage Phase 2 items are, in order:

1. Implement FEAT-020 (RLS) — closes EXC-09 and EXC-17, the two cross-tenant failures.
2. Implement FEAT-019 (RBAC content) — closes EXC-04 and EXC-31, and is a precondition for the others.
3. Add an idempotency key to the payment and ledger paths — closes EXC-29.
4. Derive `commercial.wallet.balance` from the ledger via trigger — closes EXC-40.

### 3.4 Exceptions by workflow

| Workflow | Exceptions | Count |
|:--|:--|--:|
| WF-01 | EXC-01, 02, 03, 04 | 4 |
| WF-02 | EXC-05, 06, 07 | 3 |
| WF-03 | EXC-08, 09, 10, 11 | 4 |
| WF-04 | EXC-12, 13, 14 | 3 |
| WF-05 | EXC-15, 16, 17 | 3 |
| WF-06 | EXC-18, 19, 20 | 3 |
| WF-07 | EXC-21, 22, 23, 24 | 4 |
| WF-08 | EXC-25, 26 | 2 |
| WF-09 | EXC-27, 28, 29 | 3 |
| WF-10 | EXC-30, 31 | 2 |
| WF-11 | EXC-32, 33 | 2 |
| WF-12 | EXC-34, 35, 36 | 3 |
| WF-13 | EXC-37 | 1 |
| WF-14 | EXC-38, 39, 40 | 3 |

**Every workflow has at least one exception. No workflow is happy-path-only.**

---

## 4. Exception-to-requirement traceability

| Exception | Requirements | Features | Gap reference |
|:--|:--|:--|:--|
| EXC-01 | REQ-001, BR-001 | FEAT-001 | — |
| EXC-02 | REQ-004, BR-002, SEC-008 | FEAT-002, FEAT-030 | — |
| EXC-03 | REQ-003 | FEAT-001 | — |
| EXC-04 | REQ-002, SEC-006, NFR-014 | FEAT-001 | SEC-006 is "Partial" |
| EXC-05 | REQ-012, SEC-009 | FEAT-009 | — |
| EXC-06 | REQ-012, BR-008 | FEAT-009 | — |
| EXC-07 | DATA-003 | FEAT-007, FEAT-026 | — |
| EXC-08 | REQ-017, BR-012 | FEAT-012 | — |
| EXC-09 | SEC-002 | FEAT-020 | **FEAT-020 "Documented only"** |
| EXC-10 | REQ-018, BR-013 | FEAT-013 | — |
| EXC-11 | DATA-001 | FEAT-012 | — |
| EXC-12 | REQ-019, BR-014 | FEAT-014 | — |
| EXC-13 | SEC-010, NFR-013 | FEAT-023 | **NFR-013 not enforceable** |
| EXC-14 | REQ-010, BR-006 | FEAT-007 | — |
| EXC-15 | REQ-022, BR-015 | FEAT-015 | — |
| EXC-16 | REQ-021, BR-016 | FEAT-015 | — |
| EXC-17 | SEC-002, BR-017 | FEAT-020 | **FEAT-020 "Documented only" — Critical** |
| EXC-18 | REQ-026, BR-019 | FEAT-018 | — |
| EXC-19 | REQ-027, BR-020 | FEAT-018 | — |
| EXC-20 | REQ-025, BR-018 | FEAT-018 | No submission-to-request linkage |
| EXC-21 | REQ-032, BR-025, SEC-004 | FEAT-027 | — |
| EXC-22 | REQ-030, BR-023 | FEAT-026 | — |
| EXC-23 | REQ-031, BR-024 | FEAT-026 | — |
| EXC-24 | REQ-033, BR-026 | FEAT-026 | — |
| EXC-25 | REQ-015, BR-011 | FEAT-011 | — |
| EXC-26 | DATA-007 | FEAT-011 | — |
| EXC-27 | REQ-004, BR-002 | FEAT-030 | — |
| EXC-28 | REQ-033, SEC-005 | FEAT-032 | No audit write |
| EXC-29 | SEC-005, NFR-012 | FEAT-031, FEAT-032 | **ML-07 — no idempotency key** |
| EXC-30 | REQ-006 | FEAT-003 | — |
| EXC-31 | SEC-001 | FEAT-019 | **RBAC empty** |
| EXC-32 | REQ-007, NFR-008 | FEAT-033 | No DLQ, no audit write |
| EXC-33 | REQ-007, SEC-011, NFR-017, NFR-018 | FEAT-004 | **ML-09 / OQ-011** |
| EXC-34 | OPS-001 | FEAT-038 | — |
| EXC-35 | OPS-007, NFR-015 | FEAT-037 | Not wired into the test runner |
| EXC-36 | OPS-004, NFR-010 | FEAT-040 | — |
| EXC-37 | OPS-005, NFR-020 | FEAT-035 | **OQ-010 — unscheduled** |
| EXC-38 | NFR-012 | FEAT-031 | **ML-06 — fee/balance logic absent** |
| EXC-39 | SEC-010, NFR-013 | FEAT-023, FEAT-031 | **ML-04 — no PII masking** |
| EXC-40 | NFR-012, SEC-005 | FEAT-031 | **Balance is a stored column** |
| EXC-41 | NFR-027 | FEAT-043 | — |
| EXC-42 | NFR-017 | FEAT-044 | Retention periods are the assistant's (DEC-23) |
| EXC-43 | SEC-003, SEC-012 | FEAT-022 | — |
| EXC-44 | DATA-001 | FEAT-007 | — |
| EXC-45 | — | FEAT-042 | — |

---

## 5. Related documents

| Document | Contains |
|:--|:--|
| [`docs/phase-1-discover/05-workflows.md`](05-workflows.md) | The 21 workflows these exceptions attach to |
| [`docs/phase-1-discover/01-requirements.md`](01-requirements.md) | The requirement register |
| [`docs/phase-1-discover/03-feature-inventory.md`](03-feature-inventory.md) | The feature register |
| [`docs/phase-1-discover/05-audit-event-matrix.md`](05-audit-event-matrix.md) | Which sensitive actions are audited |
| [`docs/phase-1-discover/03-competitive-benchmark.md`](03-competitive-benchmark.md) | §4.1 lists the capability gaps these exceptions reveal |
| [`docs/phase-1-discover/phase-report.md`](phase-report.md) | Phase 1 report and G1 decision |
