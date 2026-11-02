# Talentra: Phase 1 (Discover) Report and Gate G1 Decision

**Phase:** 1 Discover, steps 01-05
**Written:** 2026-10-27
**Gate:** G1 *Problem understood*. Exit test: every requirement has an ID and an actor, every NFR has a numeric target, every must-have feature appears in a workflow.
**Reviewer note:** the playbook says a gate is checked by someone who did not produce the work. This report was prepared by the assistant, so the verdict below is a **recommendation for a human reviewer**, not a sign-off.

---

## 1. Decision

**G1: CONDITIONAL.** Two of the three exit conditions hold. The third holds in form only.

| # | Exit condition | Result | Evidence |
|--:|:--|:--|:--|
| 1 | Every requirement has an ID and an actor | **Met** | 120 / 120 requirements carry an actor (`01-requirements.md` §8.2). Re-checked by `scripts/lifecycle/gen_traceability.py`, which parses all 120 and finds 0 dangling cross-references. |
| 2 | Every NFR has a numeric target | **Met in form, not in substance** | All 27 NFRs have a number and a measurement method, but all are `Proposed` with a named approver and none is approved (`04-nfr-register.md`). NFR-019 is unresolved. The availability objective (NFR-007) has no measurement method. |
| 3 | Every must-have feature appears in a workflow | **Met** | 23 / 23 (`05-workflows.md` §3). |

**What would turn G1 green:** the project owner approves or amends the 27 NFR targets, resolves OQ-004 (NFR-019), and a second person confirms conditions 1 and 3 from the registers.

## 2. What Phase 1 produced

| Step | Deliverable | Status |
|--:|:--|:--|
| 01 | [`01-requirements.md`](01-requirements.md), [`01-scope-assumptions.md`](01-scope-assumptions.md), [`01-docket-reconciliation.md`](01-docket-reconciliation.md) | done |
| 02 | [`02-personas.md`](02-personas.md) | done (8 actors against the docket's 9) |
| 03 | [`03-feature-inventory.md`](03-feature-inventory.md), [`03-competitive-benchmark.md`](03-competitive-benchmark.md) | partial: competitor facts are unverified |
| 04 | [`04-nfr-register.md`](04-nfr-register.md) | partial: targets unapproved |
| 05 | [`05-workflows.md`](05-workflows.md), [`05-exceptions.md`](05-exceptions.md), [`05-audit-event-matrix.md`](05-audit-event-matrix.md) | done |

## 3. Provenance headers

Steps 01-05 were first written while the original brief could not be found and carried the header *"PROVISIONAL — docket unavailable"*. The docket (`docs/source/originals/Talentra-Database-Design-Hackathon-Docket.pdf`) and the playbook are now in the repository and the reconciliation in `01-docket-reconciliation.md` was done against them, so those headers were replaced on 2026-10-27 with what is actually true of each document. `01-requirements.md` section 7.1 still says its docket mapping is *NOT VERIFIABLE*; the reconciliation supersedes that sentence.

## 4. Correction to the docket reconciliation

`01-docket-reconciliation.md` §3 lists 14 gaps. Checked against the migrated schema on 2026-10-27, **seven are not gaps** (GAP-01, 02, 04, 07, 08, 10, 11) and one is only partly open (GAP-14):

| Gap | Docket item | Reconciliation says | Schema shows |
|:--|:--|:--|:--|
| GAP-01 | Multilingual UI data | not implemented | `messaging.ui_translation` and `messaging.get_ui_translation` with English fallback |
| GAP-02 | Favourite and blacklisted gig workers | no requirement | `gig.gig_worker_preference` (`preference_type`, `reason`) |
| GAP-04 | Support tickets and FAQs | not implemented | `messaging.support_ticket`, `messaging.faq` |
| GAP-07 | Community posts and reactions | not implemented | `messaging.community_post`, `messaging.post_reaction` |
| GAP-08 | Assessments and scores | not implemented | `profile.candidate_assessment`, `profile.candidate_assessment_score` |
| GAP-10 | Referral tracking | not implemented | `messaging.referral_event` |
| GAP-11 | Profile view history | not implemented | `profile.profile_view_history` |
| GAP-14 | Shortlist and bookmark history | not implemented | partial: `profile.recruiter_bookmark` covers bookmarks; employer shortlist history is not separate |

**Gaps that remain real:**

| Gap | Docket item | Why it remains |
|:--|:--|:--|
| GAP-03 | Gig model versus core job model decision | Implemented as a separate `gig` schema. *The decision and its trade-offs (reporting, integrity, future change) are now recorded in the README's design notes.* |
| GAP-05 | Guest actor | Docket lists 9 actors; the register has 8. |
| GAP-06 | Recruiters cannot register candidates | *Closed in migration 022:* a trigger rejects a candidate profile created by anyone but its owner or a platform admin. |
| GAP-09 | Course enrolments | *Closed in migration 022:* `profile.course`, `profile.course_enrolment`. |
| GAP-12 | Candidate job search history | *Closed in migration 022:* `profile.candidate_search_history`. |
| GAP-13 | Candidate activity log (login, profile update, resume download) | *Closed in migration 022:* `profile.candidate_activity_log`, append-only. |

Also missing against the docket and not on the list: resume **templates** (only `profile.candidate_document` with a `document_type`), and the legacy-system **sync direction and conflict rule** the docket asks for in its integration table.

## 5. Findings the registers understated, and what became of them

These were found on 2026-10-27 by running the tests and generating catalogues from the database. They did not change the G1 verdict, but they set Phase 2's work. Each has since been acted on; the column on the right is the state now.

| Finding at the time | Now |
|:--|:--|
| Rule Group 4 largely unmet: 2 of 92 tables had all four audit columns, none had `deleted_at` | Closed by migration 020. Every soft/hard/reference table carries all four columns and nine entities are soft-deleted (`tests/test_lifecycle.sql`) |
| Access control was documentation only: empty permission tables, no roles, no row-level security | Closed by migration 021: 28 permissions and 99 mappings, five roles, row-level security on 12 tables (`tests/test_access_control.sql`) |
| A database password was hard-coded as a fallback in four scripts | Removed. The password is already in git history, so it must still be rotated |
| Tests had never been run | They run: 28 suites pass ([`../lifecycle/verification-2026-10-27.md`](../lifecycle/verification-2026-10-27.md)) |
| Seven of the 14 reconciliation gaps were not gaps | Corrected in section 4; of the six that were real, GAP-06, 09, 12 and 13 are now built (migration 022) and GAP-05 and GAP-03 remain decisions |
| Tax identifiers stored in clear text | **Still open.** The encryption design is blocked on human decisions (see `../phase-2-model/12-tax-id-security-design.md`) |

## 6. Hand-off to Phase 2

Phase 2 (Model) already has an implemented schema, so its work is to bring the documentation and the schema into agreement, not to design from scratch. The generated catalogues for steps 06, 07 and 08 are in [`../phase-2-model/`](../phase-2-model/). The open items for Gate G2 are in [`../lifecycle/step-map.md`](../lifecycle/step-map.md).

## 7. Related documents

| Document | Purpose |
|:--|:--|
| [`../lifecycle/step-map.md`](../lifecycle/step-map.md) | All 46 steps, 8 gates and the docket crosswalk |
| [`../phase-6-specify/34-traceability-matrix.md`](../phase-6-specify/34-traceability-matrix.md) | Requirement-to-test-to-migration matrix |
| [`../source/README.md`](../source/README.md) | Source index |
