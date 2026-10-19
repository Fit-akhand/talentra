-- Query 10: Analytics Time-to-Hire and Funnel Conversion KPI
-- Domain: analytics
-- Type: Analytical KPI Aggregation
-- Purpose: Compute average cycle times and conversion drop-offs across hiring stages by industry.

SELECT
    j.industry_name,
    COUNT(DISTINCT f.candidate_application_id) AS total_applications,
    COUNT(DISTINCT CASE WHEN f.new_status = 'shortlisted' THEN f.candidate_application_id END) AS shortlisted_count,
    COUNT(DISTINCT CASE WHEN f.new_status = 'interviewed' THEN f.candidate_application_id END) AS interviewed_count,
    COUNT(DISTINCT CASE WHEN f.new_status = 'offered' THEN f.candidate_application_id END) AS offered_count,
    COUNT(DISTINCT CASE WHEN f.new_status = 'joined' THEN f.candidate_application_id END) AS hired_count,
    ROUND(
        AVG(CASE WHEN f.new_status = 'joined' THEN f.status_cycle_time_hours END),
        2
    ) AS avg_time_to_hire_hours
FROM analytics.fact_application_event f
JOIN analytics.dim_job_posting j ON f.job_posting_key = j.job_posting_key
GROUP BY j.industry_name
ORDER BY hired_count DESC, total_applications DESC;
