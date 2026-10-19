-- Query 04: Concurrent Session Validation
-- Domain: core / commercial
-- Type: Critical Authentication Path
-- Purpose: Evaluate user active devices and session limits against licence entitlements during login.

SELECT
    u.id AS user_account_id,
    u.email,
    u.account_status,
    COALESCE(MAX(sl.max_devices_per_user), 2) AS max_devices_allowed,
    COUNT(DISTINCT s.device_identifier) AS current_active_devices_count,
    ARRAY_AGG(DISTINCT s.device_identifier) FILTER (WHERE s.device_identifier IS NOT NULL) AS active_devices
FROM core.user_account u
LEFT JOIN commercial.licence_seat_allocation lsa ON u.id = lsa.user_account_id AND lsa.revoked_at IS NULL
LEFT JOIN commercial.subscription_licence sl ON lsa.subscription_licence_id = sl.id AND sl.licence_status = 'active'
LEFT JOIN core.user_session s ON u.id = s.user_account_id AND s.ended_at IS NULL AND s.revoked_at IS NULL
WHERE u.id = 1
GROUP BY u.id, u.email, u.account_status;
