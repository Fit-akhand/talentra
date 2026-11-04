-- 041: what recruiters filter candidates by and the profile could not hold: notice period, current and expected pay (CTC),
-- last active time and education type; plus an optional, private, self-declared gender used for equal-opportunity reporting.
--
-- Decisions (Delegated, 2026-11-04; docs/lifecycle/decision-log.md):
--   DEC-35  Gender is stored only as an optional self-declaration the candidate alone (and platform admins) can read. It is NOT visible to
--           recruiters and NOT a search filter: filtering candidates by gender is unlawful discrimination in many jurisdictions. The portal
--           design shows a gender choice on a requirement; it is not built until the business and legal owner confirm it is lawful.
--   DEC-36  CTC is the candidate's to reveal: the amounts are hidden from recruiters unless is_ctc_visible_to_recruiters is TRUE. A recruiter
--           reads candidate pay and notice period only through profile.candidate_search_attributes, which applies the visibility rules.

BEGIN;

-- ---------------------------------------------------------------------------------------------------------------
-- Notice period and pay: one row per candidate
-- ---------------------------------------------------------------------------------------------------------------
CREATE TABLE profile.candidate_job_preference (
    id                         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    candidate_profile_id       BIGINT       NOT NULL REFERENCES profile.candidate_profile (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    notice_period_days         INTEGER,
    current_annual_ctc         NUMERIC(14,2),
    expected_annual_ctc        NUMERIC(14,2),
    ctc_currency_code          CHAR(3),
    is_ctc_visible_to_recruiters  BOOLEAN      NOT NULL DEFAULT FALSE,

    CONSTRAINT uq_candidate_job_preference_profile UNIQUE (candidate_profile_id),
    CONSTRAINT ck_candidate_job_preference_notice CHECK (notice_period_days IS NULL OR notice_period_days BETWEEN 0 AND 365),
    CONSTRAINT ck_candidate_job_preference_ctc CHECK ((current_annual_ctc IS NULL OR current_annual_ctc >= 0) AND (expected_annual_ctc IS NULL OR expected_annual_ctc >= 0)),
    CONSTRAINT ck_candidate_job_preference_currency CHECK ((current_annual_ctc IS NULL AND expected_annual_ctc IS NULL) = (ctc_currency_code IS NULL)
                                                           AND (ctc_currency_code IS NULL OR ctc_currency_code ~ '^[A-Z]{3}$'))
);
COMMENT ON TABLE profile.candidate_job_preference IS 'What a candidate wants and can offer: notice period and current and expected annual pay. Pay is the candidate''s to reveal (DEC-36); recruiters read it through profile.candidate_search_attributes.';
SELECT audit.apply_standard_lifecycle('profile', 'candidate_job_preference', 'hard');

-- ---------------------------------------------------------------------------------------------------------------
-- Self-declared gender: private to the candidate (DEC-35)
-- ---------------------------------------------------------------------------------------------------------------
CREATE TABLE profile.candidate_diversity_profile (
    id                   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    candidate_profile_id BIGINT      NOT NULL REFERENCES profile.candidate_profile (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    gender               VARCHAR(20) NOT NULL,
    declared_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT uq_candidate_diversity_profile_profile UNIQUE (candidate_profile_id),
    CONSTRAINT ck_candidate_diversity_profile_gender CHECK (gender IN ('female', 'male', 'non_binary', 'prefer_not_to_say'))
);
COMMENT ON TABLE profile.candidate_diversity_profile IS 'Optional self-declared gender, for equal-opportunity reporting only. Readable by the candidate and platform administrators; never by recruiters; never a search filter (DEC-35).';
SELECT audit.apply_standard_lifecycle('profile', 'candidate_diversity_profile', 'hard');

-- ---------------------------------------------------------------------------------------------------------------
-- Last active, and education type
-- ---------------------------------------------------------------------------------------------------------------
ALTER TABLE profile.candidate_profile ADD COLUMN last_active_at TIMESTAMPTZ;
COMMENT ON COLUMN profile.candidate_profile.last_active_at IS 'When the candidate last signed in (UTC), set by trigger on core.user_session. NULL until the first sign-in after this column existed.';
CREATE INDEX idx_candidate_profile_last_active ON profile.candidate_profile (last_active_at DESC NULLS LAST, id) WHERE profile_status = 'active' AND deleted_at IS NULL;

UPDATE profile.candidate_profile p SET last_active_at = s.last_at
  FROM (SELECT user_account_id, max(started_at) AS last_at FROM core.user_session GROUP BY user_account_id) s
 WHERE s.user_account_id = p.user_account_id;

CREATE FUNCTION profile.touch_last_active()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
BEGIN
    UPDATE profile.candidate_profile SET last_active_at = NEW.started_at
     WHERE user_account_id = NEW.user_account_id AND (last_active_at IS NULL OR last_active_at < NEW.started_at);
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION profile.touch_last_active() IS 'Moves a candidate''s last_active_at forward when a session starts; never backwards.';
CREATE TRIGGER trg_user_session_last_active AFTER INSERT ON core.user_session FOR EACH ROW EXECUTE FUNCTION profile.touch_last_active();

ALTER TABLE profile.candidate_education ADD COLUMN study_mode VARCHAR(20),
    ADD CONSTRAINT ck_candidate_education_study_mode CHECK (study_mode IS NULL OR study_mode IN ('full_time', 'part_time', 'distance'));
COMMENT ON COLUMN profile.candidate_education.study_mode IS 'How the course was studied: full_time, part_time or distance. NULL when not stated.';

-- ---------------------------------------------------------------------------------------------------------------
-- Row-level security and the recruiter's view
-- ---------------------------------------------------------------------------------------------------------------
ALTER TABLE profile.candidate_job_preference ENABLE ROW LEVEL SECURITY;
CREATE POLICY candidate_job_preference_own ON profile.candidate_job_preference FOR ALL TO talentra_app
    USING (core.owns_candidate_profile(candidate_profile_id) OR core.is_platform_admin())
    WITH CHECK (core.owns_candidate_profile(candidate_profile_id) OR core.is_platform_admin());
ALTER TABLE profile.candidate_diversity_profile ENABLE ROW LEVEL SECURITY;
CREATE POLICY candidate_diversity_profile_own ON profile.candidate_diversity_profile FOR ALL TO talentra_app
    USING (core.owns_candidate_profile(candidate_profile_id) OR core.is_platform_admin())
    WITH CHECK (core.owns_candidate_profile(candidate_profile_id) OR core.is_platform_admin());

CREATE FUNCTION profile.candidate_search_attributes_for(p_candidate_profile_id BIGINT)
RETURNS TABLE (notice_period_days INTEGER, current_annual_ctc NUMERIC, expected_annual_ctc NUMERIC, ctc_currency_code CHAR(3), is_ctc_visible BOOLEAN)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog
AS $$
    SELECT p.notice_period_days,
           CASE WHEN p.is_ctc_visible_to_recruiters OR core.owns_candidate_profile(p.candidate_profile_id) THEN p.current_annual_ctc END,
           CASE WHEN p.is_ctc_visible_to_recruiters OR core.owns_candidate_profile(p.candidate_profile_id) THEN p.expected_annual_ctc END,
           CASE WHEN p.is_ctc_visible_to_recruiters OR core.owns_candidate_profile(p.candidate_profile_id) THEN p.ctc_currency_code END,
           (p.is_ctc_visible_to_recruiters OR core.owns_candidate_profile(p.candidate_profile_id))
      FROM profile.candidate_job_preference p
     WHERE p.candidate_profile_id = p_candidate_profile_id AND core.can_view_candidate(p_candidate_profile_id);
$$;
COMMENT ON FUNCTION profile.candidate_search_attributes_for(BIGINT) IS 'One candidate''s notice period and pay as the viewer may see them: nothing for a profile the viewer cannot see, and pay amounts only when the candidate revealed them (DEC-36). Looked up per candidate so a search never scans the whole table.';
REVOKE ALL ON FUNCTION profile.candidate_search_attributes_for(BIGINT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION profile.candidate_search_attributes_for(BIGINT) TO talentra_app, talentra_readonly;

CREATE VIEW profile.candidate_search_attributes WITH (security_barrier = true) AS
SELECT p.candidate_profile_id, f.notice_period_days, f.current_annual_ctc, f.expected_annual_ctc, f.ctc_currency_code, f.is_ctc_visible
  FROM profile.candidate_job_preference p
 CROSS JOIN LATERAL profile.candidate_search_attributes_for(p.candidate_profile_id) f;
COMMENT ON VIEW profile.candidate_search_attributes IS 'What a recruiter may see of a candidate''s notice period and pay: only for profiles the viewer can see, and the pay amounts only when the candidate chose to reveal them (DEC-36).';

GRANT SELECT, INSERT, UPDATE, DELETE ON profile.candidate_job_preference, profile.candidate_diversity_profile TO talentra_app;
GRANT SELECT ON profile.candidate_job_preference TO talentra_readonly;
GRANT SELECT ON profile.candidate_search_attributes TO talentra_app, talentra_readonly;

-- ---------------------------------------------------------------------------------------------------------------
-- Retention, legacy mapping, definitions, classification
-- ---------------------------------------------------------------------------------------------------------------
UPDATE audit.entity_lifecycle_policy SET retention_days = 1095, purge_column = 'updated_at',
       retention_basis = 'Job preferences and pay are personal data: kept 3 years after the last change; also deleted with the profile',
       is_retention_approved = TRUE, retention_approved_by = 'Delegated decision DEC-36, 2026-11-04 (project owner delegated approvals to the assistant)'
 WHERE (schema_name, table_name) = ('profile', 'candidate_job_preference');
UPDATE audit.entity_lifecycle_policy SET retention_days = 1095, purge_column = 'updated_at',
       retention_basis = 'A self-declared attribute: kept 3 years after the last change; also deleted with the profile',
       is_retention_approved = TRUE, retention_approved_by = 'Delegated decision DEC-35, 2026-11-04 (project owner delegated approvals to the assistant)'
 WHERE (schema_name, table_name) = ('profile', 'candidate_diversity_profile');

INSERT INTO messaging.legacy_field_mapping (legacy_entity, legacy_field, talentra_table, talentra_column, direction, conflict_rule, owner_role, note) VALUES
 ('candidate', 'last_login', 'profile.candidate_profile', 'last_active_at', 'inbound', 'latest_update_wins', 'Data', 'The more recent sign-in, from either system, is the last activity');

DO $$
DECLARE r RECORD; t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY['profile.candidate_job_preference', 'profile.candidate_diversity_profile'] LOOP
        FOR r IN SELECT * FROM (VALUES
            ('id',                         'Surrogate primary key (64-bit identity). Never reused, never shown to users.'),
            ('created_at',                 'When the row was created (UTC). Set by trigger and never changed.'),
            ('updated_at',                 'When the row was last changed (UTC). Set by trigger.'),
            ('created_by_user_account_id', 'Account that created the row, taken from the session. NULL when the system created it (seed, migration, scheduled job).'),
            ('updated_by_user_account_id', 'Account that last changed the row, taken from the session. NULL when the system changed it.')) AS v(c, d)
        LOOP EXECUTE format('COMMENT ON COLUMN %s.%I IS %L', t, r.c, r.d); END LOOP;
    END LOOP;
END $$;
COMMENT ON COLUMN profile.candidate_job_preference.candidate_profile_id IS 'Reference to profile.candidate_profile (whose preferences). Required; one row per candidate; deleted with the profile.';
COMMENT ON COLUMN profile.candidate_job_preference.notice_period_days IS 'Days before the candidate could start a new job, 0 to 365 (0 is immediate). NULL when not stated.';
COMMENT ON COLUMN profile.candidate_job_preference.current_annual_ctc IS 'Current annual pay (cost to company) in ctc_currency_code. NULL when the candidate gave none. Sensitive; recruiters see it only if is_ctc_visible_to_recruiters is TRUE.';
COMMENT ON COLUMN profile.candidate_job_preference.expected_annual_ctc IS 'Expected annual pay in ctc_currency_code. NULL when the candidate gave none. Sensitive; recruiters see it only if is_ctc_visible_to_recruiters is TRUE.';
COMMENT ON COLUMN profile.candidate_job_preference.ctc_currency_code IS 'ISO 4217 currency of both pay figures. NULL exactly when both figures are NULL.';
COMMENT ON COLUMN profile.candidate_job_preference.is_ctc_visible_to_recruiters IS 'True when the candidate lets recruiters see the pay figures. Default FALSE: pay is the candidate''s to reveal (DEC-36).';
COMMENT ON COLUMN profile.candidate_diversity_profile.candidate_profile_id IS 'Reference to profile.candidate_profile (who declared it). Required; one row per candidate; deleted with the profile.';
COMMENT ON COLUMN profile.candidate_diversity_profile.gender IS 'Self-declared: female, male, non_binary or prefer_not_to_say. Sensitive; readable only by the candidate and platform administrators (DEC-35).';
COMMENT ON COLUMN profile.candidate_diversity_profile.declared_at IS 'When the candidate made the declaration (UTC).';

-- erasure also removes pay, notice period and the self-declared gender
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

    -- the candidate's pay, notice period and self-declared gender are personal data
    DELETE FROM profile.candidate_job_preference WHERE candidate_profile_id IN (SELECT id FROM profile.candidate_profile WHERE user_account_id = p_user_account_id);
    DELETE FROM profile.candidate_diversity_profile WHERE candidate_profile_id IN (SELECT id FROM profile.candidate_profile WHERE user_account_id = p_user_account_id);

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

SELECT audit.refresh_active_views();
SELECT * FROM master.sync_enumeration_values();
SELECT audit.sync_column_classification();
UPDATE audit.column_classification SET data_class = 'sensitive', protection = 'rls', basis = 'reviewed',
       note = 'The candidate''s to reveal: hidden from recruiters unless is_ctc_visible_to_recruiters (DEC-36).'
 WHERE (schema_name, table_name) = ('profile', 'candidate_job_preference') AND column_name IN ('current_annual_ctc', 'expected_annual_ctc');
UPDATE audit.column_classification SET data_class = 'sensitive', protection = 'rls', basis = 'reviewed',
       note = 'Self-declared, owner and administrators only, never a recruiter filter (DEC-35).'
 WHERE (schema_name, table_name, column_name) = ('profile', 'candidate_diversity_profile', 'gender');
SELECT audit.refresh_protection();

COMMIT;
