-- kpi_id: KPI-011
-- name: Notification delivery success rate
-- persona: Platform Operations (ACT-08)
-- type: lagging
-- grain: delivery
-- unit: percent
-- sources: messaging.notification_delivery
-- refresh: real-time

SELECT ROUND(100.0 * COUNT(*) FILTER (WHERE delivery_status IN ('delivered','read'))
       / NULLIF(COUNT(*) FILTER (WHERE delivery_status <> 'queued'), 0), 2) AS delivered_pct_of_attempted,
       COUNT(*) AS total_deliveries
FROM messaging.notification_delivery;
