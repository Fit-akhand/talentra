-- Query 03: Recruiter Pipeline Funnel
-- Domain: recruitment
-- Type: Operational Funnel Aggregation
-- Purpose: Recruiter dashboard aggregation displaying applicants by stage for an active job requirement.

SELECT
    ca.application_status,
    COUNT(ca.id) AS candidate_count,
    ROUND(
        AVG(EXTRACT(EPOCH FROM (ca.last_status_changed_at - ca.applied_at)) / 3600.0)::NUMERIC,
        2
    ) AS avg_hours_in_pipeline,
    MAX(ca.applied_at) AS latest_application_time
FROM recruitment.candidate_application ca
WHERE ca.job_posting_id = 1
GROUP BY ca.application_status
ORDER BY
    CASE ca.application_status
        WHEN 'applied' THEN 1
        WHEN 'shortlisted' THEN 2
        WHEN 'interviewed' THEN 3
        WHEN 'offered' THEN 4
        WHEN 'joined' THEN 5
        WHEN 'rejected' THEN 6
        ELSE 7
    END;
