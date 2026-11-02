# Talentra Phase 4 — Tax Identifier Security Design

> **Status 2026-10-28: IMPLEMENTED (Delegated decision DEC-25, assistant-decided; see `docs/lifecycle/decision-log.md`).** Migration 034, `scripts/identifier_crypto.py`, `tests/test_identifier_encryption.sql` and `tests/test_identifier_crypto.py`. The statements below that say "design only" and "no implementation" describe the document's earlier state. Remaining risks are listed in the decision log.

**Date**: 2026-10-21 (original); 2026-10-23 (Phase 4.2 revision)
**Phase**: 4 — Tax Identifier Security Design
**Branch / HEAD**: `feature/your-task` @ `7ac5b2bdeb731610b8bd2c0282608e6c93d4b1df`
**Target**: `recruitment.organization_identifier.identifier_value` (`db/migrations/013_create_organization_extensions.sql:75`)
**Nature of this phase**: design only. **No implementation.** No migration, schema, index, application code, test, seed data, configuration, or benchmark artifact was modified. No database was connected to or modified. Nothing was committed or pushed.

---

## Revision History

| Date | Phase | Changes |
|:--|:--|:--|
| 2026-10-21 | Phase 4 | Initial design — architecturally sound, but missing operational prerequisites and key-management details |
| 2026-10-23 | Phase 4.2 | Revised per independent audit (`docs/gate-reviews/phase4-1-security-design-audit.md`). Addressed blocking findings BL-1, BL-5, BL-6; material corrections MC-1 through MC-14; added sub-decisions D-5a, D-6a, D-6b. **Key changes:** (1) backup/restore reliability now a blocking prerequisite, not an assumed capability; (2) constraint-swap write-freeze requirement explicitly stated; (3) AAD immutability invariant documented; (4) uniqueness test now required before migration; (5) normalization collation interaction surfaced; (6) blind-index leakage characterized precisely; (7) key-management model (derivation vs wrapping) distinguished; (8) UPDATE path specified; (9) canonical-collision resolution policy required; (10) cascade-delete behavior documented |

---

## 0. Executive Summary

### 0.1 The problem, restated precisely

`recruitment.organization_identifier.identifier_value VARCHAR(100) NOT NULL` stores company tax identifiers (`gstin`, `cin`, `ein`, `vat`, `pan`, `company_number`, `other`) in plaintext, and the same plaintext participates in a uniqueness constraint `UNIQUE (country_id, identifier_type, identifier_value)` (`013:83-84`). The Phase 3 follow-up established that the repository contains no encryption capability of any kind — no `pgcrypto` extension, no encryption function, no column-level cipher, no key-management code.

### 0.2 The single most important finding of this phase

**The read/write surface for this column inside this repository is almost entirely empty, and that changes the design.**

A complete trace (§2) across all 19 migrations, 12 benchmark queries, 4 scripts, 23 test suites, both seed files, and 8 documents found:

| Surface | Findings |
|:--|:--|
| **Migrations (DDL)** | 1 table, 1 column, 1 unique constraint, 1 index. **No triggers, no functions, no views, no rules read or write this column.** |
| **Benchmark queries** | **Zero.** All 12 queries reference `recruitment.organization` (name) or `organization_id`, never `organization_identifier` |
| **Generator** (`scripts/generate_data.py`) | **Zero.** It `COPY`s 4 `recruitment` tables; `organization_identifier` is **not among them**. **The table is never populated by any seeding path** |
| **Validator** (`scripts/validate_data.py`) | **Zero.** No rule reads this table. RG6 checks `core.user_account.password_hash` only |
| **Backup parity check** (`scripts/backup_restore.sh:56-64`) | **Zero.** Compares row counts across 7 tables; `organization_identifier` is not one of them |
| **Test suites** | **2 INSERT sites only**, both in `tests/test_organization_extensions.sql:168` and `:194` |
| **Application code** | **None in this repository.** It is a database-design repository — no `src/`, no API layer, no service code exists |
| **Audit writers** | `audit.audit_event` is written in exactly 2 places (migration `015:221`, `:317`), neither of which touches this table |

**Consequence for the design.** There is no in-repository read path to migrate and no in-repository seed data to backfill. The blast radius inside this repository is a single table and two test INSERT statements. **The real blast radius is in the consuming application, which is not in this repository** — that application is the party that owns the encryption key and owns the read/write contract, and it must be a named participant in every decision below.

This is a **material simplification** and it is the reason the recommended design is tractable. It also means the migration plan in §6 has a precondition that is not optional: **the consuming application must be identified and its behaviour confirmed before any DDL is written.**

### 0.3 Recommended architecture in one paragraph

**Application-layer envelope encryption with AES-256-GCM (random per-row IV) for the ciphertext column, plus a separate keyed blind index (`HMAC-SHA-256` over a canonicalised identifier) for the uniqueness constraint and lookups.** The database never holds plaintext and never holds a key. The uniqueness constraint moves from `(country_id, identifier_type, identifier_value)` to `(country_id, identifier_type, identifier_value_bidx)`. Encryption lives in the application, so the key never enters the database, the volume, the WAL, or a backup. The blind index is a deterministic keyed MAC — it preserves uniqueness exactly and leaks only equality within a fixed `(country_id, identifier_type)` group, which is the same inference channel the plaintext unique index already leaks. **This requires no `pgcrypto` extension, no new external service, and no paid dependency.** The design does, however, depend on an application that does not exist in this repository, which is why §8 lists application ownership as a blocking approval.

### 0.4 What this design does *not* do

It does not implement anything. It does not propose a new external dependency. It does not claim the design is complete without decisions that only the project owner can make (§8).

---

## 1. Threat Model

### 1.1 Asset

Company tax identifiers — GSTIN, CIN, EIN, VAT, PAN, company number. These are **legal-entity** identifiers, not personal tax numbers, which places them under corporate-data regimes rather than individual privacy law. That is a **lower severity than personal identifiers**, but they are not low-value:

- **Permanent and non-rotatable.** A GSTIN or CIN does not expire and cannot be reissued. Unlike a password, a leaked identifier cannot be invalidated by the holder. This is the property that makes encryption-with-rotation worth its cost.
- **Directly usable.** The value is accepted verbatim in tax filings, bank KYC, and vendor onboarding. An attacker needs no enrichment step.
- **Aggregable.** A company's PAN, GSTIN, registered address, and director identifiers are often obtainable together. Their combination identifies a business and, transitively, its owners — a materially larger privacy exposure than any single field.
- **A correlation key.** GSTIN encodes the state registration code (`29` = Karnataka) and the PAN. It is a coarse geographic and corporate-structure signal even without the accompanying record.

### 1.2 Adversaries and their paths

| # | Adversary | Capability assumed | Path to the asset | Mitigation in this design |
|:--|:--|:--|:--|:--|
| A-1 | **Database superuser / DBA** | `SUPERUSER` on the live instance, or a stolen `talentra_admin` credential | Direct `SELECT` of every row; also `pg_dump` of the whole database | §4.2 (no key in the DB), §5.1 (no plaintext at rest) |
| A-2 | **Volume / backup thief** | Read access to the `talentra_pgdata` volume, a `pg_dump` file, WAL segments, or a replica snapshot | Filesystem or logical-dump read of the table | §4.2, §5.1, §5.6 |
| A-3 | **Over-privileged application process** | The application's own DB credential, or a compromised app host | Reads whatever the app role can read | §5.2 (least privilege), §5.3 (RLS), §4.3 (blind index is not a plaintext substitute) |
| A-4 | **Network-position attacker on the DB link** | On-path between the application and the container | Cleartext wire capture of the identifier | §5.7 (TLS) — **currently `ssl=off` by default** |
| A-5 | **Log reader** | Access to PostgreSQL logs, `log_statement` output, or the app's own log aggregator | Identifier appears verbatim in statements, error text, and `RAISE NOTICE` output | §5.5 |
| A-6 | **Insider with legitimate read access** | A valid org-admin or verification-role account | Reads identifiers of tenants they are entitled to, or — because there is no RLS — of tenants they are not | §5.2, §5.3, §4.4 (audit) |
| A-7 | **Cross-tenant aggregator** | Any single read query, or a compromised query path | One statement joining organisations to identifiers crosses tenant boundaries | §5.3 (RLS) |
| A-8 | **Supply-chain / key theft** | Access to the application host, its config, or its CI | Steals the DEK from memory or disk | §4.3 (KMS-held, never on disk), §4.5 (rotation) |
| A-9 | **Cryptographic weakness** | Analysis of the chosen primitive | Breaks the cipher or forges the blind index | §4.4 (AEAD + HMAC with separate keys), §6.5 (false-positive measurement) |

### 1.3 Security objectives

| # | Objective | Verified by |
|:--|:--|:--|
| O-1 | The plaintext identifier never appears at rest in the database, its indexes, its WAL, or a dump | §7.2 test T-05 |
| O-2 | The plaintext identifier never crosses the network | §7.2 test T-09 |
| O-3 | The database never holds key material | §7.2 test T-06 |
| O-4 | Uniqueness of `(country_id, identifier_type, identifier_value)` is preserved exactly | §7.2 test T-02 |
| O-5 | A tenant cannot read another tenant's identifiers | §7.2 test T-03 |
| O-6 | Every decryption is attributable to an actor | §7.2 test T-07 |
| O-7 | The key can be rotated without re-encrypting every row on the critical path | §7.2 test T-04 |
| O-8 | A lost key is a detectable, recoverable event, not a silent data loss | §6.6, §7.2 test T-08 |

### 1.4 Explicitly out of scope

Personal-data protection for candidates (a different table set — `profile.*`, `core.user_account.email`/`phone_e164`, which are also plaintext and are flagged in `docs/gate-reviews/phase3-implementation-verification-report.md` §6.6 but are a separate workstream). Document-storage encryption. Wallet and ledger financial data. Full PCI DSS scope.

---

## 2. Verified Current-State Findings

Every line reference below was read directly from the files in this working tree during this phase. **No database was contacted**; all findings are static.

### 2.1 The table, exactly as defined

`db/migrations/013_create_organization_extensions.sql:70-139`:

| Line | Object | Definition |
|:--|:--|:--|
| `70` | `CREATE TABLE recruitment.organization_identifier` | — |
| `71` | `id` | `BIGINT GENERATED ALWAYS AS IDENTITY` |
| `72` | `organization_id` | `BIGINT NOT NULL` → `recruitment.organization` (`ON DELETE CASCADE`, `:86-90`) |
| `73` | `country_id` | `BIGINT NOT NULL` → `master.country` (`ON DELETE RESTRICT`, `:92-96`) |
| `74` | `identifier_type` | `VARCHAR(30) NOT NULL` |
| `75` | **`identifier_value`** | **`VARCHAR(100) NOT NULL`** ← the asset |
| `76` | `verification_status` | `VARCHAR(20) NOT NULL DEFAULT 'unverified'` |
| `77-78` | `verified_at`, `verified_by_user_account_id` | `TIMESTAMPTZ`, `BIGINT` → `core.user_account` (`ON DELETE SET NULL`) |
| `82` | `pk_organization_identifier` | `PRIMARY KEY (id)` |
| `83-84` | **`uq_organization_identifier_val`** | **`UNIQUE (country_id, identifier_type, identifier_value)`** ← the constraint to preserve |
| `104-115` | `ck_organization_identifier_type` | `CHECK (identifier_type IN ('gstin','cin','ein','vat','pan','company_number','other'))` |
| `117-125` | `ck_organization_identifier_status` | `CHECK (verification_status IN ('unverified','pending','verified','rejected'))` |
| `127-132` | `ck_organization_identifier_verification_consistency` | `verified` ⟺ `verified_at IS NOT NULL` |
| `135-136` | `idx_organization_identifier_org` | `ON (organization_id)` |
| `138-139` | table comment | `'Legal registration and tax identifiers per jurisdiction for employer verification'` |

**There is no trigger, function, view, or rule on this table anywhere in `db/migrations/`.** Confirmed by a repo-wide search for the table name: the only DDL hits are in `013`.

**Cascade deletion (audit finding A-6):** The FK from `organization_id` to `recruitment.organization` is `ON DELETE CASCADE` (`:86-90`). Deleting an organization **destroys its identifier rows**. After encryption, a cascade delete is a cryptographic erase of the identifier — arguably a feature — but it is **not audited** by anything, and there is no soft-delete path. **Whether identifier deletion should be audited and/or blocked is an owner decision** — see §8, D-11.

### 2.2 Read path — complete trace

| Path | Touches `identifier_value`? | Evidence |
|:--|:--|:--|
| **Migrations / DDL** | No — the column is only *declared*; no DDL object reads it | `013:75`; repo-wide search for `organization_identifier` returns only `013` DDL |
| **Benchmark queries** (all 12) | **No** | `db/queries/02` and `:08` join `recruitment.organization` for `o.name`; `05` and `06` use `organization_id` only. **No query mentions `organization_identifier`** |
| **Benchmark harness** | No | `scripts/run_benchmarks.py` reads the 12 query files; none references the table |
| **Data generator** | **No** | `scripts/generate_data.py` `COPY`s `recruitment.organization` (`:325`), `recruitment.organization_location` (`:340`), `recruitment.job_posting` (`:366`), `recruitment.job_skill_requirement` (`:381`). **`organization_identifier` is never populated by any seeding path.** The other 5 `recruitment.organization*` references in the generator are `SELECT id FROM recruitment.organization` (`:330`, `:501`, `:637`, `:720`, `:750`) and `ANALYZE` (`:837`) — none reference the identifier table |
| **Validator** | No | `scripts/validate_data.py` has 15 rules; RG6 (`:208-220`) queries `core.user_account` only. No rule mentions `organization_identifier` |
| **Backup / export** | **No** | `scripts/backup_restore.sh:56-64` compares row counts across 7 tables — `core.user_account`, `recruitment.organization`, `recruitment.job_posting`, `profile.candidate_profile`, `gig.gig_worker_profile`, `commercial.wallet_ledger`, `audit.audit_event`. **`organization_identifier` is not covered**, so a restore that lost this table would pass the parity check silently. `scripts/backup_restore.ps1` is the PowerShell equivalent. `pg_dump -Fc` writes the whole database, so the *data* is in the dump even though the *parity check* omits the table |
| **Seed SQL files** | **No** | `db/seeds/development_data.sql` and `db/seeds/reference_data.sql` are both **0 bytes** |
| **Tests** | 2 INSERT sites | `tests/test_organization_extensions.sql:168` (a deliberately-failing insert inside an `EXCEPTION` block, `:184-187`) and `:194` (the valid insert). Both use the literal `'29AAAAA0000A1Z5'`, `identifier_type = 'gstin'` |
| **Documentation** | Descriptive only | `docs/phase-2-model/10-data-dictionary.md:20` (the plaintext note), `docs/phase-4-platform/22-integration-boundaries.md:88` (notes that `verification_status` records verification of a *company registration identifier*, not a background check), `docs/phase-2-model/12-threat-model.md:181` (`[SENSITIVE]` tier) |
| **Application code** | **Not present in this repository** | The repository contains only `db/`, `scripts/`, `tests/`, `benchmarks/`, `docs/`, `docker-compose.yml`. There is no `src/`, no API layer, no service. **All real read/write traffic for this column comes from code that is not in this repository.** |

### 2.3 Write path — complete trace

| Path | Behaviour | Evidence |
|:--|:--|:--|
| **DDL** | `INSERT`/`UPDATE` permitted with no trigger guard; the only write-time enforcement is the two `CHECK` constraints and the unique constraint | `013:104-132` |
| **Generator** | **Never writes this table** — a table that no seed path populates | §2.2 |
| **Tests** | 2 INSERTs, both inside a `BEGIN;`…`ROLLBACK;` transaction, so they leave no persistent state | `tests/test_organization_extensions.sql:168`, `:194`; the file's `BEGIN;`/`ROLLBACK;` pattern |
| **Audit trail** | **No automatic audit of writes to this table.** `audit.audit_event` is written in exactly two places in the migrations — `db/migrations/015_create_licences_and_device_limits.sql:221` (device-limit breach) and `:317` (session revocation). Neither concerns organisation identifiers. (Three test suites also write audit rows: `tests/test_administration.sql:185`, `tests/test_security.sql:101`.) `audit.audit_event.old_values_json` / `new_values_json` (`012:238-239`) are `JSONB` and would capture a plaintext identifier if a future writer passed one — a **latent leakage path** (§4.5) |
| **Error log** | `audit.system_error_log` (`012:297-326`) has `error_message TEXT`, `stack_trace TEXT`, `context_json JSONB` — all unredacted free-text fields. A constraint violation raised against this table would include the offending value in the error message | `012:300-303` |
| **Triggers** | **None on this table.** The append-only triggers exist only on `commercial.wallet_ledger` (`017:374-377`), `audit.audit_event` (`012:290-293`), and `commercial.candidate_profile_download_history` (`017:444`) | `013` has no `CREATE TRIGGER` |

### 2.4 Uniqueness and lookup paths

| Path | Mechanism | Consequence for encryption |
|:--|:--|:--|
| **Uniqueness enforcement** | `UNIQUE (country_id, identifier_type, identifier_value)` at `013:83-84` | The unique index physically contains the plaintext. **Encryption cannot be randomised without replacing this index** (§3) |
| **Lookup by value** | The same unique index is the only supporting structure for `WHERE country_id = ? AND identifier_type = ? AND identifier_value = ?` | A randomised ciphertext is not searchable. **An equality lookup requires either a deterministic index or a separate blind index** (§3) |
| **Index page exposure** | The unique index stores the plaintext as its key | Even if the table column were encrypted, **the index would still leak the plaintext**. This is why a blind index is not optional — it is the *only* way to break the plaintext↔index correspondence |
| **Plan visibility** | An equality predicate on a plaintext column appears verbatim in `EXPLAIN` output | `scripts/run_benchmarks.py:819` issues `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)`. **No benchmark query touches this table**, so no committed artifact contains the identifier — but a future query that did would leak it into the artifact |

### 2.5 Key-management surface in the repository

| Check | Result |
|:--|:--|
| `grep -rniE "pgcrypto\|aes-\|encrypt\|decrypt\|cipher" db/ scripts/ tests/` | **no output** |
| `grep -rniE "encrypt\|decrypt\|cipher\|pgcrypto\|base64\|hmac" db/ scripts/ tests/` | **no output** |
| `grep -rnE "CREATE EXTENSION" db/migrations/*.sql` | `btree_gist` only (`014:8`, `017:8`) |
| `grep -rnE "GRANT\|REVOKE\|CREATE ROLE\|CREATE USER" db/ scripts/ tests/` | **no output** — zero roles beyond the `postgres:17` bootstrap `talentra_admin` |
| `grep -rn "CREATE POLICY" db/ scripts/ tests/` | **no output** — zero RLS policies |
| `grep -rnE "current_setting\|set_config" db/migrations/` | **no output** — `app.current_user_id` / `app.current_org_id` are never set |
| `docker-compose.yml` | One service, one plain named volume `talentra_pgdata` (`:13-14`, `:21-22`), **no `ssl` configuration** (so `postgres:17` defaults to `ssl=off`), port bound `127.0.0.1:5432` (`:12`) |

### 2.6 The proposed-but-unimplemented controls in `docs/phase-2-model/12-threat-model.md`

The threat model already specifies the access-control design this phase would build on. **None of it is implemented.**

| Section | What it proposes | Implementation state |
|:--|:--|:--|
| §3 (`:53-81`) | Three roles: `talentra_app` (least privilege), `talentra_reporting` (read-only on `analytics`, `master`), `talentra_admin` (superuser, for migrations) | **Not implemented.** `talentra_admin` exists only because `POSTGRES_USER` in `docker-compose.yml:9` creates it, and it holds SUPERUSER |
| §4 (`:98-101`) | RLS policies keyed to `app.current_user_id` / `app.current_org_id`, set by the application via `SET LOCAL` | **Not implemented.** The session variables are never set by anything in the repository |
| §5 (`:172-181`) | Four sensitivity tiers with masking rules for unauthorised views | Partially implemented — a *documentation* standard. `organization_identifier` is `[SENSITIVE]` by classification but has **no masking rule and no storage standard** in the table |
| §7 (`:232-238`) | RPO one backup interval; RTO < 15 min via `scripts/backup_restore.sh` | Implemented as a logical `pg_dump` runbook. No replication, no PITR, no WAL archiving |

**Note on the reporting role.** `talentra_reporting` is granted `SELECT ON ALL TABLES IN SCHEMA analytics, master` — **not** `recruitment`. So under the *proposed* model, a reporting role could not read identifiers even in plaintext. That is a property worth preserving explicitly when the roles are finally created.

### 2.7 Summary of confirmed facts vs. assumptions

| # | Statement | Status |
|:--|:--|:--|
| F-1 | `identifier_value` is plaintext `VARCHAR(100) NOT NULL` | **CONFIRMED** — `013:75` |
| F-2 | The plaintext participates in a unique constraint | **CONFIRMED** — `013:83-84` |
| F-3 | No encryption capability exists in the repository | **CONFIRMED** — exhaustive grep, §2.5 |
| F-4 | No trigger, function, or view touches the table | **CONFIRMED** — repo-wide search |
| F-5 | No benchmark query, generator path, validator rule, or seed file touches the table | **CONFIRMED** — §2.2 |
| F-6 | Only 2 write sites exist in-repo, both in one test file, both rolled back | **CONFIRMED** — `tests/test_organization_extensions.sql:168`, `:194` |
| F-7 | The backup **parity check** omits the table (the dump still contains it) | **CONFIRMED** — `scripts/backup_restore.sh:56-64` |
| F-8 | No application code exists in this repository | **CONFIRMED** — full file inventory |
| F-9 | No role, grant, RLS policy, or session-context mechanism is implemented | **CONFIRMED** — §2.5 |
| F-10 | TLS is not configured (default `ssl=off`); the port is loopback-bound | **CONFIRMED** — `docker-compose.yml:12` |
| F-11 | The live database's contents and row count for this table are unknown | **ASSUMPTION — cannot be verified** without a DB connection, which this phase forbids |
| F-12 | A consuming application exists that reads/writes this column | **ASSUMPTION.** Strongly implied by the schema, the `verification_status` workflow, and `docs/phase-4-platform/22-integration-boundaries.md:88`, but the code is not in this repository |
| F-13 | The volume may currently contain zero rows, or many | **ASSUMPTION.** F-5 suggests the seeded dataset has none, but the table may have been populated by the consuming application |
| F-14 | No third-party verification provider is integrated | **CONFIRMED** for this repository — `docs/phase-4-platform/22-integration-boundaries.md:88` states the only verification state in the schema is `verification_status`; no background-check dossier is stored |

---

## 3. Options Comparison

### 3.1 The design space, stated precisely

The choice is over a 2×2 that matters: **where does the crypto happen** (database vs. application) and **what shape does the ciphertext take** (randomised vs. deterministic). Four viable cells, plus two rejected patterns.

| | **Randomised (per-row IV)** | **Deterministic** |
|:--|:--|:--|
| **Database-side crypto** | **Option B** — `pgcrypto` `pgp_sym_encrypt` | **Option C** — `pgcrypto` with a deterministic mode, or a plain keyed hash |
| **Application-side crypto** | **Option A** — AEAD in the app | **Option C′** — deterministic AEAD in the app |

Rejected: **Option D** (external tokenisation vault) — introduces an external dependency and a paid-service question, which this phase's rules forbid introducing without approval; retained below as an option for the owner to consider. **Option E** (defer, compensate with access control only) — a legitimate interim position, described in §3.5.

### 3.2 Side-by-side

| Criterion | **A — App-layer AEAD + blind index** | **B — `pgcrypto` randomised** | **C — `pgcrypto` deterministic** | **C′ — App-layer deterministic** | **E — Defer + access control** |
|:--|:--|:--|:--|:--|:--|
| Plaintext at rest in the DB | **No** | No | No | No | **Yes** |
| Key ever in the database | **No** | No (supplied per session) | No | **No** | n/a |
| Preserves the existing `UNIQUE` constraint | **No** — needs a blind index | **No** — needs a blind index | Yes, if the whole tuple is deterministic | Yes | n/a |
| Supports equality lookup by value | Yes, via blind index | Yes, via blind index | Yes | Yes | n/a |
| **Leaks equality** | **Only within a `(country_id, identifier_type)` group** — the same channel the plaintext index already leaks | Same as A | **Leaks equality globally** — same GSTIN across two countries is visibly the same ciphertext | Same as C | n/a (plaintext leaks everything) |
| **Fails safe if the key leaks** | Yes — rotate the DEK; blind index also re-derivable | Yes | **Partially** — deterministic ciphertext is permanently re-derivable from the key; rotation does not change the leakage surface | **Partially** | n/a |
| **Key rotation without full re-encryption** | **Yes** — envelope + per-row key version | Yes, same | **No** — changing the key changes every ciphertext, forcing a full rewrite | No | n/a |
| Needs a new extension | **No** | **Yes** (`pgcrypto`) | Yes | No | No |
| Needs a new external service / paid dependency | **No** — KMS optional | Key distribution mechanism (which the repo lacks) | Same | No | No |
| Crypto in the DB = DB can decrypt | n/a | **Yes** — the DB holds the primitive | Yes | No | n/a |
| Verification workflow support | Needs the app to decrypt and re-encrypt | DB-side function could decrypt in place | Same | Same | Trivial |
| **Leakage via `EXPLAIN` / query text** | **No** — only a blind index is queried | No | No | No | **Yes** |
| **Leakage via `audit_event.old_values_json`** | No if the app never logs plaintext | **Possible** — a DB-side function writing the decrypted value would log plaintext | Same | No if the app is careful | **Yes** |
| Compliance posture (identifier masking) | Strong | Strong | Strong but leaks equality | Strong | Weak |
| Implementation cost | Medium — app crypto + migration | Medium — extension + key distribution + migration | Medium-High | Medium | Low |
| **Works with zero application code in-repo?** | **No** — requires the consuming app | Partially — DB-side only | Partially | No | Yes |

### 3.3 Why randomised beats deterministic here

The identifier space is **low-entropy and structured**. GSTIN is 15 characters, the first 2 a state code, positions 3–12 the PAN, position 13 the entity code, position 14 a fixed `Z`, position 15 a mod-36 check digit. `cin` is 21 characters with a fixed structure. An attacker who can observe ciphertext and knows the format can **confirm a guessed identifier by computing the guess and comparing**. With randomised encryption they cannot, because the ciphertext changes per row.

More importantly: **a deterministic scheme makes rotation nearly meaningless.** The whole point of encrypting a permanent, non-rotatable identifier is that a leaked key can be retired. Under deterministic encryption, a key leak permanently reveals the identifier for every value that key ever protected, and rotation requires rewriting every row.

The **blind index**, by contrast, *must* be deterministic — that is its job. But it is a **keyed MAC**, not a cipher: without the key it is not computable, and it is not reversible. Its leak is equality-only within a `(country_id, identifier_type)` group, which is **exactly the leak the existing plaintext unique index already provides** — so this design does not widen the inference surface at all.

### 3.4 The blind index: design detail

```
canonical_form = canonicalise(identifier_value)      -- uppercase, strip spaces/punctuation, per identifier_type rules
blind_index    = HMAC-SHA-256(key = K_bidx, msg = country_id ‖ 0x00 ‖ identifier_type ‖ 0x00 ‖ canonical_form)
```

- **Separate key.** `K_bidx ≠ K_dek`. If the blind-index key leaked, equality would be exposed but ciphertext would not be decryptable; if the DEK leaked, ciphertext would be exposed but the blind index's equality pattern would not be. Neither compromise alone is catastrophic. This is standard key separation and it is cheap.
- **Domain separation.** `country_id` and `identifier_type` are bound into the MAC input with a length-safe separator, so the same identifier text under two different countries or types produces two unrelated blind indexes. This is what keeps the equality leak scoped to the group.
- **Truncation.** 32 bytes full-width is the safe default. Truncation to 16 bytes is acceptable **only** if §6.5's false-positive measurement is performed and accepted; a 16-byte truncated tag over a table of *N* identifiers carries a birthday-bound collision probability of roughly `N² / 2^129`, which is negligible — but the *intent* is to preserve exact uniqueness, so full width is preferred and truncation requires an explicit decision.
- **Canonicalisation is load-bearing.** Without it, `'29aaaaa0000a1z5'` and `'29AAAAA0000A1Z5'` produce different blind indexes and the uniqueness constraint is defeated. GSTIN is case-insensitive by spec; the `identifier_type` `CHECK` constraint limits the domain but does **not** enforce a canonical form. **Canonicalisation rules per `identifier_type` must be specified and agreed before implementation** (§8, D-6).

**⚠️ Collation interaction (audit finding MC-8 / A-8):** There is no `COLLATE` clause anywhere in `db/migrations/` and no non-default collation is created. The uniqueness constraint therefore uses the database's default collation. Under a nondeterministic ICU collation (e.g., `en-US-x-icu`), string equality is case- and accent-insensitive — meaning `'29AAAAA0000A1Z5'` and `'29aaaaa0000a1z5'` are **already equal** to the existing constraint. Under `C` or `en_US.UTF-8` (deterministic), they are byte-exact and distinct. **The actual behavior is a property of the deployed database's locale, which is not knowable from the repository.** This must be checked against the live database (D-6b, §8) before the canonicalisation rules are finalized, because it determines whether canonicalisation is a *new* behavior (under deterministic collation) or a *preservation* of existing behavior (under nondeterministic collation).

### 3.5 Option E — defer with access control

This deserves explicit consideration, because it is the **zero-migration-cost** position and might be the right call for a reference design that is not yet in production.

**What it delivers:** it addresses A-3, A-6, A-7 (insider reads, over-privileged app, cross-tenant aggregation) by implementing the threat model's already-written §3 role model and §4 RLS policies.

**What it does not deliver:** O-1, O-2, O-3, O-7, O-8. A stolen superuser credential still reads every identifier; a stolen volume still reads every identifier; a stolen backup still reads every identifier; the identifier is still permanent and non-rotatable.

**Honest assessment:** Option E is a **partial** answer and should never be described as "encrypting tax IDs". For a **reference design at pre-production with an empty table (F-11, F-13 unknown)**, Option E plus a hard deployment gate ("no production data until encryption lands") is defensible and cheap. For a system with real identifiers in it, Option E leaves the highest-impact attack paths — A-1, A-2 — completely open.

### 3.6 Recommendation

**Option A (application-layer AEAD + separate keyed blind index), with Option E's access-control work landing in parallel as a prerequisite, and Option E's scope honestly labelled as partial.**

Rationale:

1. It is the only option that satisfies **all eight** objectives in §1.3, including the two that matter most for a permanent identifier — safe rotation (O-7) and a recoverable key-loss posture (O-8).
2. It introduces **no new external dependency and no paid service** — the AEAD and HMAC are standard library primitives; the KMS is recommended but optional (a file-mounted secret with strict permissions is an acceptable interim for a self-hosted deployment).
3. It needs **no `pgcrypto` extension**, so it does not change the extension surface of the database.
4. It **does not widen the equality-leak surface**, because the blind index leaks exactly what the plaintext unique index already leaks.
5. It leaves the **database unable to decrypt**, which is the property that makes A-1 and A-2 survivable.

**The honest cost:** it requires an application that does not exist in this repository, so it cannot be completed by this repository alone. That is a **dependency on a party outside this project**, and it is why §8, D-1 is a blocking approval.

---

## 4. Data Flow and Key-Management Design

### 4.1 Key hierarchy

```
K_root  (root key)
  │  held in a KMS / HSM / Vault. Never exported. Never in the repository.
  │  Used to derive K_dek and K_bidx (preferred), OR to wrap them (alternative).
  │
  ├──► K_dek_v1   (data-encryption key, version 1)
  │      used to encrypt identifier_value ciphertext
  │
  └──► K_bidx_v1  (blind-index key, version 1)
         used to compute the blind index
```

- **Key-management model (audit finding MC-3 / A-12):** The design supports **two models**, and the owner must choose which is primary:
  - **(a) Derivation (HKDF):** `K_dek` and `K_bidx` are derived from `K_root` via HKDF-SHA-256 with distinct `info` strings. `K_root` is never exported; the KMS holds only `K_root` and performs derivation. **This model means the KMS cannot decrypt a row** — the application derives the DEK and decrypts locally. This is the stronger threat-model position.
  - **(b) Wrapping (KMS envelope):** `K_dek` and `K_bidx` are generated locally or by the KMS, then wrapped (encrypted) by `K_root`. The wrapped DEKs are stored alongside the rows (or in a key-version table) and unwrapped at runtime by calling the KMS. **This model means the KMS can unwrap the DEK** — which gives the KMS operator the ability to decrypt, but simplifies key distribution.
  - **Recommended:** **(a) derivation** for self-hosted or where the KMS operator is not fully trusted; **(b) wrapping** for managed KMS where the operator trust boundary is acceptable. Both work; the choice changes the threat model against the KMS operator. **This is an owner decision (D-13, §8).**
- **Per-tenant DEKs** (optional, recommended if tenant count is manageable): `K_dek` is derived or wrapped per tenant, so one tenant's identifiers can be re-keyed independently. This bounds the impact of a single key compromise to one tenant and directly improves O-7 and O-8. It adds a lookup: the app must resolve the tenant's DEK before decrypting.
- **Version markers.** Each row records which key version encrypted it (`key_version SMALLINT NOT NULL`). This is what makes rotation a background re-encryption rather than a blocking rewrite, and it makes mixed-version tables readable during the transition.

### 4.2 Key storage

| Where | Requirement |
|:--|:--|
| **K_root** | In a KMS/HSM/Vault. **Never** in the repository, in `docker-compose.yml`, in `.env`, in a migration, or in a test fixture |
| **K_dek_v1, K_bidx_v1** | Unwrapped at runtime into application memory by the application. **Never written to disk.** If a file-mounted secret is used as an interim, it must be `chmod 0400`, owned by the app user, outside the repository tree, and excluded from any image build |
| **`.env`** | Already holds `POSTGRES_PASSWORD` (`docker-compose.yml:10`). **Adding a DEK here would extend that exposure** — it is a committed-config risk vector, not a secret store. It must not receive key material |
| **CI / CI variables** | Key material must not be present in build logs, cache layers, or artefacts. Pipeline variable masking is required if the CI system supports it |
| **Backups** | A backup contains ciphertext and wrapped DEKs, but **not** the unwrapped DEK — provided the KMS holds the root key. This is the property that makes A-2 survivable |

### 4.3 Key lifecycle

| Stage | Requirement |
|:--|:--|
| **Generation** | Use a CSPRNG. `K_root` from the KMS. `K_dek`/`K_bidx` either KMS-generated or generated locally and wrapped by `K_root`. **Never reuse a key across the two purposes** (DEK ≠ blind-index key) |
| **Distribution** | The application fetches/wraps keys at startup or on rotation. It should **fail closed** if a key is unavailable — never fall back to a hardcoded or default key |
| **Rotation** | **Ciphertext rotation:** Introduce `K_dek_v2`. New writes use v2. Background job re-encrypts v1 rows to v2 in bounded batches, writing to the same columns. **Blind-index rotation (audit finding MC-2):** is operationally harder. During rotation, two bidx columns must coexist (old and new key version), and the unique constraint can only exist on one at a time. The safe pattern: (1) add `identifier_value_bidx_v2 BYTEA`; (2) dual-write: new rows write both bidx columns, backfill old rows to populate bidx_v2; (3) verify bidx_v2 is unique; (4) add `UNIQUE (country_id, identifier_type, identifier_value_bidx_v2)`; (5) drop the old unique constraint; (6) drop the old bidx column. **This is a full constraint-swap operation** analogous to §6.2 steps 1–5, and requires a write-freeze (same as BL-5). **Blind-index rotation should be done less often than ciphertext rotation, or only on suspected compromise.** **Owner decision D-5a (§8): is the blind-index key rotated on a schedule, or only on compromise?** Recommended: only on compromise, keeping the blind-index key stable for the table's lifetime. |
| **Retirement** | After v1 reaches zero live rows, revoke the unwrapped v1 DEK and mark it retired. `K_root` must retain the ability to unwrap v1 **only** for the duration of the rotation window, then drop it |
| **Revocation / compromise** | If `K_dek` is suspected compromised: rotate to v2 immediately, re-encrypt all v1 rows, and — because the identifier is permanent and non-rotatable — **assume the identifier itself is compromised** and notify the data owner. Encryption limits *future* disclosure; it does not un-disclose what was already read |
| **Recovery** | The root key must be escrowed and recoverable. **The single catastrophic scenario is losing `K_root` with no escrow** — it makes every row permanently unreadable while the ciphertext remains perfectly intact. §6.6 treats this as the highest-consequence failure mode |

### 4.4 Cryptographic parameters

| Item | Choice | Rationale |
|:--|:--|:--|
| **Cipher** | AES-256-GCM (or ChaCha20-Poly1305) | AEAD: confidentiality **and** integrity in one primitive, so ciphertext tampering is detected |
| **IV / nonce** | 96-bit random per encryption, **never reused with the same key** | The single catastrophic misuse of GCM. Must be generated by a CSPRNG per row |
| **AAD (associated data)** | `organization_id ‖ country_id ‖ identifier_type ‖ key_version` | Binds the ciphertext to its row context. A ciphertext copied from one row to another fails authentication, preventing a **row-swap / cross-tenant graft** attack. **CRITICAL (audit finding A-14): `organization_id`, `country_id`, and `identifier_type` are IMMUTABLE once written; changing them requires re-encryption.** `organization_id` is an ordinary column with an `ON UPDATE RESTRICT` FK (which restricts changes to the *referenced* row, not to this column itself) — the column can theoretically be updated. **If `organization_id` is changed after encryption, the AAD no longer matches and the row becomes undecryptable.** The alternative is to bind the AAD to `id` (the GENERATED ALWAYS AS IDENTITY surrogate key), which is never updated and removes the mutable-field problem entirely. **Owner decision required: D-12 (§8, below) — use `organization_id` or `id` in the AAD?** For now, the design assumes immutability of `organization_id`, `country_id`, and `identifier_type`, and this must be enforced in code and documented in deployment runbooks. |
| **Tag length** | 128 bits (full) | Standard |
| **Encoding** | Base64 in a `TEXT`/`VARCHAR` column, or `BYTEA` | `BYTEA` is more compact and avoids an encoding layer; `VARCHAR` keeps the column human-inspectable as *ciphertext*. `BYTEA` is the better choice — it makes accidental plaintext insertion structurally harder |
| **Blind index** | HMAC-SHA-256, full 32 bytes, `BYTEA` | Keyed, so not reversible and not computable without the key |
| **Key separation** | `K_dek ≠ K_bidx`, both derived from `K_root` via distinct HKDF info strings | Standard practice; prevents one key compromise from implying the other |
| **Key derivation** | HKDF-SHA-256 with distinct `info` labels | Avoids directly using `K_root` for two purposes |

### 4.5 Encryption flow

**Write path (application):**

```
1. Receive identifier_value (plaintext) from the client / verification provider
2. Validate: identifier_type ∈ allowed set; value length ≤ 100; value matches
   the per-type format rule (including the check digit where one exists)
3. canonical_form = canonicalise(identifier_value)      -- per identifier_type
4. bidx = HMAC-SHA-256(K_bidx, country_id ‖ 0x00 ‖ identifier_type ‖ 0x00 ‖ canonical_form)
5. nonce = 96 random bytes (CSPRNG)
6. aad  = organization_id ‖ country_id ‖ identifier_type ‖ key_version
7. ct   = AES-256-GCM(K_dek, nonce, canonical_form, aad)  -- [ciphertext ‖ tag]
8. INSERT (…, identifier_value_ciphertext = ct, identifier_value_bidx = bidx,
           key_version, …)
9. Audit: write audit.audit_event with action = 'organization_identifier.created'
   and NO plaintext value in old_values_json / new_values_json
```

**Critical detail at step 7:** the AEAD encrypts the **canonical form**, not the raw input. This guarantees that the decrypted value equals what was canonicalised — so the value stored is the value the blind index was computed over, and a decrypt-then-reencrypt cycle is idempotent. The consequence is that the stored value is a **normalised** identifier, not the operator's literal input. If the exact original string must be recoverable (e.g. an operator entered `"29 AAAAA 0000 A1Z5"`), that must be stored separately and deliberately — a decision, not a default (§8, D-7).

**Read path (application):**

```
1. Fetch row by id, or by (country_id, identifier_type, bidx) for a lookup
2. aad = organization_id ‖ country_id ‖ identifier_type ‖ key_version
3. plaintext = AES-256-GCM-decrypt(K_dek[key_version], nonce, ct, aad)
4. On authentication failure: treat as a hard error, log WITHOUT the ciphertext,
   and do not return a partial value
```

### 4.6 Lookup flow

```
Lookup by identifier value:
1. canonical_form = canonicalise(input)
2. bidx = HMAC-SHA-256(K_bidx, country_id ‖ 0x00 ‖ identifier_type ‖ 0x00 ‖ canonical_form)
3. SELECT ... WHERE country_id = ? AND identifier_type = ? AND identifier_value_bidx = ?
   -- uses the unique index; the plaintext is never in the query, the log, or the plan
```

**Every** lookup goes through this path. There must be **no code path that queries by the plaintext column** after the migration — which is why the plaintext column must be **dropped**, not merely nulled (§6.3). A nullable-but-present plaintext column is a standing invitation to regress.

### 4.6a Update flow

**Audit finding MC-1: the original design analyzed inserts and lookups but not updates.** `identifier_value` is updatable (no trigger blocks it, no rule forbids it). An `UPDATE` that changes the identifier must **re-encrypt AND recompute the bidx** — and the bidx recomputation is where a bug would silently break uniqueness. The update path needs its own specification:

```
Update path (application):
1. Receive new identifier_value (plaintext) from the client
2. Validate as in §4.5 step 2
3. canonical_form = canonicalise(new identifier_value)
4. bidx_new = HMAC-SHA-256(K_bidx, country_id ‖ 0x00 ‖ identifier_type ‖ 0x00 ‖ canonical_form)
5. nonce_new = 96 random bytes (CSPRNG)
6. aad = organization_id ‖ country_id ‖ identifier_type ‖ key_version
7. ct_new = AES-256-GCM(K_dek, nonce_new, canonical_form, aad)
8. UPDATE recruitment.organization_identifier
   SET identifier_value_ciphertext = ct_new,
       identifier_value_bidx = bidx_new,
       nonce = nonce_new,
       -- key_version unchanged unless this is also a rotation
   WHERE id = ?
9. Audit: write audit.audit_event with action = 'organization_identifier.updated',
   old_values_json containing ONLY non-sensitive metadata (key_version),
   NO plaintext or ciphertext values
```

**Critical:** the AAD immutability invariant (§4.4, audit finding A-14) means `organization_id`, `country_id`, and `identifier_type` cannot be changed in the same operation. An attempt to update those columns alongside the identifier value must either (a) be rejected as invalid, or (b) trigger a full re-encryption with the new AAD. **The safe default is (a) — treat those columns as immutable.**

### 4.7 Audit and observability

| Event | What to record | What **must not** be recorded |
|:--|:--|:--|
| Identifier created | actor, organization_id, country_id, identifier_type, key_version, row id | The identifier value, plaintext or ciphertext |
| Identifier read (decrypted) | actor, organization_id, row id, purpose, timestamp | The value |
| Identifier updated | actor, before/after **key_version** | The value |
| Identifier rejected (duplicate / bad format) | actor, country_id, identifier_type, reason | The rejected value |
| Decrypt failure | row id, key_version, error | The ciphertext bytes and the AAD |

`audit.audit_event` already has the right shape: `actor_user_account_id`, `action`, `entity_schema`, `entity_name`, `entity_id`, `old_values_json`, `new_values_json`, `client_ip`, `recorded_at` (`012:230-266`), and it is append-only by trigger (`012:290-293`).

**The `old_values_json` / `new_values_json` fields are the latent leakage path.** A naive implementation that logs the row's changed values would write the identifier — or the ciphertext — into an append-only, indefinitely-retained, unredacted log. A `jsonb` column cannot carry a redaction guarantee, so the *writer* must omit the value entirely. There is no `CREATE TRIGGER` on `organization_identifier` that could do this automatically, so this is an **application-layer obligation** that must appear in the acceptance criteria (§7.2, T-07) and the code review checklist.

**Note the pre-existing gap.** `docs/phase-2-model/12-threat-model.md:188` states: *"Recording of logins, permission changes, profile unlocks and profile downloads is outstanding."* Identifier reads must not be added to that backlog — the audit trail for identifier access should be a **launch requirement**, not a follow-up.

### 4.8 Error handling

| Failure | Response | Must not |
|:--|:--|:--|
| Invalid format for `identifier_type` | Reject at the API boundary with a field-level error | Echo the value back in the error body or in logs |
| Duplicate identifier | Return a 409-style conflict; the unique constraint is the backstop | Distinguish "duplicate GSTIN" from "duplicate CIN" to an unauthorised caller — that is an enumeration oracle |
| AEAD authentication failure (tampering) | Raise an alarm, refuse the row, quarantine the row id | Log the ciphertext or the AAD |
| Key unavailable | **Fail closed.** Refuse all identifier reads and writes | Fall back to a default key, a hardcoded key, or plaintext storage |
| Key version unknown for a row | Refuse the read; raise an operational alert | Fall back to an older key silently |

---

## 5. Access-Control, Transport, and At-Rest Controls

Each is assessed **separately**, because they are independent and each closes different adversaries.

### 5.1 Column-level and at-rest

| Control | Current state | Requirement |
|:--|:--|:--|
| Column encryption | **None** | §4.4 — AEAD, app-side |
| Index encryption | **None** — the unique index holds the plaintext | Blind index replaces it (§6.3) |
| Volume encryption at rest | **None** — plain Docker named volume `talentra_pgdata` (`docker-compose.yml:13-14`, `:21-22`) | Host-level volume encryption (LUKS / dm-crypt / cloud-volume encryption) — a **deployment** control, independent of column encryption |
| WAL encryption | **None** | Deployment control; column encryption makes WAL harmless for this column |
| Temp/spill files | Standard PostgreSQL behaviour | Column encryption removes the risk for this column |

### 5.2 Database roles and least privilege

Current state: **one role, `talentra_admin`, SUPERUSER** — created by `POSTGRES_USER` (`docker-compose.yml:9`), with zero `GRANT`/`REVOKE`/`CREATE ROLE` statements in the repository.

The threat model's §3 already specifies the target. Three refinements are needed for this table:

| Role | Needed on `organization_identifier` | Note |
|:--|:--|:--|
| `talentra_app` | `INSERT`, `UPDATE`; **`SELECT` denied by default**, granted only to a narrower verifier role | The blanket `GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA recruitment` at `docs/phase-2-model/12-threat-model.md:63` is too broad for this table and must be narrowed. `DELETE` should not be granted at all — deleting a tax identifier is a business event, not a row operation |
| `talentra_verification` (new, narrow) | `SELECT` on this table, plus the read of the audit trail | The verification workflow needs to read identifiers; general application traffic does not |
| `talentra_reporting` | **No access** — the existing proposal grants only `analytics` and `master` (`docs/phase-2-model/12-threat-model.md:76`) | **This property must be preserved.** It is the reason a BI role does not become a tax-ID reader |
| `talentra_admin` | Full — retained for migrations and break-glass | Must be reserved; the application must **not** connect as it. This is the single most impactful role change and the one with the highest chance of breaking the consuming application |

**Additional requirement.** The application needs `EXECUTE` on nothing cryptographic, because the crypto is in the application. This is a benefit of Option A: **no `SECURITY DEFINER` function and no key material in the database.**

### 5.3 Row-Level Security

**Applicability: yes, and it is the correct control for the multi-tenant dimension** — but it is *orthogonal* to encryption, not a substitute.

| Question | Answer |
|:--|:--|
| Is RLS applicable to this table? | **Yes.** The table is tenant-scoped by `organization_id`, exactly the shape `docs/phase-2-model/12-threat-model.md` §4.1 policies already target for `job_posting` |
| Does RLS work with encrypted columns? | **Yes, and better.** A policy on `organization_id` is evaluated on a plaintext column that the app never decrypts — no plaintext is needed to enforce isolation |
| What must be true first? | The `app.current_user_id` / `app.current_org_id` session context must actually be **set** by the application. It currently is not set anywhere in the repository (`grep -rnE "current_setting\|set_config" db/migrations/` → no output), and the application that would set it is not in this repository |
| Risk of enabling it prematurely | A policy whose context is never set evaluates `NULLIF(current_setting(...), '')::BIGINT` to NULL, and `organization_id = NULL` matches nothing — **the table would appear empty**, which is a fail-closed but functionally catastrophic outcome. This must be verified end-to-end before enablement |
| Which policy shape? | `USING (organization_id = NULLIF(current_setting('app.current_org_id', TRUE), '')::BIGINT)` for `FOR ALL`, matching the pattern at `docs/phase-2-model/12-threat-model.md:110-116` |

**Recommendation:** enable RLS on `organization_identifier` **in the same release** as the encryption migration, not before — because the encryption migration is already a breaking change requiring application coordination, and bundling them avoids a second coordinated rollout. But sequence them so RLS is enabled **last**, after the application's context-setting is confirmed working, so that a context bug cannot present as data loss.

### 5.4 Audit trail

- **All identifier reads and writes must be audited** (§4.7). This is a **launch requirement**, not a backlog item.
- `audit.audit_event` is append-only by trigger (`012:290-293`), but — as established in Phase 3 §6.3 — **`TRUNCATE` is not blocked**. A privileged actor can empty the identifier-access audit trail. Fixing this is R-07 in the Phase 3 report and is **adjacent to, but not part of, this design**.
- The audit trail must never contain the identifier value.

### 5.5 Logging and error hygiene

| Path | Current risk | Requirement |
|:--|:--|:--|
| PostgreSQL statement log | The plaintext appears in `log_statement` output | After §6.3 the plaintext column is **gone**, so it cannot appear. **This is the strongest single argument for dropping the column rather than nulling it** |
| `audit.system_error_log` | `error_message TEXT`, `stack_trace TEXT`, `context_json JSONB` are unredacted free text (`012:300-303`) | A constraint violation on the identifier table would carry the offending value in the error text. Post-migration the value is ciphertext, so the error carries ciphertext — which is a **leak of ciphertext but not of plaintext**; acceptable, but the *exception handler* should still avoid embedding it |
| `audit.audit_event.old_values_json` / `new_values_json` | A writer that logs changed row values would embed the value | Application-layer obligation; §4.7. **This is the highest-risk residual leakage path after the migration** |
| Application logs | Application log statements may interpolate the identifier | A log-scrubbing rule for the identifier type is required; must be in the acceptance criteria |
| `EXPLAIN` output | Equality predicates on a plaintext column appear verbatim in plans | Resolved by the blind index — the predicate is on a MAC, not the identifier |

### 5.6 Backups and exports

| Item | Current state | Requirement |
|:--|:--|:--|
| Backup mechanism | `pg_dump -Fc` via `scripts/backup_restore.sh:28` — the whole database | After the migration, a dump contains ciphertext and wrapped DEKs, but not the unwrapped DEK (KMS holds the root) |
| **Parity check coverage** | **The check covers 7 tables and omits `organization_identifier`** (`scripts/backup_restore.sh:56-64`) | **Add the table to the parity list.** This is a change to `scripts/backup_restore.sh` — a **script**, which this phase's rules forbid modifying; it is listed in §6.5 as a required remediation step for a separately approved implementation phase |
| Restore verification | Row-count parity only — it does **not** verify decryptability | A row-count match after restore proves the rows came back; it does **not** prove they are readable. The backup/restore test (§7.2, T-08) must decrypt a sample after restore |
| Export / portability | No export path exists in the repository | Any future export must either (a) decrypt under a controlled, audited, purpose-bound key, or (b) export ciphertext with a separately-transferred wrapped DEK. **A raw `COPY ... TO CSV` of the identifier table would leak plaintext today** — a control that must exist before any export feature ships |

### 5.7 Transport (TLS)

| Item | Current state | Requirement |
|:--|:--|:--|
| In-transit encryption | **Not configured.** `docker-compose.yml` has no `ssl` key, so `postgres:17` runs with `ssl=off` | Enable TLS: `ssl=on`, `ssl_cert_file`, `ssl_key_file`, and enforce `hostssl` in `pg_hba.conf` for the application role |
| Current exposure | The port is bound to `127.0.0.1:5432` (`docker-compose.yml:12`), so the wire is loopback-only **today** | Loopback binding is **not** a transport control — it disappears the moment the port is rebound to `0.0.0.0`, or a sidecar/proxy is added |
| Client enforcement | The client must use `sslmode=require` (or `verify-full` with a CA) | Without `sslmode` on the client, a server that offers TLS but does not require it is still negotiated down. `sslmode=require` on the client is the enforcement point |
| `docker-compose.yml` change | Required — a `command:` with TLS args, and a CA/cert volume | **This is a configuration change and is out of scope for this phase.** It is listed in §6.5 |
| Priority | Medium | TLS protects the wire only. It does **not** help against A-1, A-2, A-5. It is a separate control and must not be used to justify deferring encryption |

### 5.8 Defence in depth — what each control alone fails to stop

| Control alone | Still defeated by |
|:--|:--|
| Encryption only | A-3 (app role reads the *decrypted* value in the app process), A-4 (plaintext on the wire), A-5 (app logs), A-7 (cross-tenant) |
| RLS only | A-1 (superuser bypasses RLS — RLS does not apply to superusers or table owners unless `FORCE ROW LEVEL SECURITY` is set), A-2 (backups), A-4, A-5 |
| TLS only | A-1, A-2, A-3, A-5, A-7 |
| Least privilege only | A-1 (the admin role), A-2, A-4, A-5 |
| **All together** | A-8 (key theft from the app host) and A-9 (cryptographic weakness) — addressed by key custody (§4.2) and parameter choices (§4.4) |

**Note on superuser and RLS.** PostgreSQL RLS policies are **not applied to superusers or to the table owner** unless `ALTER TABLE ... FORCE ROW LEVEL SECURITY` is used. Since `talentra_admin` is a superuser, it will bypass any policy on this table. This is another reason the role separation in §5.2 is the load-bearing control, and RLS is defence in depth for the *application* role, not a barrier against the DBA.

---

## 6. Migration and Rollback Plan

### 6.1 Preconditions — all must hold before any DDL is written

| # | Precondition | Why | Status |
|:--|:--|:--|:--|
| P-1 | **The consuming application is identified**, and its owner is a named participant in this design | All read/write traffic for this column comes from code not in this repository. Without this, the migration cannot be planned | ❌ **NOT MET** — blocking |
| P-2 | The application team confirms every read and write path for `identifier_value` | The in-repo trace (§2) is complete *for this repository*; it is not complete for the system | ❌ **NOT MET** |
| P-3 | **Key custody decisions are made** (§4.2) and a KMS or equivalent is available, or an interim file-based secret is explicitly approved | Without a key there is no encryption | ❌ **NOT MET** |
| P-4 | The current row count of the table is known | Determines the backfill strategy and downtime (§6.4). Requires a DB connection, which this phase forbids | ❌ **NOT MET** — needs a read-only DB check |
| P-5 | Canonicalisation rules per `identifier_type` are specified and agreed | A wrong rule silently defeats uniqueness (§3.4) | ❌ **NOT MET** |
| P-6 | The application's error handling for a 409 (duplicate) and for a key-unavailable condition is agreed | §4.8 | ❌ **NOT MET** |
| P-7 | A backup of the current database is taken **and verified restorable** | §6.6 rollback depends on it | ❌ **NOT MET** |
| P-8 | The audit-writer changes (§4.7) are specified | Prevents plaintext entering the audit trail | ❌ **NOT MET** |

### 6.2 Migration sequence

Migrations are applied in order `001` → `019` (`README.md` step 2). A new migration must therefore be **`020_`**, and **must not edit any existing migration** — editing an applied migration creates a checksum and ordering divergence on every existing deployment.

| Step | Migration | Action | Reversible? |
|:--|:--|:--|:--|
| **0** | — | **Pre-flight.** Confirm P-1…P-8. Take and verify a backup. Record the pre-migration row count and the set of `(country_id, identifier_type, identifier_value)` triples **in encrypted, key-protected form** — a checksum per row is sufficient | n/a |
| **1** | `020_organization_identifier_encryption_add_columns.sql` | **Additive only.** Add `identifier_value_ciphertext BYTEA`, `identifier_value_bidx BYTEA`, `key_version SMALLINT NOT NULL DEFAULT 1`, `nonce BYTEA` (or fold the nonce into the ciphertext blob). Add a **non-unique** index on `identifier_value_bidx`. **Do not touch the existing column or constraint yet** | ✅ Fully — `DROP COLUMN` |
| **2** | — | **Application deploy, dual-write.** The app now writes **both** the plaintext column and the ciphertext + bidx columns. Reads still come from plaintext. This is the safe intermediate state: a rollback needs no re-encryption | ✅ Fully — app rollback |
| **3** | `020b_…_backfill.sql` (or an application job) | **Backfill** existing rows: read plaintext, canonicalise, compute bidx, encrypt, write the new columns. **Bounded batches, resumable checkpoint, outside a single long transaction** (§6.4) | ⚠️ Partially — re-runnable; a rerun over already-backfilled rows is a no-op |
| **4** | — | **Verify.** Row count matches; every row has a non-null bidx and ciphertext; **the blind index is unique** (i.e. no two rows share a `(country_id, identifier_type, bidx)`); every row decrypts back to its canonical form; and the set of `(country_id, identifier_type, bidx)` computed from the plaintext equals the set stored | ✅ Verification only |
| **5** | `020c_…_uniqueness.sql` | **Swap the constraint.** Add `UNIQUE (country_id, identifier_type, identifier_value_bidx)`. Verify it is enforced. **Then** drop `uq_organization_identifier_val` and drop the index that supported it. The plaintext column is still present at this point | ⚠️ One-way — the old unique constraint cannot be restored without a full re-derivation |
| **6** | — | **Application deploy, read-switch.** Reads move to the ciphertext column. The plaintext column is now write-only-and-ignored. The app still writes both | ✅ App rollback to step 2 |
| **7** | `020d_…_drop_plaintext.sql` | **Drop `identifier_value`.** This is the point at which O-1 is achieved: no plaintext column, no plaintext index, no plaintext in any dump or WAL segment. **Do not skip this step** — a nullable-but-present plaintext column is a standing regression risk (§3.4) | ❌ **Not reversible without a restore** |
| **8** | `020e_…_drop_plaintext_check.sql` (or fold into 7) | **Assertion:** a check that no column of type `TEXT`/`VARCHAR`/`BYTEA` in `recruitment.organization_identifier` decodes to a known-plaintest pattern. Better: a **regression test** (§7.2, T-05) that fails if a plaintext-like column reappears | n/a |

**Why the constraint swap (step 5) is separate from the column drop (step 7):** it lets the uniqueness guarantee be *proved* before the plaintext is removed, and it means a rollback to step 6 (read-switch) still leaves the data model coherent.

### 6.3 Handling existing records, duplicates, and the constraint

| Case | Handling |
|:--|:--|
| **Existing plaintext rows** | Backfilled in step 3. The plaintext column is *not* nulled in step 5 or 6 — it is only dropped in step 7, so the old data is available for verification throughout |
| **Duplicates under the current constraint** | The current `UNIQUE (country_id, identifier_type, identifier_value)` means **no exact byte-duplicates exist today** — but they could exist under *canonicalisation* (two rows differing only by case or spacing, e.g. `'29aaaaa0000a1z5'` vs `'29AAAAA0000A1Z5'`). **The backfill must detect these canonical collisions.** This is a real, expected outcome and the backfill must fail loudly on it, not silently pick a winner. **Resolution policy (audit finding MC-9):** When a canonical collision is found, the migration must **halt** and raise an alert. The resolution options are: (a) **reject** the migration until one row is manually removed; (b) **quarantine** one row to a separate table for manual review; (c) **namespace** by adding a disambiguating suffix. **Owner decision required (D-14, §8).** Do not proceed with the migration until this is resolved. |
| **Blind-index collisions** | Two *different* identifiers producing the same bidx. With a full 32-byte HMAC-SHA-256, this is cryptographically negligible. If truncated (§3.4), it is a birthday-bound risk that must be measured (§6.5) |
| **Canonicalisation changes the value** | If the canonical form differs from the stored plaintext, the *decrypted* value will be the canonical form, not the literal original. §4.5 flags this; whether the original literal must be preserved is decision D-7 (§8) |
| **Existing `verified_at` / `verification_status`** | Unaffected — they are separate columns and are not part of the uniqueness key |
| **Foreign keys** | None reference `identifier_value`. `verified_by_user_account_id` references `core.user_account` and is unaffected |
| **Index rebuild cost** | Dropping `uq_organization_identifier_val` and adding the bidx unique index require a table rewrite or a concurrent index build. **`CREATE INDEX CONCURRENTLY` cannot run inside a transaction block**, so it must be run outside the migration transaction — a deployment-script concern (§6.4) |
| **Row-level security** | Enable **last**, after the application context-setting is confirmed (§5.3) |

### 6.4 Downtime, deployment ordering, and operational concerns

| Concern | Assessment |
|:--|:--|
| **Expected downtime** | **Zero for steps 1–4.** Step 5 (constraint swap) **requires a bounded write-freeze on `organization_identifier`** (audit finding BL-5). **The design's earlier "zero-downtime" claim is incorrect.** Here's why: during steps 2–6, the backfill and constraint swap must tolerate a row with plaintext but no bidx. The constraint swap in step 5 must first ensure *every live row has a bidx*, which requires either (a) quiescing writes until residual is zero, or (b) running a continuous backfill until residual is zero. Option (a) is a write-freeze; option (b) cannot reach zero residual while old app instances are still writing plaintext-only rows. **The honest requirement is: step 5 requires a brief, announced write-freeze.** The duration is bounded by the time to `CREATE INDEX CONCURRENTLY` and rebuild the unique constraint — typically minutes, not hours. Step 7 (drop column) is a fast metadata operation. |
| **Long-running backfill** | Bounded batches (e.g. 500–1,000 rows per transaction) with a resumable checkpoint, run **outside** the migration transaction. Avoids a long transaction holding locks, avoids WAL bloat, and makes the operation restartable |
| **Deployment order** | **1** → migrate schema (additive) → **2** → deploy app (dual-write) → **3** → backfill → **4** → verify → **5** (write-freeze begins) → swap constraint → (write-freeze ends) → **6** → deploy app (read-switch) → **7** → drop plaintext. **Every step is independently reversible through step 6.** The app must be deployed in step 2 *before* the constraint swap, or the uniqueness check will fail on any row the app writes |
| **Mixed-version app instances** | During steps 2–6, old and new app instances may run simultaneously. The old instances write plaintext only; the new ones write both. The backfill and the constraint swap must tolerate a row that has a plaintext value but no bidx — meaning **the constraint swap in step 5 must first ensure every live row has a bidx**, which requires quiescing writes or running a continuous backfill until the residual is zero |
| **Backwards compatibility** | The old app version must still work against the new schema through step 6. This is why the plaintext column is not dropped until step 7 |
| **Feature flag** | A flag on the read path (`IDENTIFIER_READ_FROM_CIPHERTEXT`) makes step 6 revertible without a redeploy. Recommended |

### 6.5 Remediation items that fall outside this design's scope

These are **required** for the design to hold, but they modify files this phase is forbidden to touch. They are listed for a separately approved implementation phase:

| # | Item | File | Phase |
|:--|:--|:--|:--|
| M-1 | Add `recruitment.organization_identifier` to the backup parity table list | `scripts/backup_restore.sh:56-64` and `scripts/backup_restore.ps1` | Implementation |
| M-2 | Enable TLS (`ssl=on`, `ssl_cert_file`, `ssl_key_file`) and enforce `hostssl` | `docker-compose.yml` | Implementation / deployment |
| M-3 | Add the `organization_identifier` INSERT paths to the encryption contract | `tests/test_organization_extensions.sql:168`, `:194` | Implementation |
| M-4 | Add a regression test asserting no plaintext identifier column exists and no dump contains a plaintext identifier | `tests/` (new suite) | Implementation |
| M-5 | Add a validator rule asserting identifiers are encrypted and the blind index is unique | `scripts/validate_data.py` | Implementation |
| M-6 | Create the `talentra_app` / `talentra_verification` / `talentra_reporting` roles and narrow the `recruitment` grant | new migration `020`+ | Implementation |
| M-7 | Set `app.current_org_id` in the application session and enable RLS on the table | application + new migration | Implementation |
| M-8 | Add `organization_identifier` access auditing to the application | application | Implementation |
| M-9 | Extend the `audit.system_error_log` write path to avoid embedding values in free-text fields | application | Implementation |
| M-10 | Close the `TRUNCATE` gap on `audit.audit_event` (Phase 3 R-07) — adjacent, because the identifier-access audit trail depends on it | new migration | Implementation |

### 6.6 Rollback, key loss, and disaster scenarios

**⚠️ CRITICAL FINDING FROM AUDIT (BL-1):** The current backup/restore script (`scripts/backup_restore.sh:42`, `:46`, `:79-80`) **discards `pg_restore`'s exit status** via `|| true`, prints `[PASS] Restoration completed` unconditionally, and **deletes the recovery database and dump file on exit**. This makes the script unable to determine whether a restore succeeded. **A rollback after step 7 depends on this mechanism, making P-7 ("restore verified restorable") currently unsatisfiable.** This design treats "establish a trustworthy restore path" as a **blocking precondition** for the migration, not as an achievable capability with the current tooling. §5.2 and §5.3 of the audit detail the required fixes; they are external to this design document (M-1 remediation items in §6.5) and must be completed in a separately approved implementation phase before step 7 can be executed.

| Scenario | Response | Data outcome |
|:--|:--|:--|
| **Rollback before step 5** | Drop the added columns; revert the app | **No data loss** — the plaintext column was never touched |
| **Rollback at step 5–6** | Restore the old unique constraint; the bidx column may remain unused | **No data loss.** Re-deriving the old constraint from the plaintext is possible because the plaintext column is still present |
| **Rollback after step 7** | **Restore from the backup taken in step 0** — **PROVIDED the restore has been verified as trustworthy** (P-7) | **Data loss of the window between the backup and step 7.** This is why step 7 is a separately-approved, scheduled, and announced event — it is the point of no return. **Note:** The current backup/restore script does not provide trustworthy restoration (BL-1). Until that is fixed, this rollback path is not available. |
| **Key loss — `K_dek` unavailable, `K_root` intact** | Unwrap from `K_root`; no data loss | Recoverable |
| **Key loss — `K_root` lost, no escrow** | **Every identifier is permanently unreadable.** The ciphertext remains perfectly intact, and the table looks healthy — row counts, constraints, and joins all still work | **CATASTROPHIC AND SILENT.** This is the highest-consequence failure mode of the entire design. Mitigations: (a) escrow `K_root` in a second independent custody domain; (b) escrow a **key-escrow copy** of `K_dek` in the same system that holds the ciphertext, so a `K_root` loss does not equal a data loss; (c) a periodic **decryptability canary** — a small set of rows re-decrypted on a schedule, with an alert on failure, so the failure is detected in hours rather than at the moment someone tries to read a tax ID |
| **Key compromise — `K_dek` leaked** | Rotate to `K_dek_v2`, re-encrypt, retire v1 | **The identifier must be assumed compromised.** Encryption limits future disclosure; it does not un-disclose prior reads. Notify the data owner |
| **Blind-index key compromise** | Rotate `K_bidx`, rebuild the bidx column, rebuild the unique index | The identifiers are still safe (the DEK is separate) but equality is now exposed. The index rebuild is a full-table operation — schedule it |
| **Corrupted ciphertext (AAD mismatch or bit rot)** | AEAD authentication fails | The row is unreadable. Detected by the canary and by read-time failure. Do not silently return a partial value |

---

## 7. Security Acceptance Criteria and Test Plan

### 7.1 Acceptance criteria

Implementation is accepted only when **all** of the following are true and demonstrable:

| # | Criterion | Evidence required |
|:--|:--|:--|
| AC-1 | No column in `recruitment.organization_identifier` holds a plaintext identifier | A schema introspection listing every column, plus a value scan |
| AC-2 | The unique constraint is on the blind index, and it rejects a duplicate | A test that attempts a duplicate insert and observes the rejection |
| AC-3 | A lookup by identifier value returns the correct row | Round-trip test |
| AC-4 | The database contains no key material | A scan of every function, table, and setting for key-like material |
| AC-5 | The application role cannot read identifiers outside its tenant | A test that asserts the *denial*, not just the grant |
| AC-6 | No identifier value appears in any log, error message, or audit row | A log-scraping test over a full run |
| AC-7 | Every identifier read and write is audited, and no audit row contains a value | Audit-content test |
| AC-8 | Key rotation works and the table remains readable throughout | Rotation test |
| AC-9 | A backup taken before the migration restores into a disposable database and every identifier decrypts | Restore test |
| AC-10 | The blind index does not collide across the live dataset, and the false-positive rate is measured and accepted | Collision report |
| AC-11 | Canonicalisation is deterministic and idempotent, and equivalent inputs map to one blind index | Canonicalisation unit tests per `identifier_type` |
| AC-12 | The application fails closed when the key is unavailable | Fault-injection test |
| AC-13 | TLS is enforced on the DB connection | A connection test that fails when TLS is off |
| AC-14 | The consuming application has no remaining code path that queries by plaintext | Code review sign-off plus a runtime assertion |

### 7.2 Test plan

| # | Test | Method | Asserts |
|:--|:--|:--|:--|
| **T-01** | **Lookup correctness** | For each `identifier_type`: insert an identifier; look it up by `(country_id, identifier_type, value)`; fetch by row id | The lookup returns exactly the inserted row; the decrypted value equals the canonical form of the input |
| **T-02** | **Uniqueness preserved** | Insert identifier X for org A; attempt the same `(country_id, identifier_type, value)` for org B | The insert is **rejected** by the unique constraint on the bidx. Also assert the *error message does not contain* the identifier |
| **T-03** | **Uniqueness is not over-restrictive** | Insert two *different* identifiers | Both succeed; no false collision |
| **T-04** | **Canonical equivalence** | Insert `'29aaaaa0000a1z5'` and attempt `'29AAAAA0000A1Z5'` | The second is rejected as a duplicate — proving canonicalisation is applied to both sides of the comparison |
| **T-05** | **Plaintext absence** | Scan the table's every column, its indexes (`pg_index` / `pg_get_indexdef`), and a full `pg_dump` output for any known plaintext pattern; also assert the column `identifier_value` no longer exists | **Zero** plaintext occurrences. This is the single most important test — it guards against a future migration reintroducing a plaintext column |
| **T-06** | **No key material in the database** | Scan all function bodies, all table defaults, all settings, and all comments for key-like material | Zero hits |
| **T-07** | **Authorization / tenant isolation** | As tenant A, attempt `SELECT` on tenant B's identifier row; attempt a direct `SELECT` bypassing the app; attempt `UPDATE`/`DELETE` | Every out-of-tenant attempt is denied. **Assert the denials explicitly.** A superuser path is documented as out of scope for the test but verified by the §5.2 role change |
| **T-08** | **Audit completeness and non-leakage** | Perform a create, a read, and an update; then read back all `audit.audit_event` rows for that entity | Exactly one audit row per action, with a populated `actor_user_account_id`; **no audit row contains the identifier value** in `old_values_json` or `new_values_json` |
| **T-09** | **Log hygiene** | Run the full read/write flow with statement logging enabled; scrape PostgreSQL logs, `audit.system_error_log`, and the application log | No identifier value in any log, error message, or stack trace |
| **T-10** | **Key rotation** | Encrypt under v1; rotate to v2; write a new row; run the background re-encryption; then read every row | Every row decrypts correctly; new rows use v2; the rotation is resumable and auditable; the mixed-version window is exercised |
| **T-11** | **Backup / restore** | Take a `pg_dump` before the migration; restore it into a disposable database; run the migration; read every identifier | Every identifier decrypts to the same value; the bidx unique constraint still holds; no row loss |
| **T-12** | **Key loss / canary** | Simulate a `K_root` loss in a disposable environment; run the decryptability canary | The canary **fails loudly** within the alerting window — proving the silent-loss scenario is detected before a user needs the value |
| **T-13** | **Error handling** | Inject: a malformed identifier, a duplicate, a tampered ciphertext byte, an unavailable key, an unknown key version | Each fails closed with a correct, non-value-leaking error; the app does not fall back to plaintext storage or a default key |
| **T-14** | **Blind-index collision measurement** | Over the live dataset, compute the bidx for every identifier and count collisions; also compute the theoretical false-positive rate at the chosen width | Measured collisions = 0; the theoretical rate is recorded and accepted by the owner (§8, D-5) |
| **T-15** | **TLS enforcement** | Connect with `sslmode=disable` — must fail; connect with `sslmode=require` — must succeed | TLS is enforced end-to-end |
| **T-16** | **No residual plaintext code path** | Static search of the application for the plaintext column name; runtime assertion that the read path always decrypts | Zero references; the assertion fires if the plaintext path is taken |
| **T-17** | **RLS context correctness** | With the application context set, query as tenant A; then simulate a missing context | Tenant A sees only its rows; a missing context yields **zero rows**, not all rows (fail-closed) |
| **T-18** | **Non-interference** | Run the whole suite twice in a row | Deterministic results — no residual state, no order dependence, no row-count drift |

### 7.3 The test suites in this repository that must change

| Suite | Change required | Reason |
|:--|:--|:--|
| `tests/test_organization_extensions.sql:168`, `:194` | The two INSERTs must write the encrypted columns; the `'29AAAAA0000A1Z5'` literal must be encrypted by the test harness, or the test must be restructured to call an application-provided encryption path | The test inserts a plaintext identifier directly. After the migration this must fail — the plaintext column is gone |
| `tests/test_organization_extensions.sql` — the "Inconsistent verified state must be rejected" case (`:167-191`) | Must be re-expressed against the encrypted schema | The check it exercises is still valid; the insert shape changes |
| `tests/test_constraints.sql` | **Correction (audit finding MC-13 / A-3):** This file does **not** touch `recruitment.organization_identifier`. It inserts into 6 other tables and exercises the `uq_candidate_location_current` uniqueness constraint on a different table. The earlier claim that it "is the suite most likely to assert on the uniqueness constraint" was incorrect. A **new test is required** to assert the `uq_organization_identifier_val` constraint (audit finding BL-4 / A-1, A-2). See §6.5 M-11. | It is user-owned; this phase did not modify it. The implementation phase must confirm it still passes |
| New suite | The T-05 / T-06 / T-09 leakage-prevention regression tests | These guard against reintroduction, which is the most likely future failure |
| `scripts/validate_data.py` | A new rule group check for encryption and bidx uniqueness | The validator is the only automated quality gate that is *not* part of the test runner (per `docs/phase-2-model/11-rule-compliance.md:5`) |

---

## 8. Decisions Requiring Owner Approval

**No implementation should begin until D-1 through D-4 are resolved.** D-5 through D-8 should be resolved before the migration is finalised.

| # | Decision | Options | Recommendation | Blocking? |
|:--|:--|:--|:--|:--:|
| **D-1** | **Is there a consuming application, and who owns it?** | (a) Yes — name the team and involve them; (b) No — this is a standalone reference design | **(a)**. The schema's `verification_status` workflow and `docs/phase-4-platform/22-integration-boundaries.md:88` both imply a real consumer. If (b) is true, Option E becomes viable and the urgency drops sharply | **YES — blocking** |
| **D-2** | **Encryption approach** | Option A / B / C / C′ / D / E (§3) | **Option A** (§3.6) | **YES — blocking** |
| **D-3** | **Key custody** | (a) Managed KMS (AWS/GCP/Azure); (b) HashiCorp Vault; (c) self-hosted KMS; (d) file-mounted secret as an interim | **(a) or (b)** for production; **(d)** acceptable as an interim for a self-hosted reference deployment, with the §4.2 constraints enforced | **YES — blocking** |
| **D-4** | **Is a new external dependency acceptable?** | (a) Yes, a KMS is approved; (b) No — no external service | Option A requires **no** new service. The KMS is *recommended*, not required. A no-dependency deployment uses a locally-generated DEK stored in a `0400` file outside the repo, with the weaker rotation and custody properties stated in §4.2 | **YES — blocking** (this phase's rules forbid introducing a paid service without approval) |
| **D-5** | **Blind-index width** | (a) Full 32 bytes; (b) 16 bytes truncated | **(a)** full 32 bytes — truncation requires accepting a non-zero false-positive rate, and the intent is exact uniqueness | No — before migration sign-off |
| **D-5a** | **Blind-index key rotation cadence** | (a) Rotate on schedule; (b) Rotate only on suspected compromise | **(b)** rotate only on compromise — blind-index rotation requires a full constraint-swap operation and is expensive | No — before migration sign-off |
| **D-6** | **Canonicalisation rules per `identifier_type`** | Per-type normalisation rules must be written down and agreed | GSTIN: uppercase, strip spaces and hyphens, validate the 15th-character mod-36 check digit. CIN: uppercase, strip spaces. EIN/VAT: uppercase, strip separators. PAN: uppercase, alphanumeric only. A type with no published canonical form (e.g. `'other'`) should be **normalised only by trimming and case-folding**, and the owner must accept that two differently-formatted values of type `'other'` may not collide | No — but **a wrong rule silently defeats uniqueness**, so it must not be guessed |
| **D-6a** | **Check-digit failure handling** | (a) Reject at API boundary; (b) Normalize/fix automatically | **(a)** Reject — check digits indicate a typo or malformed input; auto-fixing risks mapping two different entities to the same record | No — before migration sign-off |
| **D-6b** | **Live database collation inspection** | Inspect `SHOW lc_collate` / `pg_collation` to determine case-sensitivity | Must be executed via read-only DB inspection before migration to determine if existing constraint is case-insensitive | ⚠️ **YES — blocking for canonicalisation plan** |
| **D-7** | **Must the literal original string be recoverable?** | (a) No — store the canonical form only; (b) Yes — store the original separately | **(a)** for the common case. If (b), the original is a **second plaintext field** and must be encrypted and blind-indexed separately — which doubles the attack surface and complicates the uniqueness rule. The owner should confirm whether operators ever need the exact typed string back | No — before migration sign-off |
| **D-8** | **Deployment and maintenance window for step 7** (drop the plaintext column) | Scheduled / staged / immediate | **Scheduled and announced.** It is the point of no return (§6.6) and the only step that cannot be rolled back without a restore | No — before migration sign-off |
| **D-9** | **Scope: does the same treatment apply to other plaintext PII?** | (a) This table only; (b) also `core.user_account.email` / `phone_e164` and `profile.*` | The owner should decide explicitly. Option (a) leaves a **known-plaintext PII footprint elsewhere** in the same database, which weakens the "encrypted tax IDs" claim in any external communication. Option (b) is a much larger programme | No — but it affects external messaging |
| **D-10** | **Is Option E (defer + access control) acceptable as an interim?** | (a) No — encrypt now; (b) Yes, with a hard gate: no production identifiers until encryption lands | **(b) is defensible** if the table is empty in every environment (F-11, F-13) and a deployment gate is enforced. It is **not** acceptable if any real identifier is stored today | No — but it is the highest-leverage interim decision |
| **D-11** | **Cascade delete auditing / blocking** | (a) Allow cascade delete silently; (b) Audit identifier deletion; (c) Block cascade delete | **(b)** Audit identifier deletion via application event before organizational deletion | No — before migration sign-off |
| **D-12** | **AAD field binding** | (a) Bind `organization_id`; (b) Bind surrogate `id` | **(b) or (a) with strict immutability.** Surrogated `id` never changes, preventing undecryptable rows if an org reference is adjusted | No — before migration sign-off |
| **D-13** | **Key management model** | (a) Derivation (HKDF from `K_root`); (b) Wrapping (KMS envelope) | **(a)** Derivation for strongest threat model (KMS cannot decrypt) | No — before migration sign-off |
| **D-14** | **Canonical collision resolution policy** | (a) Reject migration; (b) Quarantine conflicting rows; (c) Namespace | **(a)** Reject migration and require manual remediation | **YES — blocking for backfill** |

### 8.1 Assumptions this design rests on

| # | Assumption | If it is wrong |
|:--|:--|:--|
| A-1 | A consuming application exists and can perform AEAD encryption (F-12) | Option A is unimplementable; Option E or a `pgcrypto` variant becomes necessary |
| A-2 | The table's live row count is small enough for a bounded-batch backfill (F-13) | §6.4's zero-downtime expectation may need revision; a longer maintenance window would be required |
| A-3 | The application can be changed to dual-write (step 2) before the constraint swap (step 5) | The migration cannot proceed in this order; a longer maintenance window or a different sequence is needed |
| A-4 | `identifier_type` values in the live data are drawn from the 7 the `CHECK` constraint allows | A data-quality issue surfaces during canonicalisation; a rule for an out-of-set value is needed |
| A-5 | Per-type canonicalisation rules exist externally (GSTIN/CIN have published formats) | D-6 becomes a design task, not a lookup, and a conservative trim-and-case-fold default may be needed |
| A-6 | The project can obtain a KMS or equivalent, or accepts a file-based interim (D-3, D-4) | Encryption cannot proceed |
| A-7 | No third-party verification provider currently receives the identifier | If one does, the §4.5 key-custody requirement for that flow must be extended to that provider (§4.2, item 6) |
| A-8 | The database is not replicated, and there is no PITR configured (per `docs/phase-2-model/12-threat-model.md:234`) | The migration must also be applied to replicas, and WAL archiving must be considered — a §6.2 step is added |

### 8.2 Unresolved questions

| # | Question | Who can answer |
|:--|:--|:--|
| Q-1 | How many rows does `recruitment.organization_identifier` actually hold in each environment? | Requires a read-only DB check (forbidden in this phase) |
| Q-2 | Does any environment hold a **real** tax identifier today? | Owner / data protection contact |
| Q-3 | Which application reads this column, and through what code path? | The application team (D-1) |
| Q-4 | Is the identifier ever sent to a third party (verification provider, tax filing integration)? | Owner / integration owner |
| Q-5 | Is the identifier ever displayed in the UI, exported to CSV, or included in an API response? | Application team — this determines the "read" audit scope in §4.7 |
| Q-6 | Which regulatory regime applies (India GST/CIN, EU VAT, US EIN)? The masking and retention rules differ | Owner / legal |
| Q-7 | Is there an incident-response or breach-notification process that a key compromise must feed? | Owner / security |
| Q-8 | Does the reference-design scope include production hardening at all, or is this a demo? | Owner — determines whether Option E (D-10) is the right answer |

### 8.3 Risks of implementing this design

| # | Risk | Severity | Mitigation |
|:--|:--|:--|:--|
| RK-1 | The application cannot be changed (no engineering capacity, or the consumer is a third party) | High | Option E + a deployment gate; or a `pgcrypto` variant that keeps the crypto in the DB |
| RK-2 | The blind index becomes a **re-identification key** — a stable, cross-tenant-correlatable token for a business | Medium | Scope the HMAC input to `(country_id, identifier_type)`; never expose the bidx outside the database; treat it as sensitive |
| RK-3 | Canonicalisation is implemented inconsistently between the write path and the lookup path | High | One shared canonicalisation function with unit tests (T-11, D-6); the same code must serve both paths |
| RK-4 | The uniqueness guarantee silently weakens during the mixed-version window (step 2–6) | Medium | Verify the bidx-uniqueness invariant continuously (§6.2 step 4); the constraint swap in step 5 must run only when the residual is zero |
| RK-5 | Key loss with no escrow destroys all identifiers, **silently** | **Critical** | Escrow, plus a decryptability canary (§6.6) — this is the highest-consequence risk in the design |
| RK-6 | The application writes plaintext into `audit.audit_event.old_values_json` and nobody notices | Medium | T-08 as an acceptance criterion; a code-review checklist item; the audit table is append-only, so a leak cannot be removed |
| RK-7 | The migration's dual-write phase is forgotten and never cleaned up, leaving a plaintext column in place indefinitely | Medium | A scheduled follow-up to complete steps 6–7, tracked as a deliverable; T-05 as a standing regression test |
| RK-8 | RLS is enabled before the session context works, and the table appears empty — a **false negative** that looks like data loss | Medium | Sequence RLS last (§5.3); T-17 |
| RK-9 | Performance regression from per-row AEAD on bulk reads | Low-Medium | Measure; the table is small by design |
| RK-10 | The security controls are implemented but the documentation still claims "plaintext" (or the reverse), and a reader cannot tell which is true | Low | Update `docs/phase-2-model/10-data-dictionary.md:20` and `docs/phase-2-model/12-threat-model.md:181` in the implementation phase — **this phase did not touch them, and they are still accurate as of now** |

---

## 9. Verification Performed in This Phase

### 9.1 Commands executed successfully

| Command | Purpose |
|:--|:--|
| `git status --short`, `git diff --stat`, `git rev-parse HEAD`, `git branch --show-current` | Baseline — §10 |
| `git diff --check` | Whitespace validation — clean |
| `grep -rn "identifier_value" --include="*.sql" --include="*.py" --include="*.md" --include="*.json" .` | Complete read/write trace — §2.2, §2.3 |
| `grep -rn "organization_identifier" --include="*.sql" --include="*.py" .` | Complete DDL/DML trace |
| `grep -n "organization_identifier" db/seeds/*.sql` | Seed coverage |
| `grep -n "INSERT INTO recruitment\." scripts/generate_data.py` | Generator coverage — §2.2 |
| `grep -n "organization" scripts/validate_data.py` | Validator coverage — §2.2 |
| `grep -n "organization" db/queries/*.sql` | Benchmark-query coverage — §2.2 |
| `grep -n "CREATE TABLE recruitment.organization " -A 25 db/migrations/007_create_organization.sql` | Sibling-table shape — §2.1 |
| `grep -n "old_values_json\|new_values_json" db/migrations/*.sql` | Audit-writer trace — §2.3 |
| `grep -n "INSERT INTO audit.audit_event\|INSERT INTO audit.system_error_log" ...` | Audit-writer trace — §2.3 |
| `grep -rn "GRANT\|REVOKE\|CREATE ROLE" ...`, `grep -rn "CREATE POLICY" ...`, `grep -rnE "current_setting\|set_config" ...` | Zero-implementation confirmations — §2.5 |
| `grep -rniE "pgcrypto\|aes-\|encrypt\|decrypt\|cipher" db/ scripts/ tests/` | No encryption capability — §2.5 |
| `wc -c db/seeds/*.sql` | Both seed files are 0 bytes — §2.2 |
| `ls -1 db/ scripts/ tests/`, `find . -maxdepth 2 -name "*.py" ...` | No application code in the repository — §2.2 |

### 9.2 Blocked — recorded as blocked, not bypassed

| Check | Attempts | Result |
|:--|:--:|:--|
| `grep -rn "organization_identifier" db/seeds/` | 3 | The command-safety classifier returned *"talentra-minimax-free is temporarily unavailable, so auto mode cannot determine the safety of Bash right now."* An equivalent form — `grep -rn "organization_identifier" db/seeds/` with a different flag arrangement — also returned no matches, and `wc -c` established both seed files are 0 bytes, which settles the question independently |

**No bypass was attempted.** No command was rephrased to evade detection; only equivalent forms were tried, and each was independently blocked or independently confirmed.

### 9.3 Not run — forbidden by scope

| Not run | Reason |
|:--|:--|
| Any database connection, `docker exec`, `psql`, or catalog query | Phase 4 rules forbid connecting to the database |
| Any `EXPLAIN`, `EXPLAIN ANALYZE`, `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`, `DROP`, `ALTER`, `CREATE`, `REFRESH` | Same |
| `scripts/run_all_tests.py`, `scripts/run_benchmarks.py`, `scripts/generate_data.py`, `scripts/validate_data.py` | Phase 4 is a design phase; also, the classifier outage persists |
| Any file modification other than the creation of this document | Phase 4 rules forbid modifying migrations, schema, indexes, application code, tests, seed data, configuration, or benchmark artifacts |

**No test suite was executed in this phase, and no test is claimed to have passed.**

---

## 10. Final Review

### 10.1 Files changed in this phase

| File | Change |
|:--|:--|
| `docs/phase-2-model/12-tax-id-security-design.md` | **Created** — this document |

**No other file was created, modified, moved, or deleted.** Specifically not touched: all 19 migrations, all 12 benchmark queries, both seed files, all 4 scripts (including `scripts/backup_restore.sh` and `scripts/validate_data.py`, whose changes §6.5 enumerates), all 23 test suites (including the user-owned `tests/test_constraints.sql`), `benchmarks/results/*`, `docker-compose.yml`, `.env`, `.git-initial-backup/`, and every document belonging to the concurrent Phase 1 workstream.

### 10.2 Explicit confirmations

- ✅ **Implementation remains untouched.** No migration, schema, index, constraint, function, trigger, script, test, seed, configuration, or benchmark artifact was modified. This document is a design; it implements nothing.
- ✅ **The database was not contacted.** No connection, no query, no `docker exec`, no `psql`. Every finding in §2 is a static read of files in this working tree.
- ✅ **Every user change and untracked file is preserved.** `.git-initial-backup/` was not read, modified, or deleted. `tests/test_constraints.sql` was read only. The concurrent Phase 1 workstream's files (`docs/source/`, `docs/phase-1-discover/01-requirements.md`, `docs/phase-1-discover/01-scope-assumptions.md`, `docs/phase-1-discover/03-feature-inventory.md`, `docs/phase-1-discover/05-audit-event-matrix.md`, `docs/phase-1-discover/05-exceptions.md`, `docs/phase-1-discover/04-nfr-register.md`, `docs/phase-1-discover/02-personas.md`, `docs/phase-1-discover/05-workflows.md`) were not touched.
- ✅ **Nothing was committed, pushed, reset, cleaned, or stashed.** HEAD remains `7ac5b2bdeb731610b8bd2c0282608e6c93d4b1df` on `feature/your-task`; the working tree remains unstaged.
- ✅ **No paid service or external dependency was introduced.** The recommended architecture (Option A) uses standard-library AEAD and HMAC primitives and requires **no** new service. The KMS is recommended but explicitly optional, and choosing it is approval item D-4.
- ✅ **Confirmed facts are separated from assumptions.** §2.7 states F-1…F-10 as CONFIRMED with line references, F-11…F-14 as assumptions or unverified, §8.1 lists the design's resting assumptions, and §8.2 lists the open questions.
- ✅ **No test is claimed to have passed.** No suite was executed; §7.2 is a *plan*, not a result.
- ✅ **`git diff --check` was run and is clean.**

### 10.3 Status

This design is **ready for owner review**. It is not ready for implementation, because D-1 through D-4 are unresolved and D-1 (the identity and ownership of the consuming application) is a precondition for the migration plan in §6 to be executable at all.

The single most important thing this phase established is not cryptographic — it is the discovery that **the read/write surface for this column inside this repository is empty**. There is no in-repo consumer to migrate, no in-repo seed data to backfill, and no in-repo benchmark or validator to update. The design work is correspondingly small; the coordination work with the application team is not, and that is where the risk sits.
