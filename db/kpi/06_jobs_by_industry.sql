-- kpi_id: KPI-006
-- name: Published jobs by industry
-- persona: Executive, Employer
-- type: leading
-- grain: industry
-- unit: count
-- sources: recruitment.job_posting, master.industry
-- refresh: real-time

SELECT i.name AS industry, COUNT(*) AS published_jobs
FROM recruitment.job_posting j
JOIN master.industry i ON i.id = j.industry_id
WHERE j.job_status = 'published'
GROUP BY i.name
ORDER BY published_jobs DESC;
