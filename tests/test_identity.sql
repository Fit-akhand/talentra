
-- Test suite: tests/test_identity.sql
-- Prerequisite: migrations 001 and 002 have been applied.

BEGIN;

-- Fixtures
INSERT INTO core.user_account (email, phone_e164, phone_country_code)
VALUES
    ('identity-test-a@example.com', '+919876543210', 'IN'),
    ('identity-test-b@example.com', NULL, NULL);

INSERT INTO core.role (name, description)
VALUES
    ('identity_test_candidate', 'Temporary role for identity tests');

INSERT INTO core.user_role (user_account_id, role_id)
SELECT u.id, r.id
FROM core.user_account AS u
CROSS JOIN core.role AS r
WHERE u.email = 'identity-test-a@example.com'
  AND r.name = 'identity_test_candidate';

-- Test 1: Reject duplicate email.
DO $$
BEGIN
    INSERT INTO core.user_account (email)
    VALUES ('identity-test-a@example.com');

    RAISE EXCEPTION 'FAIL: duplicate email was accepted';
EXCEPTION
    WHEN unique_violation THEN
        RAISE NOTICE 'PASS: duplicate email rejected';
END
$$;

-- Test 2: Reject uppercase email.
DO $$
BEGIN
    INSERT INTO core.user_account (email)
    VALUES ('Identity-Test-C@example.com');

    RAISE EXCEPTION 'FAIL: uppercase email was accepted';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE 'PASS: uppercase email rejected';
END
$$;

-- Test 3: Reject invalid account status.
DO $$
BEGIN
    INSERT INTO core.user_account (email, account_status)
    VALUES ('identity-test-invalid@example.com', 'unknown');

    RAISE EXCEPTION 'FAIL: invalid account status was accepted';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE 'PASS: invalid account status rejected';
END
$$;

-- Test 4: Reject an invalid E.164 phone number.
DO $$
BEGIN
    INSERT INTO core.user_account (email, phone_e164, phone_country_code)
    VALUES ('identity-test-phone@example.com', '9876543210', 'IN');

    RAISE EXCEPTION 'FAIL: invalid phone number was accepted';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE 'PASS: invalid phone number rejected';
END
$$;

-- Test 5: Reject a duplicate user-role assignment.
DO $$
BEGIN
    INSERT INTO core.user_role (user_account_id, role_id)
    SELECT u.id, r.id
    FROM core.user_account AS u
    CROSS JOIN core.role AS r
    WHERE u.email = 'identity-test-a@example.com'
      AND r.name = 'identity_test_candidate';

    RAISE EXCEPTION 'FAIL: duplicate user-role assignment was accepted';
EXCEPTION
    WHEN unique_violation THEN
        RAISE NOTICE 'PASS: duplicate user-role assignment rejected';
END
$$;

-- Test 6: Reject a role assignment for a nonexistent account.
DO $$
BEGIN
    INSERT INTO core.user_role (user_account_id, role_id)
    SELECT 9223372036854775807, r.id
    FROM core.role AS r
    WHERE r.name = 'identity_test_candidate';

    RAISE EXCEPTION 'FAIL: orphan user-role assignment was accepted';
EXCEPTION
    WHEN foreign_key_violation THEN
        RAISE NOTICE 'PASS: orphan user-role assignment rejected';
END
$$;

-- Test 7: Reject a session whose last activity precedes its start.
DO $$
BEGIN
    INSERT INTO core.user_session (
        user_account_id,
        device_identifier,
        session_token_hash,
        started_at,
        last_activity_at
    )
    SELECT
        id,
        'identity-test-device',
        'identity-test-invalid-session-hash',
        TIMESTAMPTZ '2026-01-02 12:00:00+00',
        TIMESTAMPTZ '2026-01-01 12:00:00+00'
    FROM core.user_account
    WHERE email = 'identity-test-a@example.com';

    RAISE EXCEPTION 'FAIL: invalid session timestamps were accepted';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE 'PASS: invalid session timestamps rejected';
END
$$;

-- Test 8: Verify valid session insertion.
INSERT INTO core.user_session (
    user_account_id,
    device_identifier,
    session_token_hash
)
SELECT
    id,
    'identity-test-device-valid',
    'identity-test-valid-session-hash'
FROM core.user_account
WHERE email = 'identity-test-a@example.com';

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM core.user_session AS s
        JOIN core.user_account AS u
          ON u.id = s.user_account_id
        WHERE u.email = 'identity-test-a@example.com'
          AND s.session_token_hash = 'identity-test-valid-session-hash'
    ) THEN
        RAISE EXCEPTION 'FAIL: valid session was not persisted';
    END IF;

    RAISE NOTICE 'PASS: valid session inserted';
END
$$;

ROLLBACK;

-- If all checks passed, the transaction should finish with ROLLBACK.
