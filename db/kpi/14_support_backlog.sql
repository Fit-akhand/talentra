-- kpi_id: KPI-014
-- name: Open support tickets
-- persona: Support, Platform Operations (ACT-08)
-- type: leading
-- grain: ticket
-- unit: count
-- sources: messaging.support_ticket
-- refresh: real-time

SELECT priority, COUNT(*) AS open_tickets
FROM messaging.support_ticket
WHERE ticket_status IN ('open','in_progress','waiting_on_user')
GROUP BY priority
ORDER BY open_tickets DESC;
