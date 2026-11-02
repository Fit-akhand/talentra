-- kpi_id: KPI-008
-- name: Credit movement by type
-- persona: Finance, Employer
-- type: lagging
-- grain: entry type x reference type
-- unit: currency amount
-- sources: commercial.wallet_ledger
-- refresh: real-time

SELECT entry_type, reference_type, currency_code, COUNT(*) AS entries, SUM(amount) AS total_amount
FROM commercial.wallet_ledger
GROUP BY entry_type, reference_type, currency_code
ORDER BY total_amount DESC;
