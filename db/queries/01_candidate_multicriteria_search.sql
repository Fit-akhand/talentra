-- Query 01: Candidate Multicriteria Sourcing Filter
-- Domain: profile / master
-- Type: Lookup & Sourcing Search
-- Purpose: Find active candidates matching required skills, minimum experience, and location with visibility restrictions.
--
-- Shape: choose the 50 profiles first, in the order they will be returned, then fetch their skills and city. The
-- original aggregated the skills of every matching candidate (313,000 at laptop scale) and sorted them on disk before
-- keeping 50 (491 ms); this version stops after 50 qualifying profiles (2 ms) using
-- idx_candidate_profile_search_order (migration 028). Same profiles, same order.

WITH top_profiles AS (
    SELECT cp.id, cp.headline, cp.total_experience_years
      FROM profile.candidate_profile cp
     WHERE cp.profile_status = 'active'
       AND cp.visibility IN ('recruiters', 'public')
       AND cp.total_experience_years >= 3.0
       AND EXISTS (SELECT 1
                     FROM profile.candidate_skill cs
                     JOIN master.skill s ON s.id = cs.skill_id
                    WHERE cs.candidate_profile_id = cp.id
                      AND s.normalized_name IN ('postgresql', 'python', 'docker'))
     ORDER BY cp.total_experience_years DESC, cp.id DESC
     LIMIT 50
)
SELECT
    t.id AS candidate_profile_id,
    t.headline,
    t.total_experience_years,
    cl.city_id,
    c.name AS city_name,
    (SELECT ARRAY_AGG(s.name ORDER BY cs.is_primary DESC, cs.proficiency_level, s.name)
       FROM profile.candidate_skill cs
       JOIN master.skill s ON s.id = cs.skill_id
      WHERE cs.candidate_profile_id = t.id
        AND s.normalized_name IN ('postgresql', 'python', 'docker')) AS matching_skills
FROM top_profiles t
LEFT JOIN profile.candidate_location cl ON cl.candidate_profile_id = t.id AND cl.location_type = 'current'
LEFT JOIN master.city c ON c.id = cl.city_id
ORDER BY t.total_experience_years DESC, t.id DESC;
