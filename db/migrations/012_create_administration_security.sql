-- Migration: 012_create_administration_security.sql
-- Purpose: Implement granular RBAC permissions, separate credentials, consent tracking, user/company blocking, and append-only audit trail.
-- Requires: 001_create_schemas.sql, 002_create_identity.sql, 007_create_organization.sql
-- Engine: PostgreSQL 17

BEGIN;

-- 1. Ensure Standard Platform Roles exist
INSERT INTO core.role (name, description, is_system_role)
VALUES
    ('super_admin',      'System Super Administrator with full global rights', TRUE),
    ('admin',            'Platform Administrator for operational support', TRUE),
    ('account_admin',    'Organization Account Administrator', TRUE),
    ('guest',            'Unauthenticated or pending guest user', TRUE),
    ('candidate',        'Registered job seeker or gig worker', TRUE),
    ('employer',         'Direct employer hiring manager or admin', TRUE),
    ('recruiter',        'Corporate or agency recruiter', TRUE),
    ('consultant',       'Freelance sourcing consultant', TRUE),
    ('placement_officer','Training and Placement Officer (TPO) for campus', TRUE)
ON CONFLICT (name) DO NOTHING;


-- 2. Granular Permissions Catalogue
CREATE TABLE core.permission (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    code VARCHAR(80) NOT NULL,
    name VARCHAR(120) NOT NULL,
    module VARCHAR(50) NOT NULL,
    description VARCHAR(500),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_permission PRIMARY KEY (id),
    CONSTRAINT uq_permission_code UNIQUE (code),
    CONSTRAINT ck_permission_code
        CHECK (code ~ '^[a-z][a-z0-9_.]+[a-z0-9]$'),
    CONSTRAINT ck_permission_name
        CHECK (LENGTH(BTRIM(name)) BETWEEN 1 AND 120),
    CONSTRAINT ck_permission_module
        CHECK (LENGTH(BTRIM(module)) BETWEEN 1 AND 50)
);

COMMENT ON TABLE core.permission IS
    'Granular capability tokens assigned to platform roles';

-- 3. Role-Permission Assignments
CREATE TABLE core.role_permission (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    role_id BIGINT NOT NULL,
    permission_id BIGINT NOT NULL,
    granted_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_role_permission PRIMARY KEY (id),
    CONSTRAINT uq_role_permission UNIQUE (role_id, permission_id),

    CONSTRAINT fk_role_permission_role
        FOREIGN KEY (role_id)
        REFERENCES core.role (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT fk_role_permission_permission
        FOREIGN KEY (permission_id)
        REFERENCES core.permission (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT
);

CREATE INDEX idx_role_permission_role_id
    ON core.role_permission (role_id);

CREATE INDEX idx_role_permission_permission_id
    ON core.role_permission (permission_id);

COMMENT ON TABLE core.role_permission IS
    'Mapping defining which permissions belong to which platform roles';


-- 4. User Credentials (Decoupled from core.user_account)
CREATE TABLE core.user_credential (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    user_account_id BIGINT NOT NULL,
    credential_type VARCHAR(30) NOT NULL DEFAULT 'password',
    credential_identifier VARCHAR(255) NOT NULL,
    secret_hash TEXT NOT NULL,
    algorithm VARCHAR(50) NOT NULL DEFAULT 'argon2id',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    expires_at TIMESTAMPTZ,
    last_used_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_user_credential PRIMARY KEY (id),
    CONSTRAINT uq_user_credential_type_identifier
        UNIQUE (credential_type, credential_identifier),

    CONSTRAINT fk_user_credential_user_account
        FOREIGN KEY (user_account_id)
        REFERENCES core.user_account (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT ck_user_credential_type
        CHECK (
            credential_type IN (
                'password',
                'api_key',
                'totp_secret',
                'recovery_code',
                'oauth_sub'
            )
        ),

    CONSTRAINT ck_user_credential_secret
        CHECK (LENGTH(BTRIM(secret_hash)) > 0),

    CONSTRAINT ck_user_credential_expiration
        CHECK (expires_at IS NULL OR expires_at >= created_at)
);

CREATE INDEX idx_user_credential_user
    ON core.user_credential (user_account_id, credential_type);

COMMENT ON TABLE core.user_credential IS
    'Authentication secrets and credentials separated from the identity record; never stores cleartext';


-- 5. Consent Records (GDPR / DPDP Compliance)
CREATE TABLE core.consent_record (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    user_account_id BIGINT NOT NULL,
    consent_type VARCHAR(50) NOT NULL,
    consent_version VARCHAR(20) NOT NULL,
    is_granted BOOLEAN NOT NULL DEFAULT TRUE,
    client_ip VARCHAR(45),
    user_agent VARCHAR(500),
    granted_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    revoked_at TIMESTAMPTZ,

    CONSTRAINT pk_consent_record PRIMARY KEY (id),

    CONSTRAINT fk_consent_record_user_account
        FOREIGN KEY (user_account_id)
        REFERENCES core.user_account (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT ck_consent_record_type
        CHECK (
            consent_type IN (
                'terms_of_service',
                'privacy_policy',
                'marketing_communications',
                'third_party_recruiter_sharing',
                'background_verification'
            )
        ),

    CONSTRAINT ck_consent_record_revocation
        CHECK (revoked_at IS NULL OR revoked_at >= granted_at)
);

CREATE INDEX idx_consent_record_user_type
    ON core.consent_record (user_account_id, consent_type, granted_at DESC);

COMMENT ON TABLE core.consent_record IS
    'Auditable records of user consent for legal and privacy regulations';


-- 6. Blocking List (Candidates blocking employers, recruiters, consultants)
CREATE TABLE core.user_block (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    blocker_user_account_id BIGINT NOT NULL,
    blocked_user_account_id BIGINT,
    blocked_organization_id BIGINT,
    block_reason VARCHAR(500),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_user_block PRIMARY KEY (id),

    CONSTRAINT fk_user_block_blocker
        FOREIGN KEY (blocker_user_account_id)
        REFERENCES core.user_account (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT fk_user_block_blocked_user
        FOREIGN KEY (blocked_user_account_id)
        REFERENCES core.user_account (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT fk_user_block_blocked_organization
        FOREIGN KEY (blocked_organization_id)
        REFERENCES recruitment.organization (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT ck_user_block_target_xor
        CHECK (
            (blocked_user_account_id IS NOT NULL AND blocked_organization_id IS NULL)
            OR
            (blocked_user_account_id IS NULL AND blocked_organization_id IS NOT NULL)
        ),

    CONSTRAINT ck_user_block_not_self
        CHECK (blocker_user_account_id <> blocked_user_account_id)
);

CREATE UNIQUE INDEX uq_user_block_user
    ON core.user_block (blocker_user_account_id, blocked_user_account_id)
    WHERE blocked_user_account_id IS NOT NULL;

CREATE UNIQUE INDEX uq_user_block_organization
    ON core.user_block (blocker_user_account_id, blocked_organization_id)
    WHERE blocked_organization_id IS NOT NULL;

CREATE INDEX idx_user_block_blocked_user
    ON core.user_block (blocked_user_account_id)
    WHERE blocked_user_account_id IS NOT NULL;

CREATE INDEX idx_user_block_blocked_org
    ON core.user_block (blocked_organization_id)
    WHERE blocked_organization_id IS NOT NULL;

COMMENT ON TABLE core.user_block IS
    'Blocking relationship ensuring blocked recruiters/employers cannot view the blocker candidate';


-- 7. Append-Only Audit Trail in audit schema
CREATE TABLE audit.audit_event (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    actor_user_account_id BIGINT,
    impersonator_user_account_id BIGINT,
    action VARCHAR(80) NOT NULL,
    entity_schema VARCHAR(50) NOT NULL,
    entity_name VARCHAR(80) NOT NULL,
    entity_id BIGINT,
    old_values_json JSONB,
    new_values_json JSONB,
    client_ip VARCHAR(45),
    user_agent VARCHAR(500),
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_audit_event PRIMARY KEY (id),

    CONSTRAINT fk_audit_event_actor
        FOREIGN KEY (actor_user_account_id)
        REFERENCES core.user_account (id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,

    CONSTRAINT fk_audit_event_impersonator
        FOREIGN KEY (impersonator_user_account_id)
        REFERENCES core.user_account (id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,

    CONSTRAINT ck_audit_event_action
        CHECK (LENGTH(BTRIM(action)) BETWEEN 1 AND 80),

    CONSTRAINT ck_audit_event_entity_schema
        CHECK (LENGTH(BTRIM(entity_schema)) BETWEEN 1 AND 50),

    CONSTRAINT ck_audit_event_entity_name
        CHECK (LENGTH(BTRIM(entity_name)) BETWEEN 1 AND 80)
);

CREATE INDEX idx_audit_event_actor_recorded
    ON audit.audit_event (actor_user_account_id, recorded_at DESC);

CREATE INDEX idx_audit_event_entity
    ON audit.audit_event (entity_schema, entity_name, entity_id);

CREATE INDEX idx_audit_event_action_recorded
    ON audit.audit_event (action, recorded_at DESC);

COMMENT ON TABLE audit.audit_event IS
    'Strictly append-only audit trail recording sensitive system actions, logins, and permission changes';

-- Enforce append-only nature: forbid UPDATE and DELETE via trigger
CREATE OR REPLACE FUNCTION audit.prevent_audit_tampering()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'Audit trail is strictly append-only: % operation forbidden on audit.audit_event', TG_OP;
END;
$$;

CREATE TRIGGER trg_prevent_audit_event_tampering
BEFORE UPDATE OR DELETE ON audit.audit_event
FOR EACH ROW
EXECUTE FUNCTION audit.prevent_audit_tampering();


-- 8. System Error Logging in audit schema
CREATE TABLE audit.system_error_log (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    error_code VARCHAR(50) NOT NULL,
    error_severity VARCHAR(20) NOT NULL DEFAULT 'error',
    error_message TEXT NOT NULL,
    stack_trace TEXT,
    context_json JSONB,
    user_account_id BIGINT,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_system_error_log PRIMARY KEY (id),

    CONSTRAINT fk_system_error_log_user
        FOREIGN KEY (user_account_id)
        REFERENCES core.user_account (id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,

    CONSTRAINT ck_system_error_log_severity
        CHECK (
            error_severity IN (
                'debug',
                'info',
                'warning',
                'error',
                'critical',
                'fatal'
            )
        )
);

CREATE INDEX idx_system_error_log_severity_recorded
    ON audit.system_error_log (error_severity, recorded_at DESC);

COMMENT ON TABLE audit.system_error_log IS
    'System and operational error occurrences for monitoring and diagnostics';


-- 9. Candidate Visibility Function honoring blocks
CREATE OR REPLACE FUNCTION core.is_candidate_visible_to(
    p_candidate_profile_id BIGINT,
    p_viewer_user_id BIGINT,
    p_viewer_org_id BIGINT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_candidate_user_id BIGINT;
    v_is_blocked BOOLEAN := FALSE;
BEGIN
    SELECT user_account_id INTO v_candidate_user_id
    FROM profile.candidate_profile
    WHERE id = p_candidate_profile_id;

    IF v_candidate_user_id IS NULL THEN
        RETURN FALSE;
    END IF;

    -- A candidate can always view their own profile
    IF p_viewer_user_id = v_candidate_user_id THEN
        RETURN TRUE;
    END IF;

    -- Check if candidate has blocked the viewer user or organization
    SELECT EXISTS (
        SELECT 1
        FROM core.user_block
        WHERE blocker_user_account_id = v_candidate_user_id
          AND (
              (blocked_user_account_id IS NOT NULL AND blocked_user_account_id = p_viewer_user_id)
              OR
              (blocked_organization_id IS NOT NULL AND blocked_organization_id = p_viewer_org_id)
          )
    ) INTO v_is_blocked;

    IF v_is_blocked THEN
        RETURN FALSE;
    END IF;

    -- Check if viewer user has blocked the candidate
    SELECT EXISTS (
        SELECT 1
        FROM core.user_block
        WHERE blocker_user_account_id = p_viewer_user_id
          AND blocked_user_account_id = v_candidate_user_id
    ) INTO v_is_blocked;

    IF v_is_blocked THEN
        RETURN FALSE;
    END IF;

    RETURN TRUE;
END;
$$;

COMMIT;
