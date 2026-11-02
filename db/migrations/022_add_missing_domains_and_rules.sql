-- =============================================================================
-- Migration 022: Missing Tier 2 domains, append-only history, state-transition rules
-- Domain:        profile, master (docket section 4 Tier 2; Rule Group 10; GAP-06, GAP-09, GAP-12, GAP-13)
-- Depends on:    001-021
--
--   1. Append-only guard for view history and the other history tables that lacked one
--      (docket Rule Group 10: "Download and view history records are append-only").
--   2. New tables: candidate activity log, candidate search history, course and enrolment,
--      resume template.
--   3. Rule: recruiters (and any non-owner, non-admin) cannot register a candidate profile.
--   4. State machines: legal transitions held in master.status_transition and enforced by
--      one trigger function on the 12 stateful entities.
--
-- Enumerations in the new tables are CHECK lists, not lookup tables. That departs from Rule Group 3
-- ("a fixed set of values is held in a lookup table"); the departure and its reason are recorded in
-- docs/phase-2-model/11-rule-compliance.md. The reason: values here drive behaviour (a trigger or a
-- query branches on them), so changing one is a code change that belongs in a migration.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0. Reusable helpers
-- -----------------------------------------------------------------------------
BEGIN;

CREATE FUNCTION audit.prevent_modification()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'Table %.% is append-only: % is not permitted', TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_OP
        USING ERRCODE = 'restrict_violation';
END;
$$;

-- Registers a table in the lifecycle policy and, unless it is append-only or derived, gives it the
-- standard audit columns and trigger. Every new migration that creates a table calls this once, and
-- tests/test_lifecycle.sql fails if it forgets to.
CREATE FUNCTION audit.apply_standard_lifecycle(p_schema TEXT, p_table TEXT, p_delete_mode TEXT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_delete_mode IN ('soft', 'hard', 'reference') THEN
        EXECUTE format('ALTER TABLE %I.%I ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP', p_schema, p_table);
        EXECUTE format('ALTER TABLE %I.%I ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP', p_schema, p_table);
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = p_schema AND table_name = p_table AND column_name = 'created_by_user_account_id') THEN
            EXECUTE format('ALTER TABLE %I.%I ADD COLUMN created_by_user_account_id BIGINT', p_schema, p_table);
            EXECUTE format('ALTER TABLE %I.%I ADD CONSTRAINT %I FOREIGN KEY (created_by_user_account_id) REFERENCES core.user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT', p_schema, p_table, 'fk_' || p_table || '_created_by');
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = p_schema AND table_name = p_table AND column_name = 'updated_by_user_account_id') THEN
            EXECUTE format('ALTER TABLE %I.%I ADD COLUMN updated_by_user_account_id BIGINT', p_schema, p_table);
            EXECUTE format('ALTER TABLE %I.%I ADD CONSTRAINT %I FOREIGN KEY (updated_by_user_account_id) REFERENCES core.user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT', p_schema, p_table, 'fk_' || p_table || '_updated_by');
        END IF;
        EXECUTE format('CREATE TRIGGER %I BEFORE INSERT OR UPDATE ON %I.%I FOR EACH ROW EXECUTE FUNCTION core.maintain_audit_columns()',
                       'trg_' || p_table || '_audit_columns', p_schema, p_table);
    END IF;
    IF p_delete_mode = 'append_only' THEN
        EXECUTE format('CREATE TRIGGER %I BEFORE UPDATE OR DELETE ON %I.%I FOR EACH ROW EXECUTE FUNCTION audit.prevent_modification()',
                       'trg_' || p_table || '_append_only', p_schema, p_table);
        EXECUTE format('CREATE TRIGGER %I BEFORE TRUNCATE ON %I.%I FOR EACH STATEMENT EXECUTE FUNCTION audit.prevent_truncate()',
                       'trg_' || p_table || '_block_truncate', p_schema, p_table);
        EXECUTE format('REVOKE UPDATE, DELETE, TRUNCATE ON %I.%I FROM talentra_app', p_schema, p_table);
    END IF;
    INSERT INTO audit.entity_lifecycle_policy (schema_name, table_name, delete_mode)
    VALUES (p_schema, p_table, p_delete_mode)
    ON CONFLICT (schema_name, table_name) DO NOTHING;
END;
$$;

-- -----------------------------------------------------------------------------
-- 1. Append-only guard where it was missing
--    (wallet_ledger, audit_event and download history already have one)
-- -----------------------------------------------------------------------------
CREATE TRIGGER trg_profile_view_history_append_only
    BEFORE UPDATE OR DELETE ON profile.profile_view_history
    FOR EACH ROW EXECUTE FUNCTION audit.prevent_modification();
CREATE TRIGGER trg_application_status_history_append_only
    BEFORE UPDATE OR DELETE ON recruitment.application_status_history
    FOR EACH ROW EXECUTE FUNCTION audit.prevent_modification();
CREATE TRIGGER trg_system_error_log_append_only
    BEFORE UPDATE OR DELETE ON audit.system_error_log
    FOR EACH ROW EXECUTE FUNCTION audit.prevent_modification();

-- -----------------------------------------------------------------------------
-- 2. New tables
-- -----------------------------------------------------------------------------

-- 2.1 Candidate activity log (docket Tier 2: login, profile update, resume download) ------ GAP-13
CREATE TABLE profile.candidate_activity_log (
    id                     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_account_id        BIGINT       NOT NULL,
    candidate_profile_id   BIGINT,
    activity_type          VARCHAR(30)  NOT NULL,
    detail_json            JSONB,
    client_ip              VARCHAR(45),
    occurred_at            TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_candidate_activity_log_user_account
        FOREIGN KEY (user_account_id) REFERENCES core.user_account (id)
        ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_candidate_activity_log_candidate_profile
        FOREIGN KEY (candidate_profile_id) REFERENCES profile.candidate_profile (id)
        ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT ck_candidate_activity_log_type
        CHECK (activity_type IN ('login', 'logout', 'profile_update', 'resume_upload',
                                 'resume_download', 'password_change', 'consent_change'))
);
COMMENT ON TABLE profile.candidate_activity_log IS
    'What a candidate did and when (login, profile update, resume download). Append-only. Distinct from audit.audit_event, which records sensitive actions by anyone.';
COMMENT ON COLUMN profile.candidate_activity_log.candidate_profile_id IS
    'Nullable: login and password change happen before or without a profile.';
COMMENT ON COLUMN profile.candidate_activity_log.detail_json IS
    'Nullable: only some activities carry detail (for example which document was downloaded).';
COMMENT ON COLUMN profile.candidate_activity_log.client_ip IS
    'Nullable: not available for system-initiated events. Personal data.';
CREATE INDEX idx_candidate_activity_log_user_occurred
    ON profile.candidate_activity_log (user_account_id, occurred_at DESC);
SELECT audit.apply_standard_lifecycle('profile', 'candidate_activity_log', 'append_only');
UPDATE audit.entity_lifecycle_policy
   SET retention_days = 365, retention_basis = 'Proposed: candidate activity log, 12 months'
 WHERE (schema_name, table_name) = ('profile', 'candidate_activity_log');

-- 2.2 Candidate search history (docket Tier 2: job search history) ------------------------ GAP-12
CREATE TABLE profile.candidate_search_history (
    id                     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    candidate_profile_id   BIGINT       NOT NULL,
    query_text             VARCHAR(500),
    filters_json           JSONB,
    result_count           INTEGER      NOT NULL,
    searched_at            TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_candidate_search_history_candidate_profile
        FOREIGN KEY (candidate_profile_id) REFERENCES profile.candidate_profile (id)
        ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT ck_candidate_search_history_result_count CHECK (result_count >= 0),
    -- a search is either text, filters, or both; an empty one carries no information
    CONSTRAINT ck_candidate_search_history_not_empty
        CHECK (query_text IS NOT NULL OR filters_json IS NOT NULL)
);
COMMENT ON TABLE profile.candidate_search_history IS
    'A candidate''s job searches, for "recent searches" and alert suggestions. Hard-deleted on request or after retention.';
COMMENT ON COLUMN profile.candidate_search_history.query_text IS 'Nullable: a search can be filters only.';
COMMENT ON COLUMN profile.candidate_search_history.filters_json IS 'Nullable: a search can be text only.';
CREATE INDEX idx_candidate_search_history_profile_searched
    ON profile.candidate_search_history (candidate_profile_id, searched_at DESC);
SELECT audit.apply_standard_lifecycle('profile', 'candidate_search_history', 'hard');
UPDATE audit.entity_lifecycle_policy
   SET retention_days = 90, retention_basis = 'Proposed: search history, 90 days'
 WHERE (schema_name, table_name) = ('profile', 'candidate_search_history');

-- 2.3 Courses and enrolments (docket Tier 2: course enrolments) --------------------------- GAP-09
CREATE TABLE profile.course (
    id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code             VARCHAR(40)  NOT NULL,
    title            VARCHAR(200) NOT NULL,
    provider_name    VARCHAR(200),
    duration_hours   NUMERIC(6,1),
    language_code    VARCHAR(10),
    is_active        BOOLEAN      NOT NULL DEFAULT TRUE,

    CONSTRAINT uq_course_code UNIQUE (code),
    CONSTRAINT ck_course_code CHECK (code = lower(code) AND length(btrim(code)) >= 2),
    CONSTRAINT ck_course_title CHECK (length(btrim(title)) >= 1),
    CONSTRAINT ck_course_duration CHECK (duration_hours IS NULL OR duration_hours > 0)
);
COMMENT ON TABLE profile.course IS 'Course catalogue candidates can enrol in. Content lives with the provider; only the reference is stored.';
COMMENT ON COLUMN profile.course.provider_name IS 'Nullable: in-house courses have no external provider.';
COMMENT ON COLUMN profile.course.duration_hours IS 'Nullable: self-paced courses have no fixed duration. NULL means unknown, not zero.';
COMMENT ON COLUMN profile.course.language_code IS 'Nullable: language of instruction when known.';
SELECT audit.apply_standard_lifecycle('profile', 'course', 'hard');

CREATE TABLE profile.course_enrolment (
    id                      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    candidate_profile_id    BIGINT       NOT NULL,
    course_id               BIGINT       NOT NULL,
    enrolment_status        VARCHAR(20)  NOT NULL DEFAULT 'enrolled',
    enrolled_at             TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at            TIMESTAMPTZ,
    score_percent           NUMERIC(5,2),
    certificate_reference   VARCHAR(200),

    CONSTRAINT fk_course_enrolment_candidate_profile
        FOREIGN KEY (candidate_profile_id) REFERENCES profile.candidate_profile (id)
        ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_course_enrolment_course
        FOREIGN KEY (course_id) REFERENCES profile.course (id)
        ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_course_enrolment_candidate_course UNIQUE (candidate_profile_id, course_id),
    CONSTRAINT ck_course_enrolment_status
        CHECK (enrolment_status IN ('enrolled', 'in_progress', 'completed', 'dropped')),
    CONSTRAINT ck_course_enrolment_completed_at
        CHECK ((enrolment_status = 'completed') = (completed_at IS NOT NULL)),
    CONSTRAINT ck_course_enrolment_dates CHECK (completed_at IS NULL OR completed_at >= enrolled_at),
    CONSTRAINT ck_course_enrolment_score CHECK (score_percent IS NULL OR (score_percent >= 0 AND score_percent <= 100))
);
COMMENT ON TABLE profile.course_enrolment IS 'A candidate''s enrolment in a course, with outcome.';
COMMENT ON COLUMN profile.course_enrolment.completed_at IS 'Set if and only if the status is completed.';
COMMENT ON COLUMN profile.course_enrolment.score_percent IS 'Nullable: not every course is scored. NULL is not zero.';
COMMENT ON COLUMN profile.course_enrolment.certificate_reference IS 'Nullable: reference at the provider; never the certificate itself.';
CREATE INDEX idx_course_enrolment_course ON profile.course_enrolment (course_id);
SELECT audit.apply_standard_lifecycle('profile', 'course_enrolment', 'hard');
UPDATE audit.entity_lifecycle_policy
   SET retention_days = 730, retention_basis = 'Proposed: candidate personal data, erase after 24 months of account inactivity'
 WHERE (schema_name, table_name) = ('profile', 'course_enrolment');

-- 2.4 Resume templates (docket Tier 2: resume versions and templates) ------------------------
CREATE TABLE profile.resume_template (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code           VARCHAR(40)  NOT NULL,
    name           VARCHAR(100) NOT NULL,
    description    VARCHAR(500),
    is_active      BOOLEAN      NOT NULL DEFAULT TRUE,
    sort_order     INTEGER      NOT NULL DEFAULT 0,

    CONSTRAINT uq_resume_template_code UNIQUE (code),
    CONSTRAINT ck_resume_template_code CHECK (code = lower(code) AND length(btrim(code)) >= 2)
);
COMMENT ON TABLE profile.resume_template IS 'Layouts a candidate can build a resume from. Display names per UI language live in messaging.ui_translation under key resume_template.<code>.';
COMMENT ON COLUMN profile.resume_template.description IS 'Nullable: optional help text.';
SELECT audit.apply_standard_lifecycle('profile', 'resume_template', 'reference');

-- reference data is read-only for the application (same rule as the master schema, BR-005)
REVOKE INSERT, UPDATE, DELETE ON profile.resume_template FROM talentra_app;

INSERT INTO profile.resume_template (code, name, sort_order) VALUES
    ('classic', 'Classic', 10),
    ('modern', 'Modern', 20),
    ('compact', 'Compact', 30);

ALTER TABLE profile.candidate_document
    ADD COLUMN resume_template_id BIGINT,
    ADD CONSTRAINT fk_candidate_document_resume_template
        FOREIGN KEY (resume_template_id) REFERENCES profile.resume_template (id)
        ON UPDATE RESTRICT ON DELETE RESTRICT,
    ADD CONSTRAINT ck_candidate_document_template_only_resume
        CHECK (resume_template_id IS NULL OR document_type = 'resume');
COMMENT ON COLUMN profile.candidate_document.resume_template_id IS
    'Nullable: set only for resumes built from a template; uploaded files have none. Version history of resumes is the set of resume rows by uploaded_at.';

-- Personal tables get row-level security: the owner (or an admin) only
ALTER TABLE profile.candidate_activity_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY activity_log_read ON profile.candidate_activity_log FOR SELECT TO talentra_app
    USING (user_account_id = core.current_app_user_id() OR core.is_platform_admin());
CREATE POLICY activity_log_append ON profile.candidate_activity_log FOR INSERT TO talentra_app
    WITH CHECK (user_account_id = core.current_app_user_id() OR core.is_platform_admin());
ALTER TABLE profile.candidate_search_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY search_history_owner ON profile.candidate_search_history FOR ALL TO talentra_app
    USING (core.owns_candidate_profile(candidate_profile_id) OR core.is_platform_admin())
    WITH CHECK (core.owns_candidate_profile(candidate_profile_id) OR core.is_platform_admin());
ALTER TABLE profile.course_enrolment ENABLE ROW LEVEL SECURITY;
CREATE POLICY course_enrolment_owner ON profile.course_enrolment FOR ALL TO talentra_app
    USING (core.owns_candidate_profile(candidate_profile_id) OR core.is_platform_admin())
    WITH CHECK (core.owns_candidate_profile(candidate_profile_id) OR core.is_platform_admin());

-- -----------------------------------------------------------------------------
-- 3. Recruiters cannot register candidates (docket section 3) ------------------------------- GAP-06
--    A candidate profile may be created by its owner, or by a platform admin (support/import).
--    created_by comes from app.current_user_id when the application does not name it.
-- -----------------------------------------------------------------------------
CREATE FUNCTION profile.enforce_self_registration()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_actor BIGINT := COALESCE(NEW.created_by_user_account_id, core.current_app_user_id());
BEGIN
    IF v_actor IS NOT NULL
       AND v_actor <> NEW.user_account_id
       AND NOT EXISTS (SELECT 1 FROM core.user_role ur JOIN core.role r ON r.id = ur.role_id
                        WHERE ur.user_account_id = v_actor AND r.name IN ('super_admin', 'admin')) THEN
        RAISE EXCEPTION 'User % cannot create a candidate profile for user %: candidates register themselves',
            v_actor, NEW.user_account_id
            USING ERRCODE = 'insufficient_privilege';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_candidate_profile_self_registration
    BEFORE INSERT ON profile.candidate_profile
    FOR EACH ROW EXECUTE FUNCTION profile.enforce_self_registration();

-- -----------------------------------------------------------------------------
-- 4. State machines: legal transitions as data, enforced by one trigger function
-- -----------------------------------------------------------------------------
CREATE TABLE master.status_transition (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    entity_code   VARCHAR(60) NOT NULL,
    from_status   VARCHAR(30) NOT NULL,
    to_status     VARCHAR(30) NOT NULL,

    CONSTRAINT uq_status_transition UNIQUE (entity_code, from_status, to_status),
    CONSTRAINT ck_status_transition_distinct CHECK (from_status <> to_status)
);
COMMENT ON TABLE master.status_transition IS
    'Allowed moves of a status column. A status with no outgoing row is final. An update to a pair not listed here is rejected by enforce_status_transition.';
SELECT audit.apply_standard_lifecycle('master', 'status_transition', 'reference');

INSERT INTO master.status_transition (entity_code, from_status, to_status) VALUES
 -- candidate application pipeline (joined, rejected, withdrawn are final)
 ('recruitment.candidate_application', 'applied',     'shortlisted'), ('recruitment.candidate_application', 'applied',     'rejected'),     ('recruitment.candidate_application', 'applied',     'withdrawn'),
 ('recruitment.candidate_application', 'shortlisted', 'interviewed'), ('recruitment.candidate_application', 'shortlisted', 'rejected'),     ('recruitment.candidate_application', 'shortlisted', 'withdrawn'),
 ('recruitment.candidate_application', 'interviewed', 'offered'),     ('recruitment.candidate_application', 'interviewed', 'rejected'),     ('recruitment.candidate_application', 'interviewed', 'withdrawn'),
 ('recruitment.candidate_application', 'offered',     'joined'),      ('recruitment.candidate_application', 'offered',     'rejected'),     ('recruitment.candidate_application', 'offered',     'withdrawn'),
 -- job posting (filled, cancelled are final; a closed job may be reopened)
 ('recruitment.job_posting', 'draft',     'published'), ('recruitment.job_posting', 'draft',     'cancelled'),
 ('recruitment.job_posting', 'published', 'paused'),    ('recruitment.job_posting', 'published', 'closed'),    ('recruitment.job_posting', 'published', 'filled'),    ('recruitment.job_posting', 'published', 'cancelled'),
 ('recruitment.job_posting', 'paused',    'published'), ('recruitment.job_posting', 'paused',    'closed'),    ('recruitment.job_posting', 'paused',    'cancelled'),
 ('recruitment.job_posting', 'closed',    'published'),
 -- organisation
 ('recruitment.organization', 'pending',   'active'),    ('recruitment.organization', 'pending',   'closed'),
 ('recruitment.organization', 'active',    'suspended'), ('recruitment.organization', 'active',    'closed'),
 ('recruitment.organization', 'suspended', 'active'),    ('recruitment.organization', 'suspended', 'closed'),
 -- user account (deactivated is final)
 ('core.user_account', 'pending',   'active'),    ('core.user_account', 'pending',   'deactivated'),
 ('core.user_account', 'active',    'suspended'), ('core.user_account', 'active',    'deactivated'),
 ('core.user_account', 'suspended', 'active'),    ('core.user_account', 'suspended', 'deactivated'),
 -- gig request, application, assignment
 ('gig.gig_request', 'open',        'awarded'),     ('gig.gig_request', 'open',        'cancelled'),
 ('gig.gig_request', 'awarded',     'in_progress'), ('gig.gig_request', 'awarded',     'cancelled'),
 ('gig.gig_request', 'in_progress', 'completed'),   ('gig.gig_request', 'in_progress', 'cancelled'),
 ('gig.gig_application', 'submitted', 'accepted'), ('gig.gig_application', 'submitted', 'rejected'), ('gig.gig_application', 'submitted', 'withdrawn'),
 ('gig.gig_assignment', 'active', 'completed'),    ('gig.gig_assignment', 'active', 'terminated'),
 -- money
 ('commercial.payment_order', 'created',    'authorized'), ('commercial.payment_order', 'created',    'failed'), ('commercial.payment_order', 'created',    'cancelled'),
 ('commercial.payment_order', 'authorized', 'captured'),   ('commercial.payment_order', 'authorized', 'failed'), ('commercial.payment_order', 'authorized', 'cancelled'),
 ('commercial.payment_order', 'captured',   'refunded'),
 ('commercial.invoice', 'draft',  'issued'), ('commercial.invoice', 'draft',  'void'),
 ('commercial.invoice', 'issued', 'paid'),   ('commercial.invoice', 'issued', 'void'), ('commercial.invoice', 'issued', 'uncollectible'),
 ('commercial.subscription', 'active', 'cancelled'), ('commercial.subscription', 'active', 'expired'),
 -- sourcing and support
 ('sourcing.consultant_sourcing_request', 'requested', 'accepted'), ('sourcing.consultant_sourcing_request', 'requested', 'declined'), ('sourcing.consultant_sourcing_request', 'requested', 'revoked'),
 ('sourcing.consultant_sourcing_request', 'accepted',  'revoked'),
 ('messaging.support_ticket', 'open',            'in_progress'), ('messaging.support_ticket', 'open',            'closed'),
 ('messaging.support_ticket', 'in_progress',     'waiting_on_user'), ('messaging.support_ticket', 'in_progress', 'resolved'), ('messaging.support_ticket', 'in_progress', 'closed'),
 ('messaging.support_ticket', 'waiting_on_user', 'in_progress'), ('messaging.support_ticket', 'waiting_on_user', 'resolved'), ('messaging.support_ticket', 'waiting_on_user', 'closed'),
 ('messaging.support_ticket', 'resolved',        'closed'),      ('messaging.support_ticket', 'resolved',        'in_progress');

CREATE FUNCTION master.enforce_status_transition()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_entity  TEXT := TG_ARGV[0];
    v_column  TEXT := TG_ARGV[1];
    v_old     TEXT := to_jsonb(OLD) ->> TG_ARGV[1];
    v_new     TEXT := to_jsonb(NEW) ->> TG_ARGV[1];
BEGIN
    IF v_old IS NOT DISTINCT FROM v_new THEN
        RETURN NEW;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM master.status_transition
                    WHERE entity_code = v_entity AND from_status = v_old AND to_status = v_new) THEN
        RAISE EXCEPTION 'Illegal transition for %.%: % -> %', v_entity, v_column, v_old, v_new
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;

DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT * FROM (VALUES
        ('recruitment', 'candidate_application', 'application_status'),
        ('recruitment', 'job_posting',           'job_status'),
        ('recruitment', 'organization',          'organization_status'),
        ('core',        'user_account',          'account_status'),
        ('gig',         'gig_request',           'request_status'),
        ('gig',         'gig_application',       'application_status'),
        ('gig',         'gig_assignment',        'assignment_status'),
        ('commercial',  'payment_order',         'order_status'),
        ('commercial',  'invoice',               'invoice_status'),
        ('commercial',  'subscription',          'subscription_status'),
        ('sourcing',    'consultant_sourcing_request', 'request_status'),
        ('messaging',   'support_ticket',        'ticket_status')
    ) AS t (s, t, c)
    LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE OF %I ON %I.%I FOR EACH ROW '
            'WHEN (OLD.%I IS DISTINCT FROM NEW.%I) EXECUTE FUNCTION master.enforce_status_transition(%L, %L)',
            'trg_' || r.t || '_status_transition', r.c, r.s, r.t, r.c, r.c, r.s || '.' || r.t, r.c);
    END LOOP;
END;
$$;

COMMIT;
