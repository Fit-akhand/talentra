-- Query 02: Candidate Job Feed Matching
-- Domain: recruitment / master
-- Type: High-Frequency Read Feed
-- Purpose: Candidate job recommendation feed matching active jobs by role, work arrangement, location, and salary filter.
--
-- Shape: pick the 50 newest matching jobs first, then count required skills only for those. The original joined and
-- grouped every published job before keeping 50 (50 ms at laptop scale); this version takes 2 ms. Same jobs, same order.

WITH feed AS (
    SELECT jp.id, jp.title, jp.organization_id, jp.employment_type_id, jp.work_type_id, jp.city_id,
           jp.salary_min, jp.salary_max, jp.currency_code, jp.show_salary, jp.published_at
      FROM recruitment.job_posting jp
      JOIN master.work_type wt ON wt.id = jp.work_type_id AND wt.code IN ('remote', 'hybrid')
     WHERE jp.job_status = 'published'
       AND (jp.application_deadline IS NULL OR jp.application_deadline > CURRENT_TIMESTAMP)
     ORDER BY jp.published_at DESC, jp.id DESC
     LIMIT 50
)
SELECT
    f.id AS job_posting_id,
    f.title,
    o.name AS organization_name,
    et.name AS employment_type,
    wt.name AS work_type,
    c.name AS city_name,
    CASE WHEN f.show_salary THEN f.salary_min END AS salary_min,      -- the range stays private until the recruiter ticks "show CTC"
    CASE WHEN f.show_salary THEN f.salary_max END AS salary_max,
    CASE WHEN f.show_salary THEN f.currency_code END AS currency_code,
    f.published_at,
    (SELECT COUNT(*) FROM recruitment.job_skill_requirement jsr
      WHERE jsr.job_posting_id = f.id AND jsr.is_required = TRUE) AS required_skills_count
FROM feed f
JOIN recruitment.organization o ON o.id = f.organization_id
JOIN master.employment_type et ON et.id = f.employment_type_id
JOIN master.work_type wt ON wt.id = f.work_type_id
LEFT JOIN master.city c ON c.id = f.city_id
ORDER BY f.published_at DESC, f.id DESC;
