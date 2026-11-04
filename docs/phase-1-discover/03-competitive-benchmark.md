# Competitive Benchmark: Talentra against Naukri, foundit (Monster) and LinkedIn

**Phase 1, step 3.** Researched and rewritten 2026-10-28. It replaces the 2026-10-21 version, in which every competitor cell was `Unknown` because the web tools were unavailable, and drops that version's unsourced architectural characterisations of the three companies (they stay in git history).

## 1. Scope and method

- **Question:** which recruiter-facing capabilities do the three named competitors publish, and where does Talentra's database design match, exceed or lack them?
- **Sources:** the competitors' own pages only. Third-party reviews and comparison sites were seen but are not used for any cell.
- **Boundary:** this is a **database-design** comparison. A competitor's marketing page describes a product, not its storage layer, so storage-level claims (how a constraint is enforced) cannot be compared and are marked `Not published`.
- **Recruiter side only.** The pages read describe recruiter products. Candidate-side features (job search, applications, profile building) were not researched, so no candidate-side claim is made.

### Confidence

| Level | Meaning | Applies to |
|:--|:--|:--|
| **High** | The page was fetched and read in full by the assistant | LinkedIn Recruiter features page; LinkedIn Help article on Recruiter plans; foundit Resume Database Access page |
| **Medium** | The page is official but its body was blocked (HTTP 403) or timed out when fetched; the content comes from the search tool's summary of it | Every Naukri citation; foundit terms of use; foundit talent-solutions page |
| **Low** | Third-party | Not used |

Where a page did not mention a capability the cell says **Not stated**. That means the page does not say; it does not mean the competitor lacks it.

### Sources (all accessed 2026-10-28)

| Ref | Source | Confidence |
|:--|:--|:--|
| L1 | LinkedIn, *Recruiter features*, business.linkedin.com/talent-solutions/recruiter/recruiter-features | High |
| L2 | LinkedIn Help, *Recruiter plans comparison*, linkedin.com/help/linkedin/answer/a417251 | High |
| F1 | foundit, *Access Resume Database*, recruiter.foundit.in/rda-resume-database-access.html | High |
| F2 | foundit, *Terms of Use*, foundit.in/info/terms-of-use | Medium (page returned 403 to the fetch; content from search summary) |
| F3 | foundit, *Talent solutions*, recruiter.foundit.in/main/talent-solutions | Medium (search summary) |
| N1 | Naukri RecruiterFAQ, *Resdex database*, recruiterfaq.naukri.com/category/resdex-database | Medium (fetch timed out; search summary) |
| N2 | Naukri RecruiterZone, *Introducing Resdex Enterprise*, recruiterzone.naukri.com/introducing-resdex-enterprise/ | Medium (fetch timed out; search summary) |
| N3 | Naukri, *Recruiter Resdex*, naukri.com/blog/recruiter-resdex/ and naukri.com/recruit/premiumX | Medium (403 on fetch; search summary) |
| N4 | Naukri RecruiterZone, *Refreshed Resdex* and *Quick Start Guide* | Medium (search summary) |

## 2. Capability comparison

Talentra's column is checked against the current schema (108 base tables, migrations 001 to 034). `Impl.` = enforced by a database object. `Partial` = some of it.

| # | Capability | Talentra | Naukri | foundit | LinkedIn |
|:--|:--|:--|:--|:--|:--|
| 1 | **Candidate search filters** | Impl. (2026-11-04): keywords and boolean mode, exclusions, experience, location, skills, education and study mode, department, notice period, current pay (when revealed), recent activity (`profile.search_candidates`) | 20+ filters (title, location, skills, experience, salary), five search modes, keyword over resume sections, search within results, education type [N1 N3 N4] | Filters by company, city, industry, job role; IT / non-IT split; semantic search [F1] | 40+ filters, Boolean keyword search, AI-generated filters from a description, similar-profile search [L1 L2] |
| 2 | **Saved searches and alerts** | Impl. (2026-11-04): `profile.recruiter_search` (latest 20 and named saved searches, optional alert flag); the alert dispatch is the application's | Saved searches send email alerts on new matches [N1] | Not stated | Saved filters; alerts capped at 10 per seat (Lite) or 50 (other plans) [L1 L2] |
| 3 | **Folders / shared projects** | Partial: `profile.recruiter_bookmark` (a bookmark with a note) | Save resumes into folders [N1] | Save profiles into folders [F1] | Projects holding results, applications and notes; shared with teammates; @mentions [L1] |
| 4 | **Pipeline stages and history** | Impl.: constrained stage set, every change written to a history table by trigger, governed transitions | Not stated | Not stated | Custom pipeline stages with conversion rates [L1] |
| 5 | **Bulk outreach** | Impl.: `sourcing.outreach_batch` / `outreach_recipient`, block-aware, credits deducted | Custom emails and job details from the results page [N1] | Email and SMS to shortlisted candidates [F1] | Bulk InMail with templates, scheduled follow-ups [L1] |
| 6 | **Metering of candidate access** | Impl.: wallet with append-only ledger; per-download and per-view history | A CV view is deducted on view, contact or download; plans cap views and downloads [N3] | May cap resumes viewed per period [F2] | InMail allowance per seat per month by plan (30 / 100 / 140 / 150) [L2] |
| 7 | **Seats and licences** | Impl.: licence seats, per-user device limit enforced under a row lock | Per-recruiter usage and login reports imply named users [N2] | Not stated | Seats; 20 free collaborator licences per seat; purchaser admin owns the data (Lite) or the company does [L1 L2] |
| 8 | **Usage reporting for administrators** | Partial: audit trail, download history, `audit.ops_*` views; no per-recruiter usage report | Searches, CV views, emails, downloads per recruiter; login activity [N2 N3] | Not stated | Usage reports, saved and auto-sent, exportable [L1] |
| 9 | **Hiring analytics** | Impl.: star schema, 16 reconciled KPIs | Not stated | Not stated | Pipeline analytics, funnel insights with industry benchmarks [L1 L2] |
| 10 | **Recruiter-side candidate recommendations** | Partial (2026-11-04): a documented match percentage ranks search results; no learning model and no proactive recommendations | AI CV recommendations after a job is posted [N2] | Recommendation engine [F1] | Recommended Matches [L1] |
| 11 | **Candidate controls over discoverability** | Impl.: visibility (public / recruiters / private), blocks of users and organisations, consent records, enforced by row-level security | Not stated | Private resumes are not searchable [F2] | "Open to work" filter [L1] |
| 12 | **Candidate activity / freshness signal** | Impl. (2026-11-04): `profile.candidate_profile.last_active_at`, set at sign-in, used as filter and ranking | Freshness and last-active as search criteria and sort keys [N1 N2] | Not stated | Not stated on the pages read |
| 13 | **Interview scheduling** | **Not present** | Not stated | Not stated | Zoom, Teams, Google Meet scheduling [L1] |
| 14 | **ATS / CRM integration** | Partial: integration outbox with retries and dead letter for the nine docket boundaries; no ATS boundary | Not stated | Not stated | ATS identification of existing candidates, system connect, CRM connection [L1] |
| 15 | **Fairness tooling** | **Not present** | Not stated | Not stated | Gender-ratio alerts and filters [L1] |
| 16 | **One identity for full-time and freelance work** | Impl.: `core.user_account` with `profile.candidate_profile` and `gig.gig_worker_profile` | Not stated | Not stated | Not stated |
| 17 | **Storage-level guarantees** (no overlapping gig bookings, append-only ledgers, atomic device limits) | Impl. (exclusion constraint, triggers, row locks) | Not published | Not published | Not published |

## 3. What the research shows

**Where Talentra matches the market.** Search with filters (1), outreach (5), credit metering (6), seat limits (7) and candidate-controlled visibility (11) exist in all three competitors and in Talentra.

**Where Talentra is ahead, on the evidence read.** Rows 4, 9 and 11 are published by at most one competitor; rows 16 and 17 are published by none. That does not show a competitor lacks them: their pages do not describe those matters. Talentra's claim stands on its own evidence (`tests/`), not on a comparison.

**Where Talentra lacks what competitors publish.** Rows 2, 10, 12, 13, 14 and 15, and the thinner parts of 1 (no keyword search) and 3 (bookmark only). In descending order of how many competitors publish them and how cheap they are in a database:

| Gap | Competitors that publish it | Database-level cost | Decision (Delegated, DEC-26) |
|:--|:--|:--|:--|
| Recruiter saved searches and alerts | Naukri, LinkedIn | One table plus a dispatch job | **Built** 2026-11-04 (table and flag; dispatch is the application's); DEC-37 supersedes DEC-26 for this item |
| Folders / shared projects | all three | Two tables with row-level security | Candidate requirement; **not built** |
| Candidate last-active signal | Naukri, LinkedIn | One column maintained on login | **Built** 2026-11-04 (migration 041) |
| Recruiter-side recommendations | all three | Model and ranking, mostly outside SQL | Out of scope for a database design; record only |
| Keyword and Boolean search | Naukri, LinkedIn | Full-text index or search service | **Built** 2026-11-04 (PostgreSQL full-text search; boolean mode is OR, phrases and minus, not a full boolean language) |
| Interview scheduling, ATS/CRM, fairness tooling | LinkedIn | Application-level | Out of scope; record only |

**Why none were built.** The docket defines the scope (B1 to B82), and parity with three commercial products is not in it. Adding tables to match marketing pages would widen the schema past the evidenced product, which the first benchmark already flagged as a risk (tables with no workflow). They are recorded here, in the requirements register as candidates, and left for the owner to accept.

## 4. Limits of this research

- **Naukri is Medium throughout.** Its pages blocked or timed out under fetch; the content is the search tool's summary of those official pages. Treat each Naukri cell as probable, not read.
- **Pricing was not compared.** foundit publishes none; the figures seen were third-party.
- **Pages age.** One Naukri source refers to 2017 tax rules, so some features may have changed. All three vendors revise plans without notice; re-check before relying on a cell.
- **Recruiter side only**, as stated in section 1.
- **"Not stated" is not "absent".**

## 5. Research backlog, closed or carried

| ID | Item | Outcome |
|:--|:--|:--|
| RB-01 | Which differentiators does a competitor implement? | Answered at the level the pages allow (section 2) |
| RB-02, 03, 04, 05 | Unified identity, DB-level non-overlap, append-only ledger, database translation | **Not published** by any competitor's pages; unanswerable from marketing material |
| RB-06 | Compliance posture (PCI-DSS, GDPR, SOC 2) | **Not researched**; trust-centre pages were not read |
| RB-07 | Competitor features Talentra has only as a table | Section 3 |
| RB-08 | Price of profile-access credits | **Not researched**; only third-party prices were found |

## 6. Related documents

[`03-feature-inventory.md`](03-feature-inventory.md) (feature register) · [`01-requirements.md`](01-requirements.md) · [`../lifecycle/decision-log.md`](../lifecycle/decision-log.md)
