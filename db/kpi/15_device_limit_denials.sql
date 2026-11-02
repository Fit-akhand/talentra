-- kpi_id: KPI-015
-- name: Device-limit denials recorded in the audit trail
-- persona: Security / Platform Operations (ACT-08)
-- type: leading
-- grain: audit event
-- unit: count
-- sources: audit.audit_event
-- refresh: real-time

SELECT COUNT(*) AS device_limit_audit_events
FROM audit.audit_event
WHERE action ILIKE '%limit%' OR action ILIKE '%device%';
