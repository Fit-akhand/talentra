-- kpi_id: KPI-003
-- name: Average time to hire (hours)
-- persona: Employer (ACT-02), Executive
-- type: lagging
-- grain: joined application
-- unit: hours
-- sources: recruitment.candidate_application
-- refresh: real-time

SELECT ROUND(AVG(EXTRACT(EPOCH FROM (last_status_changed_at - applied_at)) / 3600.0)::numeric, 2) AS avg_hours_applied_to_joined,
       COUNT(*) AS joined_applications
FROM recruitment.candidate_application
WHERE application_status = 'joined';
