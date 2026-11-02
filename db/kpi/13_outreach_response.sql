-- kpi_id: KPI-013
-- name: Outreach response rate
-- persona: Recruiter (ACT-02)
-- type: lagging
-- grain: outreach recipient
-- unit: percent
-- sources: sourcing.outreach_recipient
-- refresh: real-time

SELECT ROUND(100.0 * COUNT(*) FILTER (WHERE delivery_status = 'responded')
       / NULLIF(COUNT(*) FILTER (WHERE delivery_status IN ('sent','delivered','opened','responded')), 0), 2) AS response_pct,
       COUNT(*) AS recipients
FROM sourcing.outreach_recipient;
