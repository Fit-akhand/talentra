# Talentra Phase 3 Follow-up — Close Findings Safely

**Date**: 2026-10-21
**Phase**: 3 Follow-up — close findings from `docs/phase3-implementation-verification-report.md`
**Branch / HEAD**: `feature/your-task` @ `7ac5b2bdeb731610b8bd2c0282608e6c93d4b1df`
**Scope**: documentation correction (2 items), security assessment (1 item), test-execution matrix (1 item), benchmark-artifact evidence note (1 item), report update (1 item).
**Nature**: documentation-only. No migration, schema, index, application code, seed data, configuration, test file, or benchmark artifact was changed. No database object or data was touched.

---

## 1. Working-tree inspection (performed first)

```
$ git rev-parse HEAD
7ac5b2bdeb731610b8bd2c0282608e6c93d4b1df

$ git branch --show-current
feature/your-task

$ git status --short
 M README.md
 M docs/architecture.md
 M docs/competitive-benchmark.md
 M docs/data-dictionary.md
 M docs/integration-boundaries.md
 M docs/performance-report.md
 M docs/rule-compliance.md
 M docs/threat-model.md
 M scripts/run_all_tests.py
 M scripts/run_benchmarks.py
 M tests/test_constraints.sql
?? .git-initial-backup/
?? docs/audit-event-matrix.md
?? docs/exceptions.md
?? docs/feature-inventory.md
?? docs/nfr-register.md
?? docs/personas.md
?? docs/phase2b-query-performance-validation.md
?? docs/phase2c-documentation-audit.md
?? docs/phase2d-documentation-correction-report.md
?? docs/phase2e-documentation-correction-report.md
?? docs/phase3-implementation-verification-report.md
?? docs/requirements.md
?? docs/scope-assumptions.md
?? docs/source/
?? docs/workflows.md
?? tests/test_benchmark_harness.py

$ git diff --stat
 README.md                      |  64 +--
 docs/architecture.md           |  27 +-
 docs/competitive-benchmark.md  | 286 +++++++++++--
 docs/data-dictionary.md        | 100 +++-
 docs/integration-boundaries.md |   8 +-
 docs/performance-report.md     |  84 ++--
 docs/rule-compliance.md        |  48 +-
 docs/threat-model.md           | 117 +++--
 scripts/run_all_tests.py       |  24 +-
 scripts/run_benchmarks.py      | 949 +++++++++++++++++++++++++++++++++++------
 tests/test_constraints.sql     |  43 ++
 11 files changed, 1395 insertions(+), 355 deletions(-)
```

**Observations carried into this follow-up:**

1. `docs/competitive-benchmark.md` grew from 14 to 286 changed lines since the Phase 3 baseline — the concurrent Phase 1 workstream has been editing it. **This follow-up did not touch that file.**
2. The concurrent workstream added seven further untracked documents since the Phase 3 baseline: `docs/audit-event-matrix.md`, `docs/exceptions.md`, `docs/feature-inventory.md`, `docs/nfr-register.md`, `docs/personas.md`, `docs/workflows.md`, and `docs/source/`. `docs/feature-inventory.md`, which the Phase 3 report listed as "not yet present", has now appeared.
3. `docs/rule-compliance.md` still showed 48 changed lines — the same figure as the Phase 3 baseline — confirming the concurrent workstream had **not** touched it. That made it safe to apply the two targeted RG8 corrections below without collision risk.

**All pre-existing modifications and untracked files were preserved.** `.git-initial-backup/` was not read, modified, or deleted. `tests/test_constraints.sql` was read only.

---

## 2. RG8 corrections in `docs/rule-compliance.md`

Both discrepancies from Phase 3 §5 were **still present** and were corrected. Application code, migrations, and test files were **not** modified.

### 2.1 Verification before editing (three independent sources)

| Source | `en` value for `btn.apply_job` | `es` value | Insert semantics |
|:--|:--|:--|:--|
| `db/migrations/018_create_messaging_and_translations.sql:43` | `'Apply for this Role'` | `'Postularse para este puesto'` | `ON CONFLICT (string_key, language_code) DO NOTHING` (`:53`) |
| `scripts/generate_data.py:166-167` | `'Apply Now'` | `'Postularse Ahora'` | `ON CONFLICT (string_key, language_code) DO NOTHING` (`:186`) |
| `tests/test_messaging.sql:31-47` | fallback asserted `NOT IN ('Apply for this Role', 'Apply Now')` — **tolerates both** | asserts `'Postularse para este puesto'` | — |

**The precedence argument.** Both seeders use `ON CONFLICT … DO NOTHING`, so whichever runs first wins and the second is a no-op. The documented setup order in `README.md` is: **step 2** "Apply Database Migrations (001 to 019)" → **step 4** "Seed Synthetic Data". The migration therefore writes the row first, and the loader's insert is a no-op against the existing `(string_key, language_code)` key. Consequently, in the documented setup, the `en` row is `'Apply for this Role'`.

The `es` row is unambiguous: only migration 018 seeds `'Postularse para este puesto'` for Spanish, and the loader's competing `'Postularse Ahora'` loses the same conflict. The existing doc line was already correct and was left alone.

The `'ja'` lookup has **no** seeded row in either source (seeded codes are `en/es/hi/fr` in migration 018 and `en/es/de/hi/fr` in the loader), so `messaging.get_ui_translation` falls through to the English branch and returns the `en` row.

### 2.2 D-01 — English-fallback value (corrected)

**Before:**
```sql
SELECT messaging.get_ui_translation('btn.apply_job', 'ja'); -- Returns: 'Apply Now' (English Fallback)
```

**After:**
```sql
SELECT messaging.get_ui_translation('btn.apply_job', 'ja'); -- Returns: 'Apply for this Role' (English Fallback)
```

Plus an explanatory paragraph recording both source values, the `ON CONFLICT DO NOTHING` precedence rule, the precondition under which `'Apply Now'` would appear, and the fact that `tests/test_messaging.sql:43` accepts either value.

### 2.3 D-02 — "Cyrillic" script claim (corrected)

**Before:**
> Verified: UTF-8 Unicode integrity maintained across Latin, Devanagari, and Cyrillic scripts with zero mojibake errors.

**After:** a **Unicode script coverage** bullet that keeps the Latin and Devanagari claim, adds the two concrete seeded strings as evidence, and explicitly states that no Cyrillic string exists in `messaging.ui_translation` in any seeding path — naming the seeded language-code sets for both seeders, and pointing to the one real Cyrillic literal in the schema (`('ru', 'Russian', 'Русский')` in `master.language.native_name`, `db/migrations/010_create_candidate_extensions.sql:41`) as a different table that `messaging.get_ui_translation` never reads.

**Verification of the Cyrillic claim:** `grep -nE "'ru'|'uk'|'bg'" db/migrations/018_create_messaging_and_translations.sql scripts/generate_data.py` → no output. A repo-wide scan for the Cyrillic block `[\x{0400}-\x{04FF}]` over `db/` and `scripts/` returned exactly one hit, the `master.language` row quoted above.

### 2.4 What was deliberately NOT changed

- The `es` line — already correct.
- `messaging.get_ui_translation` — no function change.
- The migration, the loader, and `tests/test_messaging.sql` — no code change. The test's tolerance of both English values is correct behaviour and was left as is.
- `docs/phase3-implementation-verification-report.md` §5 — the *finding* is retained there as the historical record; §8 of this document is the authoritative *resolution*.

---

## 3. Security assessment — plaintext tax identifiers

**Target:** `recruitment.organization_identifier.identifier_value VARCHAR(100) NOT NULL` (`db/migrations/013_create_organization_extensions.sql:75`)

**Status: assessment only. No encryption was implemented and no schema was changed.**

### 3.1 Current state — verified

| Property | Value | Evidence |
|:--|:--|:--|
| Storage | Plaintext `VARCHAR(100)`, `NOT NULL` | `013:75` |
| Identifier types carried | `gstin`, `cin`, `ein`, `vat`, `pan`, `company_number`, `other` | `013:106-115` |
| What "PAN" means here | The **Indian Permanent Account Number** (company tax ID), *not* a Primary Account Number | `013:111` |
| Uniqueness | `UNIQUE (country_id, identifier_type, identifier_value)` — the **plaintext value is a lookup key** | `013:83-84` |
| Index | `idx_organization_identifier_org` on `organization_id` | `013:135` |
| Verification state | `verification_status` ∈ {`unverified`,`pending`,`verified`,`rejected`}, with `verified_at` / `verified_by_user_account_id` | `013:76-78`, `:119-124` |
| Encryption capability in repo | **None.** `grep -rniE "pgcrypto\|aes-\|encrypt\|decrypt\|cipher" db/ scripts/ tests/` → no output | — |
| Extensions in use | `btree_gist` only (`014:8`, `017:8`) — no `pgcrypto` | — |
| Broader crypto search | `grep -rniE "encrypt\|decrypt\|cipher\|pgcrypto\|base64\|hmac" db/ scripts/ tests/` → no output | — |
| Access control on the table | **None.** No `GRANT`, `REVOKE`, or `CREATE ROLE` anywhere in the repo; the only role is `talentra_admin`, a **SUPERUSER** | `grep -rnE "GRANT \|REVOKE \|CREATE ROLE" db/ scripts/ tests/` → no output |
| Row-Level Security | **None.** `grep -rn "CREATE POLICY" db/ scripts/ tests/` → no output; no `app.current_user_id` / `app.current_org_id` is ever set | — |
| Transport | No TLS configuration in `docker-compose.yml`; `postgres:17` defaults to `ssl=off` | `docker-compose.yml` — no `ssl` key |
| Storage at rest | Plain Docker named volume `talentra_pgdata`; no encrypted-volume options declared | `docker-compose.yml:13-14` |
| Network exposure | Bound to `127.0.0.1:5432` — **not** `0.0.0.0` | `docker-compose.yml:12` |

**Sensitivity note.** GSTIN, CIN, EIN, VAT and PAN are company tax identifiers, not personal tax IDs. They identify a legal entity, and their exposure is generally governed by corporate-data regimes rather than individual privacy law. That is a *lower* severity than storing personal tax numbers — but it is **not** zero: they are permanent, non-rotatable business identifiers; they are directly usable in tax filings and bank KYC; and in the Indian context a company's PAN is often paired with its GSTIN, director identifiers, and registered address, so their aggregation materially increases the impact of a breach.

### 3.2 Risk assessment

| # | Risk | Likelihood | Impact | Rationale |
|:--|:--|:--|:--|:--|
| S-01 | **Insider / over-privileged read.** The single superuser role can read every identifier with no `GRANT` scoping and no RLS. There is no separation between an application connection and a DBA connection | High | High | Zero roles, zero grants, zero policies — verified above. Any credential leak is a full-table read of every tenant's identifiers |
| S-02 | **Backup / volume exposure.** A plain named volume means identifiers are readable in `pg_dump`, base backups, WAL, and filesystem-level copies | Medium | High | `talentra_pgdata` has no encryption options; `docker-compose.yml:13-14` |
| S-03 | **No transport encryption.** `ssl=off` by default, and the port is bound to loopback — but any local process, or any future rebind to `0.0.0.0`, exposes identifiers in cleartext on the wire | Low–Medium | Medium | `docker-compose.yml:12`; no `ssl` configuration |
| S-04 | **Logging leakage.** `identifier_value` is plaintext, so it will appear verbatim in `log_statement`, slow-query logs, error messages, `RAISE NOTICE` output, and application debug logs | Medium | Medium | Plaintext columns are logged as-is by PostgreSQL; no log-scrubbing configuration exists in the repo |
| S-05 | **Plaintext equality / uniqueness leak.** The `UNIQUE (country_id, identifier_type, identifier_value)` constraint means the plaintext is a **join and lookup key**; index pages contain the cleartext identifier, and equality predicates on it are visible in query plans and `EXPLAIN` output | High | Medium | `013:83-84` — see §3.3, this materially constrains the design options |
| S-06 | **No key rotation or revocation path.** A plaintext column has no key to rotate; a leaked identifier is permanently compromised with no remediation except data re-issue by the tax authority | Certain | Medium | Structural — this is the strongest argument for encryption |
| S-07 | **Cross-tenant aggregation.** `organization_identifier` is keyed to `organization_id`, and there is no RLS, so a query joining organizations to identifiers crosses tenant boundaries in one statement | Medium | High | Zero policies; `organization_id` is a plain column |
| S-08 | **Re-identification via stable identifier.** A GSTIN/PAN is a stable, non-rotatable business key. Combined with `organization_name` and the registered address, it identifies a business and its owners with certainty, and remains valid after a password reset | Certain | Medium | Structural property of the identifier, not of the implementation |
| S-09 | **No data-classification control in the database.** `docs/data-dictionary.md:20` correctly labels the values `[SENSITIVE]`, but that label is analyst-applied text in a Markdown file — nothing in the schema enforces it | Certain | Low | Confirms the Phase 2E finding D-02 |

**Aggregate view.** There is no *implementation* defect here: the schema stores what it says it stores, and the Phase 2E documentation now states that plainly. The risk is a **posture** gap — the repository ships a design whose own threat model (`docs/threat-model.md:10`) advertises a "Zero-Trust Relational Core" and "Cryptographic Hashing Standards", while this particular sensitive column has neither an access boundary nor encryption, and the "Cryptographic Hashing Standards" claim applies to *passwords*, not to tax identifiers.

### 3.3 Protection options

Presented for decision. **None is implemented; this is a design consultation.**

**Option A — Application-layer envelope encryption (recommended starting point)**
Encrypt `identifier_value` in the application before it reaches the database; the database stores ciphertext. A deterministic (order-preserving-insensitive) AEAD mode such as AES-256-GCM with a random per-row IV, keyed from a KMS.
- *Pros*: the database never sees plaintext, so backups, volumes, logs, and a stolen superuser credential all yield only ciphertext. Independent of the DDL and reversible without a schema change. Works with the existing `VARCHAR(100)` width if ciphertext is stored base64-encoded (or the column is widened).
- *Cons*: the application must hold the key; equality lookups and the `UNIQUE` constraint become application-level; a "blind index" column is needed to keep uniqueness and lookups working.
- *Fits the existing shape*: the codebase is already database-first, and `scripts/validate_data.py` is an application-layer rule checker, so the pattern exists.

**Option B — `pgcrypto` column-level encryption**
`CREATE EXTENSION pgcrypto;` plus `pgp_sym_encrypt(identifier_value, key)` / `pgp_sym_decrypt(...)` with the key supplied per session from a KMS or a vault-managed secret.
- *Pros*: keeps the key entirely outside the database (supplied at session start via `SET`), so a stolen data volume yields only ciphertext. The encryption primitive lives next to the data.
- *Cons*: `pgp_sym_encrypt` is **not deterministic by default**, so it cannot support the existing `UNIQUE (country_id, identifier_type, identifier_value)` constraint or equality lookups without a separate deterministic (leak-prone) index or a blind-index column. Every read becomes a decrypt round-trip, including for the `UNIQUE` check. Requires a `pgcrypto` extension change — an explicit migration — and a key-distribution mechanism the repository does not have.
- *Note*: `pgcrypto`'s `pgp_sym_encrypt` uses a random session salt, so identical plaintexts produce different ciphertexts. This is the correct cryptographic property and the direct cause of the constraint problem.

**Option C — Deterministic encryption + blind index**
Encrypt with a deterministic AEAD (or a keyed hash) and store a separate keyed blind-index column for equality and uniqueness.
- *Pros*: preserves the ability to enforce uniqueness and to look up by identifier.
- *Cons*: deterministic encryption **leaks equality** — two organizations with the same GSTIN produce identical ciphertext, which is a meaningful inference channel for a low-entropy identifier space. It is a deliberate, documented trade-off, and should only be adopted if the uniqueness guarantee is judged more valuable than the equality-leak. Blind-index columns must be `BYTEA`/fixed-width, not `VARCHAR(100)`.
- *Practical note**: a GSTIN is 15 characters with a defined checksum (the 15th character is a mod-36 check digit). A keyed blind index over the *canonical* form is materially better than over the raw string, which is likely to vary in case and spacing.

**Option D — Move the column out of the database**
Store the identifier in an external tokenization vault or KMS-backed field-encryption service, keeping only a non-reversible reference token in `recruitment.organization_identifier`.
- *Pros*: strongest separation — the database never stores the identifier in any form, and the vault holds its own access control and audit trail.
- *Cons*: an external dependency and a new failure mode; a lookup requires a round-trip to the vault, which complicates the `UNIQUE` constraint and the batch verification flow; adds operational and cost surface.

**Option E — Defer, and compensate with access control**
Leave the column plaintext but land the least-privilege role model and RLS that `docs/threat-model.md` §3 and §4 already specify as proposals.
- *Pros*: the least disruptive; the design already documents the intended controls.
- *Cons*: does nothing for S-02 (backups), S-03 (transport), S-04 (logs), or S-06 (rotation). It mitigates S-01, S-07, and S-09 only. It is a **partial** answer and should be labelled as such.

**Recommendation.** Option A, with the blind-index pattern from Option C applied only to the specific uniqueness constraint, and Option E's access-control work landing in parallel as a prerequisite. Rationale: Option A protects against every risk class including backup and superuser-credential theft, requires no migration to a `pgcrypto` extension, and fits the repository's existing application-layer rule-checking pattern. Option E is complementary, not alternative — and is a prerequisite for limiting S-01 and S-07 regardless of which encryption option is chosen.

### 3.4 Access-control requirements (prerequisite to any of the above)

These are required whatever encryption approach is adopted, and are largely the *already-designed-but-unimplemented* controls from `docs/threat-model.md`:

1. **Create a non-superuser application role** and connect as it, so a leaked application credential does not yield `SUPERUSER`. Today the only role is `talentra_admin`, created via `POSTGRES_USER` and holding SUPERUSER — the exact privilege level the threat model says the least-privilege design exists to avoid.
2. **Grant narrowly.** The application role needs `SELECT`/`INSERT`/`UPDATE` on the schemas it uses, and on `recruitment.organization_identifier` specifically it needs `INSERT`/`UPDATE` (to write identifiers) but **`SELECT` should be restricted to the verification workflow** — a role that can read all identifiers of all tenants is a large blast radius for one table.
3. **Introduce RLS on `organization_identifier`** keyed to the session context variables the threat model already specifies (`app.current_user_id`, `app.current_org_id`), with the `SET LOCAL` performed by the application in the same transaction. This closes S-07. Note this requires the session-variable mechanism to actually be *set* — today it is referenced only in the proposal and never assigned anywhere in the repo.
4. **Separate the verification role.** Reading a tax identifier to verify it, and listing identifiers for reporting, are different privilege levels and should be different grants.
5. **Restrict the superuser.** `talentra_admin` should be reserved for migrations and administration, with a documented break-glass procedure, and should not be the credential the application uses.

### 3.5 Key-management requirements

1. **Key hierarchy.** A single root key in a KMS (AWS KMS, GCP Cloud KMS, Azure Key Vault, or HashiCorp Vault) wrapping per-column or per-tenant data-encryption keys (DEKs). The application unwraps DEKs at runtime; the raw DEK should never be written to disk or to a config file in the repository.
2. **No key material in the repository.** No key, passphrase, or secret may live in `db/migrations/`, `scripts/`, `docker-compose.yml`, or `.env` committed to git. `.env` already holds `POSTGRES_PASSWORD`; adding a DEK there would extend that exposure.
3. **Rotation.** DEKs must be rotatable without re-encrypting every row on the critical path: envelope-encrypt the DEK, keep a key-version marker on each row, and support background re-encryption. This is what converts S-06 from "certain" to "mitigable".
4. **Per-tenant separation (optional).** Per-tenant DEKs let one tenant's identifier set be revoked or re-keyed independently, and bound the impact of a single key compromise to one tenant.
5. **Rotation and revocation must be backed by audit.** Every decrypt of a tax identifier should be attributable. `audit.audit_event` exists and is append-only (`db/migrations/012_create_administration_security.sql:290-293`), so the decryption path can log to it — noting that its own `TRUNCATE` gap (Phase 3 §6.3) applies here too.
6. **Key custody for verification workflows.** Third-party verification providers need the identifier, so a decrypt capability exists in the verification path; key access should be scoped to that workflow rather than to general application reads.

### 3.6 Migration considerations

1. **Add a new migration, never edit an existing one.** Migrations 001–019 are already applied in existing deployments; editing them creates a checksum/ordering divergence. A new `020_encrypt_organization_identifier.sql` (or a sequence) should carry the change. **This was not done in this phase.**
2. **Dual-read / dual-write rollout.** Add the new ciphertext column and a blind index alongside the plaintext column; write both; read from ciphertext with a plaintext fallback; backfill; verify; then drop the plaintext column in a later migration. A single-shot in-place rewrite risks an unrecoverable state where the only copy of an identifier is ciphertext under a lost key.
3. **Backfill is a full-table write.** It must run in bounded batches with a resumable checkpoint, outside a single long transaction, so it does not hold locks or bloat WAL on a large table.
4. **Constraint and index rework is unavoidable.** `UNIQUE (country_id, identifier_type, identifier_value)` (`013:83-84`) cannot survive random-nonce encryption. The migration must replace it with a unique constraint over `(country_id, identifier_type, <blind_index>)`, and add a matching index. The `CHECK` constraints on `identifier_type` and `verification_status` are unaffected.
5. **Type and width changes.** `identifier_value VARCHAR(100)` must be widened to hold base64 ciphertext plus a nonce and authentication tag (e.g. `VARCHAR(512)` or `BYTEA`), and the blind index should be `BYTEA` with a fixed length. Ciphertext is also not human-readable, so any operator-facing view or report that surfaces the identifier needs a deliberate decrypting view, which becomes an access-controlled object in its own right.
6. **Canonicalisation before encryption.** Identifiers must be normalised (case, whitespace, punctuation) before encryption and before the blind index is computed, or the same identifier will encrypt to different ciphertexts and the blind index will not match. The `identifier_type` CHECK constraint already restricts the value domain, but it does not enforce a canonical form.
7. **The generator and validator must be updated in step.** `scripts/generate_data.py` writes rows into this table, and `scripts/validate_data.py` has a Rule Group 6 sensitivity check. Both need the encryption path, and the validator needs a check that plaintext identifiers are no longer present.
8. **`uq_organization_identifier_val` and any dependent application code** must be located before the migration. Currently the only writers found in-repo are `tests/test_organization_extensions.sql:168,194`; application code is not in this repository, so the migration plan must account for consumers outside it.
9. **Backup and rollback strategy.** Take a verified backup before the backfill, and define the rollback as "restore from backup" — not "revert the migration" — because reverting would require decrypting the ciphertext with a key that may already have been rotated.

### 3.7 Testing required

1. **Round-trip correctness.** For every `identifier_type`, `encrypt → store → decrypt` returns the original value exactly, including for the longest realistic identifiers.
2. **Uniqueness is preserved.** Two organisations sharing the same `(country_id, identifier_type, identifier_value)` still collide on the blind index and are still rejected by the constraint; two organisations with *different* identifiers do not collide (measure the false-positive rate of the blind-index width).
3. **Cross-tenant isolation.** With RLS applied, a session scoped to organisation A cannot `SELECT` organisation B's identifiers, and cannot insert an identifier for another organisation. This needs a dedicated RLS test, not a claim.
4. **Least-privilege verification.** The application role cannot `SELECT` all identifiers, cannot `DROP`/`ALTER` the encryption function, and cannot read the key material. A test should assert the *denials*, not just the grants.
5. **Plaintext absence.** After migration, a scan of the table, its indexes, and `pg_dump` output finds no plaintext identifier. This is the single most important assertion, and it should be automated as a regression test — the failure mode being guarded against is a future migration reintroducing a plaintext column.
6. **Audit completeness.** Every decrypt is recorded in `audit.audit_event` with an attributable actor.
7. **Key rotation.** Rotate the DEK and confirm that previously written rows still decrypt, that new writes use the new key version, and that the rotation is auditable.
8. **Backup/restore.** Restore a backup taken before the migration into a disposable database, migrate it, and confirm every identifier decrypts and the blind index still enforces uniqueness. This catches the "lost key" scenario before it reaches production.
9. **Log hygiene.** Confirm that no identifier appears in PostgreSQL logs, in `log_statement` output, or in application logs when a query touches the column.
10. **Validator and generator parity.** `scripts/validate_data.py` Rule Group 6 must pass against encrypted data, and `scripts/generate_data.py` must produce encrypted rows — including the `medium` and `laptop` presets.
11. **Performance regression.** Encryption adds per-row CPU cost; measure the impact on the verification and reporting queries that read this table.

---

## 4. Test-execution matrix (all 23 suites)

**Prepared only. No persistent-write test was executed against the existing database.**

### 4.1 Legend

- **Tx** — transaction handling: `ISO` = `BEGIN;`…`ROLLBACK;` (writes discarded) / `COMMIT` = writes persisted / `RO` = read-only
- **Target** — `live` = the existing `talentra` database / `disp` = a disposable database
- **Safe?** — whether the suite can run against an isolated disposable test database without contaminating the live one

### 4.2 SQL suites (21)

| # | Suite | Tx | Writes | Persistent side effects | Prereqs | Safe on `live`? | Safe on disposable DB? |
|:--|:--|:--|:--|:--|:--|:--:|:--:|
| 1 | `test_administration.sql` | ISO | 14 INSERT, 1 DELETE (in-txn) | **None** — rolled back | migrations applied | ✅ Yes | ✅ Yes |
| 2 | `test_analytics.sql` | **COMMIT** | 7 INSERT (committed at `:202`), 7 DELETE (`:226-232`) | **Yes** — commits fixtures, then `CALL analytics.refresh_reporting_marts()` **twice** (`:204`, `:236`), refreshing `analytics.mv_hiring_funnel_summary` and `analytics.mv_gig_fulfilment_summary` | migrations applied; **must have `analytics.*` fact rows** or the mat views refresh to empty and the suite's own `COUNT(*) = 0` check raises | ❌ **No** — commits and mutates materialized views | ✅ Yes — but needs a seeded dataset |
| 3 | `test_business_rules.sql` | ISO | 20 INSERT | None | migrations + master seed + `job_posting`/`user_account` rows | ✅ Yes | ✅ Yes |
| 4 | `test_candidate_application.sql` | ISO | 8 INSERT | None | migrations + master seed | ✅ Yes | ✅ Yes |
| 5 | `test_candidate_document.sql` | ISO | 9 INSERT | None | migrations + master seed | ✅ Yes | ✅ Yes |
| 6 | `test_candidate_extensions.sql` | ISO | 13 INSERT | None | migrations + master seed | ✅ Yes | ✅ Yes |
| 7 | `test_commercial.sql` | ISO | 16 INSERT, 2 DELETE (in-txn) | None | migrations + master seed | ✅ Yes | ✅ Yes |
| 8 | `test_candidate_profile.sql` | ISO | 14 INSERT | None | migrations + master seed | ✅ Yes | ✅ Yes |
| 9 | `test_constraints.sql` *(user-owned)* | ISO | 17 INSERT; 3 `ON CONFLICT` clauses — 1 `DO UPDATE` (`:29`) + 2 `DO NOTHING` (`:56`, `:63`) | None | migrations + master seed | ✅ Yes | ✅ Yes |
| 10 | `test_gig.sql` | ISO | 16 INSERT | None | migrations + master seed | ✅ Yes | ✅ Yes |
| 11 | `test_identity.sql` | ISO | 11 INSERT | None | migrations | ✅ Yes | ✅ Yes |
| 12 | `test_job_posting.sql` | ISO | 10 INSERT | None | migrations + master seed | ✅ Yes | ✅ Yes |
| 13 | `test_job_questionnaire.sql` | ISO | 13 INSERT | None | migrations + master seed | ✅ Yes | ✅ Yes |
| 14 | `test_licences.sql` | ISO | 8 INSERT | None | migrations + master seed | ✅ Yes | ✅ Yes |
| 15 | `test_master_data.sql` | ISO | 17 INSERT | None | migrations | ✅ Yes | ✅ Yes |
| 16 | `test_messaging.sql` | ISO | 13 INSERT | None | migrations + master seed | ✅ Yes | ✅ Yes |
| 17 | `test_organization.sql` | ISO | 11 INSERT | None | migrations | ✅ Yes | ✅ Yes |
| 18 | `test_organization_extensions.sql` | ISO | 17 INSERT | None | migrations + master seed | ✅ Yes | ✅ Yes |
| 19 | `test_security.sql` | ISO | 13 INSERT, 2 DELETE (in-txn) | None | migrations + master seed | ✅ Yes | ✅ Yes |
| 20 | `test_sourcing.sql` | ISO | 14 INSERT | None | migrations + master seed | ✅ Yes | ✅ Yes |
| 21 | `test_seed_master_data.sql` | **RO** | **0** | **None** — pure `IF NOT EXISTS (SELECT 1 …)` assertions | migrations **plus** `004_seed_master_reference_data.sql` applied | ✅ Yes — read-only | ✅ Yes |

**Group A (safe on the live database): 20 suites** — the 19 `BEGIN;`…`ROLLBACK;` suites plus the read-only `test_seed_master_data.sql`. Every write is discarded; the live database is left byte-identical.

**Group B (persistent writes — do not run on the live database): 1 suite** — `test_analytics.sql`.

### 4.3 Python suites (2)

| # | Suite | Tx | Writes | Persistent side effects | Prereqs | Safe on `live`? | Safe on disposable DB? |
|:--|:--|:--|:--|:--|:--|:--:|:--:|
| 22 | `test_concurrency.py` | **COMMIT** (`autocommit=True`) | Creates: 3× `core.user_account`, 2× `recruitment.organization`, 1× `commercial.subscription_licence`, 1× `commercial.licence_seat_allocation`, 1× `gig.gig_worker_profile`, 5× `gig.gig_request`, 5× `gig.gig_application`, 1× `commercial.wallet`, 1× `commercial.wallet_ledger`; plus 2 sessions, 1 gig assignment, 6 wallet debits + 6 ledger rows | **Yes, and never cleaned up.** Accumulates on every run. Asserts on live state (`success_count == 2`, `successes == 1`, `success_debits == 6`) | migrations; `psycopg2`; DB reachable at `127.0.0.1:5432` with the hardcoded password at `:22` | ❌ **No** — persistent, cumulative, and **not idempotent** | ✅ Yes — but a fresh DB per run |
| 23 | `test_benchmark_harness.py` | n/a | **None — database-free** | **None.** Uses a `FakeCursor` stand-in and `tempfile.TemporaryDirectory()`. Reads the committed v1 artifact read-only and asserts it is unmodified | Python 3 stdlib only; **no `psycopg2` required** (`run_benchmarks.py:54-56` guards the import) | ✅ Yes | ✅ Yes — **no database needed at all** |

**Group C (database-free): 1 suite** — `test_benchmark_harness.py`. It is the only suite that can be executed with no database whatsoever.

### 4.4 The batch runner is not a safe unit of execution

`scripts/run_all_tests.py` discovers **all** `tests/*.sql` and executes them in a single batch, then the two Python suites. It therefore **cannot be used as-is** against the live database, because it unconditionally includes `test_analytics.sql` (Group B) and `test_concurrency.py` (Group B). It also offers no way to select a subset.

**Safe execution plans:**

| Plan | Command shape | Contamination risk |
|:--|:--|:--|
| **P1 — no database required** | `python3 tests/test_benchmark_harness.py` | None. The only suite executable today without a database |
| **P2 — Group A against the live database** | Pipe each of the 20 Group-A files individually into `docker exec -i talentra-postgres psql -U talentra_admin -d talentra` — **not** via `run_all_tests.py` | None. Every write is rolled back |
| **P3 — all 23 against a disposable database** | Create a throwaway database, apply migrations 001–019 (incl. `004`), optionally seed, then run every suite against it | None to the live database. `test_analytics.sql` still needs fact rows for its mat-view assertions |
| **P4 — Group B against a disposable database only** | Run `test_analytics.sql` and `test_concurrency.py` only against the disposable DB | None to the live database |

**P3/P4 setup requirement.** A disposable database needs the migrations applied, and `test_analytics.sql` additionally needs `analytics.*` fact rows present, otherwise `CALL analytics.refresh_reporting_marts()` produces empty materialized views and the suite raises at `:216`/`:220` ("Materialized view … is empty after refresh!"). `scripts/generate_data.py --scale dev` would supply them — but note that the generator's own translation seed writes `'Apply Now'` for `btn.apply_job`/`en` and, because it uses `ON CONFLICT DO NOTHING`, will **not** overwrite the migration-seeded `'Apply for this Role'`. The migration value wins, which is exactly the §2.1 precedence rule.

**Note on `test_concurrency.py` and the disposable database.** The suite hardcodes the DB password at `tests/test_concurrency.py:22` and reads `DB_HOST`/`DB_PORT`/`DB_NAME`/`DB_USER` from the environment with `127.0.0.1`/`5432`/`talentra`/`talentra_admin` defaults. Pointing it at a disposable database therefore requires setting `DB_NAME` (and `DB_PASSWORD`) in the environment — it is parameterised by environment variable, so no code change is needed. **This was not done in this phase.**

### 4.5 Suite-by-suite safety determination method

Every row above was derived by reading the suite files, not by executing them:

| Signal | Command | Result |
|:--|:--|:--|
| `BEGIN;` per suite | `grep -cE "^\s*BEGIN;" tests/*.sql` | 1 for 20 files, 0 for `test_seed_master_data.sql` |
| `ROLLBACK;` per suite | `grep -cE "^\s*ROLLBACK;" tests/*.sql` | 1 for 19 files, 0 for `test_analytics.sql` and `test_seed_master_data.sql` |
| `COMMIT;` per suite | `grep -cE "^\s*COMMIT;" tests/*.sql` | **1 for `test_analytics.sql` only**; 0 for all 20 others |
| `INSERT` per suite | `grep -cE "INSERT INTO" tests/*.sql` | 7–20 per writing suite; **0** for `test_seed_master_data.sql` |
| DDL in suites | `grep -icE "drop \|truncate\|alter table\|create schema\|create table" tests/*.sql` | **0 for all 21 files** — no suite creates, alters, or drops schema objects |
| Mat-view refresh | `grep -nE "REFRESH MATERIALIZED VIEW\|CALL analytics" tests/*.sql` | `test_analytics.sql:204` and `:236` only |
| Seed dependency | `grep -lnE "master\.(skill\|country\|city\|employment_type\|work_type\|qualification\|industry\|language)" tests/*.sql` | 13 suites depend on the `004` seed |

**Two useful safety properties hold across all 21 SQL suites:** no suite contains DDL, and no suite contains a `TRUNCATE`. The only destructive-capable statement class present is `DELETE`, and it appears in 4 suites — `test_administration.sql` (1), `test_commercial.sql` (2), `test_security.sql` (2), and `test_analytics.sql` (7). The first three are inside a rolled-back transaction; only `test_analytics.sql` commits.

---

## 5. Benchmark artifact — stale "Speedup Factor" labelling (unresolved evidence issue)

**No benchmark artifact was edited, and no index benefit is claimed anywhere in this document.**

### 5.1 The issue, confirmed on disk

The committed artifacts are **methodology v1** — the pre-correction format. `benchmarks/results/benchmark_results.json` (178,289 bytes) has exactly five top-level keys:

```
$ grep -nE '^  "' benchmarks/results/benchmark_results.json
2:  "benchmark_timestamp": "2026-10-17T18:31:04Z",
3:  "engine": "PostgreSQL 17",
4:  "iterations": 10,
5:  "queries": [
3744:  "index_impact": [
```

There is **no** `methodology_version`, **no** `generated_at_utc`, and **no** `planner_method_comparison` block. The v2 harness writes to versioned filenames (`METHODOLOGY_TAG = "v2"`, `scripts/run_benchmarks.py:63`) that do not exist in this checkout — so **the corrected runner has never produced a committed artifact.**

The stale labelling is present in both files:

```
$ grep -nE "Speedup|speedup|index_impact" benchmarks/results/benchmark_summary.md benchmarks/results/benchmark_results.json
benchmarks/results/benchmark_summary.md:26:| Query | Target Index Structure | With Index (ms) | Without Index / SeqScan (ms) | Speedup Factor |
benchmarks/results/benchmark_results.json:3744:  "index_impact": [
benchmarks/results/benchmark_results.json:3750:      "speedup_factor": 0.95
benchmarks/results/benchmark_results.json:3757:      "speedup_factor": 5.0
benchmarks/results/benchmark_results.json:3764:      "speedup_factor": 0.46
```

### 5.2 Why this is an *evidence* issue, not a formatting issue

The v1 `index_impact` block attributes a **speedup** to a named index by comparing "With Index (ms)" against "Without Index / SeqScan (ms)". That framing is the specific claim the Phase 2C methodology correction retracted. The v2 harness replaced it with a **diagnostic planner-method comparison** that measures the cost of *denying* the planner every index access path — and `scripts/run_benchmarks.py:499-500` states the reason explicitly:

> "The record deliberately carries no `index_target` field and no `speedup` field: nothing in this comparison supports a claim that a named index produced a speedup."

A v1 "disabled" leg is **not** equivalent to "the schema without the index". It forbids the planner from choosing *any* index access path, which can yield a different and sometimes cheaper plan over a small table — which is exactly what the committed values show: `0.95` and `0.46` are ratios **below 1.0**, meaning the crippled plan was *faster* than the default plan. Labelling those as "Speedup Factor" inverts their meaning. The `5.02` ratio (recorded here as `5.0`) is the cost of *forbidding* `idx_candidate_application_job_status`, not the benefit of creating it.

`docs/performance-report.md` §2 was relabelled in Phase 2C to "Diagnostic: Cost of Disabling Index Access Paths" and states this distinction. **The documentation and the artifact therefore disagree** — the artifact is the more quotable of the two.

### 5.3 Resolution requires a separate, approved artifact regeneration

The v2 harness is designed to fix exactly this and to **protect the v1 artifact from being overwritten** — `tests/test_benchmark_harness.py` test 12 (`test_historical_artifacts_are_never_overwritten`) asserts that a new run writes to a versioned filename and leaves the legacy files byte-identical; test 14 asserts the committed artifact still lacks `methodology_version` and still contains `index_impact`.

So the correct resolution is **to run the v2 harness and commit the new versioned artifact alongside the v1 one** — not to hand-edit the v1 file. That requires:

1. A live database with a seeded dataset, since the harness opens a `readonly=True` session but issues `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` (`scripts/run_benchmarks.py:819`), which *executes* the underlying statements.
2. Explicit authorization, since Phase 3 forbade benchmarks without it and the follow-up forbids editing artifacts.
3. A decision on whether the v1 artifact should be retained, superseded, or archived.

**Until that regeneration happens, the v1 "Speedup Factor" figures must not be cited as evidence of index benefit.**

### 5.4 Additional artifact limitations carried forward

| # | Limitation | Evidence |
|:--|:--|:--|
| A-01 | 5 of 12 measured queries returned zero rows (Q03, Q04, Q05, Q08, Q09); their latencies measure the cost of an empty result set | `docs/performance-report.md:23-29` |
| A-02 | The v1 artifact used hardcoded `= 1` identifiers; the v2 fixture-discovery correction has not been applied to any committed artifact | `scripts/run_benchmarks.py:119-231`; no `fixture` key in the artifact |
| A-03 | No server configuration is recorded, so the 100% buffer-hit ratio cannot be attributed to any `shared_buffers` value | `grep -rnE "shared_buffers\|pg_settings" scripts/run_benchmarks.py` → no output |
| A-04 | No dataset scale is recorded; the "10,000 candidates / 50,000 applications" figures come from the `medium` seed preset, not the artifact | artifact's 5 top-level keys |
| A-05 | No benchmark was re-run in this phase | — |

---

## 6. Command-execution status

### 6.1 Retried in this follow-up

| Command | Attempts | Result |
|:--|:--:|:--|
| `python3 tests/test_benchmark_harness.py` | 1 in this follow-up (plus ~10 in Phase 3) | **BLOCKED** — `talentra-minimax-free is temporarily unavailable, so auto mode cannot determine the safety of Bash right now.` |

The suite is **database-free** (step 4, row 23) and was established safe to run; it was attempted because command execution had been unavailable throughout Phase 3 and it is the one suite that needs no database. It remains **BLOCKED**. **No bypass was attempted.** The suite's 14 tests are therefore **UNVERIFIED** — this follow-up does not claim they pass.

### 6.2 Checks that succeeded in this follow-up

`git status --short`, `git diff --stat`, `git rev-parse HEAD`, `git branch --show-current`, `git diff --check`, `git diff --no-index --check /dev/null docs/phase3-followup-findings.md`, and all the `grep`/`sed` reads cited throughout this document.

### 6.3 Not run

`scripts/run_all_tests.py`, `scripts/run_benchmarks.py`, `scripts/generate_data.py`, `scripts/validate_data.py`, all 21 SQL suites, `test_concurrency.py` — none executed. No `EXPLAIN ANALYZE`, no `INSERT`/`UPDATE`/`DELETE`/`TRUNCATE`/`DROP`/`ALTER`/`CREATE`/`REFRESH`, no container or volume operation.

---

## 7. Follow-up summary

| Item | Status |
|:--|:--|
| Working tree inspected; all changes and untracked files preserved | ✅ |
| D-01 — RG8 English-fallback value corrected | ✅ `docs/rule-compliance.md:113` now states `'Apply for this Role'`, with the precedence rule and precondition explained |
| D-02 — "Cyrillic" script claim corrected | ✅ `docs/rule-compliance.md:116` now restricts the claim to Latin and Devanagari, names the seeded language sets, and locates the one real Cyrillic literal in `master.language` |
| Tax-ID security assessment | ✅ §3 — 9 risks, 5 protection options with a recommendation, 5 access-control requirements, 6 key-management requirements, 9 migration considerations, 11 test requirements. **No encryption implemented, no schema changed** |
| Test-execution matrix for all 23 suites | ✅ §4 — target, write behaviour, transaction handling, persistent side effects, prerequisites, and disposable-database safety for every suite; 4 safe execution plans |
| Benchmark harness test retried | ⚠️ **BLOCKED** — recorded as blocked, not bypassed. Suite remains **UNVERIFIED** |
| Stale "Speedup Factor" labelling documented as an unresolved evidence issue | ✅ §5 — confirmed on disk, explained, and routed to a separately approved regeneration. **No artifact edited, no index benefit claimed** |
| Phase 3 report updated with follow-up findings | ✅ §8 |
| `git diff --check` and final diff review | ✅ §9 |

---

## 8. Update to `docs/phase3-implementation-verification-report.md`

The Phase 3 report's §5 findings D-01 and D-02 are **resolved by this follow-up** and are marked accordingly below. Everything else in the Phase 3 report stands unchanged.

### 8.1 Status of the two §5 findings

| Finding | Phase 3 status | Follow-up status |
|:--|:--|:--|
| **D-01** — RG8 English fallback documented as `'Apply Now'`; authoritative value is `'Apply for this Role'` | Open | ✅ **RESOLVED** — corrected in `docs/rule-compliance.md:113`; see §2.2 of `docs/phase3-followup-findings.md` |
| **D-02** — the "Cyrillic" script claim has no UI-translation basis | Open | ✅ **RESOLVED** — corrected in `docs/rule-compliance.md:116`; see §2.3 of `docs/phase3-followup-findings.md` |

### 8.2 Status of the Phase 3 risks

| Risk | Phase 3 status | Follow-up status |
|:--|:--|:--|
| R-01 — every test suite UNVERIFIED | Open | ⚠️ **Unchanged.** The database-free suite was retried and is still **BLOCKED**; the 22 database-dependent suites were not run. A safe execution matrix now exists (`docs/phase3-followup-findings.md` §4) but no suite was executed |
| R-02 — live schema UNVERIFIED | Open | ⚠️ **Unchanged.** Catalog queries remain blocked |
| R-03 — no RLS, no roles, one superuser | Open | ⚠️ **Unchanged** (implementation), but now has a full assessment: `docs/phase3-followup-findings.md` §3.4 |
| R-04 — tax IDs stored in plaintext | Open | ⚠️ **Unchanged** (implementation) — assessment delivered in `docs/phase3-followup-findings.md` §3. **No encryption implemented, as instructed** |
| R-05 — ledger integrity is validator-enforced | Open | ⚠️ Unchanged |
| R-06 — session token hashing has no enforced algorithm | Open | ⚠️ Unchanged |
| R-07 — append-only tables are `TRUNCATE`-able | Open | ⚠️ Unchanged |
| R-08 — benchmark artifact still presents a retracted "speedup" framing | Open | ⚠️ **Unchanged** — documented as an unresolved evidence issue in `docs/phase3-followup-findings.md` §5, with the resolution path (v2 regeneration) specified. **No artifact edited** |
| R-09 — two residual documentation defects | Open | ✅ **RESOLVED** — both corrected |
| R-10 — `test_concurrency.py` accumulates state; `test_analytics.sql` commits | Open | ⚠️ Unchanged, but now precisely characterised in the execution matrix |
| R-11 — concurrent workstream writing to the repository | Open | ⚠️ **Unchanged** — the workstream has continued (7 further untracked documents; `docs/competitive-benchmark.md` expanded). Its files were not touched |

### 8.3 Amendment to §6.1 of the Phase 3 report

The Phase 3 report's security finding on tax identifiers is **confirmed and extended** by this follow-up's assessment. Two material additions:

1. **The plaintext value is a lookup key.** `UNIQUE (country_id, identifier_type, identifier_value)` (`db/migrations/013_create_organization_extensions.sql:83-84`) means the cleartext identifier appears in the index and is used for equality predicates. This is a **hard constraint** on the encryption design: random-nonce encryption cannot preserve the uniqueness constraint without a separate blind-index column. It was not identified in the Phase 3 summary.
2. **No transport encryption and no at-rest encryption for the volume.** `docker-compose.yml` declares no `ssl` configuration and the `talentra_pgdata` named volume has no encryption options. The loopback port binding (`127.0.0.1:5432`) is the only control limiting network exposure.

### 8.4 Amendment to §7 of the Phase 3 report

Benchmark limitation **B-01/B-02** is confirmed against the files on disk and is escalated from "documentation/artifact disagree" to a **named unresolved evidence issue** with a specified resolution path: regenerate under the v2 harness into a new versioned artifact, leaving v1 intact. The v2 harness already provides the protection — `tests/test_benchmark_harness.py` test 12 asserts the historical artifact is never overwritten — but the regeneration itself requires a live seeded database and explicit authorization.

### 8.5 Amendment to §10.2 of the Phase 3 report

The final working-tree status in the Phase 3 report is superseded by the status in `docs/phase3-followup-findings.md` §1 and §9.2, which reflect the further progress of the concurrent workstream.

---

## 9. Final review

### 9.1 Files changed in this follow-up

| File | Change |
|:--|:--|
| `docs/rule-compliance.md` | **Modified** — the two RG8 corrections (§2). This is the only pre-existing file touched |
| `docs/phase3-followup-findings.md` | **Created** — this document |
| `docs/phase3-implementation-verification-report.md` | **Modified** — §8 update (§7 of this document) |

**No other file was created, modified, moved, or deleted.** Specifically not touched: all 19 migrations, `scripts/*` (all four), `tests/*` (all 23, including the user-owned `tests/test_constraints.sql`), `benchmarks/results/*`, `docker-compose.yml`, `.env`, `.git-initial-backup/`, and every document belonging to the concurrent workstream.

### 9.2 Final working-tree status

```
 M README.md
 M docs/architecture.md
 M docs/competitive-benchmark.md
 M docs/data-dictionary.md
 M docs/integration-boundaries.md
 M docs/performance-report.md
 M docs/rule-compliance.md
 M docs/threat-model.md
 M scripts/run_all_tests.py
 M scripts/run_benchmarks.py
 M tests/test_constraints.sql
?? .git-initial-backup/
?? docs/audit-event-matrix.md
?? docs/exceptions.md
?? docs/feature-inventory.md
?? docs/nfr-register.md
?? docs/personas.md
?? docs/phase2b-query-performance-validation.md
?? docs/phase2c-documentation-audit.md
?? docs/phase2d-documentation-correction-report.md
?? docs/phase2e-documentation-correction-report.md
?? docs/phase3-followup-findings.md
?? docs/phase3-implementation-verification-report.md
?? docs/requirements.md
?? docs/scope-assumptions.md
?? docs/source/
?? docs/workflows.md
?? tests/test_benchmark_harness.py
```

`docs/rule-compliance.md` remains at 48 changed lines in `git diff --stat` — coincidentally the same figure as the baseline, because the two corrections replaced two lines with two longer lines of the same line count. The substantive change is visible in the diff itself.

### 9.3 Explicit confirmations

- ✅ **No database objects or data were changed.** No `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`, `DROP`, `ALTER`, `CREATE`, `REFRESH MATERIALIZED VIEW`, or `EXPLAIN ANALYZE`. No container or volume operation. No persistent-write test was run against the existing database.
- ✅ **No user changes were discarded.** Every pre-existing modification and untracked file is present. `.git-initial-backup/` was not read, modified, or deleted. `tests/test_constraints.sql` was read only. The concurrent workstream's files were not touched.
- ✅ **Nothing was committed, pushed, reset, cleaned, or stashed.** HEAD remains `7ac5b2bdeb731610b8bd2c0282608e6c93d4b1df` on `feature/your-task`; the working tree remains unstaged.
- ✅ **No migration, schema, application code, test file, or benchmark artifact was modified.** The two RG8 corrections are documentation only. The tax-ID assessment is a design document — no encryption was implemented and no column type was changed.
- ✅ **No test is claimed to have passed.** The database-free harness suite was retried and is **BLOCKED**; its 14 tests remain **UNVERIFIED**. No other suite was executed.
- ✅ **No index benefit is claimed.** The v1 "Speedup Factor" figures are documented as an unresolved evidence issue and are explicitly not to be cited as evidence of an index benefit.
