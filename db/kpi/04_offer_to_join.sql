-- kpi_id: KPI-004
-- name: Offer-to-join rate
-- persona: Employer (ACT-02)
-- type: lagging
-- grain: application
-- unit: percent
-- sources: recruitment.application_status_history
-- refresh: real-time

SELECT ROUND(100.0 * COUNT(DISTINCT CASE WHEN new_status = 'joined' THEN candidate_application_id END)
       / NULLIF(COUNT(DISTINCT CASE WHEN new_status = 'offered' THEN candidate_application_id END), 0), 2) AS offer_to_join_pct
FROM recruitment.application_status_history;
