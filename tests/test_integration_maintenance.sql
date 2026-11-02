-- Test suite: tests/test_integration_maintenance.sql
-- Covers: NFR-008, NFR-017, NFR-018, NFR-020, NFR-021, NFR-026, NFR-027; docket section 6 (integration boundaries)
-- Prerequisite: migrations 001-031 have been applied.
-- Isolation: one transaction, rolled back.

BEGIN;

DO $$
DECLARE
    v_b BIGINT; v_id BIGINT; v_id2 BIGINT; v_new BOOLEAN; v_status TEXT; v_n BIGINT; v_text TEXT; v_caught BOOLEAN;
    v_e messaging.integration_event%ROWTYPE; v_user BIGINT; v_user2 BIGINT; v_delay DOUBLE PRECISION;
BEGIN
    RAISE NOTICE '=== Integration boundaries, retry and dead letter, maintenance, telemetry ===';

    -- 1. the nine boundaries of the docket, each with all five answers
    SELECT count(*) INTO v_n FROM messaging.integration_boundary;
    IF v_n <> 9 THEN RAISE EXCEPTION 'FAIL: expected the docket''s 9 boundaries, found %', v_n; END IF;
    SELECT string_agg(c, ', ') INTO v_text FROM unnest(ARRAY['payment_gateway','identity_verification','company_verification','gig_fulfilment','legacy_sync','messaging_provider','social_sharing','geolocation','company_reviews']) c
     WHERE NOT EXISTS (SELECT 1 FROM messaging.integration_boundary b WHERE b.code = c);
    IF v_text IS NOT NULL THEN RAISE EXCEPTION 'FAIL: missing boundaries: %', v_text; END IF;
    IF EXISTS (SELECT 1 FROM messaging.integration_boundary WHERE length(btrim(source_of_truth)) < 10 OR length(btrim(stored_data)) < 5 OR length(btrim(referenced_data)) < 5
                OR length(btrim(failure_behaviour)) < 20 OR length(btrim(idempotency_rule)) < 5 OR length(btrim(audit_rule)) < 5) THEN
        RAISE EXCEPTION 'FAIL: a boundary does not answer one of the five questions the docket asks';
    END IF;
    IF (SELECT count(*) FROM messaging.integration_boundary WHERE is_optional) <> 3 THEN RAISE EXCEPTION 'FAIL: social sharing, geolocation and company reviews are the optional boundaries'; END IF;
    RAISE NOTICE 'PASS: nine boundaries, each answering ownership, stored vs referenced, failure, idempotency and audit';

    -- 2. idempotency: the same exchange cannot be stored twice
    SELECT * INTO v_id, v_new FROM messaging.enqueue_integration_event('payment_gateway', 'inbound', 'payment.captured', 'evt_1001', '{"order": 7}');
    IF NOT v_new THEN RAISE EXCEPTION 'FAIL: a first delivery was reported as a repeat'; END IF;
    SELECT * INTO v_id2, v_new FROM messaging.enqueue_integration_event('payment_gateway', 'inbound', 'payment.captured', 'evt_1001', '{"order": 7}');
    IF v_new OR v_id2 <> v_id THEN RAISE EXCEPTION 'FAIL: a replayed event created a second row'; END IF;
    SELECT * INTO v_id2, v_new FROM messaging.enqueue_integration_event('payment_gateway', 'outbound', 'payment.captured', 'evt_1001');
    IF NOT v_new THEN RAISE EXCEPTION 'FAIL: the same key in the other direction was treated as a duplicate'; END IF;
    v_caught := FALSE;
    BEGIN PERFORM messaging.enqueue_integration_event('no_such_boundary', 'inbound', 'x', 'k');
    EXCEPTION WHEN raise_exception THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: an unknown boundary was accepted'; END IF;
    RAISE NOTICE 'PASS: a replay with the same idempotency key is a no-op; direction is part of the key';

    -- 3. at most 3 attempts with exponential backoff, then a dead letter
    SELECT id INTO v_b FROM messaging.integration_boundary WHERE code = 'payment_gateway';
    SELECT * INTO v_e FROM messaging.claim_integration_events('payment_gateway', 1);
    IF v_e.id <> v_id OR v_e.attempts <> 1 OR v_e.event_status <> 'in_progress' THEN RAISE EXCEPTION 'FAIL: claim did not take the due event as attempt 1'; END IF;
    v_status := messaging.fail_integration_event(v_id, 'gateway timeout');
    SELECT EXTRACT(EPOCH FROM (next_attempt_at - CURRENT_TIMESTAMP)) INTO v_delay FROM messaging.integration_event WHERE id = v_id;
    IF v_status <> 'failed' OR v_delay NOT BETWEEN 25 AND 31 THEN RAISE EXCEPTION 'FAIL: attempt 1 failure should retry in ~30 s, got status % delay %', v_status, v_delay; END IF;
    IF EXISTS (SELECT 1 FROM messaging.claim_integration_events('payment_gateway', 5) WHERE id = v_id) THEN RAISE EXCEPTION 'FAIL: an event was claimed before its backoff elapsed'; END IF;
    UPDATE messaging.integration_event SET next_attempt_at = now() - interval '1 second' WHERE id = v_id;
    PERFORM 1 FROM messaging.claim_integration_events('payment_gateway', 5) WHERE id = v_id;
    v_status := messaging.fail_integration_event(v_id, 'gateway timeout');
    SELECT EXTRACT(EPOCH FROM (next_attempt_at - CURRENT_TIMESTAMP)) INTO v_delay FROM messaging.integration_event WHERE id = v_id;
    IF v_status <> 'failed' OR v_delay NOT BETWEEN 55 AND 61 THEN RAISE EXCEPTION 'FAIL: attempt 2 should back off ~60 s, got % / %', v_status, v_delay; END IF;
    UPDATE messaging.integration_event SET next_attempt_at = now() - interval '1 second' WHERE id = v_id;
    PERFORM 1 FROM messaging.claim_integration_events('payment_gateway', 5) WHERE id = v_id;
    v_status := messaging.fail_integration_event(v_id, 'gateway timeout');
    SELECT * INTO v_e FROM messaging.integration_event WHERE id = v_id;
    IF v_status <> 'dead_letter' OR v_e.attempts <> 3 OR v_e.event_status <> 'dead_letter' THEN RAISE EXCEPTION 'FAIL: the third failure should dead-letter after exactly 3 attempts (status %, attempts %)', v_status, v_e.attempts; END IF;
    IF NOT EXISTS (SELECT 1 FROM audit.system_error_log WHERE error_code = 'INTEGRATION_DEAD_LETTER' AND context_json ->> 'event_id' = v_id::TEXT) THEN
        RAISE EXCEPTION 'FAIL: a dead letter left no entry in the error log'; END IF;
    IF EXISTS (SELECT 1 FROM messaging.claim_integration_events('payment_gateway', 5) WHERE id = v_id) THEN RAISE EXCEPTION 'FAIL: a dead letter was claimed again'; END IF;
    IF (SELECT dead_letters FROM audit.ops_integration_health WHERE boundary = 'payment_gateway') < 1 THEN RAISE EXCEPTION 'FAIL: the dead letter is not visible in the health view'; END IF;
    RAISE NOTICE 'PASS: 3 attempts, backoff 30 s then 60 s, then a dead letter that is logged and visible (NFR-027)';

    -- 4. dead letters can be requeued; illegal moves are refused; an optional boundary gives up at once
    PERFORM messaging.requeue_dead_letter(v_id);
    SELECT * INTO v_e FROM messaging.integration_event WHERE id = v_id;
    IF v_e.event_status <> 'pending' OR v_e.attempts <> 0 THEN RAISE EXCEPTION 'FAIL: requeue did not reset the event'; END IF;
    v_caught := FALSE;
    BEGIN UPDATE messaging.integration_event SET event_status = 'succeeded', completed_at = now() WHERE id = v_id;       -- pending -> succeeded skips in_progress
    EXCEPTION WHEN check_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: pending -> succeeded was accepted'; END IF;
    v_caught := FALSE;
    BEGIN PERFORM messaging.complete_integration_event(v_id);
    EXCEPTION WHEN raise_exception THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: an event that is not in progress was completed'; END IF;
    PERFORM 1 FROM messaging.claim_integration_events('payment_gateway', 5) WHERE id = v_id;
    PERFORM messaging.complete_integration_event(v_id, 'ch_9001');
    IF (SELECT event_status || coalesce(response_ref, '') FROM messaging.integration_event WHERE id = v_id) <> 'succeededch_9001' THEN RAISE EXCEPTION 'FAIL: completion not recorded'; END IF;
    SELECT * INTO v_id, v_new FROM messaging.enqueue_integration_event('social_sharing', 'outbound', 'share', 'job-1-linkedin');
    PERFORM 1 FROM messaging.claim_integration_events('social_sharing', 5);
    IF messaging.fail_integration_event(v_id, 'platform down') <> 'dead_letter' THEN RAISE EXCEPTION 'FAIL: an optional boundary with one attempt should dead-letter at once'; END IF;
    IF (SELECT error_severity FROM audit.system_error_log WHERE context_json ->> 'event_id' = v_id::TEXT) <> 'warning' THEN RAISE EXCEPTION 'FAIL: an optional boundary should log a warning, not an error'; END IF;
    RAISE NOTICE 'PASS: requeue, state machine, completion, and optional boundaries degrade quietly';

    -- 5. retention purge applies only approved periods
    INSERT INTO core.user_account (email) VALUES ('mt-user@example.com') RETURNING id INTO v_user;
    INSERT INTO messaging.notification_delivery (recipient_user_account_id, channel, subject, delivery_status, created_at)
    VALUES (v_user, 'email', 'old', 'sent', now() - interval '400 days'), (v_user, 'email', 'new', 'sent', now());
    IF NOT EXISTS (SELECT 1 FROM core.purge_expired_data(TRUE) WHERE purged_table = 'messaging.notification_delivery' AND outcome LIKE 'skipped%') THEN
        UPDATE audit.entity_lifecycle_policy SET retention_approved_by = NULL WHERE schema_name = 'messaging' AND table_name = 'notification_delivery';
    END IF;
    UPDATE audit.entity_lifecycle_policy SET retention_approved_by = NULL WHERE schema_name = 'messaging' AND table_name = 'notification_delivery';
    IF NOT EXISTS (SELECT 1 FROM core.purge_expired_data(FALSE) WHERE purged_table = 'messaging.notification_delivery' AND outcome LIKE 'skipped%') THEN
        RAISE EXCEPTION 'FAIL: an unapproved retention period was applied'; END IF;
    IF (SELECT count(*) FROM messaging.notification_delivery WHERE recipient_user_account_id = v_user) <> 2 THEN RAISE EXCEPTION 'FAIL: the unapproved purge deleted rows'; END IF;
    UPDATE audit.entity_lifecycle_policy SET retention_approved_by = 'test approval' WHERE schema_name = 'messaging' AND table_name = 'notification_delivery';
    SELECT rows_affected INTO v_n FROM core.purge_expired_data(TRUE) WHERE purged_table = 'messaging.notification_delivery';
    IF v_n < 1 OR (SELECT count(*) FROM messaging.notification_delivery WHERE recipient_user_account_id = v_user) <> 2 THEN RAISE EXCEPTION 'FAIL: dry run should count but not delete'; END IF;
    PERFORM 1 FROM core.purge_expired_data(FALSE);
    IF (SELECT count(*) FROM messaging.notification_delivery WHERE recipient_user_account_id = v_user AND subject = 'old') <> 0
       OR (SELECT count(*) FROM messaging.notification_delivery WHERE recipient_user_account_id = v_user AND subject = 'new') <> 1 THEN
        RAISE EXCEPTION 'FAIL: the purge did not remove exactly the expired row'; END IF;
    RAISE NOTICE 'PASS: purge skips unapproved periods, dry run does not delete, and the real run removes only expired rows (NFR-017)';

    -- 6. scheduled maintenance: runs, logs, erases only when approved
    INSERT INTO core.user_account (email, created_at) VALUES ('mt-dormant@example.com', now() - interval '5 years') RETURNING id INTO v_user2;
    UPDATE audit.entity_lifecycle_policy SET retention_approved_by = NULL WHERE schema_name = 'core' AND table_name = 'user_account';
    CALL core.run_maintenance();
    IF (SELECT run_status FROM audit.maintenance_run WHERE job_name = 'erase_inactive_accounts' ORDER BY id DESC LIMIT 1) <> 'skipped' THEN RAISE EXCEPTION 'FAIL: erasure ran without an approved period'; END IF;
    IF EXISTS (SELECT 1 FROM core.user_account WHERE id = v_user2 AND deleted_at IS NOT NULL) THEN RAISE EXCEPTION 'FAIL: a dormant account was erased without approval'; END IF;
    UPDATE audit.entity_lifecycle_policy SET retention_approved_by = 'test approval' WHERE schema_name = 'core' AND table_name = 'user_account';
    CALL core.run_maintenance();
    IF NOT EXISTS (SELECT 1 FROM core.user_account WHERE id = v_user2 AND deleted_at IS NOT NULL) THEN RAISE EXCEPTION 'FAIL: the dormant account was not erased once approved'; END IF;
    IF EXISTS (SELECT 1 FROM core.user_account WHERE id = v_user AND deleted_at IS NOT NULL) THEN RAISE EXCEPTION 'FAIL: an active account was erased'; END IF;
    IF NOT EXISTS (SELECT 1 FROM audit.audit_event WHERE action = 'user.erased' AND entity_id = v_user2) THEN RAISE EXCEPTION 'FAIL: the scheduled erasure was not audited'; END IF;
    IF (SELECT run_status FROM audit.maintenance_run WHERE job_name = 'refresh_marts' ORDER BY id DESC LIMIT 1) <> 'succeeded' THEN RAISE EXCEPTION 'FAIL: the mart refresh did not succeed: %', (SELECT error_message FROM audit.maintenance_run WHERE job_name = 'refresh_marts' ORDER BY id DESC LIMIT 1); END IF;
    IF (SELECT hours_since_success FROM audit.ops_job_freshness WHERE job_name = 'refresh_marts') > 0.1 THEN RAISE EXCEPTION 'FAIL: mart staleness is not near zero right after a refresh (NFR-020)'; END IF;
    RAISE NOTICE 'PASS: maintenance refreshes marts, logs every step, and erases dormant accounts only when approved; mart staleness is measurable (NFR-020)';

    -- 7. telemetry: four metric families
    IF (SELECT count(*) FROM audit.ops_connections) < 1 THEN RAISE EXCEPTION 'FAIL: no connection metrics'; END IF;
    IF (SELECT count(*) FROM audit.ops_replication) <> 1 THEN RAISE EXCEPTION 'FAIL: no replication / WAL metric'; END IF;
    IF (SELECT count(*) FROM audit.ops_job_freshness) <> 4 THEN RAISE EXCEPTION 'FAIL: job freshness should cover four jobs'; END IF;
    IF (SELECT count(*) FROM audit.ops_database) <> 1 OR (SELECT count(*) FROM audit.ops_integration_health) <> 9 THEN RAISE EXCEPTION 'FAIL: database or integration health metrics missing'; END IF;
    PERFORM 1 FROM audit.ops_slow_queries(5);
    RAISE NOTICE 'PASS: connections, replication/WAL, job and backup freshness, query latency, integration health, size (NFR-026: 4 families, 6 views)';

    -- 8. NFR-008 delivery latency is computable
    INSERT INTO messaging.notification_delivery (recipient_user_account_id, channel, subject, delivery_status, created_at, sent_at, delivered_at)
    VALUES (v_user, 'whatsapp', 's', 'delivered', now() - interval '1 minute', now() - interval '59 seconds', now() - interval '55 seconds');
    IF (SELECT p95_seconds_to_sent FROM audit.ops_delivery_latency WHERE channel = 'whatsapp') NOT BETWEEN 0.5 AND 1.5 THEN RAISE EXCEPTION 'FAIL: delivery latency view is wrong'; END IF;
    IF EXISTS (SELECT 1 FROM audit.ops_delivery_latency WHERE p95_seconds_to_sent < 0 OR p95_seconds_to_delivered < 0) THEN RAISE EXCEPTION 'FAIL: a delivery was sent before it was created (negative latency)'; END IF;
    RAISE NOTICE 'PASS: p95 time to sent and delivered is measurable per channel (NFR-008)';

    -- 9. NFR-018 consent coverage
    INSERT INTO profile.candidate_profile (user_account_id) VALUES (v_user);
    IF NOT EXISTS (SELECT 1 FROM core.accounts_missing_consent() WHERE user_account_id = v_user) THEN RAISE EXCEPTION 'FAIL: a candidate with no consent was not reported'; END IF;
    INSERT INTO core.consent_record (user_account_id, consent_type, consent_version, is_granted) VALUES (v_user, 'terms_of_service', 'v1', TRUE), (v_user, 'privacy_policy', 'v1', TRUE);
    IF EXISTS (SELECT 1 FROM core.accounts_missing_consent() WHERE user_account_id = v_user) THEN RAISE EXCEPTION 'FAIL: a candidate with both consents is still reported'; END IF;
    RAISE NOTICE 'PASS: candidates missing terms or privacy consent are reported (NFR-018)';

    -- 10. NFR-021: no cardholder data anywhere
    SELECT string_agg(table_schema || '.' || table_name || '.' || column_name, ', ') INTO v_text
      FROM information_schema.columns
     WHERE table_schema IN ('core','master','profile','recruitment','gig','commercial','sourcing','messaging','audit','analytics')
       AND column_name ~* '(card_?number|cardholder|card_?no|cvv|cvc|card_?expir|pan_?number|iban|bank_?account|routing_?number|account_?number)';
    IF v_text IS NOT NULL THEN RAISE EXCEPTION 'FAIL: columns that could hold cardholder or bank data: %', v_text; END IF;
    RAISE NOTICE 'PASS: no column can hold a card number, CVV, IBAN or bank account (NFR-021)';

    RAISE NOTICE '=== Integration and maintenance tests passed ===';
END
$$;

ROLLBACK;
