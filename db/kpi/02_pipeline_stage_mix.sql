-- kpi_id: KPI-002
-- name: Pipeline stage mix
-- persona: Recruiter (ACT-02)
-- type: leading
-- grain: application status
-- unit: percent
-- sources: recruitment.candidate_application
-- refresh: real-time

SELECT application_status,
       COUNT(*) AS applications,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_all
FROM recruitment.candidate_application
GROUP BY application_status
ORDER BY applications DESC;
