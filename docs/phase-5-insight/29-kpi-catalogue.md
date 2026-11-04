# Talentra: KPI Catalogue (Step 29)

**Phase:** 5 Insight | **Step:** 29 KPI Discovery
**Generated** by `scripts/lifecycle/gen_kpi_catalogue.py`. Do not hand-edit; edit the SQL in [`db/kpi/`](../../db/kpi/).

**16 of 16 KPIs execute against the schema.** Each query is the definition: the formula, grain and sources below are read from its header.

## Catalogue

| ID | KPI | Persona | Type | Grain | Unit | Target | Refresh | Computable | Source tables | Query |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| KPI-001 | Applications per published job | Employer / Recruiter (ACT-02) | lagging | count / job | ratio | *unset* | real-time | yes | recruitment.job_posting, recruitment.candidate_application | [`01_hiring_volume.sql`](../../db/kpi/01_hiring_volume.sql) |
| KPI-002 | Pipeline stage mix | Recruiter (ACT-02) | leading | application status | percent | *unset* | real-time | yes | recruitment.candidate_application | [`02_pipeline_stage_mix.sql`](../../db/kpi/02_pipeline_stage_mix.sql) |
| KPI-003 | Average time to hire (hours) | Employer (ACT-02), Executive | lagging | joined application | hours | *unset* | real-time | yes | recruitment.candidate_application | [`03_time_to_hire.sql`](../../db/kpi/03_time_to_hire.sql) |
| KPI-004 | Offer-to-join rate | Employer (ACT-02) | lagging | application | percent | *unset* | real-time | yes | recruitment.application_status_history | [`04_offer_to_join.sql`](../../db/kpi/04_offer_to_join.sql) |
| KPI-005 | Average profile completeness | Candidate (ACT-01), Product | leading | current candidate dimension row | percent | *unset* | mart load | yes | analytics.dim_candidate | [`05_profile_completeness.sql`](../../db/kpi/05_profile_completeness.sql) |
| KPI-006 | Published jobs by industry | Executive, Employer | leading | industry | count | *unset* | real-time | yes | recruitment.job_posting, master.industry | [`06_jobs_by_industry.sql`](../../db/kpi/06_jobs_by_industry.sql) |
| KPI-007 | Wallets that do not reconcile to their ledger | Finance / Platform Operations (ACT-08) | lagging | wallet | count (target 0) | *unset* | daily | yes | commercial.wallet, commercial.wallet_ledger | [`07_wallet_reconciliation.sql`](../../db/kpi/07_wallet_reconciliation.sql) |
| KPI-008 | Credit movement by type | Finance, Employer | lagging | entry type x reference type | currency amount | *unset* | real-time | yes | commercial.wallet_ledger | [`08_credit_consumption.sql`](../../db/kpi/08_credit_consumption.sql) |
| KPI-009 | Gig request award rate | Gig requester, Executive | lagging | gig request | percent | *unset* | real-time | yes | gig.gig_request | [`09_gig_award_rate.sql`](../../db/kpi/09_gig_award_rate.sql) |
| KPI-010 | Average gig client rating | Gig requester, Gig worker | lagging | rating | score 0-5 | *unset* | real-time | yes | gig.gig_rating | [`10_gig_rating.sql`](../../db/kpi/10_gig_rating.sql) |
| KPI-011 | Notification delivery success rate | Platform Operations (ACT-08) | lagging | delivery | percent | *unset* | real-time | yes | messaging.notification_delivery | [`11_notification_delivery.sql`](../../db/kpi/11_notification_delivery.sql) |
| KPI-012 | Consultant submission acceptance rate | Consultant (ACT-05), Employer | lagging | submission | percent | *unset* | real-time | yes | sourcing.sourcing_submission | [`12_consultant_acceptance.sql`](../../db/kpi/12_consultant_acceptance.sql) |
| KPI-013 | Outreach response rate | Recruiter (ACT-02) | lagging | outreach recipient | percent | *unset* | real-time | yes | sourcing.outreach_recipient | [`13_outreach_response.sql`](../../db/kpi/13_outreach_response.sql) |
| KPI-014 | Open support tickets | Support, Platform Operations (ACT-08) | leading | ticket | count | *unset* | real-time | yes | messaging.support_ticket | [`14_support_backlog.sql`](../../db/kpi/14_support_backlog.sql) |
| KPI-015 | Device-limit denials recorded in the audit trail | Security / Platform Operations (ACT-08) | leading | audit event | count | *unset* | real-time | yes | audit.audit_event | [`15_device_limit_denials.sql`](../../db/kpi/15_device_limit_denials.sql) |
| KPI-016 | Profile-download credit spend | Finance, Employer | lagging | download | currency amount | *unset* | real-time | yes | commercial.candidate_profile_download_history | [`16_download_credit_spend.sql`](../../db/kpi/16_download_credit_spend.sql) |

**Target** is *unset* for every KPI. No target was provided in the docket, and inventing one would be a guess. The owner named by *Persona* must approve a target before a KPI can be reported as red or green.

## Values on the current dataset

Example output from the run that generated this file. The dataset is the `dev` seed, so values show that a query works, not what the business looks like.

| ID | First row |
|:--|:--|
| KPI-001 | applications_per_published_job=59.95 |
| KPI-002 | application_status=applied, applications=25341, pct_of_all=47.83 |
| KPI-003 | avg_hours_applied_to_joined=780.94, joined_applications=1644 |
| KPI-004 | offer_to_join_pct=31.11 |
| KPI-005 | avg_profile_completeness_pct=95.52 |
| KPI-006 | industry=Information Technology, published_jobs=66 |
| KPI-007 | unreconciled_wallets=0 |
| KPI-008 | entry_type=credit, reference_type=recharge, currency_code=USD, entries=399, total_amount=875500.00 |
| KPI-009 | award_rate_of_closed_requests_pct=93.46, total_requests=500 |
| KPI-010 | avg_rating=4.01, ratings=120 |
| KPI-011 | delivered_pct_of_attempted=81.75, total_deliveries=5000 |
| KPI-012 | accepted_pct=28.62, submissions=304 |
| KPI-013 | response_pct=18.43, recipients=1030 |
| KPI-014 | priority=medium, open_tickets=99 |
| KPI-015 | device_limit_audit_events=40 |
| KPI-016 | currency_code=USD, downloads=845, credits_spent=8450.00 |

## KPI tree

```
Hiring outcome ........ KPI-003 time to hire <- KPI-004 offer-to-join <- KPI-002 stage mix <- KPI-001 applications per job
Candidate supply ...... KPI-005 profile completeness, KPI-006 jobs by industry
Marketplace quality ... KPI-009 gig award rate, KPI-010 gig rating, KPI-012 consultant acceptance, KPI-013 outreach response
Money integrity ....... KPI-007 wallet reconciliation (target 0), KPI-008 credit movement, KPI-016 download spend
Platform health ....... KPI-011 delivery success, KPI-014 support backlog, KPI-015 device-limit denials
```

## Gaps found while making the KPIs computable (return to Phase 3)

1. **The star schema has no load process.** `analytics.refresh_reporting_marts()` only refreshes two materialised views. Nothing populates `dim_*` and `fact_*` from the operational tables except the data generator, and `fact_gig_performance` and `fact_wallet_transaction` are empty after seeding. Of the 16 KPIs, only KPI-005 reads the star schema; the rest read operational tables, because the mart cannot be trusted to be current.
2. **Query 10 (`db/queries/10_analytics_time_to_hire_kpi.sql`) used to average the cycle time of the joined event only**, that is, time spent in the previous stage, not the time from application to joining, and re-aggregated every event on each call. It now reads `analytics.mv_hiring_funnel_by_industry` (migration 028), which measures the full interval and is rebuilt by `analytics.refresh_reporting_marts()`; KPI-003 and Query 10 agree.
3. **KPIs on audit events depend on write sites that barely exist.** KPI-015 can only count what the schema writes to `audit.audit_event`, and the audit matrix records two write sites in the whole schema.
4. **The dev seed is too flat to exercise the KPIs** (playbook anti-pattern: uniform test data). In the run above: all 100 jobs have a NULL `industry_id` (KPI-006 returns no rows); every gig request is `open` (KPI-009 is undefined); every application has `last_status_changed_at = applied_at`, so KPI-003 reads exactly 0.00 hours; there are no support tickets (KPI-014) and every notification is `sent` (KPI-011 reads 0%). Step 13 (volumetrics and distributions) and step 14 must fix the generator before the KPI values mean anything.

## Gate G5

- *Every KPI is computable from the schema:* **met** for all 16 (queries execute).
- *Every dashboard number reconciles with its source:* **not assessed.** There is no dashboard; reconciliation is step 30.
