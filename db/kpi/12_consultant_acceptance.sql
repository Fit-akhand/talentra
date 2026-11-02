-- kpi_id: KPI-012
-- name: Consultant submission acceptance rate
-- persona: Consultant (ACT-05), Employer
-- type: lagging
-- grain: submission
-- unit: percent
-- sources: sourcing.sourcing_submission
-- refresh: real-time

SELECT ROUND(100.0 * COUNT(*) FILTER (WHERE submission_status IN ('accepted','hired'))
       / NULLIF(COUNT(*), 0), 2) AS accepted_pct,
       COUNT(*) AS submissions
FROM sourcing.sourcing_submission;
