-- 038: the data structures the nine integration boundaries promise (docket section 6).
--
-- migration 031 recorded, for each boundary, what the database stores. Four of those promises had no table behind them:
--   identity verification  "outcome and a token"            -> core.identity_verification
--   social sharing         "the share event"                -> messaging.share_event
--   company reviews        "figures with source and date"   -> recruitment.company_review_summary
--   geolocation            "coordinates and place reference" -> recruitment.organization_location (two columns)
--   legacy sync            "mapped ids, last sync, conflict log, and a direction and rule for every field"
--                                                          -> messaging.external_reference, legacy_field_mapping, sync_conflict
-- Decision DEC-32 (Delegated, 2026-10-28). The legacy field names are ASSUMED: no legacy system or schema was available.

BEGIN;

-- ---------------------------------------------------------------------------------------------------------------
-- Identity verification: the outcome and an opaque token, never the identity number
-- ---------------------------------------------------------------------------------------------------------------
CREATE TABLE core.identity_verification (
    id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_account_id     BIGINT       NOT NULL REFERENCES core.user_account (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    provider_code       VARCHAR(40)  NOT NULL,
    request_id          VARCHAR(100) NOT NULL,
    verification_status VARCHAR(20)  NOT NULL DEFAULT 'pending',
    provider_token_ref  VARCHAR(200),
    requested_at        TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    verified_at         TIMESTAMPTZ,
    expires_at          TIMESTAMPTZ,

    CONSTRAINT uq_identity_verification_request UNIQUE (provider_code, request_id),
    CONSTRAINT ck_identity_verification_status CHECK (verification_status IN ('pending', 'verified', 'rejected', 'expired')),
    CONSTRAINT ck_identity_verification_provider CHECK (provider_code ~ '^[a-z][a-z0-9_]+$'),
    CONSTRAINT ck_identity_verification_token CHECK (provider_token_ref IS NULL OR length(btrim(provider_token_ref)) >= 8),
    CONSTRAINT ck_identity_verification_verified CHECK (verification_status <> 'verified' OR (verified_at IS NOT NULL AND provider_token_ref IS NOT NULL)),
    CONSTRAINT ck_identity_verification_dates CHECK (expires_at IS NULL OR verified_at IS NULL OR expires_at > verified_at)
);
COMMENT ON TABLE core.identity_verification IS 'Outcome of a national-identity check done by an external service (boundary identity_verification). Stores the outcome and an opaque token; the identity number itself never reaches the database.';
CREATE INDEX idx_identity_verification_user ON core.identity_verification (user_account_id, verification_status);
SELECT audit.apply_standard_lifecycle('core', 'identity_verification', 'hard');

-- ---------------------------------------------------------------------------------------------------------------
-- Social sharing: the fact of a share, not the post
-- ---------------------------------------------------------------------------------------------------------------
CREATE TABLE messaging.share_event (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_account_id BIGINT      NOT NULL REFERENCES core.user_account (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    job_posting_id  BIGINT      NOT NULL REFERENCES recruitment.job_posting (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    channel         VARCHAR(20) NOT NULL,
    shared_at       TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT ck_share_event_channel CHECK (channel IN ('whatsapp', 'linkedin', 'x', 'facebook', 'email', 'copy_link'))
);
COMMENT ON TABLE messaging.share_event IS 'A user shared a job through an outbound link (boundary social_sharing). The external post is never stored.';
CREATE INDEX idx_share_event_job ON messaging.share_event (job_posting_id, shared_at DESC);
CREATE INDEX idx_share_event_user ON messaging.share_event (user_account_id, shared_at DESC);
SELECT audit.apply_standard_lifecycle('messaging', 'share_event', 'hard');

-- ---------------------------------------------------------------------------------------------------------------
-- Company reviews: reference figures with source and refresh date
-- ---------------------------------------------------------------------------------------------------------------
CREATE TABLE recruitment.company_review_summary (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    organization_id BIGINT       NOT NULL REFERENCES recruitment.organization (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    source          VARCHAR(100) NOT NULL,
    rating_average  NUMERIC(3,2),
    review_count    INTEGER      NOT NULL DEFAULT 0,
    salary_median   NUMERIC(14,2),
    currency_code   CHAR(3),
    source_url      VARCHAR(500),
    refreshed_at    TIMESTAMPTZ  NOT NULL,

    CONSTRAINT uq_company_review_summary UNIQUE (organization_id, source),
    CONSTRAINT ck_company_review_rating CHECK (rating_average IS NULL OR (rating_average >= 0 AND rating_average <= 5)),
    CONSTRAINT ck_company_review_count CHECK (review_count >= 0),
    CONSTRAINT ck_company_review_salary CHECK ((salary_median IS NULL) = (currency_code IS NULL) AND (salary_median IS NULL OR salary_median > 0)),
    CONSTRAINT ck_company_review_currency CHECK (currency_code IS NULL OR currency_code ~ '^[A-Z]{3}$'),
    CONSTRAINT ck_company_review_url CHECK (source_url IS NULL OR source_url ~ '^https?://'),
    CONSTRAINT ck_company_review_source CHECK (length(btrim(source)) >= 2)
);
COMMENT ON TABLE recruitment.company_review_summary IS 'Aggregated third-party figures about a company, kept with their source and refresh date (boundary company_reviews). Individual reviews are never stored.';
SELECT audit.apply_standard_lifecycle('recruitment', 'company_review_summary', 'hard');

CREATE VIEW recruitment.company_review_summary_labelled AS
SELECT s.*, (s.refreshed_at < CURRENT_TIMESTAMP - INTERVAL '30 days') AS is_stale
  FROM recruitment.company_review_summary s;
COMMENT ON VIEW recruitment.company_review_summary_labelled IS 'The review figures with a stale flag: a figure older than 30 days is labelled, not hidden (boundary company_reviews).';

-- ---------------------------------------------------------------------------------------------------------------
-- Geolocation: a place reference next to the coordinates; the service is optional
-- ---------------------------------------------------------------------------------------------------------------
ALTER TABLE recruitment.organization_location
    ADD COLUMN place_reference VARCHAR(200),
    ADD COLUMN geocoded_at TIMESTAMPTZ;
COMMENT ON COLUMN recruitment.organization_location.place_reference IS 'The mapping service''s identifier for the place. NULL until the address has been geocoded, or when the service was unavailable.';
COMMENT ON COLUMN recruitment.organization_location.geocoded_at IS 'When latitude, longitude and place_reference were obtained (UTC). NULL while the location is stored as text only.';

-- ---------------------------------------------------------------------------------------------------------------
-- Legacy sync: id mapping, a direction and a conflict rule for every field, and the conflict log
-- ---------------------------------------------------------------------------------------------------------------
CREATE TABLE messaging.external_reference (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    boundary_code  VARCHAR(40)  NOT NULL REFERENCES messaging.integration_boundary (code) ON UPDATE RESTRICT ON DELETE RESTRICT,
    entity_name    VARCHAR(100) NOT NULL,
    entity_id      BIGINT       NOT NULL,
    external_id    VARCHAR(200) NOT NULL,
    external_hash  CHAR(64),
    last_synced_at TIMESTAMPTZ,

    CONSTRAINT uq_external_reference_external UNIQUE (boundary_code, entity_name, external_id),
    CONSTRAINT uq_external_reference_entity UNIQUE (boundary_code, entity_name, entity_id),
    CONSTRAINT ck_external_reference_entity CHECK (entity_name ~ '^[a-z_]+\.[a-z0-9_]+$'),
    CONSTRAINT ck_external_reference_hash CHECK (external_hash IS NULL OR external_hash ~ '^[0-9a-f]{64}$')
);
COMMENT ON TABLE messaging.external_reference IS 'Maps a Talentra row to the same thing in an external system, so a repeated sync updates instead of duplicating. One external id per Talentra row and the reverse.';

CREATE TABLE messaging.legacy_field_mapping (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    legacy_entity   VARCHAR(60)  NOT NULL,
    legacy_field    VARCHAR(80),
    talentra_table  VARCHAR(100) NOT NULL,
    talentra_column VARCHAR(63)  NOT NULL,
    direction       VARCHAR(15)  NOT NULL,
    conflict_rule   VARCHAR(20),
    owner_role      VARCHAR(30)  NOT NULL,
    note            VARCHAR(300) NOT NULL,

    CONSTRAINT uq_legacy_field_mapping UNIQUE (talentra_table, talentra_column),
    CONSTRAINT ck_legacy_field_mapping_direction CHECK (direction IN ('inbound', 'outbound', 'bidirectional', 'not_synced')),
    CONSTRAINT ck_legacy_field_mapping_rule CHECK (conflict_rule IS NULL OR conflict_rule IN ('legacy_wins', 'talentra_wins', 'latest_update_wins', 'cutover_dependent', 'manual_review')),
    CONSTRAINT ck_legacy_field_mapping_consistent CHECK ((direction = 'not_synced') = (conflict_rule IS NULL) AND (direction = 'not_synced') = (legacy_field IS NULL)),
    CONSTRAINT ck_legacy_field_mapping_table CHECK (talentra_table ~ '^[a-z_]+\.[a-z0-9_]+$'),
    CONSTRAINT ck_legacy_field_mapping_owner CHECK (owner_role IN ('Platform', 'Security', 'Finance', 'Product', 'Data'))
);
COMMENT ON TABLE messaging.legacy_field_mapping IS 'Boundary legacy_sync: for every field of the synchronised Talentra tables, which way data flows and who wins a conflict (docket section 6). Legacy field names are assumed; the legacy schema was not available (DEC-32).';
CREATE INDEX idx_legacy_field_mapping_table ON messaging.legacy_field_mapping (talentra_table);

CREATE TABLE messaging.sync_conflict (
    id                    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    mapping_id            BIGINT      NOT NULL REFERENCES messaging.legacy_field_mapping (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    entity_id             BIGINT      NOT NULL,
    legacy_value_sha256   CHAR(64)    NOT NULL,
    talentra_value_sha256 CHAR(64)    NOT NULL,
    rule_outcome          VARCHAR(10) NOT NULL,
    final_choice          VARCHAR(10),
    detected_at           TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    resolved_at           TIMESTAMPTZ,

    CONSTRAINT ck_sync_conflict_outcome CHECK (rule_outcome IN ('legacy', 'talentra', 'review')),
    CONSTRAINT ck_sync_conflict_choice CHECK (final_choice IS NULL OR final_choice IN ('legacy', 'talentra')),
    CONSTRAINT ck_sync_conflict_hashes CHECK (legacy_value_sha256 ~ '^[0-9a-f]{64}$' AND talentra_value_sha256 ~ '^[0-9a-f]{64}$'),
    CONSTRAINT ck_sync_conflict_resolved CHECK (
        (rule_outcome <> 'review' AND resolved_at IS NOT NULL AND final_choice = rule_outcome)
        OR (rule_outcome = 'review' AND ((resolved_at IS NULL AND final_choice IS NULL) OR (resolved_at IS NOT NULL AND final_choice IS NOT NULL))))
);
COMMENT ON TABLE messaging.sync_conflict IS 'Conflict log for the legacy sync. Holds hashes, not values, because the values may be personal data. A conflict the rule settled is logged as resolved; one that needs a person stays open until a choice is recorded.';
CREATE INDEX idx_sync_conflict_open ON messaging.sync_conflict (mapping_id) WHERE resolved_at IS NULL;

CREATE FUNCTION messaging.resolve_sync_conflict(p_rule VARCHAR, p_legacy_changed TIMESTAMPTZ, p_talentra_changed TIMESTAMPTZ, p_cutover_done BOOLEAN)
RETURNS VARCHAR
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE p_rule
        WHEN 'legacy_wins'   THEN 'legacy'
        WHEN 'talentra_wins' THEN 'talentra'
        WHEN 'cutover_dependent' THEN CASE WHEN p_cutover_done THEN 'talentra' ELSE 'legacy' END
        WHEN 'latest_update_wins' THEN CASE
            WHEN p_legacy_changed IS NULL AND p_talentra_changed IS NULL THEN 'review'
            WHEN p_talentra_changed IS NULL THEN 'legacy'
            WHEN p_legacy_changed IS NULL THEN 'talentra'
            WHEN p_legacy_changed > p_talentra_changed THEN 'legacy'
            WHEN p_talentra_changed > p_legacy_changed THEN 'talentra'
            ELSE 'review' END
        ELSE 'review' END;
$$;
COMMENT ON FUNCTION messaging.resolve_sync_conflict(VARCHAR, TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN) IS
    'Applies a mapping''s conflict rule to one field: returns legacy, talentra or review (a person decides). latest_update_wins sends a tie to review; cutover_dependent uses the legacy value until cut-over and the Talentra value after.';
SELECT audit.apply_standard_lifecycle('messaging', 'external_reference', 'reference');
SELECT audit.apply_standard_lifecycle('messaging', 'legacy_field_mapping', 'reference');
SELECT audit.apply_standard_lifecycle('messaging', 'sync_conflict', 'hard');

INSERT INTO messaging.legacy_field_mapping (legacy_entity, legacy_field, talentra_table, talentra_column, direction, conflict_rule, owner_role, note) VALUES
 ('employer', 'company_name', 'recruitment.organization', 'name', 'inbound', 'cutover_dependent', 'Product', 'Legacy owns the name until cut-over; Talentra after'),
 ('candidate', 'email', 'core.user_account', 'email', 'inbound', 'manual_review', 'Security', 'The email identifies the person; two different emails for one legacy record are a possible different person and need a human'),
 ('candidate', 'mobile', 'core.user_account', 'phone_e164', 'inbound', 'latest_update_wins', 'Data', 'Contact data: the more recent change is the better one; legacy format is normalised to E.164 on the way in'),
 ('candidate', 'title', 'profile.candidate_profile', 'headline', 'inbound', 'cutover_dependent', 'Product', 'Profile text: legacy before cut-over, Talentra after'),
 ('candidate', 'about', 'profile.candidate_profile', 'professional_summary', 'inbound', 'cutover_dependent', 'Product', 'Profile text: legacy before cut-over, Talentra after'),
 ('candidate', 'about_lang', 'profile.candidate_profile', 'summary_language_code', 'inbound', 'cutover_dependent', 'Data', 'Follows the text it describes'),
 ('candidate', 'experience_years', 'profile.candidate_profile', 'total_experience_years', 'inbound', 'latest_update_wins', 'Data', 'A measurement that only goes up; the later value is right'),
 ('candidate', 'status', 'profile.candidate_profile', 'profile_status', 'bidirectional', 'latest_update_wins', 'Product', 'Either side can deactivate or reactivate; the later change wins'),
 ('job', 'employer_ref', 'recruitment.job_posting', 'organization_id', 'inbound', 'legacy_wins', 'Data', 'Ownership of an imported job never moves; resolved through messaging.external_reference'),
 ('job', 'title', 'recruitment.job_posting', 'title', 'inbound', 'cutover_dependent', 'Product', 'Job text: legacy before cut-over, Talentra after'),
 ('job', 'description', 'recruitment.job_posting', 'description', 'inbound', 'cutover_dependent', 'Product', 'Job text: legacy before cut-over, Talentra after'),
 ('job', 'description_lang', 'recruitment.job_posting', 'description_language_code', 'inbound', 'cutover_dependent', 'Data', 'Follows the text it describes'),
 ('job', 'responsibilities', 'recruitment.job_posting', 'responsibilities', 'inbound', 'cutover_dependent', 'Product', 'Job text: legacy before cut-over, Talentra after'),
 ('job', 'requirements', 'recruitment.job_posting', 'qualifications', 'inbound', 'cutover_dependent', 'Product', 'Job text: legacy before cut-over, Talentra after'),
 ('job', 'state', 'recruitment.job_posting', 'job_status', 'bidirectional', 'latest_update_wins', 'Product', 'Either side can close a job; the later change wins and the state machine still applies'),
 ('job', 'location_text', 'recruitment.job_posting', 'workplace_location_text', 'inbound', 'cutover_dependent', 'Data', 'Free text place; geocoding happens in Talentra'),
 ('job', 'salary_from', 'recruitment.job_posting', 'salary_min', 'inbound', 'cutover_dependent', 'Finance', 'Compensation moves together with currency and period (a CHECK keeps the trio consistent)'),
 ('job', 'salary_to', 'recruitment.job_posting', 'salary_max', 'inbound', 'cutover_dependent', 'Finance', 'As salary_min'),
 ('job', 'salary_currency', 'recruitment.job_posting', 'currency_code', 'inbound', 'cutover_dependent', 'Finance', 'As salary_min'),
 ('job', 'salary_unit', 'recruitment.job_posting', 'salary_period', 'inbound', 'cutover_dependent', 'Finance', 'As salary_min'),
 ('job', 'min_experience', 'recruitment.job_posting', 'minimum_experience_years', 'inbound', 'cutover_dependent', 'Product', 'Requirement text in numeric form'),
 ('job', 'max_experience', 'recruitment.job_posting', 'maximum_experience_years', 'inbound', 'cutover_dependent', 'Product', 'Requirement text in numeric form'),
 ('job', 'openings', 'recruitment.job_posting', 'vacancy_count', 'inbound', 'latest_update_wins', 'Product', 'A count either side may change as roles are filled'),
 ('job', 'posted_on', 'recruitment.job_posting', 'published_at', 'inbound', 'legacy_wins', 'Data', 'History: the original publication time is a fact'),
 ('job', 'closes_on', 'recruitment.job_posting', 'application_deadline', 'inbound', 'latest_update_wins', 'Product', 'A date either side may extend'),
 ('application', 'candidate_ref', 'recruitment.candidate_application', 'candidate_profile_id', 'inbound', 'legacy_wins', 'Data', 'Identity of the application; resolved through messaging.external_reference'),
 ('application', 'job_ref', 'recruitment.candidate_application', 'job_posting_id', 'inbound', 'legacy_wins', 'Data', 'Identity of the application; resolved through messaging.external_reference'),
 ('application', 'stage', 'recruitment.candidate_application', 'application_status', 'bidirectional', 'latest_update_wins', 'Product', 'Both systems move candidates through stages until cut-over; the later move wins and the state machine still applies'),
 ('application', 'cover_note', 'recruitment.candidate_application', 'cover_letter', 'inbound', 'legacy_wins', 'Data', 'What the candidate wrote at the time does not change'),
 ('application', 'channel', 'recruitment.candidate_application', 'application_source', 'inbound', 'legacy_wins', 'Data', 'How the application arrived is a fact'),
 ('application', 'created', 'recruitment.candidate_application', 'applied_at', 'inbound', 'legacy_wins', 'Data', 'History: the original application time is a fact');

-- everything else in the three synchronised tables is Talentra's own (keys, audit, lifecycle, visibility, documents) and is recorded as not synced
INSERT INTO messaging.legacy_field_mapping (legacy_entity, legacy_field, talentra_table, talentra_column, direction, conflict_rule, owner_role, note)
SELECT CASE c.table_name WHEN 'candidate_profile' THEN 'candidate' WHEN 'job_posting' THEN 'job' ELSE 'application' END,
       NULL, c.table_schema || '.' || c.table_name, c.column_name, 'not_synced', NULL, 'Data',
       CASE WHEN c.column_name = 'visibility' THEN 'A Talentra privacy choice; the legacy systems have no equivalent'
            WHEN c.column_name = 'candidate_document_id' THEN 'Documents are migrated separately into object storage and linked afterwards'
            ELSE 'Maintained by Talentra: key, audit, lifecycle or derived column' END
  FROM information_schema.columns c
 WHERE (c.table_schema, c.table_name) IN (('profile', 'candidate_profile'), ('recruitment', 'job_posting'), ('recruitment', 'candidate_application'))
   AND NOT EXISTS (SELECT 1 FROM messaging.legacy_field_mapping m WHERE m.talentra_table = c.table_schema || '.' || c.table_name AND m.talentra_column = c.column_name);

-- ---------------------------------------------------------------------------------------------------------------
-- Rules around the new tables
-- ---------------------------------------------------------------------------------------------------------------
-- identity verification is a governed state machine and its outcome is an audited account-status change (class 7)
INSERT INTO master.status_transition (entity_code, from_status, to_status) VALUES
 ('core.identity_verification', 'pending', 'verified'), ('core.identity_verification', 'pending', 'rejected'), ('core.identity_verification', 'pending', 'expired'),
 ('core.identity_verification', 'verified', 'expired'), ('core.identity_verification', 'rejected', 'pending'), ('core.identity_verification', 'expired', 'pending');
CREATE TRIGGER trg_identity_verification_status_transition BEFORE UPDATE OF verification_status ON core.identity_verification
    FOR EACH ROW WHEN (OLD.verification_status IS DISTINCT FROM NEW.verification_status)
    EXECUTE FUNCTION master.enforce_status_transition('core.identity_verification', 'verification_status');
CREATE TRIGGER trg_identity_verification_audit AFTER INSERT OR UPDATE ON core.identity_verification
    FOR EACH ROW EXECUTE FUNCTION audit.log_change('account.status_changed', 'provider_token_ref,request_id', 'verification_status', '');

-- personal tables: a person sees and writes only their own rows
ALTER TABLE core.identity_verification ENABLE ROW LEVEL SECURITY;
CREATE POLICY identity_verification_own ON core.identity_verification FOR ALL TO talentra_app
    USING (user_account_id = core.current_app_user_id() OR core.is_platform_admin())
    WITH CHECK (user_account_id = core.current_app_user_id() OR core.is_platform_admin());
ALTER TABLE messaging.share_event ENABLE ROW LEVEL SECURITY;
CREATE POLICY share_event_own ON messaging.share_event FOR ALL TO talentra_app
    USING (user_account_id = core.current_app_user_id() OR core.is_platform_admin())
    WITH CHECK (user_account_id = core.current_app_user_id() OR core.is_platform_admin());

GRANT SELECT, INSERT, UPDATE, DELETE ON core.identity_verification, messaging.share_event, recruitment.company_review_summary,
      messaging.external_reference, messaging.sync_conflict TO talentra_app;
GRANT SELECT ON messaging.legacy_field_mapping, recruitment.company_review_summary_labelled TO talentra_app;
GRANT SELECT ON core.identity_verification, messaging.share_event, recruitment.company_review_summary, recruitment.company_review_summary_labelled,
      messaging.external_reference, messaging.legacy_field_mapping, messaging.sync_conflict TO talentra_readonly;

-- retention: share events are behavioural data
UPDATE audit.entity_lifecycle_policy SET retention_days = 730, purge_column = 'shared_at',
       retention_basis = 'Share events are behavioural data, kept 24 months',
       is_retention_approved = TRUE, retention_approved_by = 'Delegated decision DEC-32, 2026-10-28 (project owner delegated approvals to the assistant)'
 WHERE (schema_name, table_name) = ('messaging', 'share_event');

UPDATE audit.entity_lifecycle_policy SET retention_days = 1095, purge_column = 'requested_at',
       retention_basis = 'Verification outcomes are kept 3 years after the request; they are also deleted when the account is erased',
       is_retention_approved = TRUE, retention_approved_by = 'Delegated decision DEC-32, 2026-10-28 (project owner delegated approvals to the assistant)'
 WHERE (schema_name, table_name) = ('core', 'identity_verification');

-- erasure also removes the verification record and the share events
CREATE OR REPLACE FUNCTION core.erase_user_account(p_user_account_id BIGINT, p_requested_by BIGINT DEFAULT NULL)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_now TIMESTAMPTZ := CURRENT_TIMESTAMP;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM core.user_account WHERE id = p_user_account_id AND deleted_at IS NULL) THEN
        RAISE EXCEPTION 'User account % does not exist or is already erased', p_user_account_id;
    END IF;

    -- identity: keep the row (other tables reference it) but remove everything that identifies the person
    UPDATE core.user_account
       SET email = 'erased+' || id || '@erased.invalid',
           phone_e164 = NULL,
           phone_country_code = NULL,
           password_hash = NULL,
           account_status = 'deactivated',
           deleted_at = v_now,
           deleted_by_user_account_id = COALESCE(p_requested_by, p_user_account_id)
     WHERE id = p_user_account_id;

    UPDATE core.user_credential
       SET is_active = FALSE,
           credential_identifier = 'erased:' || id,
           secret_hash = 'erased'
     WHERE user_account_id = p_user_account_id;

    UPDATE core.user_session
       SET revoked_at = v_now, ended_at = COALESCE(ended_at, v_now)
     WHERE user_account_id = p_user_account_id AND ended_at IS NULL AND revoked_at IS NULL;

    -- the verification outcome and token reference, and what the person shared, are personal data
    DELETE FROM core.identity_verification WHERE user_account_id = p_user_account_id;
    DELETE FROM messaging.share_event WHERE user_account_id = p_user_account_id;

    -- candidate data
    UPDATE profile.candidate_profile
       SET headline = NULL, professional_summary = NULL, visibility = 'private',
           deleted_at = v_now, deleted_by_user_account_id = COALESCE(p_requested_by, p_user_account_id)
     WHERE user_account_id = p_user_account_id AND deleted_at IS NULL;

    -- documents live in external object storage: mark them for the storage sweeper
    UPDATE profile.candidate_document d
       SET document_status = 'archived', archived_at = v_now,
           deleted_at = v_now, deleted_by_user_account_id = COALESCE(p_requested_by, p_user_account_id)
      FROM profile.candidate_profile p
     WHERE d.candidate_profile_id = p.id AND p.user_account_id = p_user_account_id AND d.deleted_at IS NULL;

    -- the erasure itself is a sensitive action
    INSERT INTO audit.audit_event (actor_user_account_id, action, entity_schema, entity_name, entity_id)
    VALUES (COALESCE(p_requested_by, p_user_account_id), 'user.erased', 'core', 'user_account', p_user_account_id);
END;
$$;

-- column definitions
COMMENT ON COLUMN core.identity_verification.created_at IS 'When the row was created (UTC). Set by trigger and never changed.';
COMMENT ON COLUMN core.identity_verification.updated_at IS 'When the row was last changed (UTC). Set by trigger.';
COMMENT ON COLUMN core.identity_verification.created_by_user_account_id IS 'Account that created the row, taken from the session. NULL when the system created it (seed, migration, scheduled job).';
COMMENT ON COLUMN core.identity_verification.updated_by_user_account_id IS 'Account that last changed the row, taken from the session. NULL when the system changed it.';
COMMENT ON COLUMN core.identity_verification.id IS 'Surrogate primary key (64-bit identity). Never reused, never shown to users.';
COMMENT ON COLUMN core.identity_verification.user_account_id IS 'Reference to core.user_account (the person being verified). Required.';
COMMENT ON COLUMN core.identity_verification.provider_code IS 'Which verification service handled the check (a code, not a name); the service is the source of truth for the check.';
COMMENT ON COLUMN core.identity_verification.request_id IS 'The service''s identifier for this check; with provider_code it makes a repeated callback a no-op.';
COMMENT ON COLUMN core.identity_verification.verification_status IS 'pending, verified, rejected or expired; moves only along master.status_transition.';
COMMENT ON COLUMN core.identity_verification.provider_token_ref IS 'Opaque reference the service returned for a passed check. Never an identity number. NULL until the check passes.';
COMMENT ON COLUMN core.identity_verification.requested_at IS 'When the check was requested (UTC).';
COMMENT ON COLUMN core.identity_verification.verified_at IS 'When the service confirmed the check (UTC). NULL unless the status is verified or has been.';
COMMENT ON COLUMN core.identity_verification.expires_at IS 'When the outcome stops counting (UTC). NULL when the outcome does not expire.';
COMMENT ON COLUMN messaging.share_event.created_at IS 'When the row was created (UTC). Set by trigger and never changed.';
COMMENT ON COLUMN messaging.share_event.updated_at IS 'When the row was last changed (UTC). Set by trigger.';
COMMENT ON COLUMN messaging.share_event.created_by_user_account_id IS 'Account that created the row, taken from the session. NULL when the system created it (seed, migration, scheduled job).';
COMMENT ON COLUMN messaging.share_event.updated_by_user_account_id IS 'Account that last changed the row, taken from the session. NULL when the system changed it.';
COMMENT ON COLUMN messaging.share_event.id IS 'Surrogate primary key (64-bit identity). Never reused, never shown to users.';
COMMENT ON COLUMN messaging.share_event.user_account_id IS 'Reference to core.user_account (who shared). Required.';
COMMENT ON COLUMN messaging.share_event.job_posting_id IS 'Reference to recruitment.job_posting (what was shared). Required.';
COMMENT ON COLUMN messaging.share_event.channel IS 'Where the link was shared: whatsapp, linkedin, x, facebook, email or copy_link.';
COMMENT ON COLUMN messaging.share_event.shared_at IS 'When the share happened (UTC).';
COMMENT ON COLUMN recruitment.company_review_summary.created_at IS 'When the row was created (UTC). Set by trigger and never changed.';
COMMENT ON COLUMN recruitment.company_review_summary.updated_at IS 'When the row was last changed (UTC). Set by trigger.';
COMMENT ON COLUMN recruitment.company_review_summary.created_by_user_account_id IS 'Account that created the row, taken from the session. NULL when the system created it (seed, migration, scheduled job).';
COMMENT ON COLUMN recruitment.company_review_summary.updated_by_user_account_id IS 'Account that last changed the row, taken from the session. NULL when the system changed it.';
COMMENT ON COLUMN recruitment.company_review_summary.id IS 'Surrogate primary key (64-bit identity). Never reused, never shown to users.';
COMMENT ON COLUMN recruitment.company_review_summary.organization_id IS 'Reference to recruitment.organization (the company the figures describe). Required.';
COMMENT ON COLUMN recruitment.company_review_summary.source IS 'Name of the data provider the figures came from; shown with the figures.';
COMMENT ON COLUMN recruitment.company_review_summary.rating_average IS 'Provider''s average rating from 0.00 to 5.00. NULL when the provider gave none.';
COMMENT ON COLUMN recruitment.company_review_summary.review_count IS 'Number of reviews behind the rating; zero when unknown.';
COMMENT ON COLUMN recruitment.company_review_summary.salary_median IS 'Provider''s median salary in currency_code. NULL when the provider gave none.';
COMMENT ON COLUMN recruitment.company_review_summary.currency_code IS 'ISO 4217 currency of salary_median. NULL exactly when salary_median is NULL.';
COMMENT ON COLUMN recruitment.company_review_summary.source_url IS 'Absolute URL of the provider''s page for this company. NULL when the provider gave none.';
COMMENT ON COLUMN recruitment.company_review_summary.refreshed_at IS 'When the figures were last fetched (UTC); the interface labels a figure stale when this is old.';
COMMENT ON COLUMN messaging.external_reference.created_at IS 'When the row was created (UTC). Set by trigger and never changed.';
COMMENT ON COLUMN messaging.external_reference.updated_at IS 'When the row was last changed (UTC). Set by trigger.';
COMMENT ON COLUMN messaging.external_reference.created_by_user_account_id IS 'Account that created the row, taken from the session. NULL when the system created it (seed, migration, scheduled job).';
COMMENT ON COLUMN messaging.external_reference.updated_by_user_account_id IS 'Account that last changed the row, taken from the session. NULL when the system changed it.';
COMMENT ON COLUMN messaging.external_reference.id IS 'Surrogate primary key (64-bit identity). Never reused, never shown to users.';
COMMENT ON COLUMN messaging.external_reference.boundary_code IS 'Which integration boundary the external id belongs to (messaging.integration_boundary.code).';
COMMENT ON COLUMN messaging.external_reference.entity_name IS 'schema.table of the Talentra row the external id maps to.';
COMMENT ON COLUMN messaging.external_reference.entity_id IS 'Primary key of that Talentra row.';
COMMENT ON COLUMN messaging.external_reference.external_id IS 'The other system''s identifier for the same thing.';
COMMENT ON COLUMN messaging.external_reference.external_hash IS 'SHA-256 of the payload last received for it, used to skip unchanged records. NULL before the first sync.';
COMMENT ON COLUMN messaging.external_reference.last_synced_at IS 'When the pair was last synchronised (UTC). NULL before the first sync.';
COMMENT ON COLUMN messaging.legacy_field_mapping.created_at IS 'When the row was created (UTC). Set by trigger and never changed.';
COMMENT ON COLUMN messaging.legacy_field_mapping.updated_at IS 'When the row was last changed (UTC). Set by trigger.';
COMMENT ON COLUMN messaging.legacy_field_mapping.created_by_user_account_id IS 'Account that created the row, taken from the session. NULL when the system created it (seed, migration, scheduled job).';
COMMENT ON COLUMN messaging.legacy_field_mapping.updated_by_user_account_id IS 'Account that last changed the row, taken from the session. NULL when the system changed it.';
COMMENT ON COLUMN messaging.legacy_field_mapping.id IS 'Surrogate primary key (64-bit identity). Never reused, never shown to users.';
COMMENT ON COLUMN messaging.legacy_field_mapping.legacy_entity IS 'The legacy system''s record type (assumed names: candidate, job, application, employer, candidate_skill).';
COMMENT ON COLUMN messaging.legacy_field_mapping.legacy_field IS 'The legacy system''s field name (assumed; the legacy schema was not available). NULL for Talentra columns the legacy system has no equivalent for.';
COMMENT ON COLUMN messaging.legacy_field_mapping.talentra_table IS 'schema.table receiving or sending the field.';
COMMENT ON COLUMN messaging.legacy_field_mapping.talentra_column IS 'Column in talentra_table.';
COMMENT ON COLUMN messaging.legacy_field_mapping.direction IS 'inbound (legacy to Talentra), outbound (Talentra to legacy), bidirectional, or not_synced.';
COMMENT ON COLUMN messaging.legacy_field_mapping.conflict_rule IS 'What wins when both sides changed: legacy_wins, talentra_wins, latest_update_wins, cutover_dependent or manual_review. NULL when the field is not synced.';
COMMENT ON COLUMN messaging.legacy_field_mapping.owner_role IS 'Role that decides the rule for this field (DEC-30).';
COMMENT ON COLUMN messaging.legacy_field_mapping.note IS 'Why the rule is what it is, or why the field is not synced.';
COMMENT ON COLUMN messaging.sync_conflict.created_at IS 'When the row was created (UTC). Set by trigger and never changed.';
COMMENT ON COLUMN messaging.sync_conflict.updated_at IS 'When the row was last changed (UTC). Set by trigger.';
COMMENT ON COLUMN messaging.sync_conflict.created_by_user_account_id IS 'Account that created the row, taken from the session. NULL when the system created it (seed, migration, scheduled job).';
COMMENT ON COLUMN messaging.sync_conflict.updated_by_user_account_id IS 'Account that last changed the row, taken from the session. NULL when the system changed it.';
COMMENT ON COLUMN messaging.sync_conflict.id IS 'Surrogate primary key (64-bit identity). Never reused, never shown to users.';
COMMENT ON COLUMN messaging.sync_conflict.mapping_id IS 'Reference to messaging.legacy_field_mapping (the field in conflict). Required.';
COMMENT ON COLUMN messaging.sync_conflict.entity_id IS 'Primary key of the Talentra row in conflict.';
COMMENT ON COLUMN messaging.sync_conflict.legacy_value_sha256 IS 'SHA-256 of the legacy value; the value itself is not kept because it may be personal data.';
COMMENT ON COLUMN messaging.sync_conflict.talentra_value_sha256 IS 'SHA-256 of the Talentra value at the time of the conflict.';
COMMENT ON COLUMN messaging.sync_conflict.rule_outcome IS 'What the mapping''s rule decided: legacy, talentra or review.';
COMMENT ON COLUMN messaging.sync_conflict.final_choice IS 'What a person chose when the rule said review: legacy or talentra. NULL until chosen, and for conflicts the rule settled.';
COMMENT ON COLUMN messaging.sync_conflict.detected_at IS 'When the conflict was found (UTC).';
COMMENT ON COLUMN messaging.sync_conflict.resolved_at IS 'When the conflict was settled (UTC). NULL while a review is open.';

SELECT * FROM master.sync_enumeration_values();
SELECT audit.sync_column_classification();
UPDATE audit.column_classification SET data_class = 'sensitive', protection = 'external_reference', basis = 'reviewed',
       note = 'Opaque reference returned by the verification service; the identity number is never stored.'
 WHERE (schema_name, table_name, column_name) = ('core', 'identity_verification', 'provider_token_ref');
SELECT audit.refresh_protection();

COMMIT;
