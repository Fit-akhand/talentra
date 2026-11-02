-- Test suite: tests/test_administration.sql
-- Prerequisite: migrations 001 through 012 applied.
-- Covers: BR-003, BR-004, BR-034, BR-039, REQ-006, REQ-007, SEC-001, SEC-002, SEC-003, SEC-005, SEC-010, SEC-011   (generated from the registers by scripts/lifecycle/tag_tests.py)

BEGIN;

DO $test$
DECLARE
    v_candidate_user_id BIGINT;
    v_candidate_profile_id BIGINT;
    v_recruiter_user_id BIGINT;
    v_other_user_id BIGINT;
    v_org_id BIGINT;
    v_role_id BIGINT;
    v_permission_id BIGINT;
    v_credential_id BIGINT;
    v_consent_id BIGINT;
    v_block_id BIGINT;
    v_audit_id BIGINT;
    v_error_id BIGINT;
    v_duplicate_credential_blocked BOOLEAN := FALSE;
    v_self_block_blocked BOOLEAN := FALSE;
    v_audit_update_blocked BOOLEAN := FALSE;
    v_audit_delete_blocked BOOLEAN := FALSE;
    v_is_visible BOOLEAN;
BEGIN
    -- 1. Fixture setup
    INSERT INTO core.user_account (email)
    VALUES ('admin_candidate@example.com')
    RETURNING id INTO v_candidate_user_id;

    INSERT INTO profile.candidate_profile (
        user_account_id,
        headline,
        total_experience_years,
        profile_status
    )
    VALUES (
        v_candidate_user_id,
        'Security Specialist',
        5.0,
        'active'
    )
    RETURNING id INTO v_candidate_profile_id;

    INSERT INTO core.user_account (email)
    VALUES ('admin_recruiter@example.com')
    RETURNING id INTO v_recruiter_user_id;

    INSERT INTO core.user_account (email)
    VALUES ('admin_other@example.com')
    RETURNING id INTO v_other_user_id;

    INSERT INTO recruitment.organization (
        name,
        slug,
        organization_type,
        created_by_user_account_id
    )
    VALUES (
        'Security Test Org',
        'security-test-org',
        'employer',
        v_recruiter_user_id
    )
    RETURNING id INTO v_org_id;

    -- 2. Test Permission & Role-Permission Assignment
    INSERT INTO core.permission (code, name, module, description)
    VALUES ('candidate.profile.view', 'View Candidate Profile', 'recruitment', 'Permits reading candidate details')
    RETURNING id INTO v_permission_id;

    SELECT id INTO v_role_id FROM core.role WHERE name = 'recruiter';

    INSERT INTO core.role_permission (role_id, permission_id)
    VALUES (v_role_id, v_permission_id);

    -- 3. Test User Credentials
    INSERT INTO core.user_credential (
        user_account_id,
        credential_type,
        credential_identifier,
        secret_hash,
        algorithm
    )
    VALUES (
        v_candidate_user_id,
        'password',
        'admin_candidate@example.com',
        '$argon2id$v=19$m=65536,t=3,p=4$some_hash_val',
        'argon2id'
    )
    RETURNING id INTO v_credential_id;

    BEGIN
        INSERT INTO core.user_credential (
            user_account_id,
            credential_type,
            credential_identifier,
            secret_hash
        )
        VALUES (
            v_other_user_id,
            'password',
            'admin_candidate@example.com',
            '$argon2id$v=19$m=65536,t=3,p=4$another_hash_val'
        );
    EXCEPTION
        WHEN unique_violation THEN
            v_duplicate_credential_blocked := TRUE;
    END;

    IF NOT v_duplicate_credential_blocked THEN
        RAISE EXCEPTION 'Duplicate credential identifier was accepted';
    END IF;

    -- 4. Test Consent Records
    INSERT INTO core.consent_record (
        user_account_id,
        consent_type,
        consent_version,
        is_granted,
        client_ip
    )
    VALUES (
        v_candidate_user_id,
        'privacy_policy',
        '2026.1',
        TRUE,
        '192.168.1.1'
    )
    RETURNING id INTO v_consent_id;

    -- 5. Test User Block & Candidate Visibility
    -- Self-block must fail
    BEGIN
        INSERT INTO core.user_block (
            blocker_user_account_id,
            blocked_user_account_id
        )
        VALUES (
            v_candidate_user_id,
            v_candidate_user_id
        );
    EXCEPTION
        WHEN check_violation THEN
            v_self_block_blocked := TRUE;
    END;

    IF NOT v_self_block_blocked THEN
        RAISE EXCEPTION 'Self block was allowed; expected check constraint violation';
    END IF;

    -- Prior to block, candidate is visible to recruiter
    v_is_visible := core.is_candidate_visible_to(v_candidate_profile_id, v_recruiter_user_id, v_org_id);
    IF NOT v_is_visible THEN
        RAISE EXCEPTION 'Candidate should be visible before block is created';
    END IF;

    -- Candidate blocks the recruiter organization
    INSERT INTO core.user_block (
        blocker_user_account_id,
        blocked_organization_id,
        block_reason
    )
    VALUES (
        v_candidate_user_id,
        v_org_id,
        'Previous bad hiring experience'
    )
    RETURNING id INTO v_block_id;

    -- Candidate should now be INVISIBLE to members of the blocked org
    v_is_visible := core.is_candidate_visible_to(v_candidate_profile_id, v_recruiter_user_id, v_org_id);
    IF v_is_visible THEN
        RAISE EXCEPTION 'Candidate is visible to blocked organization!';
    END IF;

    -- Candidate should still be visible to other uninvolved users
    v_is_visible := core.is_candidate_visible_to(v_candidate_profile_id, v_other_user_id, NULL);
    IF NOT v_is_visible THEN
        RAISE EXCEPTION 'Candidate should remain visible to unblocked third parties';
    END IF;

    -- 6. Test Append-Only Audit Trail
    INSERT INTO audit.audit_event (
        actor_user_account_id,
        action,
        entity_schema,
        entity_name,
        entity_id,
        client_ip
    )
    VALUES (
        v_candidate_user_id,
        'block.changed',
        'core',
        'user_block',
        v_block_id,
        '127.0.0.1'
    )
    RETURNING id INTO v_audit_id;

    -- Update on audit trail must be forbidden
    BEGIN
        UPDATE audit.audit_event
        SET action = 'tampered'
        WHERE id = v_audit_id;
    EXCEPTION
        WHEN raise_exception THEN
            v_audit_update_blocked := TRUE;
    END;

    IF NOT v_audit_update_blocked THEN
        RAISE EXCEPTION 'Audit event UPDATE was allowed; expected append-only protection';
    END IF;

    -- Delete on audit trail must be forbidden
    BEGIN
        DELETE FROM audit.audit_event
        WHERE id = v_audit_id;
    EXCEPTION
        WHEN raise_exception THEN
            v_audit_delete_blocked := TRUE;
    END;

    IF NOT v_audit_delete_blocked THEN
        RAISE EXCEPTION 'Audit event DELETE was allowed; expected append-only protection';
    END IF;

    -- 7. Test System Error Logging
    INSERT INTO audit.system_error_log (
        error_code,
        error_severity,
        error_message,
        context_json
    )
    VALUES (
        'ERR_AUTH_RATE_LIMIT',
        'warning',
        'Too many failed attempts for IP',
        '{"ip": "10.0.0.1", "attempts": 5}'::jsonb
    )
    RETURNING id INTO v_error_id;

    RAISE NOTICE 'PASS: permission and role assignments verified';
    RAISE NOTICE 'PASS: credential separation and uniqueness verified';
    RAISE NOTICE 'PASS: consent record tracking verified';
    RAISE NOTICE 'PASS: user block constraints and candidate visibility logic verified';
    RAISE NOTICE 'PASS: audit event append-only tampering protection verified';
    RAISE NOTICE 'PASS: system error log verified';
END;
$test$;

ROLLBACK;
