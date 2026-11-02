BEGIN;
-- =============================================================================
-- Migration 032: Decisions the earlier migrations left open
-- Domain:        model governance (playbook steps 08, 11, 12; docket Rule Groups 4 and 6)
-- Depends on:    001-031
--
-- 1. Every status column is either a governed state machine or a recorded exemption (decisions DEC-20 to DEC-22).
-- 2. Retention periods are approved by delegated decision, except erasure of dormant accounts (DEC-23).
-- 3. The column classification was reviewed by hand and corrected (DEC-24).
--
-- "Delegated" means: the project owner told the assistant to take these decisions (chat, 2026-10-28). It is a recorded decision
-- with a reason, not an external business approval; docs/lifecycle/decision-log.md carries the reasoning.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Status machines
-- -----------------------------------------------------------------------------
CREATE TABLE master.status_machine_exemption (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    entity_code   VARCHAR(60) NOT NULL,
    column_name   VARCHAR(63) NOT NULL,
    exemption     VARCHAR(20) NOT NULL,
    reason        VARCHAR(400) NOT NULL,

    CONSTRAINT uq_status_machine_exemption UNIQUE (entity_code, column_name),
    CONSTRAINT ck_status_machine_exemption_kind CHECK (exemption IN ('external_driver', 'append_only_history')),
    CONSTRAINT ck_status_machine_exemption_reason CHECK (length(btrim(reason)) >= 20)
);
COMMENT ON TABLE master.status_machine_exemption IS 'Status columns deliberately left without transition rules, with the reason. tests/test_state_machines.sql fails for any status column that is neither governed nor listed here.';
SELECT audit.apply_standard_lifecycle('master', 'status_machine_exemption', 'reference');

INSERT INTO master.status_machine_exemption (entity_code, column_name, exemption, reason) VALUES
 ('messaging.notification_delivery', 'delivery_status', 'external_driver',
  'Written from provider callbacks that arrive out of order (a "delivered" can precede "sent"). Rejecting a legitimate late callback would lose the truth; ordering is resolved by the provider timestamp in the application.'),
 ('sourcing.outreach_recipient', 'delivery_status', 'external_driver',
  'Same as notification delivery: set from provider callbacks and recipient replies, which are not ordered.'),
 ('recruitment.application_status_history', 'new_status', 'append_only_history',
  'A history row records a move that the application table has already validated; the history itself is append-only.'),
 ('recruitment.application_status_history', 'previous_status', 'append_only_history',
  'As new_status: it records the state left, and the history cannot be updated.'),
 ('audit.maintenance_run', 'run_status', 'append_only_history',
  'One row is written when a job finishes; the status is its outcome, not a state that changes.');

INSERT INTO master.status_transition (entity_code, from_status, to_status) VALUES
 -- licence: expired and cancelled are final; a renewal is a new licence
 ('commercial.subscription_licence', 'active', 'suspended'), ('commercial.subscription_licence', 'active', 'expired'), ('commercial.subscription_licence', 'active', 'cancelled'),
 ('commercial.subscription_licence', 'suspended', 'active'), ('commercial.subscription_licence', 'suspended', 'expired'), ('commercial.subscription_licence', 'suspended', 'cancelled'),
 -- gig worker verification
 ('gig.gig_worker_profile', 'unverified', 'verified'), ('gig.gig_worker_profile', 'unverified', 'suspended'),
 ('gig.gig_worker_profile', 'verified', 'suspended'), ('gig.gig_worker_profile', 'suspended', 'verified'),
 -- referral: strictly forward
 ('messaging.referral_event', 'invited', 'registered'), ('messaging.referral_event', 'registered', 'qualified_hire'), ('messaging.referral_event', 'qualified_hire', 'reward_paid'),
 -- candidate document: scanned before it can be used; anything can be archived (erasure archives every document)
 ('profile.candidate_document', 'uploaded', 'scanning'), ('profile.candidate_document', 'uploaded', 'rejected'), ('profile.candidate_document', 'uploaded', 'archived'),
 ('profile.candidate_document', 'scanning', 'ready'), ('profile.candidate_document', 'scanning', 'rejected'), ('profile.candidate_document', 'scanning', 'archived'),
 ('profile.candidate_document', 'ready', 'archived'), ('profile.candidate_document', 'rejected', 'archived'),
 -- candidate profile
 ('profile.candidate_profile', 'draft', 'active'), ('profile.candidate_profile', 'active', 'paused'), ('profile.candidate_profile', 'paused', 'active'),
 -- course enrolment: a short self-paced course can be completed in one step; a dropped candidate may enrol again; completed is final
 ('profile.course_enrolment', 'enrolled', 'in_progress'), ('profile.course_enrolment', 'enrolled', 'completed'), ('profile.course_enrolment', 'enrolled', 'dropped'),
 ('profile.course_enrolment', 'in_progress', 'completed'), ('profile.course_enrolment', 'in_progress', 'dropped'), ('profile.course_enrolment', 'dropped', 'enrolled'),
 -- vacancy position: an offer can be declined, which reopens the position
 ('recruitment.job_position', 'open', 'offered'), ('recruitment.job_position', 'open', 'filled'), ('recruitment.job_position', 'open', 'cancelled'),
 ('recruitment.job_position', 'offered', 'open'), ('recruitment.job_position', 'offered', 'filled'), ('recruitment.job_position', 'offered', 'cancelled'),
 -- organisation registration identifier verification; a changed identifier must be verified again
 ('recruitment.organization_identifier', 'unverified', 'pending'), ('recruitment.organization_identifier', 'unverified', 'verified'), ('recruitment.organization_identifier', 'unverified', 'rejected'),
 ('recruitment.organization_identifier', 'pending', 'verified'), ('recruitment.organization_identifier', 'pending', 'rejected'),
 ('recruitment.organization_identifier', 'rejected', 'pending'), ('recruitment.organization_identifier', 'verified', 'pending'),
 -- organisation membership: removed is final
 ('recruitment.organization_member', 'invited', 'active'), ('recruitment.organization_member', 'invited', 'removed'),
 ('recruitment.organization_member', 'active', 'suspended'), ('recruitment.organization_member', 'active', 'removed'),
 ('recruitment.organization_member', 'suspended', 'active'), ('recruitment.organization_member', 'suspended', 'removed'),
 -- outreach campaign
 ('sourcing.outreach_batch', 'draft', 'queued'), ('sourcing.outreach_batch', 'draft', 'cancelled'), ('sourcing.outreach_batch', 'queued', 'processing'),
 ('sourcing.outreach_batch', 'queued', 'cancelled'), ('sourcing.outreach_batch', 'processing', 'completed'), ('sourcing.outreach_batch', 'processing', 'cancelled'),
 -- consultant submission: accepted candidates may still fall through before they are hired
 ('sourcing.sourcing_submission', 'submitted', 'shortlisted'), ('sourcing.sourcing_submission', 'submitted', 'rejected'),
 ('sourcing.sourcing_submission', 'shortlisted', 'accepted'), ('sourcing.sourcing_submission', 'shortlisted', 'rejected'),
 ('sourcing.sourcing_submission', 'accepted', 'hired'), ('sourcing.sourcing_submission', 'accepted', 'rejected');

DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT * FROM (VALUES
        ('commercial', 'subscription_licence', 'licence_status'), ('gig', 'gig_worker_profile', 'verification_status'),
        ('messaging', 'referral_event', 'status'), ('profile', 'candidate_document', 'document_status'),
        ('profile', 'candidate_profile', 'profile_status'), ('profile', 'course_enrolment', 'enrolment_status'),
        ('recruitment', 'job_position', 'position_status'), ('recruitment', 'organization_identifier', 'verification_status'),
        ('recruitment', 'organization_member', 'membership_status'), ('sourcing', 'outreach_batch', 'status'),
        ('sourcing', 'sourcing_submission', 'submission_status')
    ) AS t (s, t, c)
    LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE OF %I ON %I.%I FOR EACH ROW WHEN (OLD.%I IS DISTINCT FROM NEW.%I) EXECUTE FUNCTION master.enforce_status_transition(%L, %L)',
            'trg_' || r.t || '_status_transition', r.c, r.s, r.t, r.c, r.c, r.s || '.' || r.t, r.c);
    END LOOP;
END;
$$;

-- -----------------------------------------------------------------------------
-- 2. Retention approvals (DEC-23)
--    Approved: ephemeral and operational data (sessions, devices, notifications, search history, outreach receipts, integration events)
--    and the periods for every other table, which are only applied by account erasure or are never purged.
--    NOT approved: erasing dormant accounts. It is irreversible and rests on a 24-month figure the assistant chose; a person
--    enables it by setting retention_approved_by on core.user_account.
-- -----------------------------------------------------------------------------
UPDATE audit.entity_lifecycle_policy SET retention_days = 730, retention_basis = 'Proposed: personal content tied to a person, 24 months after last activity'
 WHERE (schema_name, table_name) IN (('gig', 'gig_worker_preference'), ('gig', 'gig_worker_service'), ('messaging', 'job_alert_preference'), ('recruitment', 'application_question_response'));
UPDATE audit.entity_lifecycle_policy SET retention_days = 1095, retention_basis = 'Proposed: user-written community posts, 3 years'
 WHERE schema_name = 'messaging' AND table_name = 'community_post';
UPDATE audit.entity_lifecycle_policy SET retention_days = 365, retention_basis = 'Proposed: error context can carry personal data, 12 months; the log is append-only and is trimmed by archiving, not by the purge job'
 WHERE schema_name = 'audit' AND table_name = 'system_error_log';

UPDATE audit.entity_lifecycle_policy
   SET is_retention_approved = TRUE,
       retention_approved_by = 'Delegated decision DEC-23, 2026-10-28 (project owner delegated approvals to the assistant)'
 WHERE retention_days IS NOT NULL
   AND NOT (schema_name = 'core' AND table_name = 'user_account');
COMMENT ON COLUMN audit.entity_lifecycle_policy.is_retention_approved IS 'TRUE once approved. The periods were approved by delegated decision (DEC-23); core.user_account stays FALSE on purpose, so dormant accounts are not erased automatically until a person enables it.';

-- -----------------------------------------------------------------------------
-- 3. Classification, reviewed (DEC-24)
--    Rule used: a column is Personal when its CONTENT describes a person. Keys, audit stamps and system flags are Internal;
--    the linkage they create is protected at table level by row-level security.
-- -----------------------------------------------------------------------------
-- keys and audit stamps are internal everywhere outside the public reference data
UPDATE audit.column_classification SET data_class = 'internal', protection = 'grants_only'
 WHERE data_class = 'personal'
   AND (column_name = 'id' OR column_name ~ '^(created|updated|deleted)_(at|by_user_account_id)$'
        OR column_name IN ('skill_id', 'qualification_id', 'language_id', 'city_id', 'course_id', 'job_role_id', 'employment_type_id', 'candidate_assessment_id',
                           'resume_template_id', 'organization_id', 'candidate_profile_id', 'user_account_id', 'viewer_user_account_id'));
-- the assessment table is a catalogue of tests, not a record about a person
UPDATE audit.column_classification SET data_class = 'internal', protection = 'grants_only' WHERE schema_name = 'profile' AND table_name = 'candidate_assessment';
-- system facts about a document, an activity or a profile
UPDATE audit.column_classification SET data_class = 'internal', protection = 'grants_only'
 WHERE data_class = 'personal' AND (
       (table_name = 'candidate_document' AND column_name IN ('document_status', 'document_type', 'checksum_sha256', 'mime_type', 'file_size_bytes', 'storage_provider', 'is_primary', 'processed_at', 'archived_at'))
    OR (table_name = 'candidate_activity_log' AND column_name IN ('activity_type', 'occurred_at'))
    OR (table_name = 'candidate_search_history' AND column_name IN ('result_count', 'searched_at'))
    OR (table_name = 'candidate_profile_completion')
    OR (table_name = 'candidate_profile' AND column_name IN ('profile_status', 'summary_language_code'))
    OR (table_name = 'user_account' AND column_name IN ('preferred_language', 'email_verified_at', 'phone_country_code'))
    OR (table_name = 'profile_view_history' AND column_name IN ('credit_deducted', 'view_source')));
-- content that describes a person but was classified Internal by name
UPDATE audit.column_classification SET data_class = 'personal'
 WHERE (schema_name, table_name, column_name) IN (
       ('gig', 'gig_worker_profile', 'bio'), ('gig', 'gig_worker_profile', 'hourly_rate'), ('gig', 'gig_worker_profile', 'daily_rate'),
       ('gig', 'gig_worker_service', 'custom_title'), ('gig', 'gig_worker_preference', 'reason'),
       ('gig', 'gig_application', 'bid_amount'),
       ('messaging', 'community_post', 'title'), ('messaging', 'community_post', 'content'), ('messaging', 'job_alert_preference', 'keywords'),
       ('recruitment', 'application_question_response', 'response_text'), ('recruitment', 'application_question_response', 'numeric_response'),
       ('recruitment', 'application_question_response', 'boolean_response'), ('recruitment', 'application_question_response', 'selected_options_json'),
       ('sourcing', 'consultant_sourcing_request', 'decision_reason'), ('audit', 'system_error_log', 'context_json'));
-- reference configuration is not public data
UPDATE audit.column_classification SET data_class = 'internal' WHERE schema_name = 'master' AND table_name IN ('status_transition', 'status_machine_exemption');
-- re-derive protection now that classes have moved, then record the review
SELECT audit.refresh_protection();
UPDATE audit.column_classification
   SET basis = 'reviewed',
       note = COALESCE(note, 'Reviewed 2026-10-28 by delegated decision DEC-24: class set by what the column''s content describes.')
 WHERE basis = 'pattern';

SELECT audit.sync_column_classification();
COMMIT;
