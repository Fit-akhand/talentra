# Talentra Phase 4.1 — Independent Tax Identifier Security Design Audit

**Date**: 2026-10-21
**Phase**: 4.1 — Independent audit of `docs/phase4-tax-id-security-design.md`
**Branch / HEAD**: `feature/your-task` @ `7ac5b2bdeb731610b8bd2c0282608e6c93d4b1df`
**Audited artefact**: `docs/phase4-tax-id-security-design.md` (untracked, created in Phase 4)
**Nature of this phase**: **audit only.** No encryption was implemented. The database was not connected to or modified. The Phase 4 design document was **not edited** — every defect found is recorded here instead.
**Method**: independent re-verification against the repository, plus independent cryptographic assessment. The Phase 4 document's own conclusions were **not** treated as evidence; each material claim was re-checked against source.

---

## 0. Executive Verdict

# ⚠️ NEEDS REVISION

**The design is substantively sound in its central architectural choice and its factual survey is close to fully accurate. But it is not yet decision-ready, for two independent reasons.**

**Reason 1 — a factual defect in the design's own risk characterisation.** The design ranks the `pg_restore ... || true` behaviour it *noticed in the backup script* as a minor parenthetical, but does not identify what it actually means: **`scripts/backup_restore.sh:42` discards the exit status of `pg_restore` unconditionally, and the script then prints `[PASS] Restoration completed` regardless of whether the restore succeeded.** The Phase 4 design cites this script as evidence for a "restore" baseline and proposes a migration whose rollback strategy (§6.6) is *"restore from backup"*. **The one mechanism the design depends on for its irreversible step is currently capable of reporting success on a failed restore.** That is a design-blocking defect in the migration plan, and it was not surfaced as such in Phase 4.

**Reason 2 — the design's central factual claim about test coverage is wrong in a way that matters.** The design asserts (§4.1, §7.3) that `tests/test_constraints.sql` *"is the suite most likely to assert on the uniqueness constraint"* and that it *"must be re-run."* **No test anywhere in this repository asserts the `uq_organization_identifier_val` uniqueness constraint.** The constraint name appears in exactly one place in the entire repository — its own `CREATE TABLE` in migration 013. The two inserts in `tests/test_organization_extensions.sql` never attempt a duplicate, and the row id they return (`v_ident_id`, `:212`) is **assigned and never read back**. The design's §6.3 states *"The current `UNIQUE (country_id, identifier_type, identifier_value)` means no exact duplicates exist today"* — that is a **correct statement of the constraint's semantics but an invalid inference about the data**, because nothing in the repository creates the data and nothing in the repository verifies the constraint. The design partly acknowledges this (F-11, F-13) but then relies on the constraint's existence as a backstop in the migration plan without ever noting that **the backstop is currently untested**.

**Neither defect undermines the recommended architecture.** Application-layer AEAD with a separate keyed blind index remains the right recommendation, and I concur with it. The defects are in the *evidence discipline* and in the *rollback safety argument* — both of which are fixable by editing the design document, which this phase is forbidden to do.

### 0.1 What the audit confirmed as correct

| Phase 4 claim | Audit result |
|:--|:--|
| `identifier_value VARCHAR(100) NOT NULL` at `013:75` | ✅ **CONFIRMED** — exact |
| `UNIQUE (country_id, identifier_type, identifier_value)` at `013:83-84` | ✅ **CONFIRMED** — exact |
| Only migration 013 defines the table | ✅ **CONFIRMED** — `grep -rln` across `db/migrations/` returns exactly one file |
| No trigger, function, view, or rule touches the table | ✅ **CONFIRMED** — all 6 triggers in the repository are at `009:205`, `012:290`, `015:126`, `016:130`, `017:374`, `017:444`; none is on `organization_identifier` |
| No benchmark query, validator rule, or generator path touches the table | ✅ **CONFIRMED** — independently re-derived |
| `scripts/backup_restore.sh:56-64` omits the table from the parity list | ✅ **CONFIRMED** — and confirmed for `backup_restore.ps1:66-73` as well |
| Zero RLS policies, zero grants, zero roles | ✅ **CONFIRMED** |
| `talentra_reporting` is granted only `analytics` and `master` | ✅ **CONFIRMED** — `threat-model.md:75-76` |
| `talentra_admin` is a superuser, so RLS would not apply to it | ✅ **CONFIRMED** by inference from PostgreSQL semantics — and the threat model contains **zero** occurrences of `FORCE ROW LEVEL SECURITY`, so the design's warning is correct and important |
| The recommended architecture (Option A) is appropriate | ✅ **CONCUR** — with the refinements in §3 |
| The Phase 3 documents' findings are quoted accurately | ✅ **CONFIRMED** on every point checked |

---

## 1. Baseline

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
?? docs/phase3-followup-findings.md
?? docs/phase3-implementation-verification-report.md
?? docs/phase4-tax-id-security-design.md
?? docs/requirements.md
?? docs/scope-assumptions.md
?? docs/source/
?? docs/workflows.md
?? tests/test_benchmark_harness.py

$ git diff --stat | tail -1
 11 files changed, 1398 insertions(+), 357 deletions(-)
```

**Preservation confirmed.** `.git-initial-backup/` was listed (`ls -la`) and **not read into, modified, or deleted** — it is a bare git repository directory (`HEAD`, `config`, `objects/`, `refs/`, `hooks/`). `tests/test_constraints.sql` was read in full and not modified. The concurrent Phase 1 documents (`docs/source/`, `requirements.md`, `scope-assumptions.md`, `feature-inventory.md`, `audit-event-matrix.md`, `exceptions.md`, `nfr-register.md`, `personas.md`, `workflows.md`) were not touched. The Phase 4 design document was not edited.

---

## 2. Independent Verification of the Phase 4 Design's Material Claims

### 2.1 Column definition, constraints, foreign keys — CONFIRMED

Read directly from `db/migrations/013_create_organization_extensions.sql:70-139`:

| Line | Object | Audit finding |
|:--|:--|:--|
| `75` | `identifier_value VARCHAR(100) NOT NULL` | ✅ **CONFIRMED** — the sole column definition. There is **no length `CHECK` constraint** on it; the `VARCHAR(100)` type itself is the only length enforcement, and `NOT NULL` is the only nullability rule |
| `83-84` | `uq_organization_identifier_val UNIQUE (country_id, identifier_type, identifier_value)` | ✅ **CONFIRMED** — note `organization_id` is **NOT** in the key. **A single tax identifier may belong to only one organisation, globally within a `(country_id, identifier_type)` group** |
| `86-90` | `fk_organization_identifier_organization` → `recruitment.organization`, `ON UPDATE RESTRICT ON DELETE CASCADE` | ✅ **CONFIRMED** — deleting an organisation **cascades** to delete its identifier rows. The design does not mention cascade deletion; see §2.6 |
| `92-96` | `fk_organization_identifier_country` → `master.country`, `ON DELETE RESTRICT` | ✅ **CONFIRMED** |
| `98-102` | `fk_organization_identifier_verified_by` → `core.user_account`, `ON DELETE SET NULL` | ✅ **CONFIRMED** |
| `104-115` | `ck_organization_identifier_type` — 7 allowed values | ✅ **CONFIRMED** |
| `117-125` | `ck_organization_identifier_status` — 4 allowed values | ✅ **CONFIRMED** |
| `127-132` | `ck_organization_identifier_verification_consistency` | ✅ **CONFIRMED** |
| `135-136` | `idx_organization_identifier_org ON (organization_id)` | ✅ **CONFIRMED** |
| — | **Triggers / functions / views / rules on this table** | ✅ **CONFIRMED absent** — all 6 repository triggers enumerated and none is on this table |

**Additional finding not in the Phase 4 design:** there is **no `COLLATE` clause** anywhere in `db/migrations/` and **no non-default collation** is created. The uniqueness constraint therefore uses the database's default collation. PostgreSQL's default collation for `VARCHAR` is the one from the database's `LC_COLLATE`/provider — for a stock `postgres:17` image this is typically `C.UTF-8` or `en_US.UTF-8` depending on the base image locale. **Under a nondeterministic ICU collation, string equality is case- and accent-insensitive; under `C` or `en_US.UTF-8` it is byte-exact.** The design's canonicalisation proposal therefore interacts with a *database-level* behaviour it did not examine. This is a real audit finding — see §3.1.

### 2.2 Test isolation and write behaviour — CONFIRMED, with a coverage gap found

`tests/test_organization_extensions.sql`:

| Line | Finding |
|:--|:--|
| `4` | `BEGIN;` — the file opens a transaction |
| `299` | `ROLLBACK;` — the file closes it. **Every write is discarded** |
| `120`, `167`, `216`, `250` | Nested `BEGIN … EXCEPTION … END` blocks for expected-failure cases |
| `168-183` | The **deliberately-failing** insert: `'gstin'`, `'29AAAAA0000A1Z5'`, `verification_status = 'verified'`, `verified_at = NULL` — expected to raise `check_violation` |
| `194-212` | The **valid** insert, same identifier value, with `verified_at = CURRENT_TIMESTAMP` |
| `212` | `RETURNING id INTO v_ident_id;` — and `v_ident_id` is **declared at `:17` and never read again** |

**Audit finding A-1 (material):** the identifier row inserted at `:194-212` is **never read back, never asserted on, and never used**. The test proves the `ck_organization_identifier_verification_consistency` constraint fires. It proves **nothing** about `uq_organization_identifier_val` — no duplicate is ever attempted anywhere in the repository.

**Audit finding A-2 (material):** `grep` for the constraint name across the repository returns exactly one hit: **its own definition in migration 013**. There is **no test, validator rule, or script that exercises it**.

**Audit finding A-3:** `tests/test_constraints.sql` — read in full (194 lines) — inserts into `core.user_account`, `profile.candidate_profile`, `recruitment.organization`, `profile.candidate_location`, `recruitment.job_posting` (×2), and `gig.gig_request`. It **never touches `recruitment.organization_identifier`**. It does exercise uniqueness on `uq_candidate_location_current` (`:113-125`), which shows the *pattern* for a uniqueness test exists in the repository but was not applied here. The Phase 4 design's §7.3 statement that `test_constraints.sql` *"is the suite most likely to assert on the uniqueness constraint"* is therefore **factually incorrect** — it asserts on a different table's uniqueness. The file **is** rolled back (`:6` `BEGIN;`, `:193` `ROLLBACK;`) and remains safe to run after the migration, but it provides **no protection** for the identifier constraint.

**Audit finding A-4:** `tests/test_administration.sql:81,98,113` and `tests/test_security.sql:148,162` contain `credential_identifier` — these are `core.user_credential.credential_identifier` (an API-key identifier), **not** `organization_identifier`. No confusion here; recorded so the distinction is not lost.

### 2.3 Backup / restore coverage — CONFIRMED, and worse than the design states

`scripts/backup_restore.sh`:

| Line | Content | Audit assessment |
|:--|:--|:--|
| `28` | `pg_dump -U "$DB_USER" -Fc -d "$SOURCE_DB" -f "$BACKUP_FILE"` | The dump **does** include `organization_identifier` — it is a full-database custom-format dump |
| `42` | `pg_restore … --no-owner --role="$DB_USER" "$BACKUP_FILE" \|\| true` | **🔴 CRITICAL — see §5.1.** The `\|\| true` swallows the `pg_restore` exit status unconditionally |
| `46` | `echo "[PASS] Restoration completed in ${restore_elapsed}s"` | Printed **regardless of whether the restore succeeded** |
| `56-64` | The `tables=( … )` parity array | **CONFIRMED: 7 tables, `recruitment.organization_identifier` is not among them** |
| `66-75` | The parity loop | Compares `COUNT(*)` between source and recovery for those 7 tables only |
| `79-80` | `DROP DATABASE IF EXISTS $RECOVERY_DB` and `rm -f "$BACKUP_FILE"` | The recovery DB and the dump file are **destroyed at the end of the run** |

`scripts/backup_restore.ps1` has the same 7-table list (`:66-73`). It **does not** have `|| true` — but it has `$ErrorActionPreference = "Stop"` (`:11`), which does **not** apply to native executables' exit codes in Windows PowerShell, so the `pg_restore` failure is likewise **not** reliably surfaced. Line `:48` even documents the issue: *"pg_restore returns exit code 0 or 1 for minor warnings; we run inside container"* — an accurate note that nonetheless results in the exit code being **ignored**.

**Audit finding A-5 (material):** the backup parity check **cannot establish** that `organization_identifier` was backed up or restored. If the restore silently omitted the table, or restored it empty, **the script would still print `RTO VALIDATION PASSED` and exit 0.** §5 covers this in full.

### 2.4 Generator, validator, benchmark queries, seeds — CONFIRMED

| Claim | Audit result |
|:--|:--|
| `scripts/generate_data.py` never populates `organization_identifier` | ✅ **CONFIRMED** — the `COPY` targets are `recruitment.organization` (`:325`), `recruitment.organization_location` (`:340`), `recruitment.job_posting` (`:366`), `recruitment.job_skill_requirement` (`:381`). The other 6 `recruitment.organization*` references are `SELECT id FROM recruitment.organization` (`:330`, `:501`, `:637`, `:720`, `:750`) and `ANALYZE recruitment.organization` (`:837`). **None names `organization_identifier`** |
| `scripts/validate_data.py` has no rule on the table | ✅ **CONFIRMED** — the only `organization` occurrence is `:114`, an `information_schema` column-name list for the RG2 surrogate-key check. RG6 (`:208-220`) reads `core.user_account` only |
| No benchmark query touches the table | ✅ **CONFIRMED** — `db/queries/02` and `:08` join `recruitment.organization` for `o.name`; `05` and `:06` use `organization_id`. All 12 queries enumerate cleanly without the identifier table |
| `db/seeds/*.sql` are empty | ✅ **CONFIRMED** — `wc -c` reports 0 bytes for both `development_data.sql` and `reference_data.sql` |
| Only 2 write sites for the table in the whole repository | ✅ **CONFIRMED** — `tests/test_organization_extensions.sql:168` and `:194` |
| `audit.audit_event` is written in exactly 2 places | ✅ **CONFIRMED** — `db/migrations/015:221` and `:317`, neither concerning identifiers. Plus 3 test-suite inserts (`test_administration.sql:185`, `test_security.sql:101`) |
| `audit.audit_event` has `old_values_json` / `new_values_json JSONB` | ✅ **CONFIRMED** — `012:238-239` |
| `audit.system_error_log` has unredacted `error_message TEXT`, `stack_trace TEXT`, `context_json JSONB` | ✅ **CONFIRMED** — `012:300-303` |

### 2.5 Zero-implementation claims — CONFIRMED

| Claim | Result |
|:--|:--|
| Zero `GRANT` / `REVOKE` / `CREATE ROLE` / `CREATE USER` | ✅ no output |
| Zero `CREATE POLICY` | ✅ no output |
| `app.current_user_id` / `app.current_org_id` never set | ✅ no `current_setting` / `set_config` in `db/migrations/` |
| Only `btree_gist` extension | ✅ **CONFIRMED** — `014:8`, `017:8` are the only two `CREATE EXTENSION` statements in the repository |
| No crypto primitives anywhere | ✅ no output for the crypto greps |
| `docker-compose.yml` has no `ssl` configuration | ✅ **CONFIRMED** — the file is 22 lines; the only keys are `image`, `container_name`, `restart`, `environment` (3 vars), `ports`, `volumes`, `healthcheck`. **No `command:` override**, so the container runs stock `postgres:17` defaults |
| Port bound to `127.0.0.1:5432` | ✅ **CONFIRMED** — `docker-compose.yml:12` |
| `talentra_pgdata` is a plain named volume | ✅ **CONFIRMED** — `docker-compose.yml:13-14`, `:21-22`, no `driver_opts` |

### 2.6 Findings the Phase 4 design did not include

| # | Finding | Evidence | Significance |
|:--|:--|:--|:--|:--|
| **A-6** | **`ON DELETE CASCADE` from `recruitment.organization`** | `013:86-90` | Deleting an organisation **destroys its identifier rows**. After encryption, a cascade delete is a *cryptographic erase* of the identifier — arguably a feature — but it is **not audited** by anything, and there is no soft-delete path. The design's §4.7 audit requirements do not mention deletion. An owner decision is needed on whether identifier deletion should be audited and/or blocked |
| **A-7** | **The unique key omits `organization_id`** | `013:83-84` | A tax identifier is unique **per `(country_id, identifier_type)`, not per organisation.** The design's §3.4 blind-index formula correctly reproduces this by binding `country_id` and `identifier_type` into the MAC input and excluding `organization_id` — this is right, and worth stating explicitly because a reader might otherwise "fix" it by adding `organization_id` and **weaken** the guarantee |
| **A-8** | **No non-default collation anywhere in the repository** | `grep -rn "COLLATE\|CREATE COLLATION" db/migrations/*.sql` → no output | The uniqueness constraint's case-sensitivity is a **deployment/database-locale property**, not a schema property. See §3.1 |
| **A-9** | **`v_ident_id` is dead** | `tests/test_organization_extensions.sql:17`, `:212` | Evidence the identifier row was never intended to be read back. Reinforces A-1 |
| **A-10** | **The design's §2.3 states `audit.audit_event` is written "in exactly two places in the whole repository"** | `db/migrations/015:221`, `:317` are the only *migration* writers, but `tests/test_administration.sql:185` and `tests/test_security.sql:101` also insert | **Imprecise, not wrong in substance.** The design says "in exactly two places in the whole repository" where it should say "in two places in the migrations". Three test suites also write audit rows. Minor precision defect |
| **A-11** | **`pg_restore` exit-code handling in the PowerShell script** | `scripts/backup_restore.ps1:11`, `:48-49` | `$ErrorActionPreference = "Stop"` does not trap native-executable exit codes, and the script does not inspect `$LASTEXITCODE`. The comment at `:48` shows the author **knew** about the non-zero exit code and did not act on it. This strengthens A-5: the *sh* script's `|| true` and the *ps1* script's unchecked exit code are the **same defect in two languages** |

### 2.7 Design claims that are INFERRED rather than CONFIRMED

The audit distinguishes these carefully. The Phase 4 design's F-table is mostly honest about this, but three of its labels overstate the evidence.

| Design claim | Design's label | **Audit's label** | Why the audit differs |
|:--|:--|:--|:--|
| F-12 "A consuming application exists that reads/writes this column" | ASSUMPTION | **INFERRED — reasonable, and the strongest inference available** | The schema's `verification_status`/`verified_at`/`verified_by_user_account_id` triple (`013:76-78`) plus `docs/integration-boundaries.md:88` both point to a real verification workflow. The design is right to treat it as an assumption. **The audit concurs.** Note it is an inference about *intent*, not about *code*, and no such code is in the repository |
| F-13 "The volume may currently contain zero rows, or many" | ASSUMPTION | **INFERRED, and the "zero rows" half is the more likely half** | No seed path populates the table, so a *seeded* database has zero rows. But a *production* database populated by the inferred application could have many. The design is right |
| F-14 "No third-party verification provider is integrated" | CONFIRMED | **CONFIRMED for this repository; INFERRED for the system** | `docs/integration-boundaries.md:88` states the only verification state in the schema is `verification_status`. That is a *repository* fact. A provider could exist outside it. The design's wording says "for this repository" — **correct as written** |
| §6.3 "The current `UNIQUE` means no exact duplicates exist today" | asserted | **INFERRED, and only weakly supported** | The constraint *would* prevent duplicates, but **nothing in the repository creates the data and nothing tests the constraint** (A-1, A-2). If the table is populated by an external application that bypasses or predates the constraint, duplicates could exist. The design's own §6.3 later concedes this ("The backfill must detect these canonical collisions") — **so the document is internally inconsistent on this point** |
| §4.4 "AEAD ... prevents a row-swap / cross-tenant graft" | asserted | **INFERRED — correct, with a caveat** | Binding `organization_id` into the AAD does prevent transplanting a ciphertext into a different row. **But the design's AAD list includes `organization_id`, and `organization_id` is mutable** (a row's `organization_id` can be updated). The AAD must therefore be treated as immutable, and the design never states that constraint. See §3.5 |

---

## 3. Cryptographic Design Challenge

The Phase 4 §4.4 recommends AES-256-GCM with a random 96-bit IV, a 128-bit tag, and AAD of `organization_id ‖ country_id ‖ identifier_type ‖ key_version`, plus a full-width HMAC-SHA-256 blind index over `country_id ‖ identifier_type ‖ canonical_form` under a separate key. **I concur with this construction.** The following are the challenges, the identified failure modes, and the refinements.

### 3.1 Challenge: normalisation — and the collation interaction the design missed

**The design's position:** canonicalise per `identifier_type`; GSTIN uppercase + strip separators + validate the mod-36 check digit; `'other'` trimmed and case-folded only; the rules are approval item D-6.

**The audit's assessment:** the *approach* is right and the design correctly identifies that canonicalisation is load-bearing (§3.4) and correctly warns that a wrong rule silently defeats uniqueness.

**Three challenges the design did not address:**

1. **The check-digit idea is right but under-specified.** GSTIN's 15th character is a mod-36 check digit over the first 14. The design says "validate the 15th-character mod-36 check digit" — but it does not say whether a **failed check digit is a rejection or a normalisation**. If it is a rejection, the API must return a validation error and the value must not be stored; if it is a normalisation, a malformed identifier could be silently "fixed" into a different valid one. **These are materially different behaviours and the design does not distinguish them.** Owner decision needed.

2. **Under a nondeterministic collation the *existing* constraint may already be case-insensitive.** PostgreSQL's `UNIQUE` constraint uses the column's collation for comparison. If the database's default collation is a nondeterministic ICU collation, `'29AAAAA0000A1Z5'` and `'29aaaaa0000a1z5'` are **already equal** to the existing constraint — meaning the current database may already reject the lowercase variant, and the design's §3.4 premise that *"without canonicalisation, these produce different blind indexes and the uniqueness constraint is defeated"* would be **comparing against a stricter existing behaviour than it assumes**. Under the common `C` or `en_US.UTF-8` default the constraint is byte-exact and the design's premise holds. **The actual behaviour is a property of the deployed database's locale, which is not knowable from the repository.** This must be checked against the live database before the canonicalisation rules are written, because it determines whether canonicalisation is a *new* behaviour or a *preservation* of existing behaviour. This is an audit finding, not a Phase 4 error — the design simply did not examine it.

3. **The uniqueness semantics change if canonicalisation is applied to the stored value but the constraint currently compares raw bytes.** Concretely: if the live table holds both `'29AAAAA0000A1Z5'` and `'29aaaaa0000a1z5'` — possible only if the collation is case-sensitive *and* the constraint was somehow bypassed — then canonicalisation **collapses them into one**, which is a *stricter* constraint than today. The design's §6.3 addresses this as "canonical collisions" and requires the backfill to fail loudly. **That is correct** and the audit endorses it. The design should additionally record the *inverse* risk: canonicalisation can also make a previously-accepted pair collide, and a backfill that "fails loudly" on a production table leaves the migration blocked with no automated remedy. A resolution policy (reject, quarantine for manual review, or namespace) is an owner decision.

### 3.2 Challenge: uniqueness — is the composite blind-index constraint equivalent?

**Audit assessment: yes, the design's constraint is exactly equivalent, and it correctly omits `organization_id`.** This is the strongest part of the design.

The existing key is `(country_id, identifier_type, identifier_value)`. The design's replacement is `(country_id, identifier_type, identifier_value_bidx)` where `bidx = HMAC(K_bidx, country_id ‖ 0x00 ‖ identifier_type ‖ 0x00 ‖ canonical_form)`.

- The same three leading components are preserved, and the fourth is a **deterministic function of the third** (plus the two leading components, redundantly but usefully). So the replacement key is a **bijective image of the original key's semantics under the canonicalisation function** — subject only to HMAC collision probability.
- **Binding `country_id` and `identifier_type` into the MAC input is redundant for uniqueness** (they are already separate columns in the key) but is **not redundant for leakage control** — it prevents an observer who holds the bidx column from correlating the same identifier across two different `(country_id, identifier_type)` groups. This is good design and the design document states the reason (§3.4). The audit **concur**.
- **The design must state explicitly that `organization_id` is deliberately excluded.** A future reader could plausibly "correct" this by adding `organization_id` to the key — which would silently permit the same GSTIN on two organisations, weakening the guarantee that the current constraint provides. This is audit finding A-7 and should be recorded as an explicit design invariant with a warning comment in the migration.
- **What changes semantically:** uniqueness moves from *byte-exact on the raw string* to *exact on the canonical form*. Under a case-sensitive collation, the new constraint is **stricter** (it will reject case/spacing variants the old one accepted). That is the intended direction, but it is a **behavioural change** that a consuming application could trip over. It needs to be in the release notes, and it is currently buried in §3.4/§6.3 of the design rather than flagged as a behaviour change.

### 3.3 Challenge: key separation

**Audit assessment: the design's separation is correct and standard, and it is stated for the right reason.** `K_dek ≠ K_bidx`, both derived from `K_root` via distinct HKDF info strings.

- A `K_bidx` leak exposes **equality structure only** (which rows share an identifier) but not the identifiers and not the ciphertext. A `K_dek` leak exposes **both** identifiers and ciphertext, and — critically — also lets an attacker **forge** the blind index for any identifier they can guess, so they could *insert* a colliding bidx and thereby **deny service to a legitimate organisation** (a uniqueness-conflict denial of service). The design does not mention this forged-bidx DoS. It is a minor addition to the threat set, and it is *partially* mitigated by the fact that a `K_dek` leak is already catastrophic. Recording it improves the completeness of the adversary analysis.
- **One gap:** the design's key-derivation sketch (§4.1) shows `K_root` wrapping `K_dek` and `K_bidx` but §4.4 then says the DEK and blind-index key are "derived from `K_root` via distinct HKDF info strings". **These are two different key-management models** — *wrapping* (a KMS envelope operation, where `K_root` encrypts the DEK) versus *derivation* (HKDF, where `K_root` is never exported and the DEK is computed from it). They are not mutually exclusive, but the design uses the words interchangeably without stating which is primary. The distinction matters operationally: **derivation** means a KMS can be used without ever being able to export or unwrap a DEK (the KMS holds only `K_root`), whereas **wrapping** means the KMS can unwrap the DEK. For "the database must never hold a key" both work, but for "the KMS must never be able to decrypt a row" only **derivation** works. **The design should state which model is intended, because it changes the threat model against the KMS operator.** This is audit finding A-12.

### 3.4 Challenge: rotation

**Audit assessment: the design handles ciphertext rotation reasonably, but under-specifies blind-index rotation, which is the operationally harder half.**

The design's §6.2 step 5 swaps the unique constraint. §4.3 says blind-index rotation "is a heavier operation than ciphertext rotation and should be done less often, or only on suspected compromise". That is directionally right but the *mechanics* are missing:

- **During blind-index rotation, two bidx columns must coexist** (old and new key version), and the **unique constraint can only exist on one of them at a time.** So the constraint must be *dropped and re-created* on the new column, or a **composite constraint on both columns** must be used temporarily. The design does not address this. It has a *dual-write* story for ciphertext (§6.2 step 2) but **no dual-index story**.
- **A dual-write period with two bidx columns is unsafe if both carry a unique constraint**: a legitimate duplicate would be rejected by the *new* column while the *old* column still holds the old key's value, and a row written only to the old column would be invisible to a new-key lookup. The safe pattern is: write both, read from the new key with a fallback to the old, backfill, **then** move the constraint. The design's §6.2 ordering (steps 2→3→4→5) does roughly this for ciphertext and **should be mirrored for the bidx** — but mirroring it means *two* constraint swaps, not one.
- **The interaction with the mixed-version app instances is worse than the design states.** §6.4 says the constraint swap "must first ensure every live row has a bidx, which requires quiescing writes or running a continuous backfill until the residual is zero." **But a continuous backfill cannot reach a zero residual while old app instances are writing plaintext-only rows** — the old instances create new gaps continuously. So the design's own precondition effectively requires **quiescing writes to this table**, which the design's §6.4 "zero downtime" claim does not accommodate. The honest statement is: **the constraint swap requires a brief write freeze on `organization_identifier`**, unless the application is changed first to dual-write in a way that the design does not currently specify. This is audit finding A-13 and it is the **most consequential operational correction** in this audit.
- **Practical mitigation the design does not offer:** since a blind-index key rotation is expensive and rare, an alternative is to **keep the blind-index key stable for the life of the table** and treat its compromise as a table-rebuild event, while rotating the *ciphertext* key frequently. The two keys have very different blast radii and therefore **do not need the same rotation cadence**. The design treats them as symmetric; they are not. Recommend the owner decide (D-5 extension): *is the blind-index key rotated on a schedule, or only on compromise?*

### 3.5 Challenge: associated data

**Audit assessment: the AAD choice is right, but the design does not state the immutability requirement that makes it work, and it includes a field that is mutable.**

The design's AAD is `organization_id ‖ country_id ‖ identifier_type ‖ key_version`.

- **`key_version` in the AAD is correct and important** — it binds the ciphertext to the key that produced it, so a row cannot be re-labelled as a different key version.
- **`identifier_type` in the AAD is correct** — it binds the ciphertext to its type, so a ciphertext cannot be moved between types.
- **`organization_id` in the AAD is correct in intent but requires an immutability rule that the design never states.** `organization_id` is an ordinary column with an `ON UPDATE RESTRICT` FK — but `ON UPDATE RESTRICT` restricts changes to the *referenced* `recruitment.organization` row, **not** to `organization_identifier.organization_id` itself. The column can be updated freely. **If `organization_id` is changed, the AAD no longer matches and the row becomes undecryptable.** The design must state: **`organization_id`, `country_id`, and `identifier_type` are IMMUTABLE once written; changing them requires re-encryption.** The design's §5.3 talks about RLS on `organization_id` and §6.2 step 5 about the constraint, but **never states the immutability invariant**, and its §4.4 AAD silently depends on it. This is audit finding A-14 and it is a **correctness** defect, not a security defect — it would present as a decrypt failure, not a leak, but it would be diagnosed as "key corruption" and could trigger a spurious key rotation.
- **A stricter alternative the owner should consider:** bind the AAD to `id` (the surrogate primary key) instead of `organization_id`. `id` is a `GENERATED ALWAYS AS IDENTITY` column and is never updated. That removes the mutable-field problem entirely and still prevents cross-row grafting. The trade-off is that an identifier row can no longer be moved between organisations without re-encryption either — which is almost certainly the desired behaviour, since moving a tax identifier between organisations is not a legitimate operation. **Recommendation: bind `id` as well as (or instead of) `organization_id`.** This is a design refinement the audit recommends but does not impose.

### 3.6 Challenge: key loss and recovery

**Audit assessment: the design correctly identifies silent key loss as the catastrophic failure mode (§6.6) and correctly proposes escrow plus a decryptability canary. Three gaps.**

1. **The canary is described but not specified.** A canary needs a *defined* population, a *defined* cadence, a *defined* alert path, and a *defined* failure action. "A small set of rows re-decrypted on a schedule" is a direction, not a design. Without specifying the population (e.g. "one row per key version per tenant, plus N randomly chosen rows"), a canary can pass while most of the table is unreadable.
2. **Access separation between "can read the key" and "can write to the table" is not addressed.** The design's §4.2 covers key custody but not the *separation of duties* between the key custodian and the data operator. In the KMS model these are the same identity; in a self-hosted deployment they could be separated. This is a decision, not a defect.
3. **"Escrow a key-escrow copy of `K_dek` in the same system that holds the ciphertext" (§6.6 mitigation (b)) is in tension with the design's own threat model.** If the escrow copy sits in the same system as the ciphertext, then **an attacker who compromises that system gets both** — the escrow converts a *key-loss* risk into a *key-compromise* risk. The design presents it as a mitigation without stating the trade. The safer form is **escrow in a separate custody domain** (mitigation (a)), or escrow only `K_root` in a second domain so that a ciphertext-only compromise cannot decrypt but a `K_root` loss is still recoverable. The design should state the trade-off explicitly and let the owner choose. Audit finding A-15.

### 3.7 Challenge: leakage — precisely what the blind index reveals

**The audit takes issue with any implication that the blind index leaks little. It leaks a specific, quantifiable, non-trivial amount.**

**What the blind index reveals:**

| # | Leak | Detail | Compared with the plaintext unique index |
|:--|:--|:--|:--|
| L-1 | **Equality within a `(country_id, identifier_type)` group** | Two rows with the same bidx share an identifier; two rows with different bidx do not. An observer with read access to the bidx column can group rows by identifier | **Identical to the existing leak.** The plaintext unique index groups rows by identifier in exactly the same way. **No widening** |
| L-2 | **Frequency of each identifier value** | A bidx appearing in *n* rows means *n* organisations claim that identifier. Under the existing constraint *n* can only be 1 — so a bidx appearing twice would indicate a **constraint violation** | **Equivalent.** Same structure as today |
| L-3 | **Identifier is a join key across tables** | A bidx is a stable value that can be joined against any other table that stores bidx | Equivalent to the plaintext today |
| L-4 | **A bidx is a stable pseudonymous business identifier** | It is deterministic, so the *same* organisation's identifier produces the *same* bidx forever. It can be used to **track a business across time, across dumps, and across backups** — an analytics-friendly pseudonym that outlives the encryption | **Equivalent to plaintext** |
| L-5 | **Cross-group correlation via ciphertext** | Randomised AEAD means two rows with the same plaintext have *different* ciphertexts, so ciphertext does **not** leak equality. But if a system also stores a *decrypted* form anywhere (a cache, a log, an export, an API response), the equality leaks again | **Better than plaintext** — randomised encryption is strictly better here |
| L-6 | **A bidx is offline-guessable if `K_bidx` is weak** | A 16-character space is small enough that a brute-force against a *guessed* identifier is cheap **if** the key is guessable or leaked. With a strong key this is not feasible | N/A |

**The critical, non-obvious point the design does not make:** **the blind index is a permanent, cross-tenant, non-rotatable pseudonym for a business, and it is *not* covered by the same "the identifier is permanent" concern — because the identifier is permanent too.** This is not a new risk, but it means the design's §RK-2 ("the blind index becomes a re-identification key") is **correct and should be elevated, not left as Medium**. An observer who obtains the bidx column learns the *set of organisations sharing each identifier* and can track a business indefinitely. Under the current plaintext design the same observer learns the same thing — plus the identifiers. So the design's ranking of RK-2 as Medium is defensible *relative to the current state*, but the audit recommends it be restated as: **"the blind index is a permanent pseudonymous business identifier and must be classified and access-controlled at the same tier as the identifier it replaces."**

**A leakage the design does not mention at all:** the blind index **length is fixed and the identifier type is visible in the row**, so the bidx column discloses the *number of distinct identifiers per (country, type) group* and the *number of organisations per identifier* — a small amount of business-structure metadata. Low severity, but it should be stated rather than assumed absent.

### 3.8 Challenge: threat boundaries — what application-layer encryption does and does not protect against

**Audit assessment: the design's §5.8 table is accurate and appropriately humble. Two boundaries it states in passing deserve elevation, and one it misses.**

| Adversary | Does app-layer encryption help? | Audit note |
|:--|:--|:--|
| **A-1 Privileged DB user** | **Yes, for stored data.** A superuser reading the table gets ciphertext + bidx, not identifiers. The bidx still leaks structure | The design's §5.8 correctly says RLS does not apply to superusers. **Elevate:** the superuser is the single most likely insider threat, and app-layer encryption is the *only* control in the design that stops them. This is the design's strongest argument and it is underplayed |
| **A-2 Backup / volume theft** | **Yes.** The dump contains ciphertext and wrapped/derived DEKs. If the root key is in a KMS, the dump is inert | **Elevate:** this is the second-strongest argument. The design's §6.6 correctly notes the rollback story depends on backups — and the audit's §5 finding is that **the backup mechanism is not currently trustworthy** |
| **A-3 Compromised application process** | **No.** The process holds the unwrapped key and decrypts on demand. A compromised process sees plaintext | The design states this. It is the **boundary that makes application-layer encryption a partial control, not a complete one.** The design should say plainly: *this control protects the data at rest, not the process that legitimately uses it* |
| **A-4 Network attacker** | **No.** App-layer encryption is *above* the wire. The plaintext crosses the network in the app↔DB protocol | Correctly stated as requiring TLS (§5.7). **Elevate:** TLS is a **co-requisite**, not an optional extra |
| **A-5 Log reader** | **Mostly.** The plaintext is not in the DB, so statement logs are clean. But the *application* logs it | Correctly stated. The design's §4.7 `audit_event` warning is the right specific |
| **A-6/A-7 Insider and cross-tenant** | **No.** The legitimate app decrypts and returns plaintext to any caller the app authorises | RLS + least privilege. The design is right that this is orthogonal |
| **A-8 Key theft from the app host** | **No** — the host holds the unwrapped key at runtime | Correctly stated |
| **A-9 Cryptographic weakness** | Depends on parameters | The design's parameters are standard |
| **A-10 (missed by the design) An attacker who can *insert* rows** | Partially — a forged bidx can be used to **deny a legitimate organisation its identifier** by pre-inserting a conflicting row. This is an availability/integrity attack that app-layer encryption does not prevent and that RLS + write-grant narrowing do | **New.** Recorded as audit finding A-16. Severity depends on who can insert into this table, which today is anyone with the single superuser credential |

**Boundary summary the design should state:** application-layer encryption is a **data-at-rest** control. It reduces the impact of A-1, A-2, A-5-at-the-database-layer, and A-9. It **does nothing** for A-3, A-4, A-6, A-7, A-8, or A-10. A deployment that implements *only* this control has moved the plaintext out of the database and into the application — **which is a real and worthwhile improvement, but must not be described as "the identifiers are now protected."** That phrasing would be an overclaim.

### 3.9 Challenge: operational requirements

| Area | Audit assessment of the design's coverage |
|:--|:--|
| **TLS** | ✅ Good. The design correctly identifies `ssl=off` by default, the loopback binding, and the need for `sslmode=require` on the *client*. **One addition:** the design should note that `hostssl` in `pg_hba.conf` and `sslmode` on the client are **both** needed — the server offering TLS is not the same as the client requiring it. The design says this ("Without `sslmode` on the client, a server that offers TLS but does not require it is still negotiated down") — **correct** |
| **Least-privilege roles** | ✅ Good, and the design correctly preserves the `talentra_reporting` exclusion. **One addition:** the design narrows `talentra_app`'s `SELECT` on this table, but does not state that **`talentra_app` currently has no way to be prevented from `SELECT`ing** — because the blanket `GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA recruitment` at `threat-model.md:63` is a *proposal* that has never been applied. So "narrowing" is really "writing it correctly the first time" — a different and easier task. The design's framing is not wrong but slightly mischaracterises the work |
| **Access auditing** | ✅ Correctly identified as a launch requirement, and the design correctly identifies `old_values_json`/`new_values_json` as the latent leak path. **One addition:** `audit.audit_event` is append-only by trigger but **`TRUNCATE`-able** (Phase 3 R-07). The design mentions this in §5.4 and lists M-10 — **correct and appropriately connected** |
| **Secret handling** | ✅ Good, and the warning about `.env` is correct and specific. **One addition:** the design should note that `tests/test_concurrency.py:22` **hardcodes a database password in the repository** — a live example of the exact anti-pattern the design warns about, and evidence that the repo's secret hygiene is not currently good enough to also hold a DEK. The design's §4.2 says "no key material in the repository" but does not cite the existing violation that shows the rule is not yet enforced |
| **Backup/restore verification** | 🔴 **The design's §6.6 rollback strategy depends on a mechanism that is currently unsound.** See §5 |

### 3.10 Challenge: migration safety

The design's 8-step sequence is sound in structure. The audit's challenges:

| # | Challenge | Assessment |
|:--|:--|:--|
| **C-1** | **The rollback path for step 7 depends on a backup whose restore is not verified** | 🔴 **Blocking.** §5 of this audit. The design's §6.6 lists "restore from backup" as the step-7 rollback without qualifying it. The backup script masks restore failures |
| **C-2** | **The constraint swap requires a write freeze the design does not acknowledge** | 🔴 **Material.** §3.4 above. The design's "zero downtime" claim is not achievable for step 5 as specified |
| **C-3** | **The backfill's "fail loudly on canonical collisions" has no defined remedy** | ⚠️ **Material.** A production backfill that halts on a collision leaves the migration blocked. A resolution policy (reject / quarantine / manual) is needed, and it is an owner decision |
| **C-4** | **The design does not require a test of the uniqueness constraint before the migration relies on it** | ⚠️ **Material.** A-1/A-2. The constraint the migration treats as a backstop is untested. The migration should **first** add a test that proves the constraint fires, so that the constraint swap is verified against a known-working baseline |
| **C-5** | **No `UPDATE` path is analysed** | ⚠️ **Material.** The design analyses inserts and lookups but not updates. `identifier_value` is updatable (no trigger blocks it, no rule forbids it). An `UPDATE` that changes the identifier must re-encrypt **and** recompute the bidx — and the bidx recomputation is where a bug would silently break uniqueness. The design's §4.5 write flow covers insert; **the update path needs its own specification** |
| **C-6** | **Cascade delete is not addressed** | ⚠️ **Minor.** A-6 |
| **C-7** | **No statement-level rollback for the `CREATE INDEX CONCURRENTLY` step** | ⚠️ **Minor.** The design notes it cannot run in a transaction but does not say it is a separate out-of-band deployment step that must be verified independently |
| **C-8** | **The design's step 8 "assertion" migration is vague** | ⚠️ **Minor.** "A check that no column decodes to a known-plaintext pattern" is not implementable as a CHECK constraint (PostgreSQL CHECK constraints cannot call most crypto functions, and a regex on BYTEA is not meaningful). The design should specify a **test**, not a constraint — which it partly does in §7.2 T-05 |
| **C-9** | **No plan for identifiers inserted between the backup and the cutover** | ⚠️ **Minor–Material.** The step-0 backup is the rollback artefact. Any row written after the backup is lost if step 7 requires a restore. The design's §6.6 does not state this window. The mitigation is to take the backup **immediately before** step 7, not at step 0, or to capture the delta |

**Assessment of the migration plan overall:** structurally sound, with two blocking corrections (C-1, C-2) and four material ones (C-3, C-4, C-5, and the AAD immutability item A-14).

---

## 4. Audit of Decisions D-1 through D-10

**Note on ownership.** The Phase 4 instruction says *"Do not invent the name of an owner or consuming application."* The audit therefore names **roles by function only** — "data-protection owner", "platform owner", "application owner" — and marks the specific person unnamed. **No consuming application is named anywhere in this audit, and none exists in the repository.**

| # | Decision | Evidence currently available | Risk of proceeding without it | Accountable role (functional) | Blocks implementation? |
|:--|:--|:--|:--|:--|:--|
| **D-1** | Is there a consuming application, and who owns it? | **INFERRED, not confirmed.** Evidence: the `verification_status` / `verified_at` / `verified_by_user_account_id` triple (`013:76-78`); `docs/integration-boundaries.md:88` describing verification of a *company registration identifier*; the `organization_status` column (`007:14`); the whole `recruitment.organization_hierarchy` design (`013:143-189`). **No application code is in the repository** | **Severe.** Without this, the migration plan in §6 has no counterparty, the §2.2 "no in-repo consumer" finding cannot be extrapolated to the system, and **the entire premise that the blast radius is small is unverified**. Proceeding would mean designing a migration for a codebase nobody has read | **Application owner / platform owner** — *unnamed* | 🔴 **YES — blocking** |
| **D-2** | Encryption approach | The Phase 4 §3 comparison, independently re-assessed here (§3) and **endorsed**. The repository facts (no crypto, no extension, no app code) are all confirmed | **Severe.** Choosing wrong here wastes the whole programme. The audit concurs with Option A | **Data-protection owner + platform owner** | 🔴 **YES — blocking** |
| **D-3** | Key custody | **INFERRED.** The repository has **no key-management infrastructure at all** — no crypto code, no secret store, no KMS client. The *only* evidence of secret-handling practice in the repo is **negative**: `tests/test_concurrency.py:22` hardcodes a DB password, and `docker-compose.yml:10` sources `POSTGRES_PASSWORD` from `.env` | **Severe.** No custody decision means no encryption is possible. A file-based interim also silently sets the §3.8 threat boundary (the app host holds the key) | **Platform / security owner** | 🔴 **YES — blocking** |
| **D-4** | Is an external dependency acceptable? | **CONFIRMED** for the repository: no external service is currently declared, and the audit confirms Option A needs **no** new service. The KMS is optional. Note the constraint from the audit brief: no paid services may be introduced | **Moderate.** Getting this wrong either blocks a legitimate KMS or permits an unmanaged key file | **Platform owner / procurement** | 🔴 **YES — blocking** (per the phase's own rules) |
| **D-5** | Blind-index width | **CONFIRMED** design basis. The audit adds: the *rotation cadence* of the blind-index key is a separate decision that the Phase 4 D-5 does not cover, and the two keys have different blast radii (§3.4) | **Low–Moderate.** Truncation to 16 bytes introduces a birthday-bound false-positive rate that would silently reject a legitimate organisation. The **cadence** question is more consequential than the width | **Security owner** | ⚠️ No — but **before migration sign-off** |
| **D-6** | Canonicalisation rules per `identifier_type` | **INFERRED.** The `identifier_type` domain is confirmed (`013:104-115`). The *format* rules are external knowledge the audit **cannot verify from the repository** — GSTIN's mod-36 check digit, CIN's structure, and the various national VAT/EIN formats are all outside the repo. Additionally the audit found the **collation question** (§3.1) that must be answered first | **High.** A wrong rule silently defeats uniqueness. The audit adds two sub-questions the design did not ask: (a) is a failed check digit a **rejection** or a **normalisation**; (b) does the *live* collation already make the constraint case-insensitive | **Data-protection owner + domain expert (tax/regulatory)** | ⚠️ No — but **before migration sign-off** |
| **D-7** | Must the literal original string be recoverable? | **INFERRED.** The repository shows the value is free-text `VARCHAR(100)` with no format constraint, so any string is accepted today — meaning the operator's literal input *is* currently stored verbatim. That is a **real, if small, behaviour-change** the design correctly flags | **Low–Moderate.** If (b), a second encrypted field is required, doubling the surface | **Product owner** | ⚠️ No — before migration sign-off |
| **D-8** | Deployment window for step 7 (drop plaintext) | **CONFIRMED** as a decision point. The audit adds that **the window must be sized to include the write freeze the constraint swap needs** (C-2) and the delta-capture requirement (C-9) | **Moderate.** Step 7 is irreversible without a restore — and the restore path is currently unsound (§5) | **Platform / operations owner** | ⚠️ No — before migration sign-off |
| **D-9** | Scope: this table only, or other plaintext PII too? | **CONFIRMED** that `core.user_account.email` and `phone_e164` are also plaintext (`002:12-15`, with `ck_user_account_email_format` and `ck_user_account_phone_format` as *format* checks, not encryption). `profile.*` likewise. The Phase 3 report §6.6 already flags this | **Low for this phase, high for external messaging.** Leaving known-plaintext PII in the same database while claiming "encrypted tax IDs" is a communications risk | **Data-protection owner** | ⚠️ No — but it governs external claims |
| **D-10** | Is Option E (defer + access control) an acceptable interim? | **Partially CONFIRMED, partially UNVERIFIED.** CONFIRMED: the table has no seed path and no in-repo writer besides one test file, so a *seeded* database very likely has **zero** rows. **UNVERIFIED: whether any deployed environment holds real identifiers** — this needs a read-only DB check, which this phase forbids | **Severe if wrong.** Choosing defer when real identifiers are stored leaves A-1/A-2 fully open while creating a false sense of completion. Choosing encrypt now for an empty table is low-cost insurance | **Data-protection owner** | ⚠️ No — but it is the **highest-leverage interim decision** and it depends on the Q-2 answer (§8.2 of the Phase 4 design) |

**Audit conclusion on the decision set:** D-1, D-2, D-3, D-4 are correctly identified as blocking. **The Phase 4 design's decision set is complete and correctly prioritised.** The audit adds three sub-decisions that should be folded in:

- **D-6a** — Is a failed check digit a rejection or a normalisation? (§3.1)
- **D-6b** — What is the *live* database's collation, and therefore is the existing constraint already case-insensitive? (§3.1) — answerable only with a read-only DB check
- **D-5a** — Is the blind-index key rotated on a schedule, or only on compromise? (§3.4)

---

## 5. Backup / Restore Gap Assessment

### 5.1 What the existing parity check can and cannot establish

**Can establish** (for the 7 listed tables only): that `COUNT(*)` in the recovery database equals `COUNT(*)` in the source, for `core.user_account`, `recruitment.organization`, `recruitment.job_posting`, `profile.candidate_profile`, `gig.gig_worker_profile`, `commercial.wallet_ledger`, `audit.audit_event` (`scripts/backup_restore.sh:56-75`).

**Cannot establish — and this is the audit's central operational finding:**

| # | It cannot establish | Why | Evidence |
|:--|:--|:--|:--|
| **B-1** | **That `organization_identifier` was backed up at all** | The table is not in the parity list | `backup_restore.sh:56-64`; `backup_restore.ps1:66-73` |
| **B-2** | **That `organization_identifier` was restored** | Same | Same |
| **B-3** | **That the restore succeeded *at all*** | `pg_restore`'s exit status is discarded by `\|\| true`, and `[PASS] Restoration completed` is printed unconditionally | `backup_restore.sh:42`, `:46` |
| **B-4** | **That any table's data is *correct*, only that counts match** | A `COUNT(*)` parity check cannot detect a corrupted or mis-restored row, a wrong value, or a lost column | `:66-75` — the loop compares counts only |
| **B-5** | **That identifiers are *decryptable* after a restore** | Row counts say nothing about key availability or ciphertext validity | Not attempted anywhere |
| **B-6** | **That the schema was restored correctly** | The script's own comment says *"Verifying table row counts and schema integrity"* (`:55`) but **no schema-integrity check exists** — only the count loop | `:55` vs `:66-75` |
| **B-7** | **That the restore is *complete*** | `pg_restore` restores a custom-format dump; without `--exit-on-error`, object-level errors are reported but the script ignores the exit code entirely | `:42` |

**The severity is not theoretical.** A `pg_restore` that fails on a specific object (e.g. a constraint that fails to create, or a permission error) exits non-zero. The script then prints `[PASS] Restoration completed`, and the parity loop checks 7 tables. If those 7 restore correctly — which is likely, since the failure would be localised to one object — **the script prints `RTO VALIDATION PASSED` and exits 0 while the restore is incomplete.** It then **destroys the recovery database and the dump file** (`:79-80`), so the evidence is deleted.

**This makes the Phase 4 design's §6.6 rollback strategy unsafe as written.** The design's step-7 rollback is *"Restore from backup"*; the audit finds the backup-restore script can report success on a partial restore and then delete the artefact needed to diagnose it. The design must treat "**establish a trustworthy restore**" as a **precondition to the migration**, not as an assumption.

### 5.2 Recommended testable verification approach

**Not implemented here — the backup script was neither edited nor executed**, per the phase's rules. The following is a recommendation for a separately approved implementation phase.

**Level 1 — Make the restore verifiable (script change, M-1 extended).**
- Capture `pg_restore`'s exit status and **fail the script on a non-zero exit** — with an explicit allow-list for the exit code 1 that `pg_restore` returns for benign warnings, so the change is precise rather than blanket. The PowerShell script needs an explicit `$LASTEXITCODE` check, because `$ErrorActionPreference = "Stop"` does not trap native exit codes.
- Preserve the dump file and the recovery database **on failure**, so a failed restore can be diagnosed. Today they are deleted unconditionally (`:79-80`).

**Level 2 — Extend coverage (script change).**
- Add `recruitment.organization_identifier` to the parity table list. This is the design's M-1 and the audit **confirms it is still open and still necessary**.
- Add a **count-plus-checksum** comparison rather than count alone: e.g. `md5(string_agg(...))` over the ordered identifier column, or an aggregate over the bidx. A count alone (B-4) cannot detect a corrupted row.

**Level 3 — Add a decryption verification step (post-migration, and the one that matters most).**
- After restore, decrypt a **sample** of identifiers with the key version recorded on each row, and assert that each decrypts to a value that re-derives the same blind index. This is the only check that establishes B-5, and it is the check that would catch a `K_root` escrow failure before a user needed a tax ID.
- Combine with the §3.6 decryptability canary so that a key-availability failure surfaces on a schedule rather than on demand.

**Level 4 — A testable, runnable form.**
- The verification logic should live in a **test** that can run against a disposable database, consistent with the Phase 3 follow-up's execution matrix (`docs/phase3-followup-findings.md` §4) — which identified `test_analytics.sql` and `test_concurrency.py` as the two suites that must never run against the live database. A backup/restore verification test belongs in the same category: it creates and drops a database, so it is a **Group B / persistent-write** suite.
- **Recommended assertion set**, stated so it is testable without editing the script today:
  1. `pg_restore` exit status is captured and non-zero fails the run.
  2. `recruitment.organization_identifier` row count in the recovery DB equals the source.
  3. A checksum over the ordered `(country_id, identifier_type, bidx)` tuples matches between source and recovery.
  4. Every row in the recovery DB decrypts under its recorded `key_version` and re-derives its stored bidx.
  5. The dump file and recovery DB are **retained** when any assertion fails.

### 5.3 Verdict on the backup gap

🔴 **OPEN — and more severe than the Phase 4 design characterised it.** The gap is not only "the table is missing from the parity list" (which the design correctly found). It also includes **"the restore's success is never actually determined"** (B-3, B-7) and **"the artefacts needed to diagnose a failure are destroyed on exit"**. The design's M-1 remedy (add the table to the list) is **necessary but not sufficient**.

**Recommended status: treat "establish a trustworthy restore path" as a blocking precondition (P-7) for the migration, not as a parallel workstream.** The Phase 4 design's §6.1 P-7 says *"A backup of the current database is taken and verified restorable"* — the audit's finding is that the repository's own tool for verifying restorability **cannot presently establish that**, so P-7 as written is **not satisfiable today**.

---

## 6. Prioritised Blockers and Recommended Next Actions

### 6.1 Blockers (must be resolved before implementation)

| Rank | Blocker | Why it blocks | Where it belongs |
|:--|:--|:--|:--|
| **BL-1** | **`pg_restore` exit status discarded; `[PASS]` printed unconditionally; artefacts deleted on exit** (`backup_restore.sh:42,46,79-80`; `backup_restore.ps1:48-49`) | The design's irreversible step (drop plaintext) has no reliable rollback. **The design's own P-7 is currently unsatisfiable** | `scripts/backup_restore.sh`, `scripts/backup_restore.ps1` — implementation phase |
| **BL-2** | **D-1: the consuming application is unidentified** | No counterparty for the migration; the "small blast radius" premise is unverified | Owner decision |
| **BL-3** | **D-3/D-4: key custody and dependency approval** | No key, no encryption | Owner decision |
| **BL-4** | **The uniqueness constraint is untested (A-1, A-2)** | The migration treats it as a backstop and as a parity baseline; nothing proves it fires | `tests/` — implementation phase |
| **BL-5** | **The constraint swap needs a write freeze the design does not plan for (C-2)** | Step 5 as specified cannot complete without one; the "zero downtime" claim is false | Design revision + application change |
| **BL-6** | **AAD immutability invariant is missing (A-14)** | An `UPDATE` of `organization_id`/`country_id`/`identifier_type` silently breaks decryption and would be misdiagnosed as key corruption | Design revision |

### 6.2 Material corrections (revision needed, not blocking on their own)

| # | Correction | Where |
|:--|:--|:--|
| MC-1 | Specify the `UPDATE` path: re-encrypt **and** recompute the bidx, atomically | Design §4.5, §6.2 |
| MC-2 | Add a blind-index **rotation** procedure with a dual-index window, separate from the ciphertext rotation | Design §4.3, §6.2 |
| MC-3 | State the key-management model explicitly: **derivation (HKDF) vs. wrapping (KMS envelope)** — and what each implies about the KMS operator's ability to decrypt | Design §4.1, §4.4 |
| MC-4 | Define the decryptability canary concretely: population, cadence, alert path, failure action | Design §3.6/§6.6 |
| MC-5 | State the escrow trade-off: a DEK escrow copy in the same system as the ciphertext converts key-loss into key-compromise | Design §6.6 |
| MC-6 | Elevate the blind index's classification to match the identifier it replaces; state L-1…L-6 explicitly | Design §3.4, §RK-2 |
| MC-7 | Add the forged-bidx **denial-of-service** adversary (A-16) | Design §1.2, §3.8 |
| MC-8 | Add the **collation interaction**: the live DB's collation determines whether the existing constraint is already case-insensitive | Design §3.2, §6.3 |
| MC-9 | Define a **resolution policy** for canonical collisions found during backfill (reject / quarantine / manual) | Design §6.3 |
| MC-10 | State the **cascade-delete** behaviour and whether identifier deletion must be audited | Design §2, §4.7 |
| MC-11 | Correct the "written in exactly two places" imprecision — three test suites also write `audit.audit_event` | Design §2.3 (A-10) |
| MC-12 | Add a **delta-capture** step so rows written between the backup and step 7 are not lost | Design §6.6 (C-9) |
| MC-13 | Correct the §7.3 statement about `test_constraints.sql` — it does not touch the identifier table | Design §7.3 (A-3) |
| MC-14 | Note the existing secret-hygiene violation (`tests/test_concurrency.py:22`) as evidence the "no key material in the repo" rule is not yet enforced | Design §4.2 |

### 6.3 Recommended next actions, in order

| # | Action | Type | Rationale |
|:--|:--|:--|:--|
| **1** | **Revise `docs/phase4-tax-id-security-design.md`** incorporating BL-1, BL-5, BL-6, and MC-1…MC-14 | Documentation | This audit is deliberately not editing the design. The corrections are specific enough to apply directly. **This phase's rules forbid editing it, so it is the next phase's first task** |
| **2** | **Answer D-1, D-3, D-4 with the owner**; identify the consuming application and its owner | Owner decision | BL-2, BL-3. Nothing else can be finalised first |
| **3** | **Run the read-only checks that require a database connection**: live row count of `organization_identifier`; the database's `LC_COLLATE` / `pg_collation`; whether any environment holds a real identifier (Q-1, Q-2, D-6b) | Read-only DB inspection | These are the specific facts that would close Q-1, Q-2 and MC-8. **Not performed in this phase** — the brief forbids connecting to the database |
| **4** | **Fix the backup/restore script** (BL-1) and add the identifier to the parity list (M-1) | Script change, separately approved | Makes P-7 satisfiable. Independent of the encryption work and valuable on its own |
| **5** | **Add a uniqueness test for `uq_organization_identifier_val`** before the migration relies on it (BL-4) | Test change, separately approved | Establishes the baseline the migration will compare against |
| **6** | Only then: begin the implementation phase proper | — | Steps 1–5 de-risk the irreversible steps |

**On the recommended next phase:** the audit's answer is **a documentation-revision phase (4.2) that applies the corrections above**, followed by the two owner decisions (D-1, D-3/D-4) and the read-only database checks. **An implementation phase should not be scheduled yet** — the design's own §10.3 already said it is "not ready for implementation", and this audit identifies two additional *blocking* corrections (BL-1, BL-5) and one *correctness* defect (BL-6) that were not visible from the design alone.

---

## 7. Evidence Index

### 7.1 Repository evidence relied upon

| Evidence | Reference | Status |
|:--|:--|:--|
| Column definition | `db/migrations/013_create_organization_extensions.sql:75` | ✅ CONFIRMED |
| Unique constraint | `db/migrations/013_create_organization_extensions.sql:83-84` | ✅ CONFIRMED |
| `organization_id` FK with `ON DELETE CASCADE` | `013:86-90` | ✅ CONFIRMED |
| `country_id` FK, `ON DELETE RESTRICT` | `013:92-96` | ✅ CONFIRMED |
| `verified_by_user_account_id` FK, `ON DELETE SET NULL` | `013:98-102` | ✅ CONFIRMED |
| `identifier_type` CHECK (7 values) | `013:104-115` | ✅ CONFIRMED |
| `verification_status` CHECK (4 values) | `013:117-125` | ✅ CONFIRMED |
| Verification-consistency CHECK | `013:127-132` | ✅ CONFIRMED |
| Supporting index on `organization_id` | `013:135-136` | ✅ CONFIRMED |
| No trigger/function/view on the table | All 6 repo triggers: `009:205`, `012:290`, `015:126`, `016:130`, `017:374`, `017:444` | ✅ CONFIRMED absent |
| Only migration 013 defines the table | `grep -rln organization_identifier db/migrations/` → 1 file | ✅ CONFIRMED |
| No collation defined | `grep -rn "COLLATE\|CREATE COLLATION" db/migrations/*.sql` → no output | ✅ CONFIRMED |
| Test transaction boundary | `tests/test_organization_extensions.sql:4` `BEGIN;`, `:299` `ROLLBACK;` | ✅ CONFIRMED |
| Failing insert (constraint test) | `tests/test_organization_extensions.sql:168-191` | ✅ CONFIRMED |
| Valid insert | `tests/test_organization_extensions.sql:194-212` | ✅ CONFIRMED |
| `v_ident_id` never read back | `:17` (declaration), `:212` (assignment only) — 2 occurrences total | ✅ CONFIRMED |
| No test asserts the uniqueness constraint | `uq_organization_identifier_val` → 1 repo hit (its own definition) | ✅ CONFIRMED absent |
| `test_constraints.sql` does not touch the table | Read in full, 194 lines; inserts into 6 other tables | ✅ CONFIRMED |
| `test_constraints.sql` is rolled back | `:6` `BEGIN;`, `:193` `ROLLBACK;` | ✅ CONFIRMED |
| `credential_identifier` is a different table | `tests/test_administration.sql:81,98,113`; `tests/test_security.sql:148,162` → `core.user_credential` | ✅ CONFIRMED |
| Generator never populates the table | `scripts/generate_data.py:325,340,366,381` (`COPY`); `:330,501,637,720,750,837` (`recruitment.organization` only) | ✅ CONFIRMED absent |
| Validator has no rule on the table | `scripts/validate_data.py:114` (RG2 column list); RG6 at `:208-220` | ✅ CONFIRMED absent |
| No benchmark query touches the table | `db/queries/02:19`, `:08:16` (`recruitment.organization` join); `05`, `06` (`organization_id`) | ✅ CONFIRMED absent |
| Seed files empty | `wc -c db/seeds/*.sql` → 0, 0 | ✅ CONFIRMED |
| Backup parity list (7 tables, no identifier) | `scripts/backup_restore.sh:56-64`; `scripts/backup_restore.ps1:66-73` | ✅ CONFIRMED |
| **`pg_restore` exit status discarded** | `scripts/backup_restore.sh:42` (`\|\| true`); `:46` unconditional `[PASS]` | ✅ CONFIRMED — 🔴 **BL-1** |
| **Dump and recovery DB deleted on exit** | `scripts/backup_restore.sh:79-80` | ✅ CONFIRMED — 🔴 **BL-1** |
| **PowerShell restore exit code unchecked** | `scripts/backup_restore.ps1:11` (`$ErrorActionPreference`), `:48-49` (comment acknowledges exit code 1, does not check `$LASTEXITCODE`) | ✅ CONFIRMED — 🔴 **BL-1** |
| "schema integrity" claimed but not checked | `scripts/backup_restore.sh:55` (comment) vs `:66-75` (count loop only) | ✅ CONFIRMED — **B-6** |
| `audit.audit_event` written in 2 migrations | `db/migrations/015:221`, `:317` | ✅ CONFIRMED |
| `audit.audit_event` also written by 3 test suites | `tests/test_administration.sql:185`; `tests/test_security.sql:101` | ✅ CONFIRMED — **A-10** |
| `old_values_json` / `new_values_json` are `JSONB` | `012:238-239` | ✅ CONFIRMED |
| `audit.system_error_log` free-text fields | `012:300-303` | ✅ CONFIRMED |
| `talentra_reporting` scope excludes `recruitment` | `docs/threat-model.md:75-77` | ✅ CONFIRMED |
| `talentra_app` blanket grant would include the table | `docs/threat-model.md:63` | ✅ CONFIRMED (proposal only) |
| `talentra_admin` is the only role; SUPERUSER | `docker-compose.yml:9` (`POSTGRES_USER`) | ✅ CONFIRMED |
| No `FORCE ROW LEVEL SECURITY` in the threat model | `grep -c` → 0 | ✅ CONFIRMED — superuser bypass is real |
| Threat model admits audit gap | `docs/threat-model.md:188` | ✅ CONFIRMED |
| `talentra_pgdata` plain named volume, no TLS config | `docker-compose.yml:12-14`, `:21-22` | ✅ CONFIRMED |
| Only `btree_gist` extension | `db/migrations/014:8`, `:17:8` | ✅ CONFIRMED |
| Zero roles / grants / policies / session context | Repo-wide greps → no output | ✅ CONFIRMED |
| No crypto primitives | Repo-wide greps → no output | ✅ CONFIRMED |
| Hardcoded DB password in a test | `tests/test_concurrency.py:22` | ✅ CONFIRMED — **MC-14** |
| `organization_hierarchy` table | `013:143-189` | ✅ CONFIRMED |
| `recruitment.organization` columns | `db/migrations/007_create_organization.sql:4-17` | ✅ CONFIRMED |

### 7.2 Evidence NOT available, and therefore UNVERIFIED

| # | Unverified item | Why it is unavailable | How to close it |
|:--|:--|:--|:--|
| U-1 | **Live row count** of `recruitment.organization_identifier` | The brief forbids connecting to the database | Read-only DB check (next phase, step 3) |
| U-2 | **Whether any environment holds a real tax identifier** (Q-2) | Same, plus it is an organisational fact | Owner/DP contact |
| U-3 | **The live database's collation**, and therefore whether the existing unique constraint is already case-insensitive | The brief forbids connecting; the repository defines no collation | Read-only `SHOW lc_collate` / `pg_collation` check |
| U-4 | **Whether the constraint actually fires** in the live database | No test asserts it, and no DB check is permitted | Add the test (BL-4), then run it |
| U-5 | **The consuming application's identity and behaviour** (D-1) | Not in the repository | Owner decision |
| U-6 | **The per-`identifier_type` canonical formats** (D-6) | External regulatory knowledge, not repository evidence | Domain owner / regulatory source |
| U-7 | **Whether a third-party verification provider receives the identifier** (Q-4) | Not in the repository | Owner / integration owner |
| U-8 | **Whether the identifier is ever displayed, exported, or returned by an API** (Q-5) | No application code in the repository | Application owner (D-1) |
| U-9 | **Actual restore reliability** of the current backup runbook | Not executed; the brief forbids it | Execute against a disposable DB in a later phase |
| U-10 | **Whether the audit's cryptographic reasoning matches an independent crypto review** | No second reviewer in this phase | Security/crypto peer review |
| U-11 | **The behaviour of `pg_restore` under the specific failure modes that matter** (e.g. a constraint that fails to create) | Not executed; the brief forbids it | Later, against a disposable DB |
| U-12 | **Whether `talentra_admin` is genuinely the only role in the live instance** | The repo shows no `CREATE ROLE`, but the live catalog was not queried (Phase 3 established the same gap) | Read-only `pg_roles` check |

### 7.3 Blocked commands

| Command | Attempts | Result |
|:--|:--:|:--|
| `grep -rn "organization_identifier" db/seeds/` | 3 | Classifier: *"talentra-minimax-free is temporarily unavailable, so auto mode cannot determine the safety of Bash right now."* Settled independently by `wc -c` (both files 0 bytes) and by `grep -rln organization_identifier db/migrations/` |
| `grep -rn "uq_organization_identifier_val" tests/ db/ scripts/ docs/` | 1 | Same. Settled independently by the full-repo form, which returned exactly one hit |
| `grep -rn "identifier" tests/test_administration.sql tests/test_security.sql` | 1 | Same. Settled independently by the per-file form, which returned the `credential_identifier` lines |
| `grep -rn "organization_identifier" db/migrations/0[1][4-9]*.sql` | 1 | Same. Settled independently by `grep -rln organization_identifier db/migrations/`, which returned only migration 013 |
| `grep -n "ROLLBACK\|BEGIN\|COMMIT" tests/test_organization_extensions.sql` | 1 | Same. Settled independently by reading `:4` and `:299` directly |
| `grep -n "FORCE ROW LEVEL SECURITY" docs/threat-model.md db/migrations/*.sql` | 1 | Same. Settled independently by `grep -c`, which returned 0 |

**No bypass was attempted.** Only equivalent forms were tried, and each was independently blocked or independently confirmed by a different route. No command was rephrased to evade detection.

### 7.4 Not performed — forbidden by the phase's scope

| Not performed | Reason |
|:--|:--|
| Any database connection, `docker exec`, `psql`, catalog query, or `EXPLAIN` | The brief forbids connecting to the database |
| Any `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`, `DROP`, `ALTER`, `CREATE`, `REFRESH` | Same |
| Executing `scripts/backup_restore.sh` or `scripts/backup_restore.ps1` | The brief forbids executing the backup script; also it creates and drops a database |
| Executing any of the 23 test suites | Audit-only phase; and the classifier outage persists |
| Editing `docs/phase4-tax-id-security-design.md` | The brief explicitly forbids it — defects are recorded here instead |
| Editing any migration, script, test, seed, config, or benchmark artefact | Forbidden by the brief |

**No test suite was executed. No database operation was performed. No static inspection is described as a passing test anywhere in this document.**

---

## 8. Final Confirmations

- ✅ **The Phase 4 design document was not edited.** Every defect found is recorded in this file.
- ✅ **No implementation, no database operation, and no test execution was performed.** Every finding is a static read of files in this working tree.
- ✅ **All existing work preserved.** 11 modified + 17 untracked entries unchanged; `.git-initial-backup/` listed but not read into, modified, or deleted; `tests/test_constraints.sql` read only; the concurrent Phase 1 documents untouched.
- ✅ **Nothing committed, pushed, reset, cleaned, or stashed.** HEAD `7ac5b2bdeb731610b8bd2c0282608e6c93d4b1df` on `feature/your-task`; stash list empty.
- ✅ **No paid service, paid API, or new dependency introduced.**
- ✅ **CONFIRMED / INFERRED / UNVERIFIED are distinguished throughout** — §2.1–2.5 are CONFIRMED, §2.7 records where the design's label overstates the evidence, §7.2 lists twelve UNVERIFIED items.
- ✅ **No owner or consuming application is named.** Roles are functional only.

### 8.1 Summary answers

| Question | Answer |
|:--|:--|
| **1. Files created/modified** | **Created:** `docs/phase4-1-security-design-audit.md` (this file). **Modified:** none. The Phase 4 design, all migrations, scripts, tests, seeds, configs, benchmark artefacts, and the concurrent Phase 1 documents are byte-unchanged |
| **2. Independently verified** | The column definition, unique constraint (and that it omits `organization_id`), all three FKs including the `ON DELETE CASCADE`, both CHECK constraints, the supporting index, the **absence** of any trigger/function/view/rule on the table, the absence of any collation, test transaction isolation and the two write sites, the **absence of any test asserting the uniqueness constraint**, `test_constraints.sql`'s actual coverage, the generator/validator/benchmark/seed non-coverage, the backup parity list and the `pg_restore` exit-code defect in **both** backup scripts, the zero-implementation claims, the threat-model role grants, and the Phase 3 documents' quoted findings |
| **3. Unverified** | 12 items — §7.2. The load-bearing ones: the live row count, whether any environment holds a real identifier, the live database's collation, whether the constraint fires, the consuming application's identity, the per-type canonical formats, and actual restore reliability |
| **4. Contradictions / design defects** | **Yes — 3 blocking, 6 material, 14 minor.** Blocking: **BL-1** the `pg_restore` exit-status defect that undermines the design's own rollback strategy and makes its P-7 unsatisfiable; **BL-5** the constraint swap needs a write freeze the design's "zero downtime" claim denies; **BL-6** the missing AAD immutability invariant. Plus **BL-2/BL-3/BL-4** (D-1/D-3/D-4 unidentified; the constraint is untested). **Internal contradiction found:** the design's §6.3 relies on the uniqueness constraint as a backstop while §2.7/F-11 admits the data is unknown — and A-1/A-2 show nothing in the repository tests that constraint. **A factual error found:** §7.3's claim that `test_constraints.sql` "is most likely to assert on the uniqueness constraint" — it does not touch the table |
| **5. Owner decisions blocking implementation** | **D-1** (is there a consuming application, and who owns it), **D-3** (key custody), **D-4** (external dependency approval). D-2 is blocking per the design and this audit concurs. Three sub-decisions should be added: **D-6a** (check digit: reject or normalise), **D-6b** (live collation), **D-5a** (blind-index key rotation cadence) |
| **6. Backup parity gap** | 🔴 **OPEN, and broader than the design found.** Beyond the missing table (confirmed, design's M-1 — still necessary), the audit found the restore's **success is never determined** (`\|\| true` at `backup_restore.sh:42`; unchecked `$LASTEXITCODE` at `backup_restore.ps1:49`) and the **artefacts are deleted on exit** (`:79-80`). The design's M-1 remedy alone is insufficient. §5.2 gives a four-level testable approach |
| **7. Tests / database operations** | **None.** No test suite was executed; no database was connected to; no `docker`/`psql`/`EXPLAIN` was run; the backup script was neither edited nor executed. Every statement in this audit is a static inspection of repository files |
| **8. Branch, HEAD, Git status** | `feature/your-task` @ `7ac5b2bdeb731610b8bd2c0282608e6c93d4b1df`. 11 modified + 17 untracked, all unstaged. Stash list empty. Nothing committed or pushed |
| **9. Recommended next phase** | **Phase 4.2 — Design Revision**, not implementation. It should (a) apply BL-1, BL-5, BL-6 and MC-1…MC-14 to `docs/phase4-tax-id-security-design.md`; (b) obtain owner decisions D-1, D-3, D-4; (c) run the three read-only database checks that close U-1, U-3, U-4. **Then** a separate, approved implementation phase, whose first code change should be the backup/restore fix (BL-1) and the identifier uniqueness test (BL-4) — both are valuable independently of encryption. **Scheduling implementation before the design is revised would commit the project to a rollback strategy that this audit shows is currently unsound** |
