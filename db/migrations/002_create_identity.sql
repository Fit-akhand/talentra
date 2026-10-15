
-- Migration: 002_create_identity.sql
-- Purpose: Establish Talentra's shared identity and session foundation.
-- Requires: 001_create_schemas.sql
-- Engine: PostgreSQL 17

BEGIN;

-- 1. Accounts
CREATE TABLE core.user_account (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    email VARCHAR(254) NOT NULL,
    phone_e164 VARCHAR(16),
    phone_country_code VARCHAR(2),
    password_hash TEXT,
    account_status VARCHAR(20) NOT NULL DEFAULT 'active',
    preferred_language VARCHAR(10) NOT NULL DEFAULT 'en',
    email_verified_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_user_account PRIMARY KEY (id),
    CONSTRAINT uq_user_account_email UNIQUE (email),

    CONSTRAINT ck_user_account_email_lowercase
        CHECK (email = LOWER(email)),

    CONSTRAINT ck_user_account_email_format
        CHECK (email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'),

    CONSTRAINT ck_user_account_phone_format
        CHECK (
            phone_e164 IS NULL
            OR phone_e164 ~ '^\+[1-9][0-9]{1,14}$'
        ),

    CONSTRAINT ck_user_account_phone_country_code
        CHECK (
            phone_country_code IS NULL
            OR phone_country_code ~ '^[A-Z]{2}$'
        ),

    CONSTRAINT ck_user_account_status
        CHECK (
            account_status IN (
                'pending',
                'active',
                'suspended',
                'deactivated'
            )
        ),

    CONSTRAINT ck_user_account_language
        CHECK (LENGTH(BTRIM(preferred_language)) BETWEEN 2 AND 10),

    CONSTRAINT ck_user_account_password_hash
        CHECK (
            password_hash IS NULL
            OR LENGTH(password_hash) > 0
        ),

    CONSTRAINT ck_user_account_phone_pair
        CHECK (
            (phone_e164 IS NULL AND phone_country_code IS NULL)
            OR
            (phone_e164 IS NOT NULL AND phone_country_code IS NOT NULL)
        )
);

COMMENT ON TABLE core.user_account IS
    'Shared user identity and account lifecycle; excludes domain-specific profiles';

COMMENT ON COLUMN core.user_account.password_hash IS
    'Optional encoded password hash; never store a plaintext password';

COMMENT ON COLUMN core.user_account.email IS
    'Lowercase account email address, unique within Talentra';


-- 2. Roles
CREATE TABLE core.role (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    name VARCHAR(50) NOT NULL,
    description VARCHAR(500),
    is_system_role BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_role PRIMARY KEY (id),
    CONSTRAINT uq_role_name UNIQUE (name),

    CONSTRAINT ck_role_name_format
        CHECK (name ~ '^[a-z][a-z0-9_]{1,49}$'),

    CONSTRAINT ck_role_description
        CHECK (
            description IS NULL
            OR LENGTH(BTRIM(description)) BETWEEN 1 AND 500
        )
);

COMMENT ON TABLE core.role IS
    'Named platform roles used by the access-control layer';


-- 3. User-role assignments
CREATE TABLE core.user_role (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    user_account_id BIGINT NOT NULL,
    role_id BIGINT NOT NULL,
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_user_role PRIMARY KEY (id),

    CONSTRAINT uq_user_role_user_account_id_role_id
        UNIQUE (user_account_id, role_id),

    CONSTRAINT fk_user_role_user_account
        FOREIGN KEY (user_account_id)
        REFERENCES core.user_account (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT fk_user_role_role
        FOREIGN KEY (role_id)
        REFERENCES core.role (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT
);

COMMENT ON TABLE core.user_role IS
    'Many-to-many assignment of platform roles to user accounts';


-- 4. Login sessions and device metadata
CREATE TABLE core.user_session (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    user_account_id BIGINT NOT NULL,
    device_identifier VARCHAR(255) NOT NULL,
    session_token_hash VARCHAR(255) NOT NULL,
    started_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_activity_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ended_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,

    CONSTRAINT pk_user_session PRIMARY KEY (id),
    CONSTRAINT uq_user_session_token_hash UNIQUE (session_token_hash),

    CONSTRAINT fk_user_session_user_account
        FOREIGN KEY (user_account_id)
        REFERENCES core.user_account (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT ck_user_session_device_identifier
        CHECK (LENGTH(BTRIM(device_identifier)) BETWEEN 1 AND 255),

    CONSTRAINT ck_user_session_token_hash
        CHECK (LENGTH(BTRIM(session_token_hash)) BETWEEN 1 AND 255),

    CONSTRAINT ck_user_session_last_activity
        CHECK (last_activity_at >= started_at),

    CONSTRAINT ck_user_session_ended_at
        CHECK (ended_at IS NULL OR ended_at >= started_at),

    CONSTRAINT ck_user_session_revoked_at
        CHECK (revoked_at IS NULL OR revoked_at >= started_at)
);

COMMENT ON TABLE core.user_session IS
    'Session history with device identifiers and hashed session tokens';

COMMENT ON COLUMN core.user_session.session_token_hash IS
    'Hash of the session token; raw authentication tokens must never be stored';


-- 5. Indexes
-- Unique constraints already create indexes for email, role name,
-- user-role uniqueness, and session token hash.

CREATE INDEX idx_user_account_status
    ON core.user_account (account_status);

CREATE INDEX idx_user_role_role_id
    ON core.user_role (role_id);

CREATE INDEX idx_user_session_user_account_id
    ON core.user_session (user_account_id);

CREATE INDEX idx_user_session_active_user
    ON core.user_session (user_account_id, last_activity_at DESC)
    WHERE ended_at IS NULL AND revoked_at IS NULL;

CREATE INDEX idx_user_session_device_identifier
    ON core.user_session (user_account_id, device_identifier);

COMMIT;


