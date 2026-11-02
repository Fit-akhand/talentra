-- kpi_id: KPI-007
-- name: Wallets that do not reconcile to their ledger
-- persona: Finance / Platform Operations (ACT-08)
-- type: lagging
-- grain: wallet
-- unit: count (target 0)
-- sources: commercial.wallet, commercial.wallet_ledger
-- refresh: daily

SELECT COUNT(*) AS unreconciled_wallets
FROM commercial.wallet w
WHERE w.balance IS DISTINCT FROM COALESCE(
    (SELECT l.balance_after FROM commercial.wallet_ledger l WHERE l.wallet_id = w.id ORDER BY l.id DESC LIMIT 1), 0);
