-- Query 01: Candidate Multicriteria Sourcing Filter
-- Domain: profile / master
-- Type: Lookup & Sourcing Search
-- Purpose: Find active candidates matching required skills, minimum experience, and location with visibility restrictions.

SELECT
    cp.id AS candidate_profile_id,
    cp.headline,
    cp.total_experience_years,
    cl.city_id,
    c.name AS city_name,
    ARRAY_AGG(s.name ORDER BY cs.is_primary DESC, cs.proficiency_level) AS matching_skills
FROM profile.candidate_profile cp
JOIN profile.candidate_skill cs ON cp.id = cs.candidate_profile_id
JOIN master.skill s ON cs.skill_id = s.id
LEFT JOIN profile.candidate_location cl ON cp.id = cl.candidate_profile_id AND cl.location_type = 'current'
LEFT JOIN master.city c ON cl.city_id = c.id
WHERE cp.profile_status = 'active'
  AND cp.visibility IN ('recruiters', 'public')
  AND cp.total_experience_years >= 3.0
  AND s.normalized_name IN ('postgresql', 'python', 'docker')
GROUP BY cp.id, cp.headline, cp.total_experience_years, cl.city_id, c.name
HAVING COUNT(DISTINCT s.id) >= 1
ORDER BY cp.total_experience_years DESC, cp.id DESC
LIMIT 50;
