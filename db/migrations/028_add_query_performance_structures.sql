BEGIN;
-- =============================================================================
-- Migration 028: Structures that keep the two slowest queries fast at the docket's laptop scale
-- Domain:        performance (docket section 10 / backlog B71-B74; NFR-001, NFR-004)
-- Depends on:    001-027
--
-- Measured on the laptop-scale dataset (1,000,000 candidates, 100,000 jobs, 5,000,000 applications, 9.6 million
-- application events, 11 GB), PostgreSQL 16.15, default configuration:
--
--   Query 01 candidate search    491 ms  ->    2 ms   query rewritten + the index below
--   Query 02 job feed             50 ms  ->    2 ms   query rewritten; no new index was needed
--   Query 10 time-to-hire KPI   3,268 ms ->  0.4 ms   reads the summary below instead of scanning every event
--
-- Query 01 and 02 returned the same profiles and jobs, in the same order, before and after. The rewrites pick the
-- 50 rows to return first (using an ordered index and stopping early) and only then aggregate their detail, where
-- the originals aggregated every matching row and then sorted the lot on disk.
-- Query 10 trades freshness for speed: the summary is rebuilt by analytics.refresh_reporting_marts(), which already
-- runs after each mart load. The refresh costs about 3 seconds at this scale.
-- =============================================================================

-- Query 01: walk candidates in the order the query returns them, so the first 50 qualifying rows end the scan.
-- The predicate repeats the query's filter exactly; the planner can only use a partial index whose WHERE the query implies.
CREATE INDEX idx_candidate_profile_search_order
    ON profile.candidate_profile (total_experience_years DESC, id DESC)
    WHERE profile_status = 'active' AND visibility IN ('recruiters', 'public');

-- Query 10: one row per industry, built from the events once instead of on every call.
-- 'Unspecified' stands in for jobs with no industry so the unique key is never NULL (REFRESH ... CONCURRENTLY needs one).
CREATE MATERIALIZED VIEW analytics.mv_hiring_funnel_by_industry AS
WITH per_application AS (
    SELECT f.job_posting_key,
           f.candidate_application_id,
           MIN(f.event_timestamp)                                          AS applied_at,
           BOOL_OR(f.new_status = 'shortlisted')                           AS reached_shortlisted,
           BOOL_OR(f.new_status = 'interviewed')                           AS reached_interviewed,
           BOOL_OR(f.new_status = 'offered')                               AS reached_offered,
           MIN(f.event_timestamp) FILTER (WHERE f.new_status = 'joined')   AS joined_at
      FROM analytics.fact_application_event f
     GROUP BY f.job_posting_key, f.candidate_application_id
)
SELECT COALESCE(j.industry_name, 'Unspecified')                           AS industry_name,
       COUNT(*)                                                           AS total_applications,
       COUNT(*) FILTER (WHERE a.reached_shortlisted)                      AS shortlisted_count,
       COUNT(*) FILTER (WHERE a.reached_interviewed)                      AS interviewed_count,
       COUNT(*) FILTER (WHERE a.reached_offered)                          AS offered_count,
       COUNT(a.joined_at)                                                 AS hired_count,
       ROUND(AVG(EXTRACT(EPOCH FROM (a.joined_at - a.applied_at)) / 3600.0)::NUMERIC, 2) AS avg_time_to_hire_hours
  FROM per_application a
  JOIN analytics.dim_job_posting j ON j.job_posting_key = a.job_posting_key
 GROUP BY COALESCE(j.industry_name, 'Unspecified')
WITH DATA;

CREATE UNIQUE INDEX uq_mv_hiring_funnel_by_industry ON analytics.mv_hiring_funnel_by_industry (industry_name);
COMMENT ON MATERIALIZED VIEW analytics.mv_hiring_funnel_by_industry IS
    'Funnel counts and average hours from application to joining, per industry. Rebuilt by analytics.refresh_reporting_marts(); Query 10 reads it.';
GRANT SELECT ON analytics.mv_hiring_funnel_by_industry TO talentra_app, talentra_readonly, talentra_analyst;

-- The refresh now covers all three summaries. A view that has never been populated cannot be refreshed CONCURRENTLY.
CREATE OR REPLACE PROCEDURE analytics.refresh_reporting_marts()
LANGUAGE plpgsql
AS $$
DECLARE
    v_view TEXT;
BEGIN
    CALL analytics.load_reporting_marts();
    FOREACH v_view IN ARRAY ARRAY['mv_hiring_funnel_summary', 'mv_gig_fulfilment_summary', 'mv_hiring_funnel_by_industry']
    LOOP
        IF (SELECT ispopulated FROM pg_matviews WHERE schemaname = 'analytics' AND matviewname = v_view) THEN
            EXECUTE format('REFRESH MATERIALIZED VIEW CONCURRENTLY analytics.%I', v_view);
        ELSE
            EXECUTE format('REFRESH MATERIALIZED VIEW analytics.%I', v_view);
        END IF;
    END LOOP;
END;
$$;

SELECT audit.sync_column_classification();

COMMIT;
