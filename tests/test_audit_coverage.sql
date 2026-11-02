-- Test suite: tests/test_audit_coverage.sql
-- Covers: SEC-003, NFR-016, docket section 3 ("Every sensitive action must be recorded in an audit trail"), audit gaps AG-01 to AG-09
-- Prerequisite: migrations 001-029 have been applied.
-- Isolation: one transaction, rolled back.
--
-- Performs each of the 14 sensitive action classes and checks the trail, then checks what the trail must NOT contain.

BEGIN;

DO $$
DECLARE
    v_admin BIGINT; v_target BIGINT; v_other BIGINT; v_org BIGINT; v_role_id BIGINT; v_perm_id BIGINT;
    v_sess BIGINT; v_n INTEGER; v_text TEXT; v_order BIGINT; v_lic BIGINT; v_caught BOOLEAN;
    v_hash TEXT := '$argon2id$v=19$m=65536,t=3,p=4$c2FsdA$TOPSECRETHASHVALUE';
    v_start BIGINT := COALESCE((SELECT max(id) FROM audit.audit_event), 0);   -- the database may already hold events (a seeded one does); count only what this test makes
BEGIN
    RAISE NOTICE '=== Audit coverage: 14 sensitive action classes ===';

    INSERT INTO core.user_account (email) VALUES ('ac2-admin@example.com') RETURNING id INTO v_admin;
    INSERT INTO core.user_account (email) VALUES ('ac2-target@example.com') RETURNING id INTO v_target;
    INSERT INTO core.user_account (email) VALUES ('ac2-other@example.com')  RETURNING id INTO v_other;
    SELECT id INTO v_role_id FROM core.role WHERE name = 'admin';
    INSERT INTO core.user_role (user_account_id, role_id) VALUES (v_admin, v_role_id);
    INSERT INTO recruitment.organization (name, slug, created_by_user_account_id, organization_status)
    VALUES ('AC2 Org', 'ac2-org', v_admin, 'active') RETURNING id INTO v_org;

    -- every class has at least one action code
    SELECT count(*) INTO v_n FROM audit.sensitive_class_coverage WHERE action_codes = 0;
    IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL: % of the 14 sensitive classes have no action code', v_n; END IF;
    RAISE NOTICE 'PASS: all 14 sensitive action classes have an action code in the catalogue';

    -- vocabulary is closed
    v_caught := FALSE;
    BEGIN INSERT INTO audit.audit_event (action, entity_schema, entity_name) VALUES ('made.up.action', 'core', 'x');
    EXCEPTION WHEN foreign_key_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: an action outside the catalogue was accepted'; END IF;

    -- class 1: login. class 4: refused login. class 3: revocation
    PERFORM set_config('app.current_user_id', v_target::TEXT, true);
    v_sess := core.create_session_with_device_limit(v_target, 'dv1', encode(sha256('t1'::bytea), 'hex'), NULL, 'desktop', '10.0.0.9');
    PERFORM core.create_session_with_device_limit(v_target, 'dv2', encode(sha256('t2'::bytea), 'hex'));
    PERFORM core.create_session_with_device_limit(v_target, 'dv3', encode(sha256('t3'::bytea), 'hex'));
    IF (SELECT count(*) FROM audit.audit_event WHERE id > v_start AND action = 'auth.login' AND actor_user_account_id = v_target) <> 2 THEN
        RAISE EXCEPTION 'FAIL: class 1: two successful logins should leave two auth.login events'; END IF;
    IF (SELECT count(*) FROM audit.audit_event WHERE id > v_start AND action = 'device.limit_exceeded' AND actor_user_account_id = v_target) <> 1 THEN
        RAISE EXCEPTION 'FAIL: class 4: the refused login was not audited'; END IF;
    PERFORM core.revoke_user_session(v_sess, v_target, 'test');
    IF NOT EXISTS (SELECT 1 FROM audit.audit_event WHERE id > v_start AND action = 'session.revoked' AND entity_id = v_sess) THEN
        RAISE EXCEPTION 'FAIL: class 3: revocation not audited'; END IF;
    RAISE NOTICE 'PASS: classes 1, 3, 4 (login, revocation, device-limit refusal)';

    -- class 2: failed logins, and lockout
    FOR i IN 1..5 LOOP PERFORM core.record_login_failure('Nobody@Example.com', '10.0.0.7', 'unknown_account'); END LOOP;
    IF (SELECT count(*) FROM audit.audit_event WHERE id > v_start AND action = 'auth.failed') <> 5 THEN RAISE EXCEPTION 'FAIL: class 2: failures not recorded'; END IF;
    IF EXISTS (SELECT 1 FROM audit.audit_event WHERE id > v_start AND action = 'auth.failed' AND new_values_json::TEXT ILIKE '%nobody@example.com%') THEN
        RAISE EXCEPTION 'FAIL: class 2: the identifier was stored in clear text'; END IF;
    IF NOT core.is_login_locked('nobody@example.com') THEN RAISE EXCEPTION 'FAIL: five failures did not lock the identifier (case-insensitively)'; END IF;
    IF core.is_login_locked('someone-else@example.com') THEN RAISE EXCEPTION 'FAIL: an unrelated identifier is locked'; END IF;
    RAISE NOTICE 'PASS: class 2 (failed logins recorded without the identifier; lockout after 5 in 15 minutes)';

    -- class 5: credentials, with no secret in the log
    INSERT INTO core.user_credential (user_account_id, credential_type, credential_identifier, secret_hash)
    VALUES (v_target, 'password', 'ac2-target@example.com', v_hash);
    UPDATE core.user_credential SET secret_hash = '$argon2id$v=19$m=65536,t=3,p=4$c2FsdA$ANOTHERSECRET' WHERE user_account_id = v_target;
    IF (SELECT count(*) FROM audit.audit_event WHERE id > v_start AND action = 'credential.changed') <> 2 THEN RAISE EXCEPTION 'FAIL: class 5: set and rotate not both audited'; END IF;
    IF EXISTS (SELECT 1 FROM audit.audit_event WHERE id > v_start AND action = 'credential.changed'
                AND (new_values_json::TEXT LIKE '%TOPSECRETHASHVALUE%' OR new_values_json::TEXT LIKE '%ANOTHERSECRET%' OR new_values_json::TEXT LIKE '%$argon2id$%' OR new_values_json::TEXT ILIKE '%ac2-target@%')) THEN
        RAISE EXCEPTION 'FAIL: class 5: a secret or the login identifier reached the audit log'; END IF;
    RAISE NOTICE 'PASS: class 5 (credential change recorded; no secret, no identifier in the payload)';

    -- class 6: roles and permissions
    PERFORM set_config('app.current_user_id', v_admin::TEXT, true);
    SELECT id INTO v_role_id FROM core.role WHERE name = 'recruiter';
    INSERT INTO core.user_role (user_account_id, role_id) VALUES (v_other, v_role_id);
    DELETE FROM core.user_role WHERE user_account_id = v_other;
    SELECT id INTO v_perm_id FROM core.permission WHERE code = 'job.search';
    DELETE FROM core.role_permission WHERE role_id = v_role_id AND permission_id = v_perm_id;
    INSERT INTO core.role_permission (role_id, permission_id) VALUES (v_role_id, v_perm_id);
    IF NOT EXISTS (SELECT 1 FROM audit.audit_event WHERE id > v_start AND action = 'role.assigned' AND actor_user_account_id = v_admin)
       OR NOT EXISTS (SELECT 1 FROM audit.audit_event WHERE id > v_start AND action = 'role.removed' AND actor_user_account_id = v_admin)
       OR (SELECT count(*) FROM audit.audit_event WHERE id > v_start AND action = 'role_permission.changed') <> 2 THEN
        RAISE EXCEPTION 'FAIL: class 6: role or permission changes not audited with the acting admin'; END IF;
    RAISE NOTICE 'PASS: class 6 (role assigned/removed, permission granted/removed, with the acting administrator)';

    -- class 7: account status, with no contact data in the log
    UPDATE core.user_account SET account_status = 'suspended' WHERE id = v_other;
    UPDATE core.user_account SET phone_e164 = '+919812345678', phone_country_code = 'IN' WHERE id = v_other;   -- not a status change: not logged
    IF (SELECT count(*) FROM audit.audit_event WHERE id > v_start AND action = 'account.status_changed' AND entity_id = v_other) <> 1 THEN
        RAISE EXCEPTION 'FAIL: class 7: exactly one status change should be logged'; END IF;
    IF EXISTS (SELECT 1 FROM audit.audit_event WHERE id > v_start AND action = 'account.status_changed' AND (new_values_json::TEXT ILIKE '%ac2-other@%' OR new_values_json::TEXT LIKE '%9812345678%')) THEN
        RAISE EXCEPTION 'FAIL: class 7: contact details reached the audit log'; END IF;
    UPDATE recruitment.organization SET organization_status = 'suspended' WHERE id = v_org;
    IF NOT EXISTS (SELECT 1 FROM audit.audit_event WHERE id > v_start AND action = 'account.status_changed' AND organization_id = v_org) THEN
        RAISE EXCEPTION 'FAIL: class 7: organisation status change not audited with its organisation'; END IF;
    RAISE NOTICE 'PASS: class 7 (account and organisation status; other updates and personal data stay out)';

    -- class 8: impersonation
    PERFORM core.begin_impersonation(v_target, 'Investigating support ticket 4521');
    INSERT INTO core.user_block (blocker_user_account_id, blocked_user_account_id) VALUES (v_target, v_other);     -- done "as" the target
    IF (SELECT impersonator_user_account_id FROM audit.audit_event WHERE id > v_start AND action = 'block.changed' ORDER BY id DESC LIMIT 1) IS DISTINCT FROM v_admin
       OR (SELECT actor_user_account_id FROM audit.audit_event WHERE id > v_start AND action = 'block.changed' ORDER BY id DESC LIMIT 1) IS DISTINCT FROM v_target THEN
        RAISE EXCEPTION 'FAIL: class 8: an event made while impersonating does not name both the target and the administrator'; END IF;
    PERFORM core.end_impersonation();
    IF core.current_app_user_id() IS DISTINCT FROM v_admin THEN RAISE EXCEPTION 'FAIL: class 8: ending impersonation did not restore the administrator'; END IF;
    IF (SELECT count(*) FROM audit.audit_event WHERE id > v_start AND action IN ('admin.impersonation_started', 'admin.impersonation_ended')) <> 2 THEN
        RAISE EXCEPTION 'FAIL: class 8: start and end not both recorded'; END IF;
    v_caught := FALSE;
    BEGIN PERFORM core.begin_impersonation(v_other, 'short');
    EXCEPTION WHEN raise_exception THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: class 8: impersonation without a real reason was accepted'; END IF;
    PERFORM set_config('app.current_user_id', v_target::TEXT, true);
    v_caught := FALSE;
    BEGIN PERFORM core.begin_impersonation(v_other, 'A perfectly long reason here');
    EXCEPTION WHEN insufficient_privilege THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: class 8: a non-administrator was allowed to impersonate'; END IF;
    PERFORM set_config('app.current_user_id', v_admin::TEXT, true);
    v_caught := FALSE;
    BEGIN PERFORM core.begin_impersonation(v_admin, 'Trying to impersonate an admin');
    EXCEPTION WHEN insufficient_privilege THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: class 8: an administrator was allowed to impersonate an administrator'; END IF;
    RAISE NOTICE 'PASS: class 8 (impersonation needs a reason and an administrator, refuses admins, and marks every event made meanwhile)';

    -- class 9: consent; class 10: block removal
    INSERT INTO core.consent_record (user_account_id, consent_type, consent_version, is_granted, client_ip, user_agent)
    VALUES (v_target, 'privacy_policy', 'v1', TRUE, '10.1.1.1', 'TestAgent/1.0');
    UPDATE core.consent_record SET is_granted = FALSE, revoked_at = now() WHERE user_account_id = v_target;
    IF (SELECT count(*) FROM audit.audit_event WHERE id > v_start AND action = 'consent.changed') <> 2 THEN RAISE EXCEPTION 'FAIL: class 9: grant and withdrawal not both audited'; END IF;
    IF EXISTS (SELECT 1 FROM audit.audit_event WHERE id > v_start AND action = 'consent.changed' AND (new_values_json::TEXT LIKE '%10.1.1.1%' OR new_values_json::TEXT LIKE '%TestAgent%')) THEN
        RAISE EXCEPTION 'FAIL: class 9: client address or agent reached the audit log'; END IF;
    DELETE FROM core.user_block WHERE blocker_user_account_id = v_target;
    IF (SELECT count(*) FROM audit.audit_event WHERE id > v_start AND action = 'block.changed') <> 2 THEN RAISE EXCEPTION 'FAIL: class 10: block and unblock not both audited'; END IF;
    RAISE NOTICE 'PASS: classes 9 and 10 (consent and blocks; client details stay out)';

    -- classes 11, 12, 13: the append-only domain ledgers are the trail, so they must really be tamper-proof
    FOR v_text IN SELECT trail_table FROM audit.action_catalogue WHERE trail = 'domain_ledger' LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid = v_text::regclass AND NOT t.tgisinternal
                        AND t.tgfoid IN ('audit.prevent_modification'::regproc, 'commercial.prevent_ledger_tampering'::regproc,
                                         'commercial.prevent_download_history_tampering'::regproc)) THEN
            RAISE EXCEPTION 'FAIL: classes 11-13: % is named as a trail but is not append-only', v_text;
        END IF;
    END LOOP;
    RAISE NOTICE 'PASS: classes 11, 12, 13 (view/download, stage change and wallet trails are append-only ledgers)';

    -- class 14: payment, refund, licence; organisation scope
    INSERT INTO commercial.payment_order (organization_id, user_account_id, gateway_provider, gateway_order_id, order_amount, currency_code, idempotency_key)
    VALUES (v_org, v_admin, 'razorpay', 'order_SECRETREF_1', 100, 'USD', 'req-123') RETURNING id INTO v_order;
    UPDATE commercial.payment_order SET order_status = 'authorized' WHERE id = v_order;
    INSERT INTO commercial.payment_refund (payment_order_id, refund_amount, currency_code, gateway_refund_ref, refund_reason, refund_status)
    VALUES (v_order, 10, 'USD', 'rfnd_SECRETREF_2', 'customer asked', 'processed');
    INSERT INTO commercial.subscription_licence (organization_id, licence_key, licence_name, max_users, max_devices_per_user, valid_from, valid_to, licence_status)
    VALUES (v_org, 'LIC-AC2-SECRETKEY', 'Test', 5, 2, now() - interval '1 day', now() + interval '1 year', 'active') RETURNING id INTO v_lic;
    UPDATE commercial.subscription_licence SET max_devices_per_user = 3 WHERE id = v_lic;
    IF (SELECT count(*) FROM audit.audit_event WHERE id > v_start AND action = 'payment.changed' AND organization_id = v_org) <> 2
       OR (SELECT count(*) FROM audit.audit_event WHERE id > v_start AND action = 'refund.issued') <> 1
       OR (SELECT count(*) FROM audit.audit_event WHERE id > v_start AND action = 'licence.changed' AND organization_id = v_org) <> 2 THEN
        RAISE EXCEPTION 'FAIL: class 14: payment, refund and licence changes not all audited'; END IF;
    IF EXISTS (SELECT 1 FROM audit.audit_event WHERE id > v_start AND new_values_json::TEXT LIKE '%SECRETREF%' OR new_values_json::TEXT LIKE '%SECRETKEY%') THEN
        RAISE EXCEPTION 'FAIL: class 14: a gateway reference or licence key reached the audit log'; END IF;
    v_caught := FALSE;
    BEGIN INSERT INTO commercial.payment_order (organization_id, user_account_id, gateway_provider, gateway_order_id, order_amount, currency_code, idempotency_key)
          VALUES (v_org, v_admin, 'razorpay', 'order_other', 100, 'USD', 'req-123');
    EXCEPTION WHEN unique_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: a retried payment request with the same idempotency key created a second order'; END IF;
    RAISE NOTICE 'PASS: class 14 (payment, refund, licence audited with their organisation; references stay out; retries are idempotent)';

    -- tenant-scoped view: an organisation sees its own events and not the payloads
    INSERT INTO recruitment.organization_member (organization_id, user_account_id, organization_role, membership_status, joined_at)
    VALUES (v_org, v_admin, 'owner', 'active', now());
    EXECUTE 'SET LOCAL ROLE talentra_app';
    PERFORM set_config('app.current_org_id', v_org::TEXT, true);
    SELECT count(*) INTO v_n FROM audit.org_audit_event WHERE id > v_start;
    IF v_n < 4 THEN RAISE EXCEPTION 'FAIL: the organisation sees only % of its events', v_n; END IF;
    IF EXISTS (SELECT 1 FROM audit.org_audit_event WHERE organization_id <> v_org) THEN RAISE EXCEPTION 'FAIL: another organisation''s events are visible'; END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'audit' AND table_name = 'org_audit_event' AND column_name IN ('new_values_json', 'old_values_json', 'client_ip', 'user_agent')) THEN
        RAISE EXCEPTION 'FAIL: the organisation view exposes payloads or client details'; END IF;
    PERFORM set_config('app.current_org_id', '', true);
    SELECT count(*) INTO v_n FROM audit.org_audit_event;
    IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL: with no organisation context the view shows % events', v_n; END IF;
    EXECUTE 'RESET ROLE';
    RAISE NOTICE 'PASS: an organisation reads only its own events, without payloads (AG-03)';

    -- history survives: a user with audit events cannot be deleted
    v_caught := FALSE;
    BEGIN DELETE FROM core.user_account WHERE id = v_target;
    EXCEPTION WHEN foreign_key_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: a user with audit history was deleted, orphaning the trail (AG-08)'; END IF;
    RAISE NOTICE 'PASS: deleting a user with audit history is refused (AG-08)';

    RAISE NOTICE '=== Audit coverage tests passed: 14 of 14 classes ===';
END
$$;

ROLLBACK;
