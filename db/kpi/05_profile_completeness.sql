-- kpi_id: KPI-005
-- name: Average profile completeness
-- persona: Candidate (ACT-01), Product
-- type: leading
-- grain: current candidate dimension row
-- unit: percent
-- sources: analytics.dim_candidate
-- refresh: mart load

SELECT ROUND(AVG(profile_completeness_percentage), 2) AS avg_profile_completeness_pct
FROM analytics.dim_candidate
WHERE is_current;
