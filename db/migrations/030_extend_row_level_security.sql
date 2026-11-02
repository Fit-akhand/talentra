BEGIN;
-- =============================================================================
-- Migration 030: Row-level security on every table that holds a candidate's, a user's or an organisation's data
-- Domain:        security (NFR-013 "consent and block state enforced on every read path", SEC-002, SEC-014, docket section 3)
-- Depends on:    001-029
--
-- Migration 021 protected candidate_profile, but the tables hanging off it (education, skills, work history, documents,
-- language, location, projects, scores, completion) were readable through grants alone, so a blocked recruiter who asked for
-- candidate_education directly never met the block. This migration closes that for every table that carries a
-- candidate_profile_id, and adds owner or organisation policies to the other tables that hold one person's or one
-- organisation's data.
--
-- Rules, in one place
--   candidate content    anyone who may see the profile may read the rows (owner, platform admin, or a viewer the profile
--                        allows and the candidate has not blocked); only the owner or an admin may write
--   owner data           the user the row belongs to, or a platform admin
--   organisation data    members acting for the organisation, or a platform admin
--   append-only ledgers  read and insert only; never change or remove (grants already forbid it)
--
-- Roles other than talentra_app have no policy, and a table with row-level security and no matching policy returns no rows.
-- That is deliberate: talentra_readonly and talentra_support do not see candidate or tenant rows. Staff who need figures use
-- the analytics schema; support uses the masked account view.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Helpers (SECURITY DEFINER, so a policy can look at the parent without recursing into its own policy)
-- -----------------------------------------------------------------------------
CREATE FUNCTION core.can_view_candidate(p_candidate_profile_id BIGINT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
    SELECT EXISTS (
        SELECT 1
          FROM profile.candidate_profile p
         WHERE p.id = p_candidate_profile_id
           AND (p.user_account_id = core.current_app_user_id()
                OR core.is_platform_admin()
                OR (p.deleted_at IS NULL
                    -- 'public' is visible to anyone; 'recruiters' only to someone acting for an organisation; 'private' to nobody else
                    AND (p.visibility = 'public' OR (p.visibility = 'recruiters' AND core.current_org_id() IS NOT NULL))
                    AND core.is_candidate_visible_to(p.id, core.current_app_user_id(), core.current_org_id())))
    );
$$;
COMMENT ON FUNCTION core.can_view_candidate(BIGINT) IS 'The one rule for reading a candidate: the owner, a platform admin, or a viewer the profile allows (public to anyone, recruiters to someone acting for an organisation) and the candidate has not blocked.';

-- The profile table itself uses the same rule, so the profile and the rows hanging off it can never disagree.
DROP POLICY candidate_profile_read ON profile.candidate_profile;
CREATE POLICY candidate_profile_read ON profile.candidate_profile FOR SELECT TO talentra_app
    USING (core.can_view_candidate(id));

CREATE FUNCTION commercial.payment_order_org(p_order_id BIGINT) RETURNS BIGINT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog AS
$$ SELECT organization_id FROM commercial.payment_order WHERE id = p_order_id $$;
CREATE FUNCTION commercial.licence_org(p_licence_id BIGINT) RETURNS BIGINT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog AS
$$ SELECT organization_id FROM commercial.subscription_licence WHERE id = p_licence_id $$;
CREATE FUNCTION sourcing.outreach_batch_org(p_batch_id BIGINT) RETURNS BIGINT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog AS
$$ SELECT organization_id FROM sourcing.outreach_batch WHERE id = p_batch_id $$;

REVOKE EXECUTE ON FUNCTION core.can_view_candidate(BIGINT), commercial.payment_order_org(BIGINT),
                           commercial.licence_org(BIGINT), sourcing.outreach_batch_org(BIGINT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION core.can_view_candidate(BIGINT), commercial.payment_order_org(BIGINT),
                           commercial.licence_org(BIGINT), sourcing.outreach_batch_org(BIGINT) TO talentra_app;

-- -----------------------------------------------------------------------------
-- 2. Policies from three patterns
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    r RECORD;
BEGIN
    -- candidate content: visible by the profile rule, written by the owner or an admin
    FOR r IN SELECT * FROM (VALUES
        ('profile', 'candidate_education'), ('profile', 'candidate_language'), ('profile', 'candidate_location'),
        ('profile', 'candidate_skill'), ('profile', 'candidate_work_experience'), ('profile', 'candidate_project'),
        ('profile', 'candidate_document'), ('profile', 'candidate_profile_completion'), ('profile', 'candidate_assessment_score')
    ) AS t (s, t)
    LOOP
        EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY', r.s, r.t);
        EXECUTE format('CREATE POLICY %I ON %I.%I FOR SELECT TO talentra_app USING (core.can_view_candidate(candidate_profile_id))',
                       r.t || '_view', r.s, r.t);
        EXECUTE format('CREATE POLICY %I ON %I.%I FOR ALL TO talentra_app USING (core.owns_candidate_profile(candidate_profile_id) OR core.is_platform_admin()) WITH CHECK (core.owns_candidate_profile(candidate_profile_id) OR core.is_platform_admin())',
                       r.t || '_owner_write', r.s, r.t);
    END LOOP;

    -- data that belongs to one user
    FOR r IN SELECT * FROM (VALUES
        ('messaging', 'job_alert_preference', 'user_account_id'), ('messaging', 'user_notification_preference', 'user_account_id'),
        ('messaging', 'user_privacy_preference', 'user_account_id'), ('messaging', 'referral_event', 'referrer_user_account_id'),
        ('messaging', 'support_ticket', 'requester_user_account_id'), ('core', 'consent_record', 'user_account_id')
    ) AS t (s, t, c)
    LOOP
        EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY', r.s, r.t);
        EXECUTE format('CREATE POLICY %I ON %I.%I FOR ALL TO talentra_app USING (%I = core.current_app_user_id() OR core.is_platform_admin()) WITH CHECK (%I = core.current_app_user_id() OR core.is_platform_admin())',
                       r.t || '_owner', r.s, r.t, r.c, r.c);
    END LOOP;

    -- data that belongs to one organisation
    FOR r IN SELECT * FROM (VALUES
        ('profile', 'recruiter_bookmark', 'organization_id'), ('commercial', 'payment_order', 'organization_id'),
        ('commercial', 'invoice', 'organization_id'), ('commercial', 'subscription_licence', 'organization_id'),
        ('sourcing', 'outreach_batch', 'organization_id')
    ) AS t (s, t, c)
    LOOP
        EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY', r.s, r.t);
        EXECUTE format('CREATE POLICY %I ON %I.%I FOR ALL TO talentra_app USING (%I = core.current_org_id() OR core.is_platform_admin()) WITH CHECK (%I = core.current_org_id() OR core.is_platform_admin())',
                       r.t || '_org', r.s, r.t, r.c, r.c);
    END LOOP;
END;
$$;

-- -----------------------------------------------------------------------------
-- 3. Tables whose rule does not fit a pattern
-- -----------------------------------------------------------------------------
-- Profile views: the organisation that looked, the candidate who was looked at, or an admin read them; a viewer records only their own view
ALTER TABLE profile.profile_view_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY profile_view_history_read ON profile.profile_view_history FOR SELECT TO talentra_app
    USING (organization_id = core.current_org_id() OR core.owns_candidate_profile(candidate_profile_id) OR core.is_platform_admin());
CREATE POLICY profile_view_history_append ON profile.profile_view_history FOR INSERT TO talentra_app
    WITH CHECK (viewer_user_account_id = core.current_app_user_id() OR core.is_platform_admin());

-- Downloads: the paying organisation and the candidate whose profile was taken
ALTER TABLE commercial.candidate_profile_download_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY download_history_read ON commercial.candidate_profile_download_history FOR SELECT TO talentra_app
    USING (organization_id = core.current_org_id() OR core.owns_candidate_profile(candidate_profile_id) OR core.is_platform_admin());
CREATE POLICY download_history_append ON commercial.candidate_profile_download_history FOR INSERT TO talentra_app
    WITH CHECK (organization_id = core.current_org_id() OR core.is_platform_admin());

-- Children of an organisation's order, licence or campaign
ALTER TABLE commercial.payment_refund ENABLE ROW LEVEL SECURITY;
CREATE POLICY payment_refund_org ON commercial.payment_refund FOR ALL TO talentra_app
    USING (commercial.payment_order_org(payment_order_id) = core.current_org_id() OR core.is_platform_admin())
    WITH CHECK (commercial.payment_order_org(payment_order_id) = core.current_org_id() OR core.is_platform_admin());
ALTER TABLE commercial.licence_seat_allocation ENABLE ROW LEVEL SECURITY;
CREATE POLICY licence_seat_org ON commercial.licence_seat_allocation FOR ALL TO talentra_app
    USING (commercial.licence_org(subscription_licence_id) = core.current_org_id() OR user_account_id = core.current_app_user_id() OR core.is_platform_admin())
    WITH CHECK (commercial.licence_org(subscription_licence_id) = core.current_org_id() OR core.is_platform_admin());
ALTER TABLE sourcing.outreach_recipient ENABLE ROW LEVEL SECURITY;
CREATE POLICY outreach_recipient_read ON sourcing.outreach_recipient FOR SELECT TO talentra_app
    USING (sourcing.outreach_batch_org(outreach_batch_id) = core.current_org_id() OR core.owns_candidate_profile(candidate_profile_id) OR core.is_platform_admin());
CREATE POLICY outreach_recipient_write ON sourcing.outreach_recipient FOR ALL TO talentra_app
    USING (sourcing.outreach_batch_org(outreach_batch_id) = core.current_org_id() OR core.is_platform_admin())
    WITH CHECK (sourcing.outreach_batch_org(outreach_batch_id) = core.current_org_id() OR core.is_platform_admin());

-- Consultant submissions: the consultant who made them, the organisation that owns the job, the candidate, or an admin
ALTER TABLE sourcing.sourcing_submission ENABLE ROW LEVEL SECURITY;
CREATE POLICY sourcing_submission_read ON sourcing.sourcing_submission FOR SELECT TO talentra_app
    USING (submitted_by_user_account_id = core.current_app_user_id()
           OR recruitment.job_organization_id(job_posting_id) = core.current_org_id()
           OR core.owns_candidate_profile(candidate_profile_id) OR core.is_platform_admin());
CREATE POLICY sourcing_submission_write ON sourcing.sourcing_submission FOR ALL TO talentra_app
    USING (submitted_by_user_account_id = core.current_app_user_id() OR recruitment.job_organization_id(job_posting_id) = core.current_org_id() OR core.is_platform_admin())
    WITH CHECK (submitted_by_user_account_id = core.current_app_user_id() OR recruitment.job_organization_id(job_posting_id) = core.current_org_id() OR core.is_platform_admin());

-- -----------------------------------------------------------------------------
-- 4. Classification follows reality: a column is 'rls' when its table has row-level security, else 'grants_only'
-- -----------------------------------------------------------------------------
CREATE FUNCTION audit.refresh_protection()
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_changed INTEGER;
BEGIN
    UPDATE audit.column_classification x
       SET protection = CASE WHEN c.relrowsecurity THEN 'rls' ELSE 'grants_only' END
      FROM pg_class c
     WHERE c.relname = x.table_name AND c.relnamespace = x.schema_name::regnamespace
       AND x.data_class IN ('personal', 'internal', 'public') AND x.protection IN ('rls', 'grants_only')
       AND x.protection <> CASE WHEN c.relrowsecurity THEN 'rls' ELSE 'grants_only' END;
    GET DIAGNOSTICS v_changed = ROW_COUNT;
    RETURN v_changed;
END;
$$;
COMMENT ON FUNCTION audit.refresh_protection() IS 'Re-derives protection for personal columns from the catalog (row-level security on or off). Run after enabling or disabling RLS.';
SELECT audit.refresh_protection();

COMMENT ON ROLE talentra_readonly IS 'Engineers and reporting tools. Read-only; no credentials, sessions or account rows. Tables with row-level security return no rows to this role: use the analytics schema for figures.';

COMMIT;
