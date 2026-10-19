-- Query 11: Gig Revenue and Ratings Summary
-- Domain: gig / analytics
-- Type: Revenue & Marketplace Quality Summary
-- Purpose: Aggregate total platform earnings, completed projects, and average rating per currency and status.

SELECT
    ga.currency_code,
    ga.assignment_status,
    COUNT(ga.id) AS total_assignments,
    ROUND(SUM(ga.agreed_amount), 2) AS total_agreed_volume,
    COALESCE(ROUND(SUM(ge.total_earnings), 2), 0.00) AS total_reconciled_earnings,
    ROUND(AVG(gr.rating_score), 2) AS avg_client_rating
FROM gig.gig_assignment ga
LEFT JOIN gig.gig_external_earnings ge ON ga.id = ge.gig_assignment_id
LEFT JOIN gig.gig_rating gr ON ga.id = gr.gig_assignment_id
GROUP BY ga.currency_code, ga.assignment_status
ORDER BY total_agreed_volume DESC;
