# Talentra Documentation, Organised by Lifecycle Phase

The documentation follows the **Talencia Global Data-Driven Development Lifecycle**: 8 phases, 46 steps, 8 gates. File names carry the step number, so `10-data-dictionary.md` is step 10.

**Start here:** [`lifecycle/step-map.md`](lifecycle/step-map.md) shows every step, its status, its evidence, the gate verdicts, and how the hackathon docket's backlog items B1-B82 map onto the steps. It is generated from [`lifecycle/steps.json`](lifecycle/steps.json).

| Phase | Steps | Gate | Folder |
|:--|:--|:--|:--|
| 1 Discover | 01-05 | G1 | [`phase-1-discover/`](phase-1-discover/): requirements, scope, personas, features, NFRs, workflows, exceptions, audit matrix, [`phase-report.md`](phase-1-discover/phase-report.md) |
| 2 Model | 06-12 | G2 | [`phase-2-model/`](phase-2-model/): entity catalogue, data dictionary and state machines (generated from the database), generated ER diagrams, architecture, docket rule-group compliance, threat model, tax-ID design |
| 3 Prove | 13-21 | G3 | [`phase-3-prove/`](phase-3-prove/): change log (17), workflow coverage (16) and business rules catalogue (18, generated). Code in [`../db/migrations/`](../db/migrations/), [`../tests/`](../tests/), [`../scripts/generate_data.py`](../scripts/generate_data.py); evidence in [`lifecycle/verification-2026-10-27.md`](lifecycle/verification-2026-10-27.md) |
| 4 Platform | 22-28 | G4 | [`phase-4-platform/`](phase-4-platform/): integration boundaries (generated), table quality scorecard, test automation and load test, with the earlier performance reports kept as history |
| 5 Insight | 29-30 | G5 | [`phase-5-insight/`](phase-5-insight/): KPI catalogue (29), generated from the SQL in [`../db/kpi/`](../db/kpi/). Executive analytics (30) not started. |
| 6 Specify | 31-35 | G6 | [`phase-6-specify/`](phase-6-specify/): traceability matrix (generated). Other steps are outside the docket. |
| 7 Design | 36-41 | G7 | Outside the docket (no UI or application layer) except database security tests |
| 8 Release | 42-46 | G8 | Outside the docket (no application code) |

Other folders:

| Folder | Contents |
|:--|:--|
| [`gate-reviews/`](gate-reviews/) | Independent audits and correction reports from earlier phases. They quote file paths as they were **before** this restructure (for example `docs/threat-model.md`, now `docs/phase-2-model/12-threat-model.md`); their links were updated, their quoted evidence was not. |
| [`source/`](source/) | The original docket and playbook PDFs and the source index. |
| [`lifecycle/`](lifecycle/) | Step map, gate tracker data, verification record. |

## Generated documents

These are produced by scripts and must not be edited by hand:

| Document | Generator | Needs a database? |
|:--|:--|:--|
| `phase-2-model/06-entity-catalogue.md`, `07-attribute-catalogue.md` (the data dictionary), `08-state-machines.md`, `09-er-diagram-generated.md` | `scripts/lifecycle/gen_model_catalogues.py` | Yes (migrated schema, `PG*` environment variables) |
| `phase-3-prove/16-workflow-coverage.md` | `scripts/lifecycle/gen_workflow_coverage.py` | Yes |
| `phase-3-prove/18-business-rules-catalogue.md` | `scripts/lifecycle/gen_rules_catalogue.py` | Yes |
| `phase-5-insight/29-kpi-catalogue.md` | `scripts/lifecycle/gen_kpi_catalogue.py` (runs every query in `db/kpi/`) | Yes |
| `phase-6-specify/34-traceability-matrix.md` | `scripts/lifecycle/gen_traceability.py` | No |
| `lifecycle/step-map.md` | `scripts/lifecycle/gen_lifecycle_report.py` (also fails if a cited file is missing) | No |

Run `scripts/lifecycle/regenerate.sh` to rebuild all of them.

## Agentic Roadmap

The Agentic Roadmap PDF describes how the lifecycle becomes agent-assisted: Level 1 evaluator agents that score each deliverable against frozen scorecards (D1 schema, D2 schema scorecard, D3 output, D4 output scorecard), with three raters and a consolidator. That is a process layer for the delivery team and is **not built in this repository**. Prerequisites that this repository now provides: a machine-readable step list with gate criteria (`lifecycle/steps.json`) and generated, reproducible artifacts. Still missing: frozen scorecards (D2, D4) per step, a rater prompt, the orchestrator and the run log.
