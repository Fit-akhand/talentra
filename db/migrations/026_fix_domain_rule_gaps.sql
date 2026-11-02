-- =============================================================================
-- Migration 026: Close gaps found when checking the docket's rule groups against the live schema
-- Domain:        cross-cutting (docket Rule Group 3 money and content; Rule Group 7 multilingual; Rule Group 4 views)
-- Depends on:    001-025
--
--   1. Money columns without a companion currency column (RG3: "Every money column has a companion
--      currency code column"): job_alert_preference.minimum_salary, referral_event.reward_amount,
--      gig_worker_service.rate_override.
--   2. User-entered text did not record its language (RG7: "stored once in the language it was entered,
--      with the language recorded where it is known"): job_posting.description,
--      candidate_profile.professional_summary, community_post.content.
--   3. active_<table> views were created with SELECT * in migration 020, and PostgreSQL expands * once,
--      at creation. Columns added later (resume_template_id in 022, and the new ones here) were missing
--      from them. audit.refresh_active_views() rebuilds them; tests/test_lifecycle.sql now fails if one
--      goes stale again.
-- =============================================================================

-- 1. Currency companions. A currency is required exactly when an amount is present.
BEGIN;

ALTER TABLE messaging.job_alert_preference
    ADD COLUMN currency_code CHAR(3),
    ADD CONSTRAINT ck_job_alert_preference_currency_format CHECK (currency_code IS NULL OR currency_code ~ '^[A-Z]{3}$'),
    ADD CONSTRAINT ck_job_alert_preference_salary_currency CHECK (minimum_salary IS NULL OR currency_code IS NOT NULL);
COMMENT ON COLUMN messaging.job_alert_preference.currency_code IS 'Nullable: required when minimum_salary is set (ISO 4217), otherwise NULL.';

ALTER TABLE messaging.referral_event
    ADD COLUMN currency_code CHAR(3),
    ADD CONSTRAINT ck_referral_event_currency_format CHECK (currency_code IS NULL OR currency_code ~ '^[A-Z]{3}$'),
    ADD CONSTRAINT ck_referral_event_reward_currency CHECK (reward_amount IS NULL OR currency_code IS NOT NULL);
COMMENT ON COLUMN messaging.referral_event.currency_code IS 'Nullable: required when reward_amount is set (ISO 4217), otherwise NULL.';

ALTER TABLE gig.gig_worker_service
    ADD COLUMN currency_code CHAR(3),
    ADD CONSTRAINT ck_gig_worker_service_currency_format CHECK (currency_code IS NULL OR currency_code ~ '^[A-Z]{3}$'),
    ADD CONSTRAINT ck_gig_worker_service_rate_currency CHECK (rate_override IS NULL OR currency_code IS NOT NULL);
COMMENT ON COLUMN gig.gig_worker_service.currency_code IS 'Nullable: required when rate_override is set (ISO 4217), otherwise NULL.';

-- 2. Language of user-entered text. A language code from the reference list, or NULL when not known.

ALTER TABLE recruitment.job_posting
    ADD COLUMN description_language_code VARCHAR(10),
    ADD CONSTRAINT fk_job_posting_description_language FOREIGN KEY (description_language_code)
        REFERENCES master.language (code) ON UPDATE RESTRICT ON DELETE RESTRICT;
COMMENT ON COLUMN recruitment.job_posting.description_language_code IS 'Nullable: language the description was written in, when known. The text is stored once, as entered.';

ALTER TABLE profile.candidate_profile
    ADD COLUMN summary_language_code VARCHAR(10),
    ADD CONSTRAINT fk_candidate_profile_summary_language FOREIGN KEY (summary_language_code)
        REFERENCES master.language (code) ON UPDATE RESTRICT ON DELETE RESTRICT;
COMMENT ON COLUMN profile.candidate_profile.summary_language_code IS 'Nullable: language the professional summary was written in, when known.';

ALTER TABLE messaging.community_post
    ADD COLUMN content_language_code VARCHAR(10),
    ADD CONSTRAINT fk_community_post_content_language FOREIGN KEY (content_language_code)
        REFERENCES master.language (code) ON UPDATE RESTRICT ON DELETE RESTRICT;
COMMENT ON COLUMN messaging.community_post.content_language_code IS 'Nullable: language the post was written in, when known.';

-- 3. Rebuild the active_ views so they pick up every current column
CREATE FUNCTION audit.refresh_active_views()
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    r RECORD;
    v_count INTEGER := 0;
BEGIN
    FOR r IN
        SELECT n.nspname AS s, substr(c.relname, 8) AS t
          FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE c.relkind = 'v' AND c.relname LIKE 'active\_%'
           AND n.nspname IN ('core','profile','recruitment','gig','messaging')
    LOOP
        EXECUTE format('CREATE OR REPLACE VIEW %I.%I AS SELECT * FROM %I.%I WHERE deleted_at IS NULL',
                       r.s, 'active_' || r.t, r.s, r.t);
        v_count := v_count + 1;
    END LOOP;
    RETURN v_count;
END;
$$;
COMMENT ON FUNCTION audit.refresh_active_views() IS 'Re-expands SELECT * in every active_ view. Run it in any migration that adds a column to a soft-deleted table.';

SELECT audit.refresh_active_views();
SELECT audit.sync_column_classification();

COMMIT;
