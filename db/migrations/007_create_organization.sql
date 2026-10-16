
BEGIN;

CREATE TABLE recruitment.organization (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    name VARCHAR(200) NOT NULL,
    slug VARCHAR(120) NOT NULL,
    organization_type VARCHAR(30) NOT NULL DEFAULT 'employer',
    description TEXT,
    website_url VARCHAR(2048),
    contact_email VARCHAR(254),
    contact_phone_e164 VARCHAR(16),
    country_id BIGINT,
    organization_status VARCHAR(20) NOT NULL DEFAULT 'pending',
    created_by_user_account_id BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_organization PRIMARY KEY (id),

    CONSTRAINT uq_organization_slug UNIQUE (slug),

    CONSTRAINT fk_organization_country
        FOREIGN KEY (country_id)
        REFERENCES master.country (id)
        ON UPDATE RESTRICT ON DELETE RESTRICT,

    CONSTRAINT fk_organization_created_by_user_account
        FOREIGN KEY (created_by_user_account_id)
        REFERENCES core.user_account (id)
        ON UPDATE RESTRICT ON DELETE RESTRICT,

    CONSTRAINT ck_organization_name
        CHECK (LENGTH(BTRIM(name)) BETWEEN 1 AND 200),

    CONSTRAINT ck_organization_slug
        CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),

    CONSTRAINT ck_organization_type
        CHECK (
            organization_type IN (
                'employer',
                'recruitment_agency',
                'consultancy',
                'educational_institution',
                'other'
            )
        ),

    CONSTRAINT ck_organization_website_url
        CHECK (
            website_url IS NULL
            OR (
                LENGTH(BTRIM(website_url)) BETWEEN 1 AND 2048
                AND website_url ~ '^https?://[^[:space:]]+$'
            )
        ),

    CONSTRAINT ck_organization_contact_email
        CHECK (
            contact_email IS NULL
            OR (
                contact_email = LOWER(contact_email)
                AND contact_email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
            )
        ),

    CONSTRAINT ck_organization_contact_phone
        CHECK (
            contact_phone_e164 IS NULL
            OR contact_phone_e164 ~ '^\+[1-9][0-9]{1,14}$'
        ),

    CONSTRAINT ck_organization_status
        CHECK (
            organization_status IN (
                'pending',
                'active',
                'suspended',
                'closed'
            )
        )
);

COMMENT ON TABLE recruitment.organization IS
    'Employer and recruitment organizations using the Talentra platform';

COMMENT ON COLUMN recruitment.organization.slug IS
    'Globally unique URL-safe organization identifier';

COMMENT ON COLUMN recruitment.organization.created_by_user_account_id IS
    'User account that initially created the organization';

CREATE INDEX idx_organization_status_created
    ON recruitment.organization (organization_status, created_at DESC);

CREATE INDEX idx_organization_country_id
    ON recruitment.organization (country_id);

CREATE INDEX idx_organization_created_by_user_account_id
    ON recruitment.organization (created_by_user_account_id);


CREATE TABLE recruitment.organization_member (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    organization_id BIGINT NOT NULL,
    user_account_id BIGINT NOT NULL,
    organization_role VARCHAR(30) NOT NULL DEFAULT 'recruiter',
    membership_status VARCHAR(20) NOT NULL DEFAULT 'invited',
    invited_by_user_account_id BIGINT,
    invited_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    joined_at TIMESTAMPTZ,
    removed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_organization_member PRIMARY KEY (id),

    CONSTRAINT uq_organization_member_organization_user
        UNIQUE (organization_id, user_account_id),

    CONSTRAINT fk_organization_member_organization
        FOREIGN KEY (organization_id)
        REFERENCES recruitment.organization (id)
        ON UPDATE RESTRICT ON DELETE RESTRICT,

    CONSTRAINT fk_organization_member_user_account
        FOREIGN KEY (user_account_id)
        REFERENCES core.user_account (id)
        ON UPDATE RESTRICT ON DELETE RESTRICT,

    CONSTRAINT fk_organization_member_invited_by
        FOREIGN KEY (invited_by_user_account_id)
        REFERENCES core.user_account (id)
        ON UPDATE RESTRICT ON DELETE SET NULL,

    CONSTRAINT ck_organization_member_role
        CHECK (
            organization_role IN (
                'owner',
                'admin',
                'recruiter',
                'hiring_manager',
                'billing_manager',
                'consultant'
            )
        ),

    CONSTRAINT ck_organization_member_status
        CHECK (
            membership_status IN (
                'invited',
                'active',
                'suspended',
                'removed'
            )
        ),

    CONSTRAINT ck_organization_member_joined_at
        CHECK (
            joined_at IS NULL
            OR joined_at >= invited_at
        ),

    CONSTRAINT ck_organization_member_removed_at
        CHECK (
            removed_at IS NULL
            OR removed_at >= invited_at
        ),

    CONSTRAINT ck_organization_member_removed_status
        CHECK (
            (membership_status = 'removed' AND removed_at IS NOT NULL)
            OR
            (membership_status <> 'removed' AND removed_at IS NULL)
        ),

    CONSTRAINT ck_organization_member_active_joined
        CHECK (
            membership_status <> 'active'
            OR joined_at IS NOT NULL
        )
);

COMMENT ON TABLE recruitment.organization_member IS
    'Organization-specific memberships and roles for shared user accounts';

COMMENT ON COLUMN recruitment.organization_member.organization_role IS
    'Organization-scoped role; distinct from platform-wide core.role';

CREATE INDEX idx_organization_member_user_status
    ON recruitment.organization_member
       (user_account_id, membership_status);

CREATE INDEX idx_organization_member_org_status_role
    ON recruitment.organization_member
       (organization_id, membership_status, organization_role);

CREATE INDEX idx_organization_member_invited_by
    ON recruitment.organization_member (invited_by_user_account_id)
    WHERE invited_by_user_account_id IS NOT NULL;

COMMIT;
