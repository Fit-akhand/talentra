-- Query 02: Candidate Job Feed Matching
-- Domain: recruitment / master
-- Type: High-Frequency Read Feed
-- Purpose: Candidate job recommendation feed matching active jobs by role, work arrangement, location, and salary filter.

SELECT
    jp.id AS job_posting_id,
    jp.title,
    o.name AS organization_name,
    et.name AS employment_type,
    wt.name AS work_type,
    c.name AS city_name,
    jp.salary_min,
    jp.salary_max,
    jp.currency_code,
    jp.published_at,
    COUNT(jsr.id) AS required_skills_count
FROM recruitment.job_posting jp
JOIN recruitment.organization o ON jp.organization_id = o.id
JOIN master.employment_type et ON jp.employment_type_id = et.id
JOIN master.work_type wt ON jp.work_type_id = wt.id
LEFT JOIN master.city c ON jp.city_id = c.id
LEFT JOIN recruitment.job_skill_requirement jsr ON jp.id = jsr.job_posting_id AND jsr.is_required = TRUE
WHERE jp.job_status = 'published'
  AND (jp.application_deadline IS NULL OR jp.application_deadline > CURRENT_TIMESTAMP)
  AND (wt.code IN ('remote', 'hybrid'))
GROUP BY jp.id, jp.title, o.name, et.name, wt.name, c.name, jp.salary_min, jp.salary_max, jp.currency_code, jp.published_at
ORDER BY jp.published_at DESC
LIMIT 50;
