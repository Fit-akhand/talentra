# Talentra: Entity Catalogue (Step 06)

**Phase:** 2 Model | **Step:** 06 Entities Discovery
**Generated** by `scripts/lifecycle/gen_model_catalogues.py` from a migrated database. Do not hand-edit.

Every table the implemented schema holds, with its bounded schema, kind, size, relationship counts and the Rule Group 4 audit and lifecycle columns it carries.

**Totals:** 113 base tables + 3 partitions = 116 relations across 10 schemas.

## Summary by schema

| Schema | Tables | Partitions |
|:--|--:|--:|
| `core` | 11 | 0 |
| `master` | 13 | 0 |
| `profile` | 18 | 0 |
| `recruitment` | 16 | 3 |
| `gig` | 9 | 0 |
| `commercial` | 11 | 0 |
| `sourcing` | 5 | 0 |
| `messaging` | 17 | 0 |
| `audit` | 6 | 0 |
| `analytics` | 7 | 0 |

## Entities

Audit columns = `created_at`, `created_by`, `updated_at`, `updated_by` (RG4). Soft delete = has `deleted_at`.

### `core`

| Table | Cols | FK out | FK in | Audit cols (RG4) | Soft delete | Triggers |
|:--|--:|--:|--:|:--|:--|:--|
| `consent_record` | 13 | 1 | 0 | all 4 | no | trg_consent_record_audit, trg_consent_record_audit_columns |
| `identity_verification` | 13 | 1 | 0 | all 4 | no | trg_identity_verification_audit, trg_identity_verification_audit_columns, trg_identity_verification_status_transition |
| `permission` | 9 | 1 | 1 | all 4 | no | trg_permission_audit_columns |
| `role` | 8 | 1 | 2 | all 4 | no | trg_role_audit_columns |
| `role_permission` | 8 | 3 | 0 | all 4 | no | trg_role_permission_audit, trg_role_permission_audit_columns |
| `user_account` | 14 | 1 | 104 | all 4 | yes | trg_user_account_audit_columns, trg_user_account_status_audit, trg_user_account_status_transition |
| `user_block` | 9 | 2 | 0 | all 4 | no | trg_user_block_audit, trg_user_block_audit_columns |
| `user_credential` | 13 | 1 | 0 | all 4 | no | trg_user_credential_audit, trg_user_credential_audit_columns |
| `user_device` | 14 | 1 | 0 | all 4 | no | trg_user_device_audit_columns |
| `user_role` | 8 | 2 | 0 | all 4 | no | trg_user_role_audit, trg_user_role_audit_columns |
| `user_session` | 12 | 1 | 0 | all 4 | no | trg_user_session_audit_columns |

### `master`

| Table | Cols | FK out | FK in | Audit cols (RG4) | Soft delete | Triggers |
|:--|--:|--:|--:|:--|:--|:--|
| `city` | 8 | 2 | 4 | all 4 | no | trg_city_audit_columns |
| `country` | 10 | 1 | 3 | all 4 | no | trg_country_audit_columns |
| `employment_type` | 8 | 1 | 2 | all 4 | no | trg_employment_type_audit_columns |
| `enumeration_value` | 9 | 1 | 0 | all 4 | no | trg_enumeration_value_audit_columns |
| `industry` | 8 | 1 | 2 | all 4 | no | trg_industry_audit_columns |
| `job_role` | 10 | 2 | 3 | all 4 | no | trg_job_role_audit_columns |
| `language` | 9 | 1 | 5 | all 4 | no | trg_language_audit_columns |
| `qualification` | 8 | 1 | 1 | all 4 | no | trg_qualification_audit_columns |
| `skill` | 9 | 1 | 4 | all 4 | no | trg_skill_audit_columns |
| `state` | 9 | 2 | 1 | all 4 | no | trg_state_audit_columns |
| `status_machine_exemption` | 9 | 1 | 0 | all 4 | no | trg_status_machine_exemption_audit_columns |
| `status_transition` | 8 | 1 | 0 | all 4 | no | trg_status_transition_audit_columns |
| `work_type` | 8 | 1 | 2 | all 4 | no | trg_work_type_audit_columns |

### `profile`

| Table | Cols | FK out | FK in | Audit cols (RG4) | Soft delete | Triggers |
|:--|--:|--:|--:|:--|:--|:--|
| `candidate_activity_log` | 7 | 2 | 0 | none | no | trg_candidate_activity_log_append_only, trg_candidate_activity_log_block_truncate |
| `candidate_assessment` | 12 | 2 | 1 | all 4 | no | trg_candidate_assessment_audit_columns |
| `candidate_assessment_score` | 12 | 3 | 0 | all 4 | no | trg_candidate_assessment_score_audit_columns |
| `candidate_document` | 21 | 3 | 1 | all 4 | yes | trg_candidate_document_audit_columns, trg_candidate_document_status_transition |
| `candidate_education` | 14 | 3 | 0 | all 4 | no | trg_candidate_education_audit_columns |
| `candidate_language` | 11 | 3 | 0 | all 4 | no | trg_candidate_language_audit_columns |
| `candidate_location` | 8 | 3 | 0 | all 4 | no | trg_candidate_location_audit_columns |
| `candidate_profile` | 14 | 2 | 19 | all 4 | yes | trg_candidate_profile_audit_columns, trg_candidate_profile_self_registration, trg_candidate_profile_status_transition |
| `candidate_profile_completion` | 15 | 2 | 0 | all 4 | no | trg_candidate_profile_completion_audit_columns |
| `candidate_project` | 15 | 2 | 0 | all 4 | no | trg_candidate_project_audit_columns |
| `candidate_search_history` | 10 | 2 | 0 | all 4 | no | trg_candidate_search_history_audit_columns |
| `candidate_skill` | 10 | 3 | 0 | all 4 | no | trg_candidate_skill_audit_columns |
| `candidate_work_experience` | 14 | 4 | 0 | all 4 | no | trg_candidate_work_experience_audit_columns |
| `course` | 11 | 1 | 1 | all 4 | no | trg_course_audit_columns |
| `course_enrolment` | 12 | 3 | 0 | all 4 | no | trg_course_enrolment_audit_columns, trg_course_enrolment_status_transition |
| `profile_view_history` | 7 | 3 | 0 | none | no | trg_profile_view_history_append_only, trg_profile_view_history_block_truncate |
| `recruiter_bookmark` | 9 | 3 | 0 | all 4 | no | trg_recruiter_bookmark_audit_columns |
| `resume_template` | 10 | 1 | 1 | all 4 | no | trg_resume_template_audit_columns |

### `recruitment`

| Table | Cols | FK out | FK in | Audit cols (RG4) | Soft delete | Triggers |
|:--|--:|--:|--:|:--|:--|:--|
| `application_question_response` | 11 | 3 | 0 | all 4 | no | trg_application_question_response_audit_columns |
| `application_status_history` | 7 | 2 | 0 | none | no | trg_application_status_history_append_only, trg_application_status_history_block_truncate |
| `candidate_application` | 13 | 4 | 3 | all 4 | no | trg_candidate_application_audit_columns, trg_candidate_application_status_history, trg_candidate_application_status_transition |
| `candidate_application_partitioned` (partitioned) | 13 | 0 | 0 | all 4 | no | trg_candidate_application_partitioned_audit_columns |
| `company_review_summary` | 13 | 2 | 0 | all 4 | no | trg_company_review_summary_audit_columns |
| `job_position` | 10 | 3 | 0 | all 4 | no | trg_job_position_audit_columns, trg_job_position_status_transition |
| `job_posting` | 30 | 8 | 9 | all 4 | yes | trg_job_posting_audit_columns, trg_job_posting_status_transition |
| `job_questionnaire` | 9 | 2 | 1 | all 4 | no | trg_job_questionnaire_audit_columns |
| `job_questionnaire_question` | 11 | 2 | 1 | all 4 | no | trg_job_questionnaire_question_audit_columns |
| `job_skill_requirement` | 10 | 3 | 0 | all 4 | no | trg_job_skill_requirement_audit_columns |
| `organization` | 16 | 2 | 19 | all 4 | yes | trg_organization_audit_columns, trg_organization_status_audit, trg_organization_status_transition |
| `organization_hierarchy` | 9 | 2 | 0 | all 4 | no | trg_organization_hierarchy_audit_columns |
| `organization_identifier` | 14 | 3 | 0 | all 4 | no | trg_organization_identifier_audit_columns, trg_organization_identifier_binding, trg_organization_identifier_status_transition |
| `organization_location` | 17 | 3 | 0 | all 4 | no | trg_organization_location_audit_columns |
| `organization_member` | 13 | 2 | 0 | all 4 | no | trg_organization_member_audit, trg_organization_member_audit_columns, trg_organization_member_status_transition |
| `recruiter_client_mapping` | 11 | 2 | 0 | all 4 | no | trg_recruiter_client_mapping_audit_columns |

### `gig`

| Table | Cols | FK out | FK in | Audit cols (RG4) | Soft delete | Triggers |
|:--|--:|--:|--:|:--|:--|:--|
| `gig_application` | 14 | 3 | 1 | all 4 | no | trg_gig_application_audit_columns, trg_gig_application_status_transition |
| `gig_assignment` | 16 | 4 | 2 | all 4 | no | trg_gig_assignment_audit_columns, trg_gig_assignment_status_transition |
| `gig_external_earnings` | 12 | 2 | 0 | all 4 | no | trg_gig_external_earnings_audit_columns |
| `gig_rating` | 11 | 2 | 0 | all 4 | no | trg_gig_rating_audit_columns |
| `gig_request` | 17 | 2 | 2 | all 4 | yes | trg_gig_request_audit_columns, trg_gig_request_status_transition |
| `gig_worker_availability` | 9 | 2 | 0 | all 4 | no | trg_gig_worker_availability_audit_columns |
| `gig_worker_preference` | 9 | 3 | 0 | all 4 | no | trg_gig_worker_preference_audit_columns |
| `gig_worker_profile` | 17 | 1 | 5 | all 4 | yes | trg_gig_worker_profile_audit_columns, trg_gig_worker_profile_status_transition |
| `gig_worker_service` | 10 | 3 | 0 | all 4 | no | trg_gig_worker_service_audit_columns |

### `commercial`

| Table | Cols | FK out | FK in | Audit cols (RG4) | Soft delete | Triggers |
|:--|--:|--:|--:|:--|:--|:--|
| `candidate_profile_download_history` | 8 | 4 | 0 | none | no | trg_candidate_profile_download_history_block_truncate, trg_prevent_download_history_tampering |
| `credit_price` | 9 | 1 | 0 | all 4 | no | trg_credit_price_audit_columns |
| `invoice` | 15 | 3 | 0 | all 4 | no | trg_invoice_audit_columns, trg_invoice_status_transition |
| `licence_seat_allocation` | 10 | 2 | 0 | all 4 | no | trg_enforce_licence_max_users, trg_licence_seat_allocation_audit_columns, trg_licence_seat_audit |
| `payment_order` | 13 | 2 | 2 | all 4 | no | trg_payment_order_audit, trg_payment_order_audit_columns, trg_payment_order_status_transition |
| `payment_refund` | 12 | 2 | 0 | all 4 | no | trg_payment_refund_audit, trg_payment_refund_audit_columns |
| `subscription` | 13 | 3 | 0 | all 4 | no | trg_subscription_audit, trg_subscription_audit_columns, trg_subscription_status_transition |
| `subscription_licence` | 13 | 2 | 2 | all 4 | no | trg_subscription_licence_audit, trg_subscription_licence_audit_columns, trg_subscription_licence_status_transition |
| `subscription_plan` | 15 | 1 | 1 | all 4 | no | trg_subscription_plan_audit_columns |
| `wallet` | 8 | 2 | 1 | all 4 | no | trg_wallet_audit_columns |
| `wallet_ledger` | 12 | 3 | 2 | partial: created_by | no | trg_prevent_wallet_ledger_tampering, trg_wallet_ledger_block_truncate |

### `sourcing`

| Table | Cols | FK out | FK in | Audit cols (RG4) | Soft delete | Triggers |
|:--|--:|--:|--:|:--|:--|:--|
| `consultant_sourcing_request` | 12 | 2 | 1 | all 4 | no | trg_consultant_sourcing_request_audit_columns, trg_consultant_sourcing_request_status_transition, trg_enforce_consultant_openness |
| `job_consultant_policy` | 11 | 2 | 0 | all 4 | no | trg_job_consultant_policy_audit_columns |
| `outreach_batch` | 15 | 3 | 1 | all 4 | no | trg_outreach_batch_audit_columns, trg_outreach_batch_status_transition |
| `outreach_recipient` | 11 | 3 | 0 | all 4 | no | trg_outreach_recipient_audit_columns, trg_outreach_recipient_block |
| `sourcing_submission` | 13 | 5 | 0 | all 4 | no | trg_sourcing_submission_audit_columns, trg_sourcing_submission_status_transition |

### `messaging`

| Table | Cols | FK out | FK in | Audit cols (RG4) | Soft delete | Triggers |
|:--|--:|--:|--:|:--|:--|:--|
| `community_post` | 14 | 2 | 1 | all 4 | yes | trg_community_post_audit_columns |
| `external_reference` | 11 | 2 | 0 | all 4 | no | trg_external_reference_audit_columns |
| `faq` | 10 | 1 | 0 | all 4 | no | trg_faq_audit_columns |
| `integration_boundary` | 16 | 1 | 2 | all 4 | no | trg_integration_boundary_audit_columns |
| `integration_event` | 19 | 2 | 0 | all 4 | no | trg_integration_event_audit_columns, trg_integration_event_status_transition |
| `job_alert_preference` | 16 | 4 | 0 | all 4 | no | trg_job_alert_preference_audit_columns |
| `legacy_field_mapping` | 13 | 1 | 1 | all 4 | no | trg_legacy_field_mapping_audit_columns |
| `notification_delivery` | 15 | 2 | 0 | all 4 | no | trg_notification_delivery_audit_columns |
| `notification_template` | 11 | 1 | 1 | all 4 | no | trg_notification_template_audit_columns |
| `post_reaction` | 8 | 2 | 0 | all 4 | no | trg_post_reaction_audit_columns |
| `referral_event` | 13 | 1 | 0 | all 4 | no | trg_referral_event_audit_columns, trg_referral_event_status_transition |
| `share_event` | 9 | 2 | 0 | all 4 | no | trg_share_event_audit_columns |
| `support_ticket` | 14 | 1 | 0 | all 4 | yes | trg_support_ticket_audit_columns, trg_support_ticket_status_transition |
| `sync_conflict` | 13 | 2 | 0 | all 4 | no | trg_sync_conflict_audit_columns |
| `ui_translation` | 9 | 2 | 0 | all 4 | no | trg_ui_translation_audit_columns |
| `user_notification_preference` | 9 | 1 | 0 | all 4 | no | trg_user_notification_preference_audit_columns |
| `user_privacy_preference` | 10 | 1 | 0 | all 4 | no | trg_user_privacy_preference_audit_columns |

### `audit`

| Table | Cols | FK out | FK in | Audit cols (RG4) | Soft delete | Triggers |
|:--|--:|--:|--:|:--|:--|:--|
| `action_catalogue` | 10 | 1 | 1 | all 4 | no | trg_action_catalogue_audit_columns |
| `audit_event` | 13 | 3 | 0 | none | no | trg_audit_event_block_truncate, trg_prevent_audit_event_tampering |
| `column_classification` | 12 | 1 | 0 | all 4 | no | trg_column_classification_audit_columns |
| `entity_lifecycle_policy` | 13 | 1 | 0 | all 4 | no | trg_entity_lifecycle_policy_audit_columns |
| `maintenance_run` | 8 | 0 | 0 | none | no | trg_maintenance_run_append_only, trg_maintenance_run_block_truncate |
| `system_error_log` | 8 | 1 | 0 | none | no | trg_system_error_log_append_only, trg_system_error_log_block_truncate |

### `analytics`

| Table | Cols | FK out | FK in | Audit cols (RG4) | Soft delete | Triggers |
|:--|--:|--:|--:|:--|:--|:--|
| `dim_candidate` | 9 | 0 | 1 | none | no | - |
| `dim_date` | 10 | 0 | 4 | none | no | - |
| `dim_job_posting` | 12 | 2 | 1 | none | no | - |
| `dim_organization` | 9 | 0 | 4 | none | no | - |
| `fact_application_event` | 12 | 4 | 0 | none | no | - |
| `fact_gig_performance` | 10 | 2 | 0 | none | no | - |
| `fact_wallet_transaction` | 10 | 2 | 0 | none | no | - |

### Partitions

| Partition | Parent |
|:--|:--|
| `recruitment.candidate_application_y2025` | `candidate_application_partitioned` |
| `recruitment.candidate_application_y2026` | `candidate_application_partitioned` |
| `recruitment.candidate_application_y2027` | `candidate_application_partitioned` |

## Conformance snapshot (Rule Group 4)

- Base tables with all four audit columns: **98 / 113**.
- Per column: `created_at` 98/113, `created_by` 99/113, `updated_at` 98/113, `updated_by` 98/113, `deleted_at` 9/113.
- The docket requires all four on every business table, and a `deleted_at` on every soft-deleted entity with the soft/hard classification stated per entity. No table has `deleted_at` and no classification is recorded: both are open RG4 gaps.
- Tables without all four audit columns are listed above; each is either append-only (no `updated_*` by design) or a gap to resolve in Step 17.
