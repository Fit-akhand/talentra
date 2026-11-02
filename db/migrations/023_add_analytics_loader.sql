-- =============================================================================
-- Migration 023: Star-schema load process
-- Domain:        analytics (docket Rule Group 8 "analytical objects"; lifecycle steps 29-30; NFR-004)
-- Depends on:    001-022
--
-- Migration 019 created the dimensions and facts, but nothing loaded them except the test-data
-- generator, and analytics.refresh_reporting_marts() only refreshed two materialised views. This
-- migration adds the missing load:
--
--   analytics.ensure_dim_date(from, to)       extends the calendar (019 stopped at 2027-12-31)
--   analytics.load_reporting_marts()          loads dimensions (Type-2 where tracked) and facts
--   analytics.refresh_reporting_marts()       now loads first, then refreshes the materialised views
--
-- The load is incremental and idempotent: running it twice loads nothing the second time. Each fact
-- row records the id of the operational row it came from, with a unique constraint, so a replay
-- cannot double-count.
-- =============================================================================

BEGIN;

ALTER TABLE analytics.fact_application_event
    ADD COLUMN source_history_id BIGINT,
    ADD CONSTRAINT uq_fact_app_event_source_history UNIQUE (source_history_id);
COMMENT ON COLUMN analytics.fact_application_event.source_history_id IS
    'recruitment.application_status_history.id this event was loaded from. NULL only for rows loaded before migration 023.';

ALTER TABLE analytics.fact_wallet_transaction
    ADD COLUMN source_wallet_ledger_id BIGINT,
    ADD CONSTRAINT uq_fact_wallet_tx_source_ledger UNIQUE (source_wallet_ledger_id);
COMMENT ON COLUMN analytics.fact_wallet_transaction.source_wallet_ledger_id IS
    'commercial.wallet_ledger.id this row was loaded from. NULL only for rows loaded before migration 023.';

ALTER TABLE analytics.fact_gig_performance
    ADD CONSTRAINT uq_fact_gig_performance_assignment UNIQUE (gig_assignment_id);

-- -----------------------------------------------------------------------------
-- Calendar
-- -----------------------------------------------------------------------------
CREATE FUNCTION analytics.ensure_dim_date(p_from DATE, p_to DATE)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_added INTEGER;
BEGIN
    INSERT INTO analytics.dim_date (date_key, calendar_date, day_of_month, day_name, day_of_week,
                                    month_number, month_name, quarter_number, year_number, is_weekend)
    SELECT TO_CHAR(d, 'YYYYMMDD')::INTEGER, d::DATE, EXTRACT(DAY FROM d)::INTEGER, TO_CHAR(d, 'Day'),
           EXTRACT(ISODOW FROM d)::INTEGER, EXTRACT(MONTH FROM d)::INTEGER, TO_CHAR(d, 'Month'),
           EXTRACT(QUARTER FROM d)::INTEGER, EXTRACT(YEAR FROM d)::INTEGER,
           EXTRACT(ISODOW FROM d) IN (6, 7)
      FROM generate_series(p_from, p_to, INTERVAL '1 day') AS d
    ON CONFLICT (date_key) DO NOTHING;
    GET DIAGNOSTICS v_added = ROW_COUNT;
    RETURN v_added;
END;
$$;

-- -----------------------------------------------------------------------------
-- Loader
-- -----------------------------------------------------------------------------
CREATE PROCEDURE analytics.load_reporting_marts()
LANGUAGE plpgsql
AS $$
DECLARE
    v_from DATE;
BEGIN
    -- calendar: from the earliest operational date we will reference to a year ahead
    SELECT LEAST(CURRENT_DATE,
                 COALESCE((SELECT MIN(applied_at)::DATE FROM recruitment.candidate_application), CURRENT_DATE),
                 COALESCE((SELECT MIN(recorded_at)::DATE FROM commercial.wallet_ledger), CURRENT_DATE))
      INTO v_from;
    PERFORM analytics.ensure_dim_date(v_from, (CURRENT_DATE + INTERVAL '1 year')::DATE);

    -- ---- dim_organization (Type 2: name, type, country, industry) -------------------------------
    -- the work tables are dropped on commit, but a caller may run the load twice in one transaction
    DROP TABLE IF EXISTS tmp_org_src;
    DROP TABLE IF EXISTS tmp_candidate_src;
    CREATE TEMP TABLE tmp_org_src ON COMMIT DROP AS
    SELECT o.id AS organization_id, o.name, o.organization_type, c.iso_alpha3 AS country_code, ind.name AS industry_name
      FROM recruitment.organization o
      LEFT JOIN master.country c ON c.id = o.country_id
      LEFT JOIN LATERAL (
            SELECT i.name FROM recruitment.job_posting j JOIN master.industry i ON i.id = j.industry_id
             WHERE j.organization_id = o.id GROUP BY i.name ORDER BY COUNT(*) DESC, i.name LIMIT 1) ind ON TRUE;

    UPDATE analytics.dim_organization d
       SET is_current = FALSE, valid_to = CURRENT_TIMESTAMP
      FROM tmp_org_src s
     WHERE d.organization_id = s.organization_id AND d.is_current
       AND (d.organization_name, d.organization_type, d.country_code, d.industry_name)
           IS DISTINCT FROM (s.name, s.organization_type, s.country_code, s.industry_name);

    INSERT INTO analytics.dim_organization (organization_id, organization_name, organization_type, country_code, industry_name, valid_from)
    SELECT s.organization_id, s.name, s.organization_type, s.country_code, s.industry_name, CURRENT_TIMESTAMP
      FROM tmp_org_src s
     WHERE NOT EXISTS (SELECT 1 FROM analytics.dim_organization d WHERE d.organization_id = s.organization_id AND d.is_current);

    -- ---- dim_candidate (Type 2: city, experience, completeness, primary skill) -------------------
    CREATE TEMP TABLE tmp_candidate_src ON COMMIT DROP AS
    SELECT p.id AS candidate_profile_id,
           city.name AS current_city_name,
           p.total_experience_years,
           COALESCE(pc.total_score_percentage,
                    25.0 * (p.headline IS NOT NULL)::INT + 25.0 * (p.professional_summary IS NOT NULL)::INT
                  + 25.0 * EXISTS (SELECT 1 FROM profile.candidate_skill k WHERE k.candidate_profile_id = p.id)::INT
                  + 25.0 * (loc.city_id IS NOT NULL)::INT)::NUMERIC(5,2) AS completeness,
           sk.name AS primary_skill_name
      FROM profile.candidate_profile p
      LEFT JOIN profile.candidate_profile_completion pc ON pc.candidate_profile_id = p.id
      LEFT JOIN LATERAL (SELECT l.city_id FROM profile.candidate_location l
                          WHERE l.candidate_profile_id = p.id AND l.location_type = 'current' ORDER BY l.id LIMIT 1) loc ON TRUE
      LEFT JOIN master.city city ON city.id = loc.city_id
      LEFT JOIN LATERAL (SELECT s.name FROM profile.candidate_skill k JOIN master.skill s ON s.id = k.skill_id
                          WHERE k.candidate_profile_id = p.id ORDER BY k.is_primary DESC, k.id LIMIT 1) sk ON TRUE;

    UPDATE analytics.dim_candidate d
       SET is_current = FALSE, valid_to = CURRENT_TIMESTAMP
      FROM tmp_candidate_src s
     WHERE d.candidate_profile_id = s.candidate_profile_id AND d.is_current
       AND (d.current_city_name, d.total_experience_years, d.profile_completeness_percentage, d.primary_skill_name)
           IS DISTINCT FROM (s.current_city_name, s.total_experience_years, s.completeness, s.primary_skill_name);

    INSERT INTO analytics.dim_candidate (candidate_profile_id, current_city_name, total_experience_years,
                                         profile_completeness_percentage, primary_skill_name, valid_from)
    SELECT s.candidate_profile_id, s.current_city_name, s.total_experience_years, s.completeness, s.primary_skill_name, CURRENT_TIMESTAMP
      FROM tmp_candidate_src s
     WHERE NOT EXISTS (SELECT 1 FROM analytics.dim_candidate d WHERE d.candidate_profile_id = s.candidate_profile_id AND d.is_current);

    -- ---- dim_job_posting (Type 1: the latest description wins) ----------------------------------
    INSERT INTO analytics.dim_job_posting (job_posting_id, organization_key, job_title, job_role_name, industry_name,
                                           employment_type_code, work_type_code, currency_code, salary_min, salary_max, published_date_key)
    SELECT j.id, d.organization_key, j.title, r.name, i.name, et.code, wt.code, j.currency_code, j.salary_min, j.salary_max,
           CASE WHEN j.published_at IS NULL THEN NULL ELSE TO_CHAR(j.published_at, 'YYYYMMDD')::INTEGER END
      FROM recruitment.job_posting j
      JOIN analytics.dim_organization d ON d.organization_id = j.organization_id AND d.is_current
      LEFT JOIN master.job_role r ON r.id = j.job_role_id
      LEFT JOIN master.industry i ON i.id = j.industry_id
      LEFT JOIN master.employment_type et ON et.id = j.employment_type_id
      LEFT JOIN master.work_type wt ON wt.id = j.work_type_id
    ON CONFLICT (job_posting_id) DO UPDATE
       SET job_title = EXCLUDED.job_title, job_role_name = EXCLUDED.job_role_name, industry_name = EXCLUDED.industry_name,
           employment_type_code = EXCLUDED.employment_type_code, work_type_code = EXCLUDED.work_type_code,
           currency_code = EXCLUDED.currency_code, salary_min = EXCLUDED.salary_min, salary_max = EXCLUDED.salary_max,
           published_date_key = EXCLUDED.published_date_key;

    -- ---- fact_application_event: one row per status change, with time spent in the previous status ---
    INSERT INTO analytics.fact_application_event (candidate_application_id, date_key, job_posting_key, candidate_key, organization_key,
                                                  previous_status, new_status, status_cycle_time_hours, is_terminal_state,
                                                  event_timestamp, source_history_id)
    SELECT h.candidate_application_id,
           TO_CHAR(h.changed_at, 'YYYYMMDD')::INTEGER,
           dj.job_posting_key, dc.candidate_key, dj.organization_key,
           h.previous_status, h.new_status,
           ROUND((EXTRACT(EPOCH FROM (h.changed_at - LAG(h.changed_at) OVER (PARTITION BY h.candidate_application_id ORDER BY h.changed_at, h.id))) / 3600.0)::NUMERIC, 2),
           h.new_status IN ('joined', 'rejected', 'withdrawn'),
           h.changed_at, h.id
      FROM recruitment.application_status_history h
      JOIN recruitment.candidate_application a ON a.id = h.candidate_application_id
      JOIN analytics.dim_job_posting dj ON dj.job_posting_id = a.job_posting_id
      JOIN analytics.dim_candidate dc ON dc.candidate_profile_id = a.candidate_profile_id AND dc.is_current
     WHERE NOT EXISTS (SELECT 1 FROM analytics.fact_application_event f WHERE f.source_history_id = h.id);

    -- ---- fact_gig_performance: one row per finished assignment ------------------------------------
    INSERT INTO analytics.fact_gig_performance (gig_assignment_id, organization_key, completion_date_key, agreed_amount,
                                                actual_reconciled_earnings, currency_code, duration_days, client_rating, assignment_status)
    SELECT ga.id, d.organization_key,
           TO_CHAR(ga.assigned_end_date, 'YYYYMMDD')::INTEGER,
           ga.agreed_amount, COALESCE(e.total_earnings, 0), ga.currency_code,
           (ga.assigned_end_date - ga.assigned_start_date + 1),
           r.rating_score, ga.assignment_status
      FROM gig.gig_assignment ga
      JOIN gig.gig_request gr ON gr.id = ga.gig_request_id
      JOIN analytics.dim_organization d ON d.organization_id = gr.organization_id AND d.is_current
      LEFT JOIN gig.gig_external_earnings e ON e.gig_assignment_id = ga.id
      LEFT JOIN gig.gig_rating r ON r.gig_assignment_id = ga.id
     WHERE ga.assignment_status IN ('completed', 'terminated')
       AND NOT EXISTS (SELECT 1 FROM analytics.fact_gig_performance f WHERE f.gig_assignment_id = ga.id)
    ON CONFLICT (gig_assignment_id) DO NOTHING;

    -- ---- fact_wallet_transaction: one row per ledger entry ----------------------------------------
    INSERT INTO analytics.fact_wallet_transaction (wallet_id, organization_key, date_key, entry_type, amount, currency_code,
                                                   reference_type, recorded_timestamp, source_wallet_ledger_id)
    SELECT l.wallet_id, d.organization_key, TO_CHAR(l.recorded_at, 'YYYYMMDD')::INTEGER, l.entry_type, l.amount,
           l.currency_code, l.reference_type, l.recorded_at, l.id
      FROM commercial.wallet_ledger l
      JOIN commercial.wallet w ON w.id = l.wallet_id
      JOIN analytics.dim_organization d ON d.organization_id = w.organization_id AND d.is_current
     WHERE NOT EXISTS (SELECT 1 FROM analytics.fact_wallet_transaction f WHERE f.source_wallet_ledger_id = l.id);
END;
$$;

COMMENT ON PROCEDURE analytics.load_reporting_marts() IS
    'Incremental, idempotent load of dim_* and fact_* from operational tables. Run by analytics.refresh_reporting_marts().';

-- -----------------------------------------------------------------------------
-- refresh_reporting_marts: load first, then refresh the aggregates built on the facts
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE analytics.refresh_reporting_marts()
LANGUAGE plpgsql
AS $$
BEGIN
    CALL analytics.load_reporting_marts();
    -- CONCURRENTLY cannot run on a view that has never been populated; the first refresh must be plain
    IF (SELECT ispopulated FROM pg_matviews WHERE schemaname = 'analytics' AND matviewname = 'mv_hiring_funnel_summary') THEN
        REFRESH MATERIALIZED VIEW CONCURRENTLY analytics.mv_hiring_funnel_summary;
    ELSE
        REFRESH MATERIALIZED VIEW analytics.mv_hiring_funnel_summary;
    END IF;
    IF (SELECT ispopulated FROM pg_matviews WHERE schemaname = 'analytics' AND matviewname = 'mv_gig_fulfilment_summary') THEN
        REFRESH MATERIALIZED VIEW CONCURRENTLY analytics.mv_gig_fulfilment_summary;
    ELSE
        REFRESH MATERIALIZED VIEW analytics.mv_gig_fulfilment_summary;
    END IF;
END;
$$;

COMMIT;
