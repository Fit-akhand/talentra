-- Query 07: Non-Overlapping Gig Worker Matching
-- Domain: gig / master
-- Type: Complex Range Search
-- Purpose: Find available gig workers with matching skill whose calendar has availability and NO overlapping active assignments.

SELECT
    gwp.id AS gig_worker_profile_id,
    gwp.headline,
    gwp.hourly_rate,
    gwp.currency_code,
    gwp.average_rating,
    gwp.total_completed_gigs
FROM gig.gig_worker_profile gwp
JOIN gig.gig_worker_service gws ON gwp.id = gws.gig_worker_profile_id
JOIN master.skill s ON gws.skill_id = s.id
WHERE gwp.is_available = TRUE
  AND s.normalized_name = 'python'
  -- Verify worker has declared availability spanning target project window ('2026-11-01' to '2026-11-15')
  AND EXISTS (
      SELECT 1
      FROM gig.gig_worker_availability gwa
      WHERE gwa.gig_worker_profile_id = gwp.id
        AND gwa.available_from <= '2026-11-01'
        AND gwa.available_to >= '2026-11-15'
  )
  -- Verify NO active gig assignment overlaps target window
  AND NOT EXISTS (
      SELECT 1
      FROM gig.gig_assignment ga
      WHERE ga.gig_worker_profile_id = gwp.id
        AND ga.assignment_status = 'active'
        AND daterange(ga.assigned_start_date, ga.assigned_end_date, '[]') && daterange('2026-11-01'::DATE, '2026-11-15'::DATE, '[]')
  )
ORDER BY gwp.average_rating DESC NULLS LAST, gwp.total_completed_gigs DESC
LIMIT 25;
