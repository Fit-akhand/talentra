-- Query 08: Candidate Profile Download Audit History
-- Domain: commercial / profile
-- Type: Compliance & Billing Audit Retrieval
-- Purpose: Retrieve append-only history of candidate profile downloads by recruiters with billing deductions.

SELECT
    dh.id AS download_history_id,
    dh.downloaded_at,
    o.name AS downloading_organization,
    u.email AS downloader_email,
    cp.headline AS candidate_headline,
    dh.credit_deduction_amount,
    dh.currency_code,
    dh.wallet_ledger_id
FROM commercial.candidate_profile_download_history dh
JOIN recruitment.organization o ON dh.organization_id = o.id
JOIN core.user_account u ON dh.downloader_user_account_id = u.id
JOIN profile.candidate_profile cp ON dh.candidate_profile_id = cp.id
WHERE dh.organization_id = 1
ORDER BY dh.downloaded_at DESC
LIMIT 50;
