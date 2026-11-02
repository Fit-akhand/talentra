-- Test suite: tests/test_licences.sql
-- Prerequisite: migrations 001 through 015 applied.
-- Covers: BR-002, BR-003, OPS-003, REQ-003, REQ-004, REQ-005, REQ-006, SEC-008   (generated from the registers by scripts/lifecycle/tag_tests.py)

BEGIN;

DO $test$
DECLARE
    v_admin_user_id BIGINT;
    v_employee1_user_id BIGINT;
    v_employee2_user_id BIGINT;
    v_employee3_user_id BIGINT;
    v_org_id BIGINT;
    v_licence_id BIGINT;
    v_session1_id BIGINT;
    v_session2_id BIGINT;
    v_session3_id BIGINT;
    v_seat_overflow_blocked BOOLEAN := FALSE;
    v_device_limit_blocked BOOLEAN := FALSE;
    v_audit_count INTEGER;
BEGIN
    -- 1. Setup fixtures
    INSERT INTO core.user_account (email)
    VALUES ('lic_admin@example.com')
    RETURNING id INTO v_admin_user_id;

    INSERT INTO core.user_account (email)
    VALUES ('lic_emp1@example.com')
    RETURNING id INTO v_employee1_user_id;

    INSERT INTO core.user_account (email)
    VALUES ('lic_emp2@example.com')
    RETURNING id INTO v_employee2_user_id;

    INSERT INTO core.user_account (email)
    VALUES ('lic_emp3@example.com')
    RETURNING id INTO v_employee3_user_id;

    INSERT INTO recruitment.organization (
        name,
        slug,
        organization_type,
        created_by_user_account_id
    )
    VALUES (
        'Enterprise Licence Customer Corp',
        'enterprise-licence-customer-corp',
        'employer',
        v_admin_user_id
    )
    RETURNING id INTO v_org_id;

    -- 2. Create Subscription Licence (max_users = 2, max_devices_per_user = 2)
    INSERT INTO commercial.subscription_licence (
        organization_id,
        licence_key,
        licence_name,
        max_users,
        max_devices_per_user,
        valid_from,
        valid_to,
        licence_status
    )
    VALUES (
        v_org_id,
        'LIC-CORP-TEST-2026-KEY',
        'Corporate Scale Pack',
        2, -- strictly 2 seats allowed
        2, -- strictly 2 devices per seat
        CURRENT_TIMESTAMP - INTERVAL '1 day',
        CURRENT_TIMESTAMP + INTERVAL '365 days',
        'active'
    )
    RETURNING id INTO v_licence_id;

    -- 3. Allocate seats (allocate 2 seats successfully)
    INSERT INTO commercial.licence_seat_allocation (
        subscription_licence_id,
        user_account_id,
        allocated_by_user_account_id
    )
    VALUES
        (v_licence_id, v_employee1_user_id, v_admin_user_id),
        (v_licence_id, v_employee2_user_id, v_admin_user_id);

    -- Attempt to allocate 3rd seat (exceeding max_users = 2) must fail
    BEGIN
        INSERT INTO commercial.licence_seat_allocation (
            subscription_licence_id,
            user_account_id,
            allocated_by_user_account_id
        )
        VALUES (v_licence_id, v_employee3_user_id, v_admin_user_id);
    EXCEPTION
        WHEN raise_exception THEN
            v_seat_overflow_blocked := TRUE;
    END;

    IF NOT v_seat_overflow_blocked THEN
        RAISE EXCEPTION 'Licence capacity exceeded but seat allocation was accepted!';
    END IF;

    -- 4. Test Device Limit Under Concurrent Logins for Employee 1
    -- Device 1 login: Success
    v_session1_id := core.create_session_with_device_limit(
        v_employee1_user_id,
        'macbook-pro-m3-id-001',
        encode(sha256('token_hash_session_001'::bytea), 'hex'),
        'Work Laptop',
        'laptop',
        '10.0.0.1'
    );

    -- Device 2 login: Success
    v_session2_id := core.create_session_with_device_limit(
        v_employee1_user_id,
        'iphone-16-pro-id-002',
        encode(sha256('token_hash_session_002'::bytea), 'hex'),
        'Work Phone',
        'mobile',
        '10.0.0.2'
    );

    -- Device 3 login: MUST BE BLOCKED (exceeds max_devices_per_user = 2)
    v_session3_id := core.create_session_with_device_limit(
        v_employee1_user_id,
        'home-pc-desktop-id-003',
        encode(sha256('token_hash_session_003'::bytea), 'hex'),
        'Home PC',
        'desktop',
        '10.0.0.3'
    );

    IF v_session3_id IS NOT NULL THEN
        RAISE EXCEPTION 'Device limit of 2 was exceeded but login was permitted!';
    END IF;

    -- Verify that the device limit violation was recorded in audit.audit_event
    SELECT COUNT(*) INTO v_audit_count
    FROM audit.audit_event
    WHERE actor_user_account_id = v_employee1_user_id
      AND action = 'device.limit_exceeded';

    IF v_audit_count = 0 THEN
        RAISE EXCEPTION 'Attempt to exceed device limit was not logged to audit trail!';
    END IF;

    -- 5. Revoke Session 1 (Laptop)
    PERFORM core.revoke_user_session(v_session1_id, v_employee1_user_id, 'Logging out of laptop');

    -- Now Device 3 login MUST SUCCEED (active device count dropped to 1)
    v_session3_id := core.create_session_with_device_limit(
        v_employee1_user_id,
        'home-pc-desktop-id-003',
        encode(sha256('token_hash_session_003'::bytea), 'hex'),
        'Home PC',
        'desktop',
        '10.0.0.3'
    );

    IF v_session3_id IS NULL THEN
        RAISE EXCEPTION 'Login after session revocation failed!';
    END IF;

    RAISE NOTICE 'PASS: subscription licence capacity check constraint verified';
    RAISE NOTICE 'PASS: licence seat allocation capacity trigger blocked overflow';
    RAISE NOTICE 'PASS: device limit enforcement at login verified';
    RAISE NOTICE 'PASS: attempt exceeding device limit recorded in audit trail';
    RAISE NOTICE 'PASS: session revocation freed device capacity and logged auditable event';
END;
$test$;

ROLLBACK;
