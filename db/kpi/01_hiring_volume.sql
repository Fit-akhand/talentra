-- kpi_id: KPI-001
-- name: Applications per published job
-- persona: Employer / Recruiter (ACT-02)
-- type: lagging
-- grain: count / job
-- unit: ratio
-- sources: recruitment.job_posting, recruitment.candidate_application
-- refresh: real-time

SELECT ROUND(COUNT(a.id)::numeric / NULLIF(COUNT(DISTINCT j.id), 0), 2) AS applications_per_published_job
FROM recruitment.job_posting j
LEFT JOIN recruitment.candidate_application a ON a.job_posting_id = j.id
WHERE j.job_status = 'published';
