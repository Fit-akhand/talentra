# Talentra: Data Volume Sheet (Step 13)

**Phase:** 3 Prove | **Step:** 13 Data Volumetrics and Distribution Profile
**Generated** by `scripts/lifecycle/gen_volume_sheet.py` from a seeded database. Do not hand-edit.

## Method and limits

- **Base:** the database this was generated from (medium seed: 10,000 candidates, 1,000 jobs, 52,984 applications, 200 organisations, 2,000 gig workers, 10,450 accounts).
- **Horizons:** *launch* is 10% of the docket's laptop dataset; *one year* is the laptop dataset itself (1,000,000 candidates, 5,000,000 applications); *three years* is the docket's target (10,000,000 candidates, 100,000,000 applications). Which year each is reached is a business forecast the assistant cannot make; the horizons are volumes, not dates.
- **Scaling:** every table follows one driver, found from its heaviest non-audit foreign key, at the ratio measured on the base. Static tables (master data) do not grow. Ratios that drift with scale (applications per candidate is 5 at the base, 5 at the laptop dataset and 10 at the target) are carried by treating applications as their own driver.
- **Size:** rows x the bytes per row measured on the base, indexes included. This is a model; the check on it is below.

## Check against a measurement

The laptop dataset was measured at **11 GB** on disk (PostgreSQL 16.15, before migrations 029 to 037). The model's one-year total is **13.3 GB**. Within 25% of the measurement. The measurement predates migrations 029 to 037, which add tables and indexes, so a small difference in either direction is expected.

## Totals

| Horizon | Estimated size (tables and indexes) |
|:--|--:|
| Launch | 1.4 GB |
| One year (laptop dataset) | 13.3 GB |
| Three years (docket target) | 181.9 GB |

## Per table

Columns with a null rate of 50% or more are listed; a nullable column not listed is mostly filled.

| Table | Driver | Base rows | Launch | One year | Three years | Size at 3 years | Mostly-null columns |
|:--|:--|--:|--:|--:|--:|--:|:--|
| `recruitment.candidate_application` | applications | 52,984 | 500,000 | 5,000,000 | 100,000,000 | 56.8 GB | `candidate_document_id` 100%, `cover_letter` 100% |
| `recruitment.application_status_history` | applications | 100,460 | 948,022 | 9,480,220 | 189,604,408 | 27.1 GB | `change_reason` 100%, `previous_status` 53% |
| `recruitment.application_question_response` | applications | 40,400 | 381,247 | 3,812,471 | 76,249,433 | 14.5 GB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100%, `response_text` 75%, `selected_options_json` 75% |
| `profile.candidate_search_document` | candidates | 10,000 | 100,000 | 1,000,000 | 10,000,000 | 9.8 GB | - |
| `profile.candidate_work_experience` | candidates | 24,466 | 244,660 | 2,446,600 | 24,466,000 | 8.7 GB | `description` 100%, `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `profile.candidate_skill` | candidates | 36,357 | 363,570 | 3,635,700 | 36,357,000 | 6.9 GB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `profile.candidate_profile` | candidates | 10,000 | 100,000 | 1,000,000 | 10,000,000 | 6.0 GB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100%, `deleted_at` 100%, `deleted_by_user_account_id` 100% |
| `core.consent_record` | accounts | 24,909 | 243,130 | 2,431,309 | 24,313,090 | 4.6 GB | `client_ip` 100%, `user_agent` 100%, `revoked_at` 100%, `created_by_user_account_id` 100% |
| `profile.candidate_education` | candidates | 10,000 | 100,000 | 1,000,000 | 10,000,000 | 4.3 GB | `description` 100%, `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `core.user_credential` | accounts | 10,450 | 102,000 | 1,020,000 | 10,200,000 | 3.8 GB | `expires_at` 100%, `last_used_at` 100%, `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `profile.candidate_language` | candidates | 20,002 | 200,020 | 2,000,200 | 20,002,000 | 3.6 GB | `updated_by_user_account_id` 100%, `created_by_user_account_id` 100% |
| `messaging.user_notification_preference` | accounts | 16,000 | 156,172 | 1,561,722 | 15,617,224 | 3.1 GB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `profile.candidate_document` | candidates | 6,972 | 69,720 | 697,200 | 6,972,000 | 2.9 GB | `processed_at` 100%, `archived_at` 100%, `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `core.user_account` | accounts | 10,450 | 102,000 | 1,020,000 | 10,200,000 | 2.5 GB | `password_hash` 100%, `email_verified_at` 100%, `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `audit.audit_event` | accounts | 2,635 | 25,719 | 257,196 | 2,571,961 | 1.8 GB | `impersonator_user_account_id` 100%, `old_values_json` 100%, `organization_id` 100%, `user_agent` 100% |
| `profile.candidate_location` | candidates | 10,000 | 100,000 | 1,000,000 | 10,000,000 | 1.8 GB | `updated_by_user_account_id` 100%, `created_by_user_account_id` 100% |
| `core.user_role` | accounts | 10,450 | 102,000 | 1,020,000 | 10,200,000 | 1.5 GB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `messaging.notification_delivery` | accounts | 5,000 | 48,803 | 488,038 | 4,880,382 | 1.5 GB | `notification_template_id` 100%, `external_provider_message_id` 100%, `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `profile.candidate_profile_completion` | candidates | 10,000 | 100,000 | 1,000,000 | 10,000,000 | 1.5 GB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `profile.candidate_activity_log` | accounts | 7,465 | 72,864 | 728,641 | 7,286,411 | 1.4 GB | `detail_json` 100% |
| `profile.candidate_project` | candidates | 6,529 | 65,290 | 652,900 | 6,529,000 | 1.3 GB | `project_url` 100%, `description` 100%, `outcome` 100%, `created_by_user_account_id` 100% |
| `messaging.user_privacy_preference` | accounts | 10,000 | 97,607 | 976,076 | 9,760,765 | 1.3 GB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `profile.candidate_job_preference` | candidates | 7,535 | 75,350 | 753,500 | 7,534,999 | 1.1 GB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `recruitment.job_posting` | jobs | 1,000 | 10,000 | 100,000 | 1,000,000 | 933.9 MB | `application_deadline` 100%, `responsibilities` 100%, `qualifications` 100%, `workplace_location_text` 100% |
| `profile.candidate_search_history` | candidates | 4,027 | 40,270 | 402,700 | 4,027,000 | 786.4 MB | `filters_json` 100%, `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `core.identity_verification` | accounts | 2,500 | 24,401 | 244,019 | 2,440,191 | 743.6 MB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `profile.profile_view_history` | accounts | 2,783 | 27,164 | 271,642 | 2,716,421 | 623.7 MB | - |
| `recruitment.job_skill_requirement` | jobs | 3,000 | 30,000 | 300,000 | 3,000,000 | 598.0 MB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `profile.candidate_assessment_score` | candidates | 2,500 | 25,000 | 250,000 | 2,500,000 | 532.5 MB | `updated_by_user_account_id` 100%, `created_by_user_account_id` 100% |
| `profile.candidate_diversity_profile` | candidates | 3,490 | 34,900 | 349,000 | 3,490,000 | 507.9 MB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `messaging.job_alert_preference` | accounts | 2,000 | 19,521 | 195,215 | 1,952,153 | 495.8 MB | `last_dispatched_at` 100%, `created_by_user_account_id` 100%, `updated_by_user_account_id` 100%, `job_role_id` 100% |
| `messaging.share_event` | accounts | 2,000 | 19,521 | 195,215 | 1,952,153 | 471.8 MB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `recruitment.job_recruiter_assignment` | accounts | 2,000 | 19,521 | 195,215 | 1,952,153 | 431.8 MB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `gig.gig_worker_service` | gig workers | 4,000 | 20,000 | 200,000 | 2,000,000 | 397.3 MB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `recruitment.job_position` | candidates | 1,440 | 14,399 | 144,000 | 1,440,000 | 393.2 MB | `updated_by_user_account_id` 100%, `created_by_user_account_id` 100%, `filled_by_candidate_profile_id` 54%, `filled_at` 54% |
| `sourcing.sourcing_submission` | applications | 304 | 2,868 | 28,687 | 573,758 | 386.5 MB | `candidate_application_id` 100%, `consultant_notes` 100%, `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `profile.course_enrolment` | candidates | 1,500 | 15,000 | 150,000 | 1,500,000 | 368.6 MB | `certificate_reference` 100%, `created_by_user_account_id` 100%, `updated_by_user_account_id` 100%, `completed_at` 65% |
| `recruitment.job_posting_perk` | jobs | 1,958 | 19,580 | 195,800 | 1,958,000 | 344.1 MB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `commercial.candidate_profile_download_history` | accounts | 845 | 8,247 | 82,478 | 824,784 | 319.8 MB | - |
| `recruitment.job_questionnaire_question` | jobs | 1,204 | 12,040 | 120,400 | 1,204,000 | 286.7 MB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100%, `options_json` 75% |
| `sourcing.outreach_recipient` | candidates | 1,030 | 10,300 | 103,000 | 1,030,000 | 286.7 MB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100%, `response_recorded_at` 84% |
| `messaging.post_reaction` | accounts | 1,181 | 11,527 | 115,274 | 1,152,746 | 279.9 MB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `gig.gig_worker_profile` | gig workers | 2,000 | 10,000 | 100,000 | 1,000,000 | 278.5 MB | `bio` 100%, `created_by_user_account_id` 100%, `deleted_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `core.user_session` | accounts | 348 | 3,396 | 33,967 | 339,674 | 271.9 MB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100%, `ended_at` 96%, `revoked_at` 96% |
| `profile.recruiter_bookmark` | accounts | 578 | 5,641 | 56,417 | 564,172 | 255.9 MB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `recruitment.organization_member` | accounts | 400 | 3,904 | 39,043 | 390,430 | 231.9 MB | `invited_by_user_account_id` 100%, `removed_at` 100%, `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `recruitment.job_qualification_requirement` | jobs | 799 | 7,990 | 79,900 | 799,000 | 196.6 MB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `commercial.payment_order` | accounts | 399 | 3,894 | 38,945 | 389,454 | 191.9 MB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100%, `idempotency_key` 100% |
| `commercial.wallet_ledger` | organisations | 1,257 | 6,285 | 62,850 | 628,500 | 188.4 MB | `correction_of_ledger_id` 99%, `reference_id` 68% |
| `messaging.support_ticket` | accounts | 400 | 3,904 | 39,043 | 390,430 | 183.9 MB | `deleted_at` 100%, `deleted_by_user_account_id` 100%, `assigned_agent_user_id` 100%, `created_by_user_account_id` 100% |
| `gig.gig_application` | gig workers | 949 | 4,745 | 47,450 | 474,500 | 180.2 MB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `gig.gig_worker_availability` | gig workers | 2,000 | 10,000 | 100,000 | 1,000,000 | 176.1 MB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `commercial.invoice` | accounts | 399 | 3,894 | 38,945 | 389,454 | 175.9 MB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `recruitment.job_posting_location` | jobs | 438 | 4,380 | 43,800 | 438,000 | 172.0 MB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `sourcing.consultant_sourcing_request` | accounts | 276 | 2,693 | 26,939 | 269,397 | 159.9 MB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100%, `decision_reason` 53% |
| `core.user_block` | accounts | 300 | 2,928 | 29,282 | 292,822 | 151.9 MB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100%, `blocked_user_account_id` 67% |
| `recruitment.organization_identifier` | accounts | 200 | 1,952 | 19,521 | 195,215 | 143.9 MB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `core.user_device` | accounts | 280 | 2,733 | 27,330 | 273,301 | 135.9 MB | `revoked_at` 100%, `updated_by_user_account_id` 100%, `created_by_user_account_id` 100% |
| `gig.gig_request` | organisations | 500 | 2,500 | 25,000 | 250,000 | 131.1 MB | `deleted_at` 100%, `deleted_by_user_account_id` 100% |
| `commercial.licence_seat_allocation` | accounts | 400 | 3,904 | 39,043 | 390,430 | 127.9 MB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100%, `revoked_at` 100% |
| `messaging.community_post` | accounts | 200 | 1,952 | 19,521 | 195,215 | 127.9 MB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100%, `deleted_at` 100%, `deleted_by_user_account_id` 100% |
| `gig.gig_assignment` | gig workers | 300 | 1,500 | 15,000 | 150,000 | 114.7 MB | `last_reconciled_at` 100%, `updated_by_user_account_id` 100%, `created_by_user_account_id` 100% |
| `profile.recruiter_search` | accounts | 60 | 585 | 5,856 | 58,564 | 111.9 MB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100%, `name` 67% |
| `recruitment.job_questionnaire` | jobs | 301 | 3,010 | 30,100 | 301,000 | 106.5 MB | - |
| `sourcing.job_consultant_policy` | jobs | 180 | 1,800 | 18,000 | 180,000 | 106.5 MB | `terms_and_conditions` 100%, `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `messaging.referral_event` | accounts | 300 | 2,928 | 29,282 | 292,822 | 103.9 MB | `referred_user_account_id` 100%, `created_by_user_account_id` 100%, `updated_by_user_account_id` 100%, `currency_code` 88% |
| `sourcing.outreach_batch` | jobs | 66 | 660 | 6,600 | 66,000 | 98.3 MB | `job_posting_id` 100% |
| `gig.gig_rating` | accounts | 120 | 1,171 | 11,712 | 117,129 | 96.0 MB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `recruitment.organization` | organisations | 200 | 1,000 | 10,000 | 100,000 | 90.1 MB | `deleted_at` 100%, `deleted_by_user_account_id` 100%, `contact_email` 100%, `contact_phone_e164` 100% |
| `recruitment.recruiter_client_mapping` | accounts | 40 | 390 | 3,904 | 39,043 | 72.0 MB | `effective_to` 100%, `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `commercial.subscription` | organisations | 200 | 1,000 | 10,000 | 100,000 | 65.5 MB | `cancelled_at` 100%, `created_by_user_account_id` 100%, `updated_by_user_account_id` 100%, `cancellation_reason` 100% |
| `commercial.payment_refund` | accounts | 13 | 126 | 1,268 | 12,688 | 64.0 MB | `updated_by_user_account_id` 100%, `created_by_user_account_id` 100% |
| `recruitment.organization_location` | organisations | 200 | 1,000 | 10,000 | 100,000 | 61.4 MB | `address_line2` 100%, `latitude` 100%, `longitude` 100%, `created_by_user_account_id` 100% |
| `commercial.subscription_licence` | organisations | 200 | 1,000 | 10,000 | 100,000 | 53.2 MB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `gig.gig_external_earnings` | gig workers | 300 | 1,500 | 15,000 | 150,000 | 49.2 MB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `commercial.wallet` | organisations | 200 | 1,000 | 10,000 | 100,000 | 45.1 MB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `gig.gig_worker_preference` | gig workers | 40 | 200 | 2,000 | 20,000 | 41.0 MB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `recruitment.company_review_summary` | organisations | 111 | 555 | 5,550 | 55,500 | 41.0 MB | `source_url` 100%, `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `recruitment.organization_hierarchy` | organisations | 20 | 100 | 1,000 | 10,000 | 36.9 MB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `analytics.fact_application_event` | static | 100,460 | 100,460 | 100,460 | 100,460 | 19.7 MB | `previous_status` 53%, `status_cycle_time_hours` 53% |
| `analytics.dim_candidate` | static | 10,000 | 10,000 | 10,000 | 10,000 | 1.6 MB | `valid_to` 100% |
| `audit.column_classification` | static | 1,434 | 1,434 | 1,434 | 1,434 | 852.0 KB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `analytics.dim_job_posting` | static | 1,000 | 1,000 | 1,000 | 1,000 | 753.7 KB | - |
| `analytics.fact_wallet_transaction` | static | 1,257 | 1,257 | 1,257 | 1,257 | 311.3 KB | - |
| `messaging.ui_translation` | static | 391 | 391 | 391 | 391 | 229.4 KB | `updated_by_user_account_id` 100%, `created_by_user_account_id` 100% |
| `master.enumeration_value` | static | 381 | 381 | 381 | 381 | 221.2 KB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `analytics.dim_date` | static | 1,095 | 1,095 | 1,095 | 1,095 | 213.0 KB | - |
| `audit.entity_lifecycle_policy` | static | 123 | 123 | 123 | 123 | 106.5 KB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100%, `purge_column` 90%, `retention_approved_by` 55% |
| `core.role_permission` | static | 107 | 107 | 107 | 107 | 106.5 KB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `master.job_role` | static | 25 | 25 | 25 | 25 | 98.3 KB | `description` 100%, `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `messaging.legacy_field_mapping` | static | 65 | 65 | 65 | 65 | 98.3 KB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `analytics.dim_organization` | static | 200 | 200 | 200 | 200 | 90.1 KB | `valid_to` 100% |
| `analytics.fact_gig_performance` | static | 120 | 120 | 120 | 120 | 90.1 KB | - |
| `master.status_transition` | static | 151 | 151 | 151 | 151 | 90.1 KB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `messaging.integration_event` | static | 8 | 8 | 8 | 8 | 81.9 KB | `entity_schema` 100%, `entity_name` 100%, `entity_id` 100%, `last_error` 100% |
| `master.country` | static | 8 | 8 | 8 | 8 | 73.7 KB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `master.skill` | static | 34 | 34 | 34 | 34 | 65.5 KB | `description` 100%, `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `messaging.external_reference` | static | 50 | 50 | 50 | 50 | 57.3 KB | `external_hash` 100%, `updated_by_user_account_id` 100%, `created_by_user_account_id` 100% |
| `master.city` | static | 11 | 11 | 11 | 11 | 57.3 KB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `master.employment_type` | static | 6 | 6 | 6 | 6 | 57.3 KB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `master.industry` | static | 12 | 12 | 12 | 12 | 57.3 KB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `master.language` | static | 10 | 10 | 10 | 10 | 57.3 KB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `master.qualification` | static | 8 | 8 | 8 | 8 | 57.3 KB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `master.state` | static | 10 | 10 | 10 | 10 | 57.3 KB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `master.work_type` | static | 3 | 3 | 3 | 3 | 57.3 KB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `profile.candidate_assessment` | static | 6 | 6 | 6 | 6 | 57.3 KB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `audit.action_catalogue` | static | 21 | 21 | 21 | 21 | 49.2 KB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100%, `trail_table` 81% |
| `core.permission` | static | 29 | 29 | 29 | 29 | 49.2 KB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `core.role` | static | 9 | 9 | 9 | 9 | 49.2 KB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `master.status_machine_exemption` | static | 5 | 5 | 5 | 5 | 49.2 KB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `messaging.faq` | static | 5 | 5 | 5 | 5 | 49.2 KB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `messaging.integration_boundary` | static | 9 | 9 | 9 | 9 | 49.2 KB | `updated_by_user_account_id` 100%, `created_by_user_account_id` 100% |
| `messaging.notification_template` | static | 3 | 3 | 3 | 3 | 49.2 KB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `profile.resume_template` | static | 3 | 3 | 3 | 3 | 49.2 KB | `description` 100%, `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `commercial.credit_price` | static | 6 | 6 | 6 | 6 | 41.0 KB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `commercial.subscription_plan` | static | 2 | 2 | 2 | 2 | 41.0 KB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `master.department` | static | 16 | 16 | 16 | 16 | 41.0 KB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `master.job_perk` | static | 12 | 12 | 12 | 12 | 41.0 KB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `profile.course` | static | 8 | 8 | 8 | 8 | 41.0 KB | `created_by_user_account_id` 100%, `updated_by_user_account_id` 100% |
| `audit.maintenance_run` | static | 0 | 0 | 0 | 0 | 0 B | - |
| `audit.system_error_log` | accounts | 0 | 0 | 0 | 0 | 0 B | - |
| `messaging.sync_conflict` | static | 0 | 0 | 0 | 0 | 0 B | - |
| `recruitment.candidate_application_partitioned` | static | 50,000 | 50,000 | 50,000 | 50,000 | 0 B | `cover_letter` 100%, `candidate_document_id` 100% |

## What the sheet shows

- The five largest tables at three years: `recruitment.candidate_application` (56.8 GB), `recruitment.application_status_history` (27.1 GB), `recruitment.application_question_response` (14.5 GB), `profile.candidate_search_document` (9.8 GB), `profile.candidate_work_experience` (8.7 GB).
- Static tables: 43 of 123.
- Tables that hold history or events (`audit.audit_event`, application status history, view history, wallet ledger) grow with activity, not with the entity count, so the model understates them if usage per user rises. They are the ones to watch and the first candidates for partitioning (the application table already is).
