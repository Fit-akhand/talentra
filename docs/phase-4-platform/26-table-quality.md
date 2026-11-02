# Table Quality Scorecard (Step 26)

**Phase:** 4 Platform | **Step:** 26 Test Automation (Data Quality)
**Generated** by `scripts/lifecycle/gen_quality_scorecard.py` from the catalog and the seeded database. Do not hand-edit.

Seven checks per table: (1) primary key, (2) every column defined, (3) every column classified, (4) lifecycle policy row, (5) every foreign key leads an index (audit actor columns, references to master data and the analytics schema are exempt, DEC-33), (6) rows present in the seed, (7) every nullable column says what NULL means. The data-level checks (formats, references, reconciliation) are the validator's fifteen (`scripts/validate_data.py`).

**113 of 113 tables score 7 of 7.** Mean score 7.00.

## Waived checks

| Table | Check | Reason |
|:--|--:|:--|
| `audit.maintenance_run` | 6 | written by the scheduled maintenance job; running it during a seed could erase seeded accounts |
| `audit.system_error_log` | 6 | written by the application at run time; the database seed does not fabricate errors |
| `messaging.sync_conflict` | 6 | written by the migration tooling when a legacy sync finds a conflict; no sync is run by the seed |

## All tables

| Table | Score |
|:--|--:|
| `analytics.dim_candidate` | 7 |
| `analytics.dim_date` | 7 |
| `analytics.dim_job_posting` | 7 |
| `analytics.dim_organization` | 7 |
| `analytics.fact_application_event` | 7 |
| `analytics.fact_gig_performance` | 7 |
| `analytics.fact_wallet_transaction` | 7 |
| `audit.action_catalogue` | 7 |
| `audit.audit_event` | 7 |
| `audit.column_classification` | 7 |
| `audit.entity_lifecycle_policy` | 7 |
| `audit.maintenance_run` | 7 |
| `audit.system_error_log` | 7 |
| `commercial.candidate_profile_download_history` | 7 |
| `commercial.credit_price` | 7 |
| `commercial.invoice` | 7 |
| `commercial.licence_seat_allocation` | 7 |
| `commercial.payment_order` | 7 |
| `commercial.payment_refund` | 7 |
| `commercial.subscription` | 7 |
| `commercial.subscription_licence` | 7 |
| `commercial.subscription_plan` | 7 |
| `commercial.wallet` | 7 |
| `commercial.wallet_ledger` | 7 |
| `core.consent_record` | 7 |
| `core.identity_verification` | 7 |
| `core.permission` | 7 |
| `core.role` | 7 |
| `core.role_permission` | 7 |
| `core.user_account` | 7 |
| `core.user_block` | 7 |
| `core.user_credential` | 7 |
| `core.user_device` | 7 |
| `core.user_role` | 7 |
| `core.user_session` | 7 |
| `gig.gig_application` | 7 |
| `gig.gig_assignment` | 7 |
| `gig.gig_external_earnings` | 7 |
| `gig.gig_rating` | 7 |
| `gig.gig_request` | 7 |
| `gig.gig_worker_availability` | 7 |
| `gig.gig_worker_preference` | 7 |
| `gig.gig_worker_profile` | 7 |
| `gig.gig_worker_service` | 7 |
| `master.city` | 7 |
| `master.country` | 7 |
| `master.employment_type` | 7 |
| `master.enumeration_value` | 7 |
| `master.industry` | 7 |
| `master.job_role` | 7 |
| `master.language` | 7 |
| `master.qualification` | 7 |
| `master.skill` | 7 |
| `master.state` | 7 |
| `master.status_machine_exemption` | 7 |
| `master.status_transition` | 7 |
| `master.work_type` | 7 |
| `messaging.community_post` | 7 |
| `messaging.external_reference` | 7 |
| `messaging.faq` | 7 |
| `messaging.integration_boundary` | 7 |
| `messaging.integration_event` | 7 |
| `messaging.job_alert_preference` | 7 |
| `messaging.legacy_field_mapping` | 7 |
| `messaging.notification_delivery` | 7 |
| `messaging.notification_template` | 7 |
| `messaging.post_reaction` | 7 |
| `messaging.referral_event` | 7 |
| `messaging.share_event` | 7 |
| `messaging.support_ticket` | 7 |
| `messaging.sync_conflict` | 7 |
| `messaging.ui_translation` | 7 |
| `messaging.user_notification_preference` | 7 |
| `messaging.user_privacy_preference` | 7 |
| `profile.candidate_activity_log` | 7 |
| `profile.candidate_assessment` | 7 |
| `profile.candidate_assessment_score` | 7 |
| `profile.candidate_document` | 7 |
| `profile.candidate_education` | 7 |
| `profile.candidate_language` | 7 |
| `profile.candidate_location` | 7 |
| `profile.candidate_profile` | 7 |
| `profile.candidate_profile_completion` | 7 |
| `profile.candidate_project` | 7 |
| `profile.candidate_search_history` | 7 |
| `profile.candidate_skill` | 7 |
| `profile.candidate_work_experience` | 7 |
| `profile.course` | 7 |
| `profile.course_enrolment` | 7 |
| `profile.profile_view_history` | 7 |
| `profile.recruiter_bookmark` | 7 |
| `profile.resume_template` | 7 |
| `recruitment.application_question_response` | 7 |
| `recruitment.application_status_history` | 7 |
| `recruitment.candidate_application` | 7 |
| `recruitment.candidate_application_partitioned` | 7 |
| `recruitment.company_review_summary` | 7 |
| `recruitment.job_position` | 7 |
| `recruitment.job_posting` | 7 |
| `recruitment.job_questionnaire` | 7 |
| `recruitment.job_questionnaire_question` | 7 |
| `recruitment.job_skill_requirement` | 7 |
| `recruitment.organization` | 7 |
| `recruitment.organization_hierarchy` | 7 |
| `recruitment.organization_identifier` | 7 |
| `recruitment.organization_location` | 7 |
| `recruitment.organization_member` | 7 |
| `recruitment.recruiter_client_mapping` | 7 |
| `sourcing.consultant_sourcing_request` | 7 |
| `sourcing.job_consultant_policy` | 7 |
| `sourcing.outreach_batch` | 7 |
| `sourcing.outreach_recipient` | 7 |
| `sourcing.sourcing_submission` | 7 |
