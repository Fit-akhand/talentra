-- 042: candidate keyword search with a match score, saved and recent recruiter searches, the "sourced" pipeline stage,
-- the recruiter assigned to an application, and the candidate table of a requirement page.
--
-- Decision DEC-37 (Delegated, 2026-11-04; docs/lifecycle/decision-log.md):
--   * Keyword search uses PostgreSQL full text search (english configuration) over one maintained document per candidate.
--     Keywords are comma-separated phrases; "mark all as mandatory" ANDs them, otherwise any may match. Boolean mode hands the whole text to
--     websearch_to_tsquery, so OR, "quoted phrases" and -excluded words work (AND is implicit). It is not a full boolean language.
--   * The match percentage is a documented heuristic, not a learned model: keywords 35, skills 30, experience 15, location 10, recency 10,
--     counting only the criteria the recruiter used. A search scores the 1,000 most recently active matches (p_pool), then ranks them.
--   * "Sourced" is a first stage of an application a recruiter creates for a candidate who has not applied yet.

BEGIN;

-- ---------------------------------------------------------------------------------------------------------------
-- 1. Search document
-- ---------------------------------------------------------------------------------------------------------------
CREATE TABLE profile.candidate_search_document (
    id                   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    candidate_profile_id BIGINT      NOT NULL UNIQUE REFERENCES profile.candidate_profile (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    document             TSVECTOR    NOT NULL,
    refreshed_at         TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE profile.candidate_search_document IS 'One full-text document per candidate, built from the headline, summary, skills, work history and education, and kept current by triggers. Derived data: rebuilt from the profile, deleted with it.';
CREATE INDEX idx_candidate_search_document_gin ON profile.candidate_search_document USING gin (document);
SELECT audit.apply_standard_lifecycle('profile', 'candidate_search_document', 'derived');

CREATE FUNCTION profile.refresh_candidate_search_document(p_candidate_profile_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, profile, master
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM profile.candidate_profile WHERE id = p_candidate_profile_id AND deleted_at IS NULL) THEN
        DELETE FROM profile.candidate_search_document WHERE candidate_profile_id = p_candidate_profile_id;
        RETURN;
    END IF;
    INSERT INTO profile.candidate_search_document (candidate_profile_id, document, refreshed_at)
    SELECT p.id,
           setweight(to_tsvector('english', coalesce(p.headline, '')), 'A')
        || setweight(to_tsvector('english', coalesce((SELECT string_agg(s.name, ' ') FROM profile.candidate_skill cs JOIN master.skill s ON s.id = cs.skill_id WHERE cs.candidate_profile_id = p.id), '')), 'B')
        || setweight(to_tsvector('english', coalesce((SELECT string_agg(w.job_title || ' ' || w.employer_name, ' ') FROM profile.candidate_work_experience w WHERE w.candidate_profile_id = p.id), '')), 'B')
        || setweight(to_tsvector('english', coalesce(p.professional_summary, '')), 'C')
        || setweight(to_tsvector('english', coalesce((SELECT string_agg(coalesce(w.description, ''), ' ') FROM profile.candidate_work_experience w WHERE w.candidate_profile_id = p.id), '')), 'D')
        || setweight(to_tsvector('english', coalesce((SELECT string_agg(e.institution_name || ' ' || coalesce(e.field_of_study, ''), ' ') FROM profile.candidate_education e WHERE e.candidate_profile_id = p.id), '')), 'C'),
           CURRENT_TIMESTAMP
      FROM profile.candidate_profile p WHERE p.id = p_candidate_profile_id
    ON CONFLICT (candidate_profile_id) DO UPDATE SET document = EXCLUDED.document, refreshed_at = EXCLUDED.refreshed_at;
END;
$$;
COMMENT ON FUNCTION profile.refresh_candidate_search_document(BIGINT) IS 'Rebuilds one candidate''s search document, or removes it when the profile is deleted.';
REVOKE ALL ON FUNCTION profile.refresh_candidate_search_document(BIGINT) FROM PUBLIC;

CREATE FUNCTION profile.rebuild_candidate_search_documents()
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, profile, master
AS $$
DECLARE v_n BIGINT;
BEGIN
    INSERT INTO profile.candidate_search_document (candidate_profile_id, document, refreshed_at)
    SELECT p.id,
           setweight(to_tsvector('english', coalesce(p.headline, '')), 'A')
        || setweight(to_tsvector('english', coalesce(sk.t, '')), 'B') || setweight(to_tsvector('english', coalesce(we.t, '')), 'B')
        || setweight(to_tsvector('english', coalesce(p.professional_summary, '')), 'C')
        || setweight(to_tsvector('english', coalesce(we.d, '')), 'D') || setweight(to_tsvector('english', coalesce(ed.t, '')), 'C'),
           CURRENT_TIMESTAMP
      FROM profile.candidate_profile p
      LEFT JOIN (SELECT cs.candidate_profile_id, string_agg(s.name, ' ') AS t FROM profile.candidate_skill cs JOIN master.skill s ON s.id = cs.skill_id GROUP BY 1) sk ON sk.candidate_profile_id = p.id
      LEFT JOIN (SELECT candidate_profile_id, string_agg(job_title || ' ' || employer_name, ' ') AS t, string_agg(coalesce(description, ''), ' ') AS d FROM profile.candidate_work_experience GROUP BY 1) we ON we.candidate_profile_id = p.id
      LEFT JOIN (SELECT candidate_profile_id, string_agg(institution_name || ' ' || coalesce(field_of_study, ''), ' ') AS t FROM profile.candidate_education GROUP BY 1) ed ON ed.candidate_profile_id = p.id
     WHERE p.deleted_at IS NULL
    ON CONFLICT (candidate_profile_id) DO UPDATE SET document = EXCLUDED.document, refreshed_at = EXCLUDED.refreshed_at;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    DELETE FROM profile.candidate_search_document d WHERE NOT EXISTS (SELECT 1 FROM profile.candidate_profile p WHERE p.id = d.candidate_profile_id AND p.deleted_at IS NULL);
    RETURN v_n;
END;
$$;
COMMENT ON FUNCTION profile.rebuild_candidate_search_documents() IS 'Set-based rebuild of every search document; used after a bulk load, when the triggers are switched off with SET talentra.skip_search_refresh = ''on''.';
REVOKE ALL ON FUNCTION profile.rebuild_candidate_search_documents() FROM PUBLIC;

CREATE FUNCTION profile.trg_refresh_search_document()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_key TEXT := CASE WHEN TG_TABLE_NAME = 'candidate_profile' THEN 'id' ELSE 'candidate_profile_id' END;
    v_new BIGINT; v_old BIGINT;
BEGIN
    IF current_setting('talentra.skip_search_refresh', true) = 'on' THEN RETURN NULL; END IF;
    IF TG_OP <> 'DELETE' THEN v_new := (to_jsonb(NEW) ->> v_key)::BIGINT; END IF;
    IF TG_OP <> 'INSERT' THEN v_old := (to_jsonb(OLD) ->> v_key)::BIGINT; END IF;
    IF v_new IS NOT NULL THEN PERFORM profile.refresh_candidate_search_document(v_new); END IF;
    IF v_old IS NOT NULL AND v_old IS DISTINCT FROM v_new THEN PERFORM profile.refresh_candidate_search_document(v_old); END IF;
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION profile.trg_refresh_search_document() IS 'Keeps profile.candidate_search_document current. Does nothing while talentra.skip_search_refresh is ''on''.';
CREATE TRIGGER trg_candidate_profile_search AFTER INSERT OR UPDATE OF headline, professional_summary, deleted_at ON profile.candidate_profile FOR EACH ROW EXECUTE FUNCTION profile.trg_refresh_search_document();
CREATE TRIGGER trg_candidate_skill_search AFTER INSERT OR UPDATE OR DELETE ON profile.candidate_skill FOR EACH ROW EXECUTE FUNCTION profile.trg_refresh_search_document();
CREATE TRIGGER trg_candidate_work_experience_search AFTER INSERT OR UPDATE OR DELETE ON profile.candidate_work_experience FOR EACH ROW EXECUTE FUNCTION profile.trg_refresh_search_document();
CREATE TRIGGER trg_candidate_education_search AFTER INSERT OR UPDATE OR DELETE ON profile.candidate_education FOR EACH ROW EXECUTE FUNCTION profile.trg_refresh_search_document();

SELECT profile.rebuild_candidate_search_documents();

ALTER TABLE profile.candidate_search_document ENABLE ROW LEVEL SECURITY;
CREATE POLICY candidate_search_document_read ON profile.candidate_search_document FOR SELECT TO talentra_app USING (core.can_view_candidate(candidate_profile_id));
GRANT SELECT ON profile.candidate_search_document TO talentra_app, talentra_readonly;

-- ---------------------------------------------------------------------------------------------------------------
-- 2. Keyword queries and the search itself
-- ---------------------------------------------------------------------------------------------------------------
CREATE FUNCTION profile.keyword_terms(p_text TEXT)
RETURNS TSQUERY[]
LANGUAGE sql IMMUTABLE
AS $$
    SELECT coalesce(array_agg(q) FILTER (WHERE q::text <> ''), '{}')
      FROM (SELECT phraseto_tsquery('english', btrim(t)) AS q FROM regexp_split_to_table(coalesce(p_text, ''), '[,;\n]') AS t WHERE btrim(t) <> '') x;
$$;
COMMENT ON FUNCTION profile.keyword_terms(TEXT) IS 'Splits comma-separated keywords into one phrase query each ("Java developer, Springboot" is two terms).';

CREATE FUNCTION profile.build_keyword_query(p_text TEXT, p_match_all BOOLEAN DEFAULT FALSE, p_boolean_mode BOOLEAN DEFAULT FALSE)
RETURNS TSQUERY
LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE v_terms TSQUERY[]; v_q TSQUERY; v_t TSQUERY;
BEGIN
    IF p_text IS NULL OR btrim(p_text) = '' THEN RETURN NULL; END IF;
    IF p_boolean_mode THEN
        v_q := websearch_to_tsquery('english', p_text);
        RETURN CASE WHEN v_q::text = '' THEN NULL ELSE v_q END;
    END IF;
    v_terms := profile.keyword_terms(p_text);
    FOREACH v_t IN ARRAY v_terms LOOP
        v_q := CASE WHEN v_q IS NULL THEN v_t WHEN p_match_all THEN v_q && v_t ELSE v_q || v_t END;
    END LOOP;
    RETURN v_q;
END;
$$;
COMMENT ON FUNCTION profile.build_keyword_query(TEXT, BOOLEAN, BOOLEAN) IS 'Keywords to a tsquery: comma-separated phrases joined by AND (mark all as mandatory) or OR; boolean mode uses websearch syntax (OR, "phrases", -exclude). NULL when there is nothing to search for.';

-- Runs as its owner so that visibility is decided once per candidate (core.can_view_candidate, evaluated last) instead of once per candidate
-- per table through row-level security, which made a search take seconds. The function applies the same rules itself: only active, non-deleted
-- profiles whose visibility is recruiters or public, never one the viewer may not see, only for a user acting for an organisation (or an admin),
-- pay only when the candidate revealed it, and gender never.
ALTER FUNCTION core.can_view_candidate(BIGINT) COST 1000;

CREATE FUNCTION profile.search_candidates(
    p_keywords TEXT DEFAULT NULL, p_exclude_keywords TEXT DEFAULT NULL, p_all_keywords BOOLEAN DEFAULT FALSE, p_boolean_mode BOOLEAN DEFAULT FALSE,
    p_min_experience NUMERIC DEFAULT NULL, p_max_experience NUMERIC DEFAULT NULL,
    p_city_ids BIGINT[] DEFAULT NULL, p_skill_ids BIGINT[] DEFAULT NULL, p_qualification_ids BIGINT[] DEFAULT NULL, p_study_mode TEXT DEFAULT NULL,
    p_department_ids BIGINT[] DEFAULT NULL, p_max_notice_days INTEGER DEFAULT NULL,
    p_ctc_min NUMERIC DEFAULT NULL, p_ctc_max NUMERIC DEFAULT NULL, p_include_undisclosed_ctc BOOLEAN DEFAULT TRUE,
    p_active_within_days INTEGER DEFAULT NULL, p_limit INTEGER DEFAULT 50, p_offset INTEGER DEFAULT 0, p_pool INTEGER DEFAULT 1000)
RETURNS TABLE (candidate_profile_id BIGINT, match_percent INTEGER, headline TEXT, total_experience_years NUMERIC, last_active_at TIMESTAMPTZ,
               notice_period_days INTEGER, matched_skills INTEGER)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog
SET enable_hashjoin = off          -- the pool must come from an ordered index scan that stops after p_pool visible matches,
SET enable_mergejoin = off         -- with one index lookup per candidate; a hash or merge join would examine every candidate first
SET plan_cache_mode = force_custom_plan   -- plan for the actual filters, not for unknown ones
AS $$
#variable_conflict use_column
BEGIN
RETURN QUERY
WITH q AS (
    SELECT profile.build_keyword_query(p_keywords, p_all_keywords, p_boolean_mode) AS inc,
           profile.build_keyword_query(p_exclude_keywords, FALSE, FALSE) AS exc,
           CASE WHEN p_boolean_mode THEN NULL ELSE profile.keyword_terms(p_keywords) END AS terms,
           (core.current_org_id() IS NOT NULL OR core.is_platform_admin()) AS allowed          -- decided once, not per candidate
), pool AS (
    SELECT cp.id, cp.headline::TEXT AS headline, cp.total_experience_years AS exp_years, cp.last_active_at AS last_active, pref.notice_period_days AS notice,
           d.document, q.inc, q.terms,
           (SELECT count(*) FROM profile.candidate_skill cs WHERE cs.candidate_profile_id = cp.id AND cs.skill_id = ANY (p_skill_ids))::INTEGER AS matched_skills
      FROM profile.candidate_profile cp
      CROSS JOIN q
      LEFT JOIN profile.candidate_search_document d ON d.candidate_profile_id = cp.id
      LEFT JOIN profile.candidate_job_preference pref ON pref.candidate_profile_id = cp.id
     WHERE q.allowed
       AND cp.profile_status = 'active' AND cp.deleted_at IS NULL AND cp.visibility IN ('recruiters', 'public')
       AND (q.inc IS NULL OR d.document @@ q.inc)
       AND (q.exc IS NULL OR d.document IS NULL OR NOT (d.document @@ q.exc))
       AND (p_min_experience IS NULL OR cp.total_experience_years >= p_min_experience)
       AND (p_max_experience IS NULL OR cp.total_experience_years <= p_max_experience)
       AND (p_city_ids IS NULL OR EXISTS (SELECT 1 FROM profile.candidate_location l WHERE l.candidate_profile_id = cp.id AND l.city_id = ANY (p_city_ids)))
       AND (p_skill_ids IS NULL OR EXISTS (SELECT 1 FROM profile.candidate_skill cs WHERE cs.candidate_profile_id = cp.id AND cs.skill_id = ANY (p_skill_ids)))
       AND (p_qualification_ids IS NULL OR EXISTS (SELECT 1 FROM profile.candidate_education e WHERE e.candidate_profile_id = cp.id AND e.qualification_id = ANY (p_qualification_ids)
                                                    AND (p_study_mode IS NULL OR e.study_mode = p_study_mode)))
       AND (p_qualification_ids IS NOT NULL OR p_study_mode IS NULL OR EXISTS (SELECT 1 FROM profile.candidate_education e WHERE e.candidate_profile_id = cp.id AND e.study_mode = p_study_mode))
       AND (p_department_ids IS NULL OR EXISTS (SELECT 1 FROM profile.candidate_work_experience w WHERE w.candidate_profile_id = cp.id AND w.department_id = ANY (p_department_ids)))
       AND (p_max_notice_days IS NULL OR pref.notice_period_days <= p_max_notice_days)
       AND (p_ctc_min IS NULL AND p_ctc_max IS NULL
            OR (pref.is_ctc_visible_to_recruiters AND pref.current_annual_ctc IS NOT NULL AND pref.current_annual_ctc >= coalesce(p_ctc_min, 0) AND pref.current_annual_ctc <= coalesce(p_ctc_max, pref.current_annual_ctc))
            OR (p_include_undisclosed_ctc AND (pref.candidate_profile_id IS NULL OR NOT pref.is_ctc_visible_to_recruiters OR pref.current_annual_ctc IS NULL)))
       AND (p_active_within_days IS NULL OR cp.last_active_at >= CURRENT_TIMESTAMP - p_active_within_days * INTERVAL '1 day')
       AND core.can_view_candidate(cp.id)
     ORDER BY cp.last_active_at DESC NULLS LAST, cp.id
     LIMIT least(greatest(p_pool, p_limit + p_offset), 5000)
), scored AS (
    SELECT p.*,
           CASE WHEN p.inc IS NULL THEN NULL WHEN p.terms IS NULL OR cardinality(p.terms) = 0 THEN 1.0
                ELSE (SELECT count(*) FROM unnest(p.terms) t WHERE p.document @@ t)::NUMERIC / cardinality(p.terms) END AS f_kw,
           CASE WHEN p_skill_ids IS NULL THEN NULL ELSE p.matched_skills::NUMERIC / cardinality(p_skill_ids) END AS f_sk,
           CASE WHEN p_min_experience IS NULL AND p_max_experience IS NULL THEN NULL ELSE 1.0 END AS f_ex,
           CASE WHEN p_city_ids IS NULL THEN NULL ELSE 1.0 END AS f_lo,
           CASE WHEN p.last_active IS NULL THEN 0.1 WHEN p.last_active >= CURRENT_TIMESTAMP - INTERVAL '7 days' THEN 1.0
                WHEN p.last_active >= CURRENT_TIMESTAMP - INTERVAL '30 days' THEN 0.7 WHEN p.last_active >= CURRENT_TIMESTAMP - INTERVAL '90 days' THEN 0.4 ELSE 0.1 END AS f_re
      FROM pool p
)
SELECT s.id, round(100 * (coalesce(35 * s.f_kw, 0) + coalesce(30 * s.f_sk, 0) + coalesce(15 * s.f_ex, 0) + coalesce(10 * s.f_lo, 0) + 10 * s.f_re)
                   / (CASE WHEN s.f_kw IS NULL THEN 0 ELSE 35 END + CASE WHEN s.f_sk IS NULL THEN 0 ELSE 30 END + CASE WHEN s.f_ex IS NULL THEN 0 ELSE 15 END
                      + CASE WHEN s.f_lo IS NULL THEN 0 ELSE 10 END + 10))::INTEGER AS match_percent,
       s.headline, s.exp_years, s.last_active, s.notice, s.matched_skills
  FROM scored s
 ORDER BY 2 DESC, s.last_active DESC NULLS LAST, s.id
 LIMIT least(p_limit, 200) OFFSET p_offset;
END;
$$;
COMMENT ON FUNCTION profile.search_candidates(TEXT, TEXT, BOOLEAN, BOOLEAN, NUMERIC, NUMERIC, BIGINT[], BIGINT[], BIGINT[], TEXT, BIGINT[], INTEGER, NUMERIC, NUMERIC, BOOLEAN, INTEGER, INTEGER, INTEGER, INTEGER) IS
    'Recruiter profile search: keywords (comma-separated phrases or boolean mode), exclusions, experience, cities, skills, education level and study mode, department, notice period, current pay (hidden pay counts as undisclosed), recent activity. Returns nothing unless the caller acts for an organisation. Applies visibility, blocks and pay privacy itself (it runs as its owner for speed). Scores the p_pool (default 1,000) most recently active matches and returns at most 200 ranked by a documented match percentage (DEC-37).';
REVOKE ALL ON FUNCTION profile.search_candidates(TEXT, TEXT, BOOLEAN, BOOLEAN, NUMERIC, NUMERIC, BIGINT[], BIGINT[], BIGINT[], TEXT, BIGINT[], INTEGER, NUMERIC, NUMERIC, BOOLEAN, INTEGER, INTEGER, INTEGER, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION profile.keyword_terms(TEXT), profile.build_keyword_query(TEXT, BOOLEAN, BOOLEAN) TO talentra_app, talentra_readonly;
GRANT EXECUTE ON FUNCTION profile.search_candidates(TEXT, TEXT, BOOLEAN, BOOLEAN, NUMERIC, NUMERIC, BIGINT[], BIGINT[], BIGINT[], TEXT, BIGINT[], INTEGER, NUMERIC, NUMERIC, BOOLEAN, INTEGER, INTEGER, INTEGER, INTEGER) TO talentra_app;

-- ---------------------------------------------------------------------------------------------------------------
-- 3. Recent and saved recruiter searches
-- ---------------------------------------------------------------------------------------------------------------
CREATE TABLE profile.recruiter_search (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    organization_id BIGINT       NOT NULL REFERENCES recruitment.organization (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    user_account_id BIGINT       NOT NULL REFERENCES core.user_account (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    name            VARCHAR(100),
    criteria_json   JSONB        NOT NULL,
    result_count    INTEGER      NOT NULL,
    last_run_at     TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_alert_enabled   BOOLEAN      NOT NULL DEFAULT FALSE,

    CONSTRAINT ck_recruiter_search_name CHECK (name IS NULL OR length(btrim(name)) BETWEEN 1 AND 100),
    CONSTRAINT ck_recruiter_search_count CHECK (result_count >= 0),
    CONSTRAINT ck_recruiter_search_alert CHECK (NOT is_alert_enabled OR name IS NOT NULL),
    CONSTRAINT ck_recruiter_search_criteria CHECK (jsonb_typeof(criteria_json) = 'object')
);
COMMENT ON TABLE profile.recruiter_search IS 'A recruiter''s searches: the most recent unnamed ones ("Recently searched") and the named ones they saved, optionally with an alert.';
CREATE UNIQUE INDEX uq_recruiter_search_name ON profile.recruiter_search (user_account_id, lower(btrim(name))) WHERE name IS NOT NULL;
CREATE INDEX idx_recruiter_search_user ON profile.recruiter_search (user_account_id, last_run_at DESC);
CREATE INDEX idx_recruiter_search_organization ON profile.recruiter_search (organization_id);
SELECT audit.apply_standard_lifecycle('profile', 'recruiter_search', 'hard');
ALTER TABLE profile.recruiter_search ENABLE ROW LEVEL SECURITY;
CREATE POLICY recruiter_search_own ON profile.recruiter_search FOR ALL TO talentra_app
    USING ((user_account_id = core.current_app_user_id() AND organization_id = core.current_org_id()) OR core.is_platform_admin())
    WITH CHECK ((user_account_id = core.current_app_user_id() AND organization_id = core.current_org_id()) OR core.is_platform_admin());
GRANT SELECT, INSERT, UPDATE, DELETE ON profile.recruiter_search TO talentra_app;
GRANT SELECT ON profile.recruiter_search TO talentra_readonly;

CREATE FUNCTION profile.record_recruiter_search(p_criteria JSONB, p_result_count INTEGER, p_name TEXT DEFAULT NULL, p_alert BOOLEAN DEFAULT FALSE)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE v_user BIGINT := core.current_app_user_id(); v_org BIGINT := core.current_org_id(); v_id BIGINT;
BEGIN
    IF v_user IS NULL OR v_org IS NULL THEN RAISE EXCEPTION 'a search is recorded for a user acting for an organisation' USING ERRCODE = 'insufficient_privilege'; END IF;
    IF p_name IS NOT NULL THEN
        INSERT INTO profile.recruiter_search (organization_id, user_account_id, name, criteria_json, result_count, is_alert_enabled)
        VALUES (v_org, v_user, btrim(p_name), p_criteria, p_result_count, p_alert)
        ON CONFLICT (user_account_id, lower(btrim(name))) WHERE name IS NOT NULL
        DO UPDATE SET criteria_json = EXCLUDED.criteria_json, result_count = EXCLUDED.result_count, is_alert_enabled = EXCLUDED.is_alert_enabled, last_run_at = CURRENT_TIMESTAMP
        RETURNING id INTO v_id;
    ELSE
        INSERT INTO profile.recruiter_search (organization_id, user_account_id, criteria_json, result_count) VALUES (v_org, v_user, p_criteria, p_result_count) RETURNING id INTO v_id;
        DELETE FROM profile.recruiter_search WHERE id IN (SELECT id FROM profile.recruiter_search WHERE user_account_id = v_user AND name IS NULL ORDER BY last_run_at DESC, id DESC OFFSET 20);
    END IF;
    RETURN v_id;
END;
$$;
COMMENT ON FUNCTION profile.record_recruiter_search(JSONB, INTEGER, TEXT, BOOLEAN) IS 'Records a search for the acting recruiter. Unnamed: kept as one of the latest 20. Named: saved (updated if the name exists), optionally with an alert.';
GRANT EXECUTE ON FUNCTION profile.record_recruiter_search(JSONB, INTEGER, TEXT, BOOLEAN) TO talentra_app;

-- ---------------------------------------------------------------------------------------------------------------
-- 4. The "sourced" stage and the recruiter on an application
-- ---------------------------------------------------------------------------------------------------------------
ALTER TABLE recruitment.candidate_application DROP CONSTRAINT ck_candidate_application_status;
ALTER TABLE recruitment.candidate_application ADD CONSTRAINT ck_candidate_application_status
    CHECK (application_status IN ('sourced', 'applied', 'shortlisted', 'interviewed', 'offered', 'joined', 'rejected', 'withdrawn'));
ALTER TABLE recruitment.application_status_history DROP CONSTRAINT ck_application_status_history_previous;
ALTER TABLE recruitment.application_status_history ADD CONSTRAINT ck_application_status_history_previous
    CHECK (previous_status IS NULL OR previous_status IN ('sourced', 'applied', 'shortlisted', 'interviewed', 'offered', 'joined', 'rejected', 'withdrawn'));
ALTER TABLE recruitment.application_status_history DROP CONSTRAINT ck_application_status_history_new;
ALTER TABLE recruitment.application_status_history ADD CONSTRAINT ck_application_status_history_new
    CHECK (new_status IN ('sourced', 'applied', 'shortlisted', 'interviewed', 'offered', 'joined', 'rejected', 'withdrawn'));
ALTER TABLE recruitment.candidate_application DROP CONSTRAINT ck_candidate_application_source;
ALTER TABLE recruitment.candidate_application ADD CONSTRAINT ck_candidate_application_source
    CHECK (application_source IN ('direct', 'job_alert', 'referral', 'campus', 'recruiter_sourced', 'other'));
ALTER TABLE recruitment.candidate_application ADD CONSTRAINT ck_candidate_application_sourced
    CHECK (application_status <> 'sourced' OR application_source = 'recruiter_sourced');
INSERT INTO master.status_transition (entity_code, from_status, to_status) VALUES
    ('recruitment.candidate_application', 'sourced', 'applied'), ('recruitment.candidate_application', 'sourced', 'shortlisted'),
    ('recruitment.candidate_application', 'sourced', 'rejected'), ('recruitment.candidate_application', 'sourced', 'withdrawn');

ALTER TABLE recruitment.candidate_application ADD COLUMN assigned_recruiter_user_account_id BIGINT,
    ADD CONSTRAINT fk_candidate_application_recruiter FOREIGN KEY (assigned_recruiter_user_account_id) REFERENCES core.user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT;
COMMENT ON COLUMN recruitment.candidate_application.assigned_recruiter_user_account_id IS 'Reference to core.user_account (the recruiter handling this candidate on this job). Must be a recruiter of the job''s organisation or mapped to it as a client. NULL when no one is assigned.';
CREATE INDEX idx_candidate_application_recruiter ON recruitment.candidate_application (assigned_recruiter_user_account_id) WHERE assigned_recruiter_user_account_id IS NOT NULL;

CREATE FUNCTION recruitment.enforce_application_recruiter()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' AND NEW.assigned_recruiter_user_account_id IS NULL AND NEW.application_status = 'sourced'
       AND core.current_app_user_id() IS NOT NULL
       AND recruitment.is_recruiter_for_organization(core.current_app_user_id(), recruitment.job_organization_id(NEW.job_posting_id)) THEN
        NEW.assigned_recruiter_user_account_id := core.current_app_user_id();       -- the recruiter who sources a candidate owns that candidate
    END IF;
    IF NEW.assigned_recruiter_user_account_id IS NOT NULL
       AND NOT recruitment.is_recruiter_for_organization(NEW.assigned_recruiter_user_account_id, recruitment.job_organization_id(NEW.job_posting_id)) THEN
        RAISE EXCEPTION 'user % is not a recruiter of the organisation that owns job %', NEW.assigned_recruiter_user_account_id, NEW.job_posting_id USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION recruitment.enforce_application_recruiter() IS 'The recruiter on an application must belong to the job''s organisation (or be mapped to it as a client); a recruiter who sources a candidate becomes that candidate''s recruiter.';
CREATE TRIGGER trg_candidate_application_recruiter BEFORE INSERT OR UPDATE OF assigned_recruiter_user_account_id, job_posting_id ON recruitment.candidate_application
    FOR EACH ROW EXECUTE FUNCTION recruitment.enforce_application_recruiter();

-- a status change can carry the recruiter's comment ("Candidate fulfils all criteria"): history rows are append-only, so the reason has to be
-- supplied when the row is written, through the session setting app.status_change_reason
CREATE OR REPLACE FUNCTION recruitment.record_application_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO recruitment.application_status_history (candidate_application_id, previous_status, new_status, changed_by_user_account_id, changed_at)
        VALUES (NEW.id, NULL, NEW.application_status, NEW.created_by_user_account_id, NEW.applied_at);
        RETURN NEW;
    END IF;
    IF NEW.application_status IS DISTINCT FROM OLD.application_status THEN
        NEW.last_status_changed_at := CURRENT_TIMESTAMP;
        INSERT INTO recruitment.application_status_history (candidate_application_id, previous_status, new_status, changed_by_user_account_id, changed_at, change_reason)
        VALUES (NEW.id, OLD.application_status, NEW.application_status, NEW.updated_by_user_account_id, CURRENT_TIMESTAMP,
                nullif(btrim(current_setting('app.status_change_reason', true)), ''));
    END IF;
    RETURN NEW;
END;
$$;

CREATE FUNCTION recruitment.change_application_status(p_candidate_application_id BIGINT, p_new_status TEXT, p_reason TEXT DEFAULT NULL)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM set_config('app.status_change_reason', coalesce(p_reason, ''), true);
    UPDATE recruitment.candidate_application SET application_status = p_new_status, updated_by_user_account_id = coalesce(core.current_app_user_id(), updated_by_user_account_id)
     WHERE id = p_candidate_application_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'application % does not exist or is not visible to you', p_candidate_application_id USING ERRCODE = 'no_data_found'; END IF;
    PERFORM set_config('app.status_change_reason', '', true);
END;
$$;
COMMENT ON FUNCTION recruitment.change_application_status(BIGINT, TEXT, TEXT) IS 'Moves an application to another stage and records the recruiter''s reason in the same history row. The legal moves and row-level security still apply.';
GRANT EXECUTE ON FUNCTION recruitment.change_application_status(BIGINT, TEXT, TEXT) TO talentra_app;

-- a recruiter may create a "sourced" application for a candidate they can see, on their organisation's job
CREATE POLICY application_sourced ON recruitment.candidate_application FOR INSERT TO talentra_app
    WITH CHECK (application_status = 'sourced' AND recruitment.job_organization_id(job_posting_id) = core.current_org_id() AND core.can_view_candidate(candidate_profile_id));

INSERT INTO messaging.legacy_field_mapping (legacy_entity, legacy_field, talentra_table, talentra_column, direction, conflict_rule, owner_role, note) VALUES
 ('application', NULL, 'recruitment.candidate_application', 'assigned_recruiter_user_account_id', 'not_synced', NULL, 'Data', 'Recruiters are Talentra user accounts; legacy recruiter names are not matched to accounts');

-- ---------------------------------------------------------------------------------------------------------------
-- 5. The candidate table of a requirement page
-- ---------------------------------------------------------------------------------------------------------------
CREATE VIEW recruitment.job_candidate_pipeline WITH (security_barrier = true) AS
SELECT a.id AS candidate_application_id, a.job_posting_id, a.candidate_profile_id, cp.headline::TEXT AS candidate_headline, cp.last_active_at,
       a.application_status, a.application_source, a.applied_at, a.last_status_changed_at, a.assigned_recruiter_user_account_id,
       (SELECT h.change_reason FROM recruitment.application_status_history h WHERE h.candidate_application_id = a.id ORDER BY h.id DESC LIMIT 1) AS last_comment
  FROM recruitment.candidate_application a
  JOIN profile.candidate_profile cp ON cp.id = a.candidate_profile_id
 WHERE recruitment.job_organization_id(a.job_posting_id) = core.current_org_id() OR core.is_platform_admin();
COMMENT ON VIEW recruitment.job_candidate_pipeline IS 'The candidate table on a requirement page: every application to the organisation''s jobs with its stage, source, recruiter and latest comment. Contact details are not here; they follow the candidate visibility rules.';
GRANT SELECT ON recruitment.job_candidate_pipeline TO talentra_app, talentra_readonly;

-- ---------------------------------------------------------------------------------------------------------------
-- Retention, definitions, classification
-- ---------------------------------------------------------------------------------------------------------------
UPDATE audit.entity_lifecycle_policy SET retention_days = 365, purge_column = 'last_run_at',
       retention_basis = 'Searches show what a recruiter was looking for: kept 12 months after the last run, saved or not',
       is_retention_approved = TRUE, retention_approved_by = 'Delegated decision DEC-37, 2026-11-04 (project owner delegated approvals to the assistant)'
 WHERE (schema_name, table_name) = ('profile', 'recruiter_search');
UPDATE audit.entity_lifecycle_policy SET retention_days = 1095, purge_column = 'refreshed_at',
       retention_basis = 'Derived from the profile and rebuilt with it; a document not refreshed for 3 years belongs to an abandoned profile',
       is_retention_approved = TRUE, retention_approved_by = 'Delegated decision DEC-37, 2026-11-04 (project owner delegated approvals to the assistant)'
 WHERE (schema_name, table_name) = ('profile', 'candidate_search_document');

COMMENT ON COLUMN profile.candidate_search_document.candidate_profile_id IS 'Reference to profile.candidate_profile (whose document). One document per candidate (unique); deleted with the profile.';
COMMENT ON COLUMN profile.candidate_search_document.id IS 'Surrogate primary key (64-bit identity). Never reused, never shown to users.';
COMMENT ON COLUMN profile.candidate_search_document.document IS 'Weighted full-text vector of headline (A), skills and job titles (B), summary and education (C) and work descriptions (D). Personal data derived from the profile.';
COMMENT ON COLUMN profile.candidate_search_document.refreshed_at IS 'When the document was last rebuilt (UTC).';
DO $$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT * FROM (VALUES
        ('id',                         'Surrogate primary key (64-bit identity). Never reused, never shown to users.'),
        ('created_at',                 'When the row was created (UTC). Set by trigger and never changed.'),
        ('updated_at',                 'When the row was last changed (UTC). Set by trigger.'),
        ('created_by_user_account_id', 'Account that created the row, taken from the session. NULL when the system created it (seed, migration, scheduled job).'),
        ('updated_by_user_account_id', 'Account that last changed the row, taken from the session. NULL when the system changed it.')) AS v(c, d)
    LOOP EXECUTE format('COMMENT ON COLUMN profile.recruiter_search.%I IS %L', r.c, r.d); END LOOP;
END $$;
COMMENT ON COLUMN profile.recruiter_search.organization_id IS 'Reference to recruitment.organization (the company the recruiter was acting for). Required.';
COMMENT ON COLUMN profile.recruiter_search.user_account_id IS 'Reference to core.user_account (the recruiter who searched). Required.';
COMMENT ON COLUMN profile.recruiter_search.name IS 'Name the recruiter gave a saved search. NULL for an unnamed recent search.';
COMMENT ON COLUMN profile.recruiter_search.criteria_json IS 'The filters used, as a JSON object (keywords, experience, cities, skill ids...). Must not carry candidate data.';
COMMENT ON COLUMN profile.recruiter_search.result_count IS 'How many candidates the search found when it last ran; zero or more.';
COMMENT ON COLUMN profile.recruiter_search.last_run_at IS 'When the search last ran (UTC).';
COMMENT ON COLUMN profile.recruiter_search.is_alert_enabled IS 'True when the recruiter wants an alert about new matches; only a named (saved) search can have one. Default FALSE.';

SELECT audit.refresh_active_views();
SELECT * FROM master.sync_enumeration_values();
SELECT audit.sync_column_classification();
SELECT audit.refresh_protection();

COMMIT;
