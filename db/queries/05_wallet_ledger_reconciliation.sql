-- Query 05: Wallet Ledger Balance Reconciliation
-- Domain: commercial
-- Type: Financial Integrity Audit
-- Purpose: Verify cached wallet balance matches the append-only ledger transaction history exactly.

SELECT
    w.id AS wallet_id,
    w.organization_id,
    w.balance AS current_cached_balance,
    w.currency_code,
    COALESCE(SUM(
        CASE
            WHEN wl.entry_type IN ('credit', 'correction_credit') THEN wl.amount
            WHEN wl.entry_type IN ('debit', 'correction_debit') THEN -wl.amount
            ELSE 0.00
        END
    ), 0.00) AS computed_ledger_balance,
    COUNT(wl.id) AS total_ledger_transactions,
    MAX(wl.recorded_at) AS last_transaction_at,
    CASE
        WHEN w.balance = COALESCE(SUM(
            CASE
                WHEN wl.entry_type IN ('credit', 'correction_credit') THEN wl.amount
                WHEN wl.entry_type IN ('debit', 'correction_debit') THEN -wl.amount
                ELSE 0.00
            END
        ), 0.00) THEN TRUE
        ELSE FALSE
    END AS is_reconciled
FROM commercial.wallet w
LEFT JOIN commercial.wallet_ledger wl ON w.id = wl.wallet_id
WHERE w.organization_id = 1
GROUP BY w.id, w.organization_id, w.balance, w.currency_code;
