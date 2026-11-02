-- kpi_id: KPI-016
-- name: Profile-download credit spend
-- persona: Finance, Employer
-- type: lagging
-- grain: download
-- unit: currency amount
-- sources: commercial.candidate_profile_download_history
-- refresh: real-time

SELECT currency_code, COUNT(*) AS downloads, SUM(credit_deduction_amount) AS credits_spent
FROM commercial.candidate_profile_download_history
GROUP BY currency_code;
