# Talentra: Entity-Relationship Diagrams, generated (Step 09)

**Phase:** 2 Model | **Step:** 09 Database, Tables and Relationships
**Generated** by `scripts/lifecycle/gen_model_catalogues.py`. Do not hand-edit.

One diagram per schema showing its tables and the foreign keys between them; foreign keys that cross schemas are listed in a table instead, to keep each diagram readable. Columns are omitted: see the attribute catalogue. `}o--||` reads: many rows on the left reference one row on the right. Audit columns (`created_by`, `updated_by`, `deleted_by`) point at `core.user_account` from nearly every table and are left out of the diagrams.

## `core` (11 tables)

```mermaid
erDiagram
    consent_record }o--|| user_account : "user_account_id"
    identity_verification }o--|| user_account : "user_account_id"
    role_permission }o--|| permission : "permission_id"
    role_permission }o--|| role : "role_id"
    user_block }o--|| user_account : "blocked_user_account_id"
    user_block }o--|| user_account : "blocker_user_account_id"
    user_credential }o--|| user_account : "user_account_id"
    user_device }o--|| user_account : "user_account_id"
    user_role }o--|| role : "role_id"
    user_role }o--|| user_account : "user_account_id"
    user_session }o--|| user_account : "user_account_id"
```

## `master` (15 tables)

```mermaid
erDiagram
    city }o--|| state : "state_id"
    job_role }o--|| industry : "industry_id"
    state }o--|| country : "country_id"
    department
    employment_type
    enumeration_value
    job_perk
    language
    qualification
    skill
    status_machine_exemption
    status_transition
    work_type
```

## `profile` (22 tables)

```mermaid
erDiagram
    candidate_activity_log }o--|| candidate_profile : "candidate_profile_id"
    candidate_assessment_score }o--|| candidate_assessment : "candidate_assessment_id"
    candidate_assessment_score }o--|| candidate_profile : "candidate_profile_id"
    candidate_diversity_profile }o--|| candidate_profile : "candidate_profile_id"
    candidate_document }o--|| candidate_profile : "candidate_profile_id"
    candidate_document }o--|| resume_template : "resume_template_id"
    candidate_education }o--|| candidate_profile : "candidate_profile_id"
    candidate_job_preference }o--|| candidate_profile : "candidate_profile_id"
    candidate_language }o--|| candidate_profile : "candidate_profile_id"
    candidate_location }o--|| candidate_profile : "candidate_profile_id"
    candidate_profile_completion }o--|| candidate_profile : "candidate_profile_id"
    candidate_project }o--|| candidate_profile : "candidate_profile_id"
    candidate_search_document }o--|| candidate_profile : "candidate_profile_id"
    candidate_search_history }o--|| candidate_profile : "candidate_profile_id"
    candidate_skill }o--|| candidate_profile : "candidate_profile_id"
    candidate_work_experience }o--|| candidate_profile : "candidate_profile_id"
    course_enrolment }o--|| candidate_profile : "candidate_profile_id"
    course_enrolment }o--|| course : "course_id"
    profile_view_history }o--|| candidate_profile : "candidate_profile_id"
    recruiter_bookmark }o--|| candidate_profile : "candidate_profile_id"
    recruiter_search
```

## `recruitment` (20 tables)

```mermaid
erDiagram
    application_question_response }o--|| candidate_application : "candidate_application_id"
    application_question_response }o--|| job_questionnaire_question : "job_questionnaire_question_id"
    application_status_history }o--|| candidate_application : "candidate_application_id"
    candidate_application }o--|| job_posting : "job_posting_id"
    company_review_summary }o--|| organization : "organization_id"
    job_position }o--|| job_posting : "job_posting_id"
    job_posting }o--|| organization : "organization_id"
    job_posting_location }o--|| job_posting : "job_posting_id"
    job_posting_perk }o--|| job_posting : "job_posting_id"
    job_qualification_requirement }o--|| job_posting : "job_posting_id"
    job_questionnaire }o--|| job_posting : "job_posting_id"
    job_questionnaire_question }o--|| job_questionnaire : "job_questionnaire_id"
    job_recruiter_assignment }o--|| job_posting : "job_posting_id"
    job_skill_requirement }o--|| job_posting : "job_posting_id"
    organization_hierarchy }o--|| organization : "child_organization_id"
    organization_hierarchy }o--|| organization : "parent_organization_id"
    organization_identifier }o--|| organization : "organization_id"
    organization_location }o--|| organization : "organization_id"
    organization_member }o--|| organization : "organization_id"
    recruiter_client_mapping }o--|| organization : "agency_organization_id"
    recruiter_client_mapping }o--|| organization : "client_organization_id"
    candidate_application_partitioned
```

## `gig` (9 tables)

```mermaid
erDiagram
    gig_application }o--|| gig_request : "gig_request_id"
    gig_application }o--|| gig_worker_profile : "gig_worker_profile_id"
    gig_assignment }o--|| gig_application : "gig_application_id"
    gig_assignment }o--|| gig_request : "gig_request_id"
    gig_assignment }o--|| gig_worker_profile : "gig_worker_profile_id"
    gig_external_earnings }o--|| gig_assignment : "gig_assignment_id"
    gig_rating }o--|| gig_assignment : "gig_assignment_id"
    gig_worker_availability }o--|| gig_worker_profile : "gig_worker_profile_id"
    gig_worker_preference }o--|| gig_worker_profile : "gig_worker_profile_id"
    gig_worker_service }o--|| gig_worker_profile : "gig_worker_profile_id"
```

## `commercial` (11 tables)

```mermaid
erDiagram
    candidate_profile_download_history }o--|| wallet_ledger : "wallet_ledger_id"
    invoice }o--|| payment_order : "payment_order_id"
    licence_seat_allocation }o--|| subscription_licence : "subscription_licence_id"
    payment_refund }o--|| payment_order : "payment_order_id"
    subscription }o--|| subscription_licence : "subscription_licence_id"
    subscription }o--|| subscription_plan : "subscription_plan_id"
    wallet_ledger }o--|| wallet : "wallet_id"
    wallet_ledger }o--|| wallet_ledger : "correction_of_ledger_id"
    credit_price
```

## `sourcing` (5 tables)

```mermaid
erDiagram
    outreach_recipient }o--|| outreach_batch : "outreach_batch_id"
    sourcing_submission }o--|| consultant_sourcing_request : "consultant_sourcing_request_id"
    job_consultant_policy
```

## `messaging` (17 tables)

```mermaid
erDiagram
    external_reference }o--|| integration_boundary : "boundary_code"
    integration_event }o--|| integration_boundary : "boundary_id"
    notification_delivery }o--|| notification_template : "notification_template_id"
    post_reaction }o--|| community_post : "community_post_id"
    sync_conflict }o--|| legacy_field_mapping : "mapping_id"
    faq
    job_alert_preference
    referral_event
    share_event
    support_ticket
    ui_translation
    user_notification_preference
    user_privacy_preference
```

## `audit` (6 tables)

```mermaid
erDiagram
    audit_event }o--|| action_catalogue : "action"
    column_classification
    entity_lifecycle_policy
    maintenance_run
    system_error_log
```

## `analytics` (7 tables)

```mermaid
erDiagram
    dim_job_posting }o--|| dim_date : "published_date_key"
    dim_job_posting }o--|| dim_organization : "organization_key"
    fact_application_event }o--|| dim_candidate : "candidate_key"
    fact_application_event }o--|| dim_date : "date_key"
    fact_application_event }o--|| dim_job_posting : "job_posting_key"
    fact_application_event }o--|| dim_organization : "organization_key"
    fact_gig_performance }o--|| dim_date : "completion_date_key"
    fact_gig_performance }o--|| dim_organization : "organization_key"
    fact_wallet_transaction }o--|| dim_date : "date_key"
    fact_wallet_transaction }o--|| dim_organization : "organization_key"
```

## Foreign keys across schemas

90 relationships (audit-column references excluded).

| From | Column | To |
|:--|:--|:--|
| `audit.audit_event` | `actor_user_account_id` | `core.user_account` |
| `audit.audit_event` | `impersonator_user_account_id` | `core.user_account` |
| `audit.audit_event` | `organization_id` | `recruitment.organization` |
| `audit.system_error_log` | `user_account_id` | `core.user_account` |
| `commercial.candidate_profile_download_history` | `downloader_user_account_id` | `core.user_account` |
| `commercial.candidate_profile_download_history` | `candidate_profile_id` | `profile.candidate_profile` |
| `commercial.candidate_profile_download_history` | `organization_id` | `recruitment.organization` |
| `commercial.invoice` | `organization_id` | `recruitment.organization` |
| `commercial.licence_seat_allocation` | `allocated_by_user_account_id` | `core.user_account` |
| `commercial.licence_seat_allocation` | `user_account_id` | `core.user_account` |
| `commercial.payment_order` | `user_account_id` | `core.user_account` |
| `commercial.payment_order` | `organization_id` | `recruitment.organization` |
| `commercial.subscription_licence` | `organization_id` | `recruitment.organization` |
| `commercial.wallet` | `organization_id` | `recruitment.organization` |
| `core.user_block` | `blocked_organization_id` | `recruitment.organization` |
| `gig.gig_rating` | `rater_user_account_id` | `core.user_account` |
| `gig.gig_request` | `organization_id` | `recruitment.organization` |
| `gig.gig_worker_preference` | `organization_id` | `recruitment.organization` |
| `gig.gig_worker_profile` | `user_account_id` | `core.user_account` |
| `gig.gig_worker_service` | `skill_id` | `master.skill` |
| `messaging.community_post` | `author_user_account_id` | `core.user_account` |
| `messaging.community_post` | `content_language_code` | `master.language` |
| `messaging.job_alert_preference` | `user_account_id` | `core.user_account` |
| `messaging.job_alert_preference` | `city_id` | `master.city` |
| `messaging.job_alert_preference` | `job_role_id` | `master.job_role` |
| `messaging.job_alert_preference` | `work_type_id` | `master.work_type` |
| `messaging.notification_delivery` | `recipient_user_account_id` | `core.user_account` |
| `messaging.post_reaction` | `user_account_id` | `core.user_account` |
| `messaging.referral_event` | `referred_user_account_id` | `core.user_account` |
| `messaging.referral_event` | `referrer_user_account_id` | `core.user_account` |
| `messaging.share_event` | `user_account_id` | `core.user_account` |
| `messaging.share_event` | `job_posting_id` | `recruitment.job_posting` |
| `messaging.support_ticket` | `assigned_agent_user_id` | `core.user_account` |
| `messaging.support_ticket` | `requester_user_account_id` | `core.user_account` |
| `messaging.ui_translation` | `language_code` | `master.language` |
| `messaging.user_notification_preference` | `user_account_id` | `core.user_account` |
| `messaging.user_privacy_preference` | `user_account_id` | `core.user_account` |
| `profile.candidate_activity_log` | `user_account_id` | `core.user_account` |
| `profile.candidate_assessment` | `skill_id` | `master.skill` |
| `profile.candidate_education` | `qualification_id` | `master.qualification` |
| `profile.candidate_language` | `language_id` | `master.language` |
| `profile.candidate_location` | `city_id` | `master.city` |
| `profile.candidate_profile` | `user_account_id` | `core.user_account` |
| `profile.candidate_profile` | `summary_language_code` | `master.language` |
| `profile.candidate_skill` | `skill_id` | `master.skill` |
| `profile.candidate_work_experience` | `department_id` | `master.department` |
| `profile.candidate_work_experience` | `employment_type_id` | `master.employment_type` |
| `profile.candidate_work_experience` | `job_role_id` | `master.job_role` |
| `profile.profile_view_history` | `viewer_user_account_id` | `core.user_account` |
| `profile.profile_view_history` | `organization_id` | `recruitment.organization` |
| `profile.recruiter_bookmark` | `user_account_id` | `core.user_account` |
| `profile.recruiter_bookmark` | `organization_id` | `recruitment.organization` |
| `profile.recruiter_search` | `user_account_id` | `core.user_account` |
| `profile.recruiter_search` | `organization_id` | `recruitment.organization` |
| `recruitment.application_status_history` | `changed_by_user_account_id` | `core.user_account` |
| `recruitment.candidate_application` | `assigned_recruiter_user_account_id` | `core.user_account` |
| `recruitment.candidate_application` | `candidate_document_id` | `profile.candidate_document` |
| `recruitment.candidate_application` | `candidate_profile_id` | `profile.candidate_profile` |
| `recruitment.job_position` | `filled_by_candidate_profile_id` | `profile.candidate_profile` |
| `recruitment.job_posting` | `city_id` | `master.city` |
| `recruitment.job_posting` | `department_id` | `master.department` |
| `recruitment.job_posting` | `employment_type_id` | `master.employment_type` |
| `recruitment.job_posting` | `industry_id` | `master.industry` |
| `recruitment.job_posting` | `job_role_id` | `master.job_role` |
| `recruitment.job_posting` | `description_language_code` | `master.language` |
| `recruitment.job_posting` | `work_type_id` | `master.work_type` |
| `recruitment.job_posting_location` | `city_id` | `master.city` |
| `recruitment.job_posting_perk` | `job_perk_id` | `master.job_perk` |
| `recruitment.job_qualification_requirement` | `qualification_id` | `master.qualification` |
| `recruitment.job_recruiter_assignment` | `assigned_by_user_account_id` | `core.user_account` |
| `recruitment.job_recruiter_assignment` | `recruiter_user_account_id` | `core.user_account` |
| `recruitment.job_skill_requirement` | `skill_id` | `master.skill` |
| `recruitment.organization` | `country_id` | `master.country` |
| `recruitment.organization_identifier` | `verified_by_user_account_id` | `core.user_account` |
| `recruitment.organization_identifier` | `country_id` | `master.country` |
| `recruitment.organization_location` | `city_id` | `master.city` |
| `recruitment.organization_member` | `invited_by_user_account_id` | `core.user_account` |
| `recruitment.organization_member` | `user_account_id` | `core.user_account` |
| `recruitment.recruiter_client_mapping` | `recruiter_user_account_id` | `core.user_account` |
| `sourcing.consultant_sourcing_request` | `consultant_user_account_id` | `core.user_account` |
| `sourcing.consultant_sourcing_request` | `decided_by_user_account_id` | `core.user_account` |
| `sourcing.consultant_sourcing_request` | `job_posting_id` | `recruitment.job_posting` |
| `sourcing.job_consultant_policy` | `job_posting_id` | `recruitment.job_posting` |
| `sourcing.outreach_batch` | `job_posting_id` | `recruitment.job_posting` |
| `sourcing.outreach_batch` | `organization_id` | `recruitment.organization` |
| `sourcing.outreach_recipient` | `candidate_profile_id` | `profile.candidate_profile` |
| `sourcing.sourcing_submission` | `submitted_by_user_account_id` | `core.user_account` |
| `sourcing.sourcing_submission` | `candidate_profile_id` | `profile.candidate_profile` |
| `sourcing.sourcing_submission` | `candidate_application_id` | `recruitment.candidate_application` |
| `sourcing.sourcing_submission` | `job_posting_id` | `recruitment.job_posting` |
