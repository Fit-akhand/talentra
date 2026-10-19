-- Query 09: High-Volume Notification Delivery Retrieval
-- Domain: messaging
-- Type: User Communication Feed
-- Purpose: Fast paginated retrieval of unread and recent notifications for a user.

SELECT
    nd.id AS notification_id,
    nd.channel,
    nd.subject,
    nd.body_snippet,
    nd.delivery_status,
    nd.sent_at,
    nd.read_at
FROM messaging.notification_delivery nd
WHERE nd.recipient_user_account_id = 1
ORDER BY nd.created_at DESC
LIMIT 20;
