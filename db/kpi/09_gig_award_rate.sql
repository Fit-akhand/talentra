-- kpi_id: KPI-009
-- name: Gig request award rate
-- persona: Gig requester, Executive
-- type: lagging
-- grain: gig request
-- unit: percent
-- sources: gig.gig_request
-- refresh: real-time

SELECT ROUND(100.0 * COUNT(*) FILTER (WHERE request_status IN ('awarded','in_progress','completed'))
       / NULLIF(COUNT(*) FILTER (WHERE request_status <> 'open'), 0), 2) AS award_rate_of_closed_requests_pct,
       COUNT(*) AS total_requests
FROM gig.gig_request;
