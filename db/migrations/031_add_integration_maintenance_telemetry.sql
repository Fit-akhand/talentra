BEGIN;
-- =============================================================================
-- Migration 031: Integration boundaries with retry and dead-letter, scheduled maintenance, telemetry
-- Domain:        messaging (integration), audit (maintenance, telemetry)  -- NFR-008, NFR-017, NFR-020, NFR-026, NFR-027
-- Depends on:    001-030
--
-- Docket section 6 asks, for each of nine external boundaries: who owns the data, what is stored versus referenced, what
-- happens when the other side is down, how duplicates are prevented, and how the exchange is audited. Until now that was a
-- table in a document. This migration makes it executable:
--
--   messaging.integration_boundary   one row per boundary, holding those five answers
--   messaging.integration_event      every exchange: an idempotency key (duplicates cannot be stored twice), up to 3 attempts
--                                    with exponential backoff, then a dead letter that is visible and requeueable
--
-- It also adds what keeps the platform running without a person: a maintenance procedure (mart refresh, retention purge,
-- erasure of inactive accounts) with a run log, and operational views covering the four metric families the NFR names.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. The nine boundaries
-- -----------------------------------------------------------------------------
CREATE TABLE messaging.integration_boundary (
    id                    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code                  VARCHAR(40)  NOT NULL,
    name                  VARCHAR(100) NOT NULL,
    source_of_truth       VARCHAR(300) NOT NULL,
    stored_data           VARCHAR(500) NOT NULL,
    referenced_data       VARCHAR(500) NOT NULL,
    failure_behaviour     VARCHAR(500) NOT NULL,
    idempotency_rule      VARCHAR(300) NOT NULL,
    audit_rule            VARCHAR(300) NOT NULL,
    is_optional           BOOLEAN      NOT NULL DEFAULT FALSE,
    max_attempts          INTEGER      NOT NULL DEFAULT 3,
    base_backoff_seconds  INTEGER      NOT NULL DEFAULT 30,

    CONSTRAINT uq_integration_boundary_code UNIQUE (code),
    CONSTRAINT ck_integration_boundary_attempts CHECK (max_attempts BETWEEN 1 AND 10),
    CONSTRAINT ck_integration_boundary_backoff CHECK (base_backoff_seconds BETWEEN 1 AND 86400)
);
COMMENT ON TABLE messaging.integration_boundary IS 'Docket section 6: the nine external boundaries and the five answers required of each. The retry policy (attempts, backoff) is data, not code.';
COMMENT ON COLUMN messaging.integration_boundary.is_optional IS 'An optional boundary (the docket says to treat geolocation as optional) never blocks the feature that triggered it: a dead letter degrades quietly.';
SELECT audit.apply_standard_lifecycle('messaging', 'integration_boundary', 'reference');

INSERT INTO messaging.integration_boundary
    (code, name, source_of_truth, stored_data, referenced_data, failure_behaviour, idempotency_rule, audit_rule, is_optional, max_attempts, base_backoff_seconds) VALUES
 ('payment_gateway', 'Payment gateway',
  'Gateway for money movement; Talentra for orders, invoices and the wallet ledger',
  'Transaction reference, status, amount, currency, invoice and wallet ledger entries',
  'Card and bank data (never stored); the gateway''s own customer records',
  'An order stays created or authorized; the wallet is credited only on a confirmed capture. After 3 failed attempts the event is dead-lettered and the order is left for a person to settle.',
  'idempotency_key on the payment order (unique per organisation) and on every gateway event',
  'payment_order and payment_refund changes are audit events (classes 14); the wallet ledger is the financial trail', FALSE, 3, 30),
 ('identity_verification', 'Identity verification service',
  'The verification service for the check; Talentra for the outcome',
  'Verification outcome and an opaque token',
  'The raw identity number (never stored in clear text)',
  'The account stays unverified; features that need verification stay locked. Retried 3 times, then dead-lettered.',
  'The verification request id supplied by the service',
  'Outcome changes are account status changes (class 7)', FALSE, 3, 60),
 ('company_verification', 'Company registration and tax verification',
  'The registry for the record; Talentra for the verification status',
  'Verification status and the identifiers used for lookup (encrypted, see recruitment.organization_identifier)',
  'The registry''s full company record',
  'The organisation stays pending; job posting that needs verification waits. Retried 3 times, then dead-lettered.',
  'organization_identifier id plus the registry lookup date',
  'Status changes are organisation status changes (class 7)', FALSE, 3, 60),
 ('gig_fulfilment', 'Gig fulfilment system',
  'The fulfilment system for execution and earnings; Talentra for the handoff reference and reconciled status',
  'Handoff reference, assignment status, reconciled earnings (gig_external_earnings)',
  'The work product and the fulfilment system''s internal state',
  'The assignment keeps its last reconciled status and reconciliation is retried; earnings are never guessed. Dead-lettered after 3 attempts.',
  'external_handoff_ref on the assignment, and the sync hash on earnings',
  'Reconciliations are rows in gig_external_earnings with a sync hash; failures are in the dead-letter queue', FALSE, 3, 120),
 ('legacy_sync', 'Legacy job and candidate systems',
  'The legacy system until cut-over, then Talentra. Candidate profile and job text: Talentra wins on conflict after cut-over; legacy wins before it. Status: the later timestamp wins.',
  'Mapped ids, last sync time, conflict log',
  'Legacy-only fields not in the Talentra model',
  'Records that fail validation go to the dead-letter queue with the reason; the batch continues. Nothing is dropped silently.',
  'The legacy system''s record id plus its version or modified-at stamp',
  'Every conflict and every rejected record is an integration_event', FALSE, 3, 300),
 ('messaging_provider', 'Messaging and notification providers',
  'The provider for delivery; Talentra for preferences and the delivery record',
  'Delivery status, preferences, a short body snippet for audit',
  'The full message body beyond what audit needs',
  'The delivery is marked failed and retried with backoff; after 3 attempts it is dead-lettered and the user sees the in-app notification instead.',
  'The provider message id (external_provider_message_id) on the delivery',
  'notification_delivery rows are the record; dead letters are in integration_event', FALSE, 3, 30),
 ('social_sharing', 'Social sharing',
  'The social platform for the post; Talentra for the fact that a share happened',
  'The share event',
  'The external post content',
  'Not retried: a failed share is shown to the user and dropped. A lost share event costs nothing.',
  'job posting id + platform + user, per day',
  'Share events are integration_event rows', TRUE, 1, 30),
 ('geolocation', 'Mapping and geolocation service',
  'The service for coordinates; Talentra for the stored place reference',
  'Coordinates and place references',
  'Map tiles and street data',
  'Optional: if the service is down the location is stored as text without coordinates and geocoded later. Never blocks a posting.',
  'The place text plus country, hashed',
  'Lookups are integration_event rows only when they fail', TRUE, 3, 300),
 ('company_reviews', 'Company review and salary data',
  'The data provider',
  'Aggregated figures with source and refresh date',
  'Individual reviews and the provider''s raw dataset',
  'The previous figures stay visible with their refresh date; a stale figure is labelled, not hidden. Retried daily.',
  'source + role + period',
  'Refreshes are integration_event rows', TRUE, 3, 3600);

-- -----------------------------------------------------------------------------
-- 2. The exchange log: outbox, inbox, retry and dead letter in one table
-- -----------------------------------------------------------------------------
CREATE TABLE messaging.integration_event (
    id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    boundary_id       BIGINT       NOT NULL,
    direction         VARCHAR(8)   NOT NULL,
    event_type        VARCHAR(60)  NOT NULL,
    idempotency_key   VARCHAR(150) NOT NULL,
    entity_schema     VARCHAR(63),
    entity_name       VARCHAR(63),
    entity_id         BIGINT,
    payload_json      JSONB,
    event_status      VARCHAR(12)  NOT NULL DEFAULT 'pending',
    attempts          INTEGER      NOT NULL DEFAULT 0,
    next_attempt_at   TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_error        VARCHAR(500),
    response_ref      VARCHAR(150),
    completed_at      TIMESTAMPTZ,

    CONSTRAINT fk_integration_event_boundary FOREIGN KEY (boundary_id)
        REFERENCES messaging.integration_boundary (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    -- a duplicate delivery of the same exchange cannot be stored twice
    CONSTRAINT uq_integration_event_idempotency UNIQUE (boundary_id, direction, idempotency_key),
    CONSTRAINT ck_integration_event_direction CHECK (direction IN ('outbound', 'inbound')),
    CONSTRAINT ck_integration_event_status CHECK (event_status IN ('pending', 'in_progress', 'succeeded', 'failed', 'dead_letter')),
    CONSTRAINT ck_integration_event_attempts CHECK (attempts >= 0),
    CONSTRAINT ck_integration_event_key CHECK (length(btrim(idempotency_key)) >= 1),
    CONSTRAINT ck_integration_event_payload_size CHECK (payload_json IS NULL OR pg_column_size(payload_json) <= 65536),
    CONSTRAINT ck_integration_event_completed CHECK ((event_status = 'succeeded') = (completed_at IS NOT NULL) OR event_status = 'dead_letter')
);
COMMENT ON TABLE messaging.integration_event IS 'Every exchange with an external system. Idempotency key makes a replay a no-op; a failed event is retried with exponential backoff up to the boundary''s limit, then becomes a dead letter that stays visible until a person requeues or closes it.';
COMMENT ON COLUMN messaging.integration_event.payload_json IS 'Nullable: not every exchange carries a body. Keep personal data and secrets out; reference ids instead. Capped at 64 KB.';
COMMENT ON COLUMN messaging.integration_event.entity_schema IS 'Nullable: the local row this exchange is about, when there is one (with entity_name and entity_id).';
COMMENT ON COLUMN messaging.integration_event.last_error IS 'Nullable: the most recent failure message; NULL until something fails.';
COMMENT ON COLUMN messaging.integration_event.response_ref IS 'Nullable: the external system''s reference for the exchange, set on success.';
COMMENT ON COLUMN messaging.integration_event.completed_at IS 'Nullable: set when the exchange succeeded; a dead letter has none.';
CREATE INDEX idx_integration_event_due ON messaging.integration_event (boundary_id, next_attempt_at) WHERE event_status IN ('pending', 'failed');
CREATE INDEX idx_integration_event_dead ON messaging.integration_event (boundary_id) WHERE event_status = 'dead_letter';
SELECT audit.apply_standard_lifecycle('messaging', 'integration_event', 'hard');

INSERT INTO master.status_transition (entity_code, from_status, to_status) VALUES
 ('messaging.integration_event', 'pending',     'in_progress'),
 ('messaging.integration_event', 'in_progress', 'succeeded'),
 ('messaging.integration_event', 'in_progress', 'failed'),
 ('messaging.integration_event', 'in_progress', 'dead_letter'),
 ('messaging.integration_event', 'failed',      'in_progress'),
 ('messaging.integration_event', 'failed',      'dead_letter'),
 ('messaging.integration_event', 'dead_letter', 'pending');
CREATE TRIGGER trg_integration_event_status_transition BEFORE UPDATE OF event_status ON messaging.integration_event
    FOR EACH ROW WHEN (OLD.event_status IS DISTINCT FROM NEW.event_status)
    EXECUTE FUNCTION master.enforce_status_transition('messaging.integration_event', 'event_status');

-- Enqueue. Returns the event id and whether this call created it; a repeat of the same key returns the original.
CREATE FUNCTION messaging.enqueue_integration_event(
    p_boundary_code TEXT, p_direction TEXT, p_event_type TEXT, p_idempotency_key TEXT,
    p_payload JSONB DEFAULT NULL, p_entity_schema TEXT DEFAULT NULL, p_entity_name TEXT DEFAULT NULL, p_entity_id BIGINT DEFAULT NULL)
RETURNS TABLE (event_id BIGINT, is_new BOOLEAN)
LANGUAGE plpgsql
AS $$
DECLARE
    v_boundary BIGINT;
    v_id BIGINT;
BEGIN
    SELECT id INTO v_boundary FROM messaging.integration_boundary WHERE code = p_boundary_code;
    IF v_boundary IS NULL THEN RAISE EXCEPTION 'Unknown integration boundary %', p_boundary_code; END IF;
    INSERT INTO messaging.integration_event (boundary_id, direction, event_type, idempotency_key, payload_json, entity_schema, entity_name, entity_id)
    VALUES (v_boundary, p_direction, p_event_type, p_idempotency_key, p_payload, p_entity_schema, p_entity_name, p_entity_id)
    ON CONFLICT (boundary_id, direction, idempotency_key) DO NOTHING
    RETURNING id INTO v_id;
    IF v_id IS NOT NULL THEN
        RETURN QUERY SELECT v_id, TRUE;
    ELSE
        RETURN QUERY SELECT e.id, FALSE FROM messaging.integration_event e
                      WHERE e.boundary_id = v_boundary AND e.direction = p_direction AND e.idempotency_key = p_idempotency_key;
    END IF;
END;
$$;

-- A worker claims due events. SKIP LOCKED lets several workers run without taking the same event.
CREATE FUNCTION messaging.claim_integration_events(p_boundary_code TEXT, p_batch INTEGER DEFAULT 10)
RETURNS SETOF messaging.integration_event
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH due AS (
        SELECT e.id FROM messaging.integration_event e
          JOIN messaging.integration_boundary b ON b.id = e.boundary_id
         WHERE b.code = p_boundary_code AND e.event_status IN ('pending', 'failed') AND e.next_attempt_at <= CURRENT_TIMESTAMP
         ORDER BY e.next_attempt_at, e.id
         LIMIT p_batch
           FOR UPDATE OF e SKIP LOCKED)
    UPDATE messaging.integration_event e SET event_status = 'in_progress', attempts = e.attempts + 1
      FROM due WHERE e.id = due.id
    RETURNING e.*;
END;
$$;

CREATE FUNCTION messaging.complete_integration_event(p_event_id BIGINT, p_response_ref TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    UPDATE messaging.integration_event SET event_status = 'succeeded', completed_at = CURRENT_TIMESTAMP, response_ref = p_response_ref, last_error = NULL
     WHERE id = p_event_id AND event_status = 'in_progress';
    IF NOT FOUND THEN RAISE EXCEPTION 'Integration event % is not in progress', p_event_id; END IF;
END;
$$;

-- Failure: back off exponentially (base, 2x base, 4x base ...); once the boundary's attempt limit is reached, dead-letter it and say so in the error log.
CREATE FUNCTION messaging.fail_integration_event(p_event_id BIGINT, p_error TEXT)
RETURNS VARCHAR
LANGUAGE plpgsql
AS $$
DECLARE
    v_e messaging.integration_event%ROWTYPE;
    v_b messaging.integration_boundary%ROWTYPE;
BEGIN
    SELECT * INTO v_e FROM messaging.integration_event WHERE id = p_event_id AND event_status = 'in_progress' FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Integration event % is not in progress', p_event_id; END IF;
    SELECT * INTO v_b FROM messaging.integration_boundary WHERE id = v_e.boundary_id;
    IF v_e.attempts >= v_b.max_attempts THEN
        UPDATE messaging.integration_event SET event_status = 'dead_letter', last_error = left(p_error, 500) WHERE id = p_event_id;
        INSERT INTO audit.system_error_log (error_code, error_severity, error_message, context_json)
        VALUES ('INTEGRATION_DEAD_LETTER', CASE WHEN v_b.is_optional THEN 'warning' ELSE 'error' END,
                format('Integration event %s on boundary %s gave up after %s attempts: %s', p_event_id, v_b.code, v_e.attempts, left(p_error, 200)),
                jsonb_build_object('event_id', p_event_id, 'boundary', v_b.code, 'event_type', v_e.event_type, 'attempts', v_e.attempts));
        RETURN 'dead_letter';
    END IF;
    UPDATE messaging.integration_event
       SET event_status = 'failed', last_error = left(p_error, 500),
           next_attempt_at = CURRENT_TIMESTAMP + make_interval(secs => v_b.base_backoff_seconds * power(2, v_e.attempts - 1))
     WHERE id = p_event_id;
    RETURN 'failed';
END;
$$;

CREATE FUNCTION messaging.requeue_dead_letter(p_event_id BIGINT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    UPDATE messaging.integration_event SET event_status = 'pending', attempts = 0, next_attempt_at = CURRENT_TIMESTAMP
     WHERE id = p_event_id AND event_status = 'dead_letter';
    IF NOT FOUND THEN RAISE EXCEPTION 'Integration event % is not a dead letter', p_event_id; END IF;
END;
$$;

-- -----------------------------------------------------------------------------
-- 3. Maintenance: a run log, retention purge, erasure of inactive accounts, mart refresh
-- -----------------------------------------------------------------------------
CREATE TABLE audit.maintenance_run (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_name      VARCHAR(60) NOT NULL,
    run_status    VARCHAR(10) NOT NULL,
    started_at    TIMESTAMPTZ NOT NULL,
    finished_at   TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),   -- not CURRENT_TIMESTAMP: inside one transaction that would be earlier than started_at
    rows_affected BIGINT,
    detail_json   JSONB,
    error_message VARCHAR(500),

    CONSTRAINT ck_maintenance_run_status CHECK (run_status IN ('succeeded', 'failed', 'skipped')),
    CONSTRAINT ck_maintenance_run_times CHECK (finished_at >= started_at)
);
COMMENT ON TABLE audit.maintenance_run IS 'One row per scheduled job execution, written when it finishes. Append-only: the data behind "when did the marts last refresh" and "when was the last backup verified".';
COMMENT ON COLUMN audit.maintenance_run.rows_affected IS 'Nullable: jobs that do not touch rows (a mart refresh, a backup check) report none.';
COMMENT ON COLUMN audit.maintenance_run.detail_json IS 'Nullable: per-table counts for a purge, the reason for a skip.';
COMMENT ON COLUMN audit.maintenance_run.error_message IS 'Nullable: set only when run_status is failed.';
CREATE INDEX idx_maintenance_run_job_finished ON audit.maintenance_run (job_name, finished_at DESC);
SELECT audit.apply_standard_lifecycle('audit', 'maintenance_run', 'append_only');
GRANT INSERT ON audit.maintenance_run TO talentra_app;

-- which column dates a row for retention purposes
ALTER TABLE audit.entity_lifecycle_policy ADD COLUMN purge_column VARCHAR(63);
ALTER TABLE audit.entity_lifecycle_policy ADD COLUMN retention_approved_by VARCHAR(200);
COMMENT ON COLUMN audit.entity_lifecycle_policy.purge_column IS 'Nullable: the timestamp column the retention period is counted from. NULL means rows of this table are not purged by the scheduled job (financial and append-only records, and personal data removed through account erasure).';
COMMENT ON COLUMN audit.entity_lifecycle_policy.retention_approved_by IS 'Nullable: who approved the retention period, with the decision reference. NULL while unapproved.';

UPDATE audit.entity_lifecycle_policy SET purge_column = v.c
  FROM (VALUES ('core', 'user_device', 'last_seen_at'), ('messaging', 'notification_delivery', 'created_at'),
               ('sourcing', 'outreach_recipient', 'created_at'), ('profile', 'candidate_search_history', 'searched_at')) AS v (s, t, c)
 WHERE audit.entity_lifecycle_policy.schema_name = v.s AND audit.entity_lifecycle_policy.table_name = v.t;
-- ended sessions only: an open session has no ended_at and is never purged
UPDATE audit.entity_lifecycle_policy SET purge_column = 'ended_at' WHERE schema_name = 'core' AND table_name = 'user_session';
-- integration events: terminal ones, 90 days; dead letters are kept until a person closes them
UPDATE audit.entity_lifecycle_policy SET retention_days = 90, retention_basis = 'Proposed: completed exchanges, 90 days; dead letters are not purged', purge_column = 'completed_at'
 WHERE schema_name = 'messaging' AND table_name = 'integration_event';

CREATE FUNCTION core.purge_expired_data(p_dry_run BOOLEAN DEFAULT FALSE)
RETURNS TABLE (purged_table TEXT, rows_affected BIGINT, outcome TEXT)
LANGUAGE plpgsql
AS $$
DECLARE
    r RECORD;
    v_n BIGINT;
BEGIN
    FOR r IN SELECT schema_name, table_name, purge_column, retention_days, retention_approved_by
               FROM audit.entity_lifecycle_policy
              WHERE delete_mode = 'hard' AND retention_days IS NOT NULL AND purge_column IS NOT NULL
              ORDER BY schema_name, table_name
    LOOP
        IF r.retention_approved_by IS NULL THEN
            RETURN QUERY SELECT r.schema_name || '.' || r.table_name, 0::BIGINT, 'skipped: retention period not approved'::TEXT;
            CONTINUE;
        END IF;
        BEGIN
            IF p_dry_run THEN
                EXECUTE format('SELECT count(*) FROM %I.%I WHERE %I IS NOT NULL AND %I < CURRENT_TIMESTAMP - make_interval(days => %s)',
                               r.schema_name, r.table_name, r.purge_column, r.purge_column, r.retention_days) INTO v_n;
                RETURN QUERY SELECT r.schema_name || '.' || r.table_name, v_n, 'would delete'::TEXT;
            ELSE
                -- dead letters stay until a person deals with them
                EXECUTE format('DELETE FROM %I.%I WHERE %I IS NOT NULL AND %I < CURRENT_TIMESTAMP - make_interval(days => %s)',
                               r.schema_name, r.table_name, r.purge_column, r.purge_column, r.retention_days);
                GET DIAGNOSTICS v_n = ROW_COUNT;
                RETURN QUERY SELECT r.schema_name || '.' || r.table_name, v_n, 'deleted'::TEXT;
            END IF;
        EXCEPTION WHEN foreign_key_violation THEN
            RETURN QUERY SELECT r.schema_name || '.' || r.table_name, 0::BIGINT, 'skipped: rows are still referenced'::TEXT;
        END;
    END LOOP;
END;
$$;
COMMENT ON FUNCTION core.purge_expired_data(BOOLEAN) IS 'Deletes rows older than their approved retention period from tables that name a purge column. Unapproved periods are skipped, never applied. Financial and append-only records are not touched.';

CREATE PROCEDURE core.run_maintenance()
LANGUAGE plpgsql
AS $$
DECLARE
    v_started TIMESTAMPTZ;
    v_rows BIGINT;
    v_detail JSONB;
    v_erase_approved BOOLEAN;
    r RECORD;
BEGIN
    -- 1. marts
    v_started := clock_timestamp();
    BEGIN
        CALL analytics.refresh_reporting_marts();
        INSERT INTO audit.maintenance_run (job_name, run_status, started_at) VALUES ('refresh_marts', 'succeeded', v_started);
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO audit.maintenance_run (job_name, run_status, started_at, error_message) VALUES ('refresh_marts', 'failed', v_started, left(SQLERRM, 500));
    END;

    -- 2. retention purge
    v_started := clock_timestamp();
    BEGIN
        SELECT COALESCE(sum(p.rows_affected), 0), COALESCE(jsonb_object_agg(p.purged_table, p.outcome || ' ' || p.rows_affected), '{}'::JSONB)
          INTO v_rows, v_detail FROM core.purge_expired_data(FALSE) p;
        INSERT INTO audit.maintenance_run (job_name, run_status, started_at, rows_affected, detail_json) VALUES ('purge_expired_data', 'succeeded', v_started, v_rows, v_detail);
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO audit.maintenance_run (job_name, run_status, started_at, error_message) VALUES ('purge_expired_data', 'failed', v_started, left(SQLERRM, 500));
    END;

    -- 3. erase accounts inactive past their approved period
    v_started := clock_timestamp();
    SELECT retention_approved_by IS NOT NULL INTO v_erase_approved FROM audit.entity_lifecycle_policy WHERE schema_name = 'core' AND table_name = 'user_account';
    IF NOT COALESCE(v_erase_approved, FALSE) THEN
        INSERT INTO audit.maintenance_run (job_name, run_status, started_at, detail_json)
        VALUES ('erase_inactive_accounts', 'skipped', v_started, jsonb_build_object('reason', 'retention period for core.user_account is not approved'));
    ELSE
        v_rows := 0;
        BEGIN
            FOR r IN SELECT user_account_id FROM core.find_inactive_accounts() LOOP
                PERFORM core.erase_user_account(r.user_account_id, NULL);
                v_rows := v_rows + 1;
            END LOOP;
            INSERT INTO audit.maintenance_run (job_name, run_status, started_at, rows_affected) VALUES ('erase_inactive_accounts', 'succeeded', v_started, v_rows);
        EXCEPTION WHEN OTHERS THEN
            INSERT INTO audit.maintenance_run (job_name, run_status, started_at, error_message) VALUES ('erase_inactive_accounts', 'failed', v_started, left(SQLERRM, 500));
        END;
    END IF;
END;
$$;
COMMENT ON PROCEDURE core.run_maintenance() IS 'The scheduled job: refresh marts, purge expired data, erase inactive accounts. Each step logs its own run and one failing step does not stop the next. Call every 15 minutes from cron, pg_cron or a container loop.';

-- -----------------------------------------------------------------------------
-- 4. Telemetry: the four metric families the NFR names (query latency, connections, replication / WAL, backup freshness), plus the two this system adds
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'pg_stat_statements is not available (%); the query-latency view will be empty', SQLERRM;
END;
$$;

CREATE FUNCTION audit.ops_slow_queries(p_limit INTEGER DEFAULT 20)
RETURNS TABLE (query_text TEXT, calls BIGINT, mean_ms DOUBLE PRECISION, max_ms DOUBLE PRECISION, total_ms DOUBLE PRECISION)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY EXECUTE format(
        'SELECT left(query, 200), calls, mean_exec_time, max_exec_time, total_exec_time FROM pg_stat_statements WHERE dbid = (SELECT oid FROM pg_database WHERE datname = current_database()) ORDER BY mean_exec_time DESC LIMIT %s', p_limit);
EXCEPTION WHEN OTHERS THEN
    RETURN;   -- extension absent or not preloaded: no rows, no error
END;
$$;
COMMENT ON FUNCTION audit.ops_slow_queries(INTEGER) IS 'Metric family 1: query latency, from pg_stat_statements. Empty when the extension is not loaded (set shared_preload_libraries = pg_stat_statements).';

CREATE VIEW audit.ops_connections AS
SELECT COALESCE(state, 'background') AS state, count(*) AS connections,
       (SELECT setting::INT FROM pg_settings WHERE name = 'max_connections') AS max_connections
  FROM pg_stat_activity WHERE datname = current_database() OR datname IS NULL GROUP BY COALESCE(state, 'background');
COMMENT ON VIEW audit.ops_connections IS 'Metric family 2: connections by state against max_connections.';

CREATE VIEW audit.ops_replication AS
SELECT pg_is_in_recovery() AS is_replica,
       pg_current_wal_lsn()::TEXT AS current_wal_lsn,
       (SELECT count(*) FROM pg_stat_replication) AS replicas_attached,
       (SELECT COALESCE(max(pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)), 0) FROM pg_stat_replication) AS max_replay_lag_bytes;
COMMENT ON VIEW audit.ops_replication IS 'Metric family 3: replication and WAL position. A single-node deployment shows zero replicas.';

CREATE VIEW audit.ops_job_freshness AS
SELECT j.job_name,
       max(r.finished_at) FILTER (WHERE r.run_status = 'succeeded') AS last_success_at,
       round(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - max(r.finished_at) FILTER (WHERE r.run_status = 'succeeded'))) / 3600.0, 2) AS hours_since_success,
       count(*) FILTER (WHERE r.run_status = 'failed' AND r.finished_at > CURRENT_TIMESTAMP - INTERVAL '24 hours') AS failures_last_24h
  FROM (VALUES ('refresh_marts'), ('purge_expired_data'), ('erase_inactive_accounts'), ('backup_restore_check')) AS j (job_name)
  LEFT JOIN audit.maintenance_run r ON r.job_name = j.job_name
 GROUP BY j.job_name;
COMMENT ON VIEW audit.ops_job_freshness IS 'Metric family 4: how long since each scheduled job and the backup check last succeeded. Mart staleness (NFR-020, 24 h) is the refresh_marts row.';

CREATE VIEW audit.ops_database AS
SELECT pg_database_size(current_database()) AS size_bytes,
       (SELECT count(*) FROM pg_stat_user_tables) AS tables,
       (SELECT COALESCE(sum(n_dead_tup), 0) FROM pg_stat_user_tables) AS dead_tuples;
COMMENT ON VIEW audit.ops_database IS 'Size and dead-tuple count, for capacity and vacuum health.';

CREATE VIEW audit.ops_integration_health AS
SELECT b.code AS boundary,
       count(*) FILTER (WHERE e.event_status = 'pending')     AS pending,
       count(*) FILTER (WHERE e.event_status = 'failed')      AS retrying,
       count(*) FILTER (WHERE e.event_status = 'dead_letter') AS dead_letters,
       round(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - min(e.created_at) FILTER (WHERE e.event_status IN ('pending', 'failed')))) / 60.0, 1) AS oldest_waiting_minutes
  FROM messaging.integration_boundary b
  LEFT JOIN messaging.integration_event e ON e.boundary_id = b.id
 GROUP BY b.code;
COMMENT ON VIEW audit.ops_integration_health IS 'Per boundary: waiting, retrying and dead-lettered events, and how long the oldest has waited.';

CREATE VIEW audit.ops_delivery_latency AS
SELECT channel,
       count(*) FILTER (WHERE sent_at IS NOT NULL) AS sent,
       percentile_cont(0.95) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (sent_at - created_at))) FILTER (WHERE sent_at IS NOT NULL)      AS p95_seconds_to_sent,
       percentile_cont(0.95) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (delivered_at - created_at))) FILTER (WHERE delivered_at IS NOT NULL) AS p95_seconds_to_delivered
  FROM messaging.notification_delivery GROUP BY channel;
COMMENT ON VIEW audit.ops_delivery_latency IS 'NFR-008: 95th percentile seconds from creation to sent and to delivered, per channel.';

GRANT SELECT ON audit.ops_connections, audit.ops_replication, audit.ops_job_freshness, audit.ops_database,
                audit.ops_integration_health, audit.ops_delivery_latency TO talentra_auditor, talentra_readonly;
GRANT EXECUTE ON FUNCTION audit.ops_slow_queries(INTEGER) TO talentra_auditor, talentra_readonly;

-- -----------------------------------------------------------------------------
-- 5. NFR-018: no candidate without the two consents the platform needs
-- -----------------------------------------------------------------------------
CREATE FUNCTION core.accounts_missing_consent()
RETURNS TABLE (user_account_id BIGINT)
LANGUAGE sql
STABLE
AS $$
    SELECT p.user_account_id
      FROM profile.candidate_profile p
     WHERE p.deleted_at IS NULL
       AND (SELECT count(DISTINCT c.consent_type) FROM core.consent_record c
             WHERE c.user_account_id = p.user_account_id AND c.is_granted AND c.revoked_at IS NULL
               AND c.consent_type IN ('terms_of_service', 'privacy_policy')) < 2;
$$;
COMMENT ON FUNCTION core.accounts_missing_consent() IS 'Candidates who have not currently granted both terms_of_service and privacy_policy. NFR-018 target: none.';

-- classification for the new columns; payload_json is treated as personal until proven otherwise
SELECT audit.sync_column_classification();
UPDATE audit.column_classification SET data_class = 'personal', protection = 'grants_only',
       note = 'May carry personal data from the other system; keep it to reference ids.'
 WHERE schema_name = 'messaging' AND table_name = 'integration_event' AND column_name = 'payload_json';

COMMIT;
