-- Migration: 015_create_licences_and_device_limits.sql
-- Purpose: Implement commercial subscription licences, seat allocations, user device registration, and database-level enforcement of device limits under concurrent logins.
-- Requires: 001_create_schemas.sql, 002_create_identity.sql, 007_create_organization.sql, 012_create_administration_security.sql
-- Engine: PostgreSQL 17

BEGIN;

-- 1. Subscription Licences
CREATE TABLE IF NOT EXISTS commercial.subscription_licence (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    organization_id BIGINT NOT NULL,
    licence_key VARCHAR(64) NOT NULL,
    licence_name VARCHAR(100) NOT NULL,
    max_users INTEGER NOT NULL,
    max_devices_per_user INTEGER NOT NULL,
    valid_from TIMESTAMPTZ NOT NULL,
    valid_to TIMESTAMPTZ NOT NULL,
    licence_status VARCHAR(20) NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_subscription_licence PRIMARY KEY (id),
    CONSTRAINT uq_subscription_licence_key UNIQUE (licence_key),

    CONSTRAINT fk_subscription_licence_organization
        FOREIGN KEY (organization_id)
        REFERENCES recruitment.organization (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT ck_subscription_licence_max_users
        CHECK (max_users > 0),

    CONSTRAINT ck_subscription_licence_max_devices
        CHECK (max_devices_per_user > 0),

    CONSTRAINT ck_subscription_licence_dates
        CHECK (valid_to >= valid_from),

    CONSTRAINT ck_subscription_licence_status
        CHECK (licence_status IN ('active', 'expired', 'suspended', 'cancelled'))
);

CREATE INDEX IF NOT EXISTS idx_subscription_licence_org_status
    ON commercial.subscription_licence (organization_id, licence_status);

COMMENT ON TABLE commercial.subscription_licence IS
    'Corporate subscription licences specifying positive maximum users and device limits per user';


-- 2. Licence Seat Allocations
CREATE TABLE IF NOT EXISTS commercial.licence_seat_allocation (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    subscription_licence_id BIGINT NOT NULL,
    user_account_id BIGINT NOT NULL,
    allocated_by_user_account_id BIGINT,
    allocated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    revoked_at TIMESTAMPTZ,

    CONSTRAINT pk_licence_seat_allocation PRIMARY KEY (id),

    CONSTRAINT fk_licence_seat_licence
        FOREIGN KEY (subscription_licence_id)
        REFERENCES commercial.subscription_licence (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT fk_licence_seat_user
        FOREIGN KEY (user_account_id)
        REFERENCES core.user_account (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT fk_licence_seat_allocated_by
        FOREIGN KEY (allocated_by_user_account_id)
        REFERENCES core.user_account (id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,

    CONSTRAINT ck_licence_seat_revoked_at
        CHECK (revoked_at IS NULL OR revoked_at >= allocated_at)
);

-- At most one active seat per user per licence
CREATE UNIQUE INDEX IF NOT EXISTS uq_licence_seat_active_user
    ON commercial.licence_seat_allocation (subscription_licence_id, user_account_id)
    WHERE revoked_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_licence_seat_user
    ON commercial.licence_seat_allocation (user_account_id)
    WHERE revoked_at IS NULL;

COMMENT ON TABLE commercial.licence_seat_allocation IS
    'Active seat assignments mapping users to corporate subscription licences';

-- Trigger to verify allocated seats do not exceed max_users
CREATE OR REPLACE FUNCTION commercial.enforce_licence_max_users()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_max_users INTEGER;
    v_current_active_seats INTEGER;
BEGIN
    SELECT max_users INTO v_max_users
    FROM commercial.subscription_licence
    WHERE id = NEW.subscription_licence_id
    FOR UPDATE;

    SELECT COUNT(*) INTO v_current_active_seats
    FROM commercial.licence_seat_allocation
    WHERE subscription_licence_id = NEW.subscription_licence_id
      AND revoked_at IS NULL
      AND id <> COALESCE(NEW.id, -1);

    IF (v_current_active_seats + 1) > v_max_users THEN
        RAISE EXCEPTION 'Licence capacity exceeded: maximum % users allowed on licence %',
            v_max_users, NEW.subscription_licence_id;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_licence_max_users ON commercial.licence_seat_allocation;
CREATE TRIGGER trg_enforce_licence_max_users
BEFORE INSERT ON commercial.licence_seat_allocation
FOR EACH ROW
WHEN (NEW.revoked_at IS NULL)
EXECUTE FUNCTION commercial.enforce_licence_max_users();


-- 3. Registered User Devices
CREATE TABLE IF NOT EXISTS core.user_device (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    user_account_id BIGINT NOT NULL,
    device_identifier VARCHAR(255) NOT NULL,
    device_name VARCHAR(100),
    device_type VARCHAR(30) NOT NULL DEFAULT 'desktop',
    operating_system VARCHAR(50),
    is_trusted BOOLEAN NOT NULL DEFAULT TRUE,
    first_seen_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    revoked_at TIMESTAMPTZ,

    CONSTRAINT pk_user_device PRIMARY KEY (id),
    CONSTRAINT uq_user_device_identifier UNIQUE (user_account_id, device_identifier),

    CONSTRAINT fk_user_device_user
        FOREIGN KEY (user_account_id)
        REFERENCES core.user_account (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT ck_user_device_type
        CHECK (device_type IN ('desktop', 'laptop', 'mobile', 'tablet', 'other'))
);

CREATE INDEX IF NOT EXISTS idx_user_device_user
    ON core.user_device (user_account_id);

COMMENT ON TABLE core.user_device IS
    'Known physical and virtual devices registered per user account';


-- 4. Database-level Device Limit Enforcement at Login
CREATE OR REPLACE FUNCTION core.create_session_with_device_limit(
    p_user_account_id BIGINT,
    p_device_identifier VARCHAR(255),
    p_session_token_hash VARCHAR(255),
    p_device_name VARCHAR(100) DEFAULT NULL,
    p_device_type VARCHAR(30) DEFAULT 'desktop',
    p_client_ip VARCHAR(45) DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_max_devices INTEGER := 2; -- Default allowance for personal/free accounts
    v_active_sessions_count INTEGER := 0;
    v_is_existing_active_device BOOLEAN := FALSE;
    v_new_session_id BIGINT;
BEGIN
    -- Lock user account to serialize concurrent login attempts
    PERFORM id FROM core.user_account WHERE id = p_user_account_id FOR UPDATE;

    -- Determine allowed devices from active subscription licence seat if present
    SELECT sl.max_devices_per_user INTO v_max_devices
    FROM commercial.licence_seat_allocation lsa
    JOIN commercial.subscription_licence sl ON lsa.subscription_licence_id = sl.id
    WHERE lsa.user_account_id = p_user_account_id
      AND lsa.revoked_at IS NULL
      AND sl.licence_status = 'active'
      AND CURRENT_TIMESTAMP BETWEEN sl.valid_from AND sl.valid_to
    ORDER BY sl.max_devices_per_user DESC
    LIMIT 1;

    IF v_max_devices IS NULL THEN
        v_max_devices := 2; -- Standard fallback
    END IF;

    -- Count active sessions for distinct devices
    SELECT COUNT(DISTINCT device_identifier) INTO v_active_sessions_count
    FROM core.user_session
    WHERE user_account_id = p_user_account_id
      AND ended_at IS NULL
      AND revoked_at IS NULL;

    -- Check if this specific device already holds an active session
    SELECT EXISTS (
        SELECT 1
        FROM core.user_session
        WHERE user_account_id = p_user_account_id
          AND device_identifier = p_device_identifier
          AND ended_at IS NULL
          AND revoked_at IS NULL
    ) INTO v_is_existing_active_device;

    -- If limit reached and this is a NEW device, record in audit trail and reject login
    IF (v_active_sessions_count >= v_max_devices) AND NOT v_is_existing_active_device THEN
        INSERT INTO audit.audit_event (
            actor_user_account_id,
            action,
            entity_schema,
            entity_name,
            entity_id,
            new_values_json,
            client_ip
        )
        VALUES (
            p_user_account_id,
            'device.limit_exceeded',
            'core',
            'user_session',
            p_user_account_id,
            jsonb_build_object(
                'device_identifier', p_device_identifier,
                'active_sessions', v_active_sessions_count,
                'max_devices_allowed', v_max_devices
            ),
            p_client_ip
        );

        -- Return NULL to reject session while preserving the audit event
        RETURN NULL;
    END IF;

    -- Register or update device metadata
    INSERT INTO core.user_device (
        user_account_id,
        device_identifier,
        device_name,
        device_type,
        last_seen_at
    )
    VALUES (
        p_user_account_id,
        p_device_identifier,
        p_device_name,
        p_device_type,
        CURRENT_TIMESTAMP
    )
    ON CONFLICT (user_account_id, device_identifier) DO UPDATE
    SET last_seen_at = CURRENT_TIMESTAMP,
        device_name = COALESCE(EXCLUDED.device_name, core.user_device.device_name);

    -- Create active session
    INSERT INTO core.user_session (
        user_account_id,
        device_identifier,
        session_token_hash,
        started_at,
        last_activity_at
    )
    VALUES (
        p_user_account_id,
        p_device_identifier,
        p_session_token_hash,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
    )
    RETURNING id INTO v_new_session_id;

    RETURN v_new_session_id;
END;
$$;


-- 5. Auditable Session Revocation
CREATE OR REPLACE FUNCTION core.revoke_user_session(
    p_session_id BIGINT,
    p_actor_user_id BIGINT,
    p_revocation_reason VARCHAR(255) DEFAULT 'User requested logout'
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_user_account_id BIGINT;
    v_device_identifier VARCHAR(255);
BEGIN
    SELECT user_account_id, device_identifier
    INTO v_user_account_id, v_device_identifier
    FROM core.user_session
    WHERE id = p_session_id;

    IF v_user_account_id IS NULL THEN
        RAISE EXCEPTION 'Session % does not exist', p_session_id;
    END IF;

    UPDATE core.user_session
    SET ended_at = CURRENT_TIMESTAMP,
        revoked_at = CURRENT_TIMESTAMP
    WHERE id = p_session_id;

    -- Record revocation in audit log
    INSERT INTO audit.audit_event (
        actor_user_account_id,
        action,
        entity_schema,
        entity_name,
        entity_id,
        new_values_json
    )
    VALUES (
        p_actor_user_id,
        'session.revoked',
        'core',
        'user_session',
        p_session_id,
        jsonb_build_object(
            'device_identifier', v_device_identifier,
            'reason', p_revocation_reason
        )
    );
END;
$$;

COMMIT;
