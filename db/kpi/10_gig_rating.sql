-- kpi_id: KPI-010
-- name: Average gig client rating
-- persona: Gig requester, Gig worker
-- type: lagging
-- grain: rating
-- unit: score 0-5
-- sources: gig.gig_rating
-- refresh: real-time

SELECT ROUND(AVG(rating_score), 2) AS avg_rating, COUNT(*) AS ratings
FROM gig.gig_rating;
