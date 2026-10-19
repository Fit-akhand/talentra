-- Query 06: Sourcing Outreach Filter with Block Exclusion
-- Domain: sourcing / core
-- Type: Outreach Security Check
-- Purpose: Find candidate candidates for outreach excluding any candidate who has blocked the recruiter or organization.

SELECT
    cp.id AS candidate_profile_id,
    cp.headline,
    u.email,
    cp.total_experience_years
FROM profile.candidate_profile cp
JOIN core.user_account u ON cp.user_account_id = u.id
JOIN profile.candidate_skill cs ON cp.id = cs.candidate_profile_id
JOIN master.skill s ON cs.skill_id = s.id
WHERE cp.profile_status = 'active'
  AND s.normalized_name = 'postgresql'
  AND NOT EXISTS (
      -- Exclude if candidate blocked this recruiter user or this recruiter organization
      SELECT 1
      FROM core.user_block ub
      WHERE ub.blocker_user_account_id = cp.user_account_id
        AND (ub.blocked_user_account_id = 2 OR ub.blocked_organization_id = 1)
  )
LIMIT 50;
