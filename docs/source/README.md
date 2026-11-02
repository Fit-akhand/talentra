# Authoritative Source Index — Talentra Phase 1 Discover

**Purpose:** Single canonical record of every source document consulted during Phase 1 — Discover, with
version, location, and evidentiary weight. All Phase 1 deliverables cite sources via the IDs assigned here.

**Phase 1 remediation date:** 2026-10-21
**Repository:** `Talentra_Database_Design` (`https://github.com/yashxtw/Talentra_Database_Design.git`)
**Branch / commit at authoring:** `feature/your-task` @ `7ac5b2b`

---

## 1. Source classes and evidence hierarchy

The Phase 1 brief mandates the following evidence hierarchy. Sources are classified against it here.

| Rank | Source class | Purpose | Present? |
|:--|:--|:--|:--|
| 1 | Authoritative hackathon docket | Project scope, mandatory deliverables | **PRESENT** — see §2 |
| 2 | Authoritative lifecycle playbook | Phase procedures, exit gates | **PRESENT** — see §3 |
| 3 | Approved project decisions / requirements docs | Accepted scope and constraints | **NOT FOUND** — see §4 |
| 4 | Existing schema, migrations, tests, benchmarks, implementation | Current-state evidence | **PRESENT** — see §5 |
| 5 | Official competitor documentation / reliable external sources | Competitor research | **NOT ACCESSIBLE** — see §7 |
| 6 | Clearly labelled assumptions | Where no authoritative answer exists | **APPLIED** — see §8 |

---

## 2. Source S-001 — Talentra Database Design Hackathon Docket

| Field | Value |
|:--|:--|
| **Status** | **FOUND — authoritative source available locally** |
| **Document title** | Talentra: Database Design Hackathon — Project Docket for a Job Search and Demand Management Platform |
| **Prepared by** | Northbridge Workforce Systems |
| **Document metadata** | Duration: 2 days; team size: 3 to 5; database engine: PostgreSQL or MySQL |
| **Location** | `docs/source/originals/Talentra-Database-Design-Hackathon-Docket.pdf` |
| **Source classification** | Authoritative hackathon docket |
| **Purpose** | Defines the Talentra problem statement, project scope, business rules, mandatory and expected data domains, data standards, integration boundaries, dataset scale, delivery plan, milestones, and required deliverables. |
| **Impact on Step 1** | The docket is now available as the primary source for requirement decomposition. Requirements must be traced to the brief, with unique IDs, statements, source references, priorities, and ambiguity notes. Existing implementation evidence may support verification, but it must not replace the original source as the basis for identifying requirements. |
| **Impact on G1** | The original brief is available for evaluating requirement traceability. G1 must not be marked passed until the applicable exit conditions have been checked against the docket and supporting Phase 1 deliverables. |

### 2.1 Original source discovery and historical search log

The following entries document the original search attempts made before the docket was located. They are retained as historical evidence and do not represent the current availability status.

| # | Location / method | Result at the time |
|:--|:--|:--|
| 1 | `grep -rl "Talencia" .` (whole repository, all file types) | No matches. |
| 2 | Search attempts against the user home tree, including `~/Downloads`, `~/Desktop`, `~/Documents`, `~/`, and `/tmp` | Blocked by the host command-safety classifier, which returned `talentra-minimax-free is temporarily unavailable`. Multiple command forms were attempted. |
| 3 | `git log --all --diff-filter=A --name-only` | 87 paths were reviewed; no docket, brief, or playbook was found in the repository history at that time. |
| 4 | `git log --all --diff-filter=D --name-status` | Three deleted paths were identified, all migration-file renames. No business-analysis document was found among those deletions. |
| 5 | `git branch -a` and `git stash list` | Branches and stashes were inspected; no docket was identified through those checks. |
| 6 | Repository search for filenames containing `playbook`, `docket`, `talencia`, or `brief` | No matching source document was found in the repository at that time. |
| 7 | Repository text search for `playbook`, `talencia`, `exit gate`, `G1`, `phase 1`, `discover`, and `hackathon` | Only four unrelated implementation or test references were found. |
| 8 | `git remote -v` and attempted upstream repository inspection | The upstream remote was identified, but the external file-listing attempt was blocked. |

### 2.2 Subsequent discovery and current evidence

After the initial search, the original docket was located in the user's Downloads directory:

`~/Downloads/Talentra-Database-Design-Hackathon-Docket.pdf`

It was subsequently copied into the repository at:

`docs/source/originals/Talentra-Database-Design-Hackathon-Docket.pdf`

The local copy is the source used for the current Phase 1 review. The historical search results above remain valid as records of what was found at the time, but the earlier conclusion that the docket was unavailable is superseded by this discovery.

### 2.3 Requirements traceability implications

The docket is the authoritative source for identifying and classifying project requirements. Requirement decomposition must cover the relevant content of the original brief, including:

- Problem statement, goals, and project scope.
- Explicit out-of-scope items.
- Actors, privileges, and access restrictions.
- Mandatory, expected, and optional data domains.
- Business rules and data standards.
- External integration boundaries.
- Dataset sizing and performance evidence requirements.
- Phase milestones, backlog items, and required deliverables.

Each requirement must receive a unique identifier and include the fields required by the Phase 1 instructions: ID, statement, source, priority, and ambiguity notes. Actor mappings, acceptance criteria, verification methods, and cross-references should be retained where applicable.

Existing migrations, tests, queries, and engineering documents are supporting implementation evidence. They can demonstrate whether a requirement has been implemented or verified, but implementation alone does not establish that the requirement originated in the authoritative docket.

The current `docs/phase-1-discover/01-requirements.md` and other Phase 1 artefacts must therefore be reviewed against the newly available source. Their existing requirement IDs should be preserved where practical, but their provenance, priority, scope classification, and traceability must be corrected wherever the original brief requires it.

**Current disposition:** Source S-001 is available. Requirement-level traceability and the G1 exit conditions remain to be validated; the availability of the PDF alone does not establish that Step 1 or Phase 1 has passed.


## 3. Source S-002 — Talencia Global Data-Driven Development Lifecycle Playbook

| Field | Value |
|:--|:--|
| **Status** | **FOUND — authoritative source available locally** |
| **Impact** | The lifecycle playbook is available locally and must be reviewed to verify its Phase 1 procedures and exit-gate requirements. The three G1 conditions recorded here must be checked against the actual playbook before compliance is claimed. |
| **Consequence for G1** | G1 remains **NOT YET VERIFIED** until the playbook's applicable conditions are checked against the Phase 1 deliverables and the evidence is recorded. |
---

## 4. Source S-003 — Approved project decisions and requirements documents

No formally approved project decision record, ADR, or ratified scope statement has yet been identified. The working requirements register at `docs/phase-1-discover/01-requirements.md` exists, but its existence does not establish formal approval. Its requirements must be traced against the authoritative hackathon docket (S-001), and any approved decisions must be supported by a recorded approval artefact. Later-phase documentation-audit reports are supporting engineering evidence, not substitutes for approved business decisions.

## 5. Source S-004 — Implementation and current-state evidence (PRESENT, PRIMARY)

These are the authoritative sources for **current-state** facts. Every requirement, feature, NFR, and workflow in this phase that is marked *Implemented* is backed by a specific line reference into one of these.

| ID | Artefact | Path | Role in Phase 1 |
|:--|:--|:--|:--|
| S-004-A | SQL migrations (19 files, `001`–`019`) | `db/migrations/` | Schema, constraints, triggers, functions, state machines. **Primary evidence for "what is implemented".** |
| S-004-B | Benchmark queries (12 files) | `db/queries/` | The 12 defined workload queries. |
| S-004-C | Test suites (21 SQL + 2 Python) | `tests/` | Executable acceptance evidence. |
| S-004-D | Benchmark runner | `scripts/run_benchmarks.py` | Measurement method for latency NFRs. |
| S-004-E | Data generator | `scripts/generate_data.py` | Workload definition and dataset scale. |
| S-004-F | Data-quality validator | `scripts/validate_data.py` | Measurement method for data-quality NFRs. |
| S-004-G | Test-suite runner | `scripts/run_all_tests.py` | Test orchestration. |
| S-004-H | Backup/restore runbook | `scripts/backup_restore.sh`, `.ps1` | Only RTO measurement method in the repository. |
| S-004-I | Container orchestration | `docker-compose.yml` | Runtime configuration evidence. |
| S-004-J | Benchmark artefacts | `benchmarks/results/benchmark_results.json`, `benchmark_summary.md` | Recorded measurements. |
| S-004-K | Architecture dossier | `docs/phase-2-model/09-architecture.md` | Bounded contexts, invariants, engine configuration. |
| S-004-L | Threat model | `docs/phase-2-model/12-threat-model.md` | Security requirements, RPO/RTO, role matrix, PII tiers. |
| S-004-M | Integration boundaries | `docs/phase-4-platform/22-integration-boundaries.md` | **Richest existing exception-handling evidence** — failure strategy, idempotency keys, retry/backoff, audit trace, state machines for 9 external boundaries. |
| S-004-N | Data dictionary | `docs/phase-2-model/10-data-dictionary.md` | Column-level nullability, sensitivity classification, business justification. |
| S-004-O | Rule-compliance dossier | `docs/phase-2-model/11-rule-compliance.md` | 10 rule groups (RG1–RG10) — the closest thing to a formalised business-rule catalogue. |
| S-004-P | ER architecture | `docs/phase-2-model/09-er-diagram.md` | Relationship model across 10 schemas. |
| S-004-Q | Performance report | `docs/phase-4-platform/28-performance-report.md` | Latency measurements and extrapolation model. |
| S-004-R | Phase 2B validation | `docs/phase-4-platform/28-query-performance-validation.md` | Query-level benchmark analysis (H-series findings). |
| S-004-S | Phase 2C audit | `docs/gate-reviews/phase2c-documentation-audit.md` | 69 classified documentation findings (A/C/T series). |
| S-004-T | Phase 2D corrections | `docs/gate-reviews/phase2d-documentation-correction-report.md` | Applied corrections + deferred items D1–D12. |
| S-004-U | Phase 2E corrections | `docs/gate-reviews/phase2e-documentation-correction-report.md` | Applied corrections + unresolved items U-01–U-10. |

### 5.1 Target provenance rule applied throughout

The authoritative docket (S-001) and lifecycle playbook (S-002) are available locally. Numeric targets and their provenance must be checked against the relevant source text before they are classified as official. Source availability alone does not establish that a particular target appears in either document.

The following provenance labels are used consistently in every Phase 1 register:

| Label | Meaning | May it satisfy G1 Condition 2? |
|:--|:--|:--|
| `Official` | Stated in an authoritative source and traceable to a specific section or requirement | Yes, when the source explicitly states the target and it is applicable |
| `Approved Decision` | Ratified by a named project owner | Only with a recorded approval artefact |
| `Proposed` | Engineer-derived candidate target awaiting business approval | **No** — it is proposed, not approved |
| `Measured` | An observed value from an executed run | Not a target |
| `Configuration` | A system setting, not a service objective | Not a target |
| `Assumption` | Explicitly reasoned, with owner and review condition | Not an official target |

---

## 6. Source S-005 — Local environment and configuration

| Artefact | Path | Note |
|:--|:--|:--|
| Environment template | `.env.example` | Referenced only. `.env` was **never read**; no secret value appears in any Phase 1 document. |
| Schema bootstrap | `db/migrations/001_create_schemas.sql` | Establishes the 10 bounded schemas. |

---

## 7. Source S-006 — External competitor sources

| Field | Value |
|:--|:--|
| **Status** | **NOT ACCESSIBLE** |
| **Attempted** | `WebSearch` (2 distinct queries) and `WebFetch` (GitHub repository file listing) — **all blocked** by the host command-safety classifier outage (`talentra-minimax-free is temporarily unavailable`), which affects the external-tool permission path as well as Bash. |
| **Impact** | Competitor capability claims cannot be sourced. Per the Phase 1 instruction, competitor cells are recorded as **`Unknown`** with an explicit evidence gap, and a **research backlog** is created in [`docs/phase-1-discover/03-feature-inventory.md`](../phase-1-discover/03-feature-inventory.md) §7 rather than filled with unverified assertions. |
| **Non-negotiable** | The pre-existing third-party characterisations in `docs/phase-1-discover/03-competitive-benchmark.md` (Naukri / Monster / LinkedIn columns) are **explicitly not verified** — see [`docs/phase-1-discover/03-competitive-benchmark.md`](../phase-1-discover/03-competitive-benchmark.md) §2, which now carries the same disclosure that Phase 2D applied. No new unsourced competitor claim has been introduced. |

---

## 8. Source S-007 — Assumptions

All assumptions introduced by this phase are registered in [`docs/phase-1-discover/01-scope-assumptions.md`](../phase-1-discover/01-scope-assumptions.md) §5 with an ID (`A-NNN`), rationale, confidence, impact, and review condition. Assumptions are not presented as official requirements. The two records below explain how source discovery changed the status of earlier assumptions.

| ID | Assumption / finding | Current disposition |
|:--|:--|:--|
| **A-001** | The three G1 conditions faithfully represent the playbook's Exit Gate G1. | **Confirmed** against S-002, pages 6 and 18. Retained as a traceability record, not an active assumption. G1 passage remains unverified until the Phase 1 deliverables are evaluated. |
| **A-002** | The implemented schema represents the intended Talentra product scope. | **Active — scope reconciliation pending.** S-001 is available; compare its scope and requirements against the existing register and schema before retiring this assumption. |
---

## 9. Source index — quick reference

| ID | Source | Version / date | Location | Availability |
|:--|:--|:--|:--|:--|
| S-001 | Talentra Database Design Hackathon Docket | — | `docs/source/originals/Talentra-Database-Design-Hackathon-Docket.pdf` | **PRESENT** |
| S-002 | Talencia Global Data-Driven Development Lifecycle Playbook | v1.0, Oct 2026 | `docs/source/originals/Talencia Global - Data-Driven Development Lifecycle - Detailed Playbook.pdf` | **PRESENT** |
| S-003 | Approved project decisions / requirements | — | — | **NOT FOUND** |
| S-004-A | SQL migrations 001–019 | — | `db/migrations/` | Present |
| S-004-B | Benchmark queries 01–12 | — | `db/queries/` | Present |
| S-004-C | Test suites (21 SQL + 2 Python) | — | `tests/` | Present |
| S-004-D–I | Scripts, container, artefacts | — | `scripts/`, `docker-compose.yml`, `benchmarks/results/` | Present |
| S-004-J–U | Engineering dossiers (architecture, threat model, integration boundaries, data dictionary, rule compliance, ER, performance, Phase 2B–2E) | 2B/2C/2D/2E dated 2026-10-20/21 | `docs/` | Present |
| S-005 | Environment template / schema bootstrap | — | `.env.example`, `db/migrations/001_create_schemas.sql` | Present |
| S-006 | Official competitor documentation | — | — | **NOT ACCESSIBLE** |
| S-007 | Assumptions register | 2026-10-21 | [`docs/phase-1-discover/01-scope-assumptions.md`](../phase-1-discover/01-scope-assumptions.md) | Created by this phase |

---

## 10. Glossary

| Term | Meaning in this project |
|:--|:--|
| **Docket** | The authoritative hackathon brief defining scope and mandatory deliverables. Available locally at `docs/source/originals/Talentra-Database-Design-Hackathon-Docket.pdf`; primary source for project scope and requirements. |
| **Playbook** | The Talencia Global lifecycle document defining phase procedures and exit gates. Available locally at `docs/source/originals/Talencia Global - Data-Driven Development Lifecycle - Detailed Playbook.pdf`; Phase 1 procedures and G1 criteria verified on pages 6 and 18. |
| **Gate G1** | Phase 1 exit gate: Problem Understood. The three conditions are: every requirement has an ID and an actor; every NFR has a numeric target; and every must-have feature appears in a workflow. The criteria are confirmed against the playbook, but gate passage remains unverified until the Phase 1 deliverables are evaluated. |
| **Bounded context** | A schema (`core`, `master`, `profile`, `recruitment`, `gig`, `sourcing`, `commercial`, `messaging`, `audit`, `analytics`) owning a coherent domain. |
| **Rule Group (RG)** | One of the 10 formalised rule groups in `docs/phase-2-model/11-rule-compliance.md` (RG1–RG10). The nearest existing analogue to a business-rule catalogue. |
| **Target provenance** | The label distinguishing an official target from a proposed one, a measurement, a configuration value, or an assumption. See §5.1. |
| **Implemented** | The behaviour is enforced by a verifiable database object (DDL, constraint, trigger, or function). |
| **Documented only** | The behaviour is described in prose but no enforcing object exists. |
| **Gap (Phase 1)** | A deliverable absent from the Phase 1 set, recorded in [`docs/phase-1-discover/phase-report.md`](../phase-1-discover/phase-report.md) §6. |
| **Not Verified** | A claim or gate outcome has not yet been established by sufficient evidence. The docket and playbook are available, but competitor research remains outstanding and G1 has not yet been evaluated against the Phase 1 deliverables. |