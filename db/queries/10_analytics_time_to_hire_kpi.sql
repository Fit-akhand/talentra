-- Query 10: Analytics Time-to-Hire and Funnel Conversion KPI
-- Domain: analytics
-- Type: Analytical KPI Aggregation
-- Purpose: Average time from application to joining, and how many applications reached each stage, by industry.
--
-- Reads analytics.mv_hiring_funnel_by_industry (migration 028), which analytics.refresh_reporting_marts() rebuilds from
-- fact_application_event. Time to hire is the elapsed time from the first event (applied) to the joined event. An earlier
-- version averaged the cycle time of the joined row, which is the time spent in the previous stage, and then aggregated
-- every event on each call (3.3 s at laptop scale, 0.4 ms now). The numbers are as fresh as the last refresh.

SELECT
    industry_name,
    total_applications,
    shortlisted_count,
    interviewed_count,
    offered_count,
    hired_count,
    avg_time_to_hire_hours
FROM analytics.mv_hiring_funnel_by_industry
ORDER BY hired_count DESC, total_applications DESC;
