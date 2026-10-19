-- Migration: 013_create_organization_extensions.sql
-- Purpose: Implement multi-branch locations, tax/registration identifiers, organization hierarchy, and effective-dated recruiter mapping.
-- Requires: 001_create_schemas.sql, 002_create_identity.sql, 003_create_master_data.sql, 007_create_organization.sql
-- Engine: PostgreSQL 17

BEGIN;

-- 1. Organization Multi-Branch Locations
CREATE TABLE recruitment.organization_location (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    organization_id BIGINT NOT NULL,
    city_id BIGINT NOT NULL,
    location_name VARCHAR(150) NOT NULL,
    address_line1 VARCHAR(255) NOT NULL,
    address_line2 VARCHAR(255),
    postal_code VARCHAR(20) NOT NULL,
    is_headquarters BOOLEAN NOT NULL DEFAULT FALSE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    latitude NUMERIC(9,6),
    longitude NUMERIC(9,6),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_organization_location PRIMARY KEY (id),

    CONSTRAINT fk_organization_location_organization
        FOREIGN KEY (organization_id)
        REFERENCES recruitment.organization (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT fk_organization_location_city
        FOREIGN KEY (city_id)
        REFERENCES master.city (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT ck_organization_location_name
        CHECK (LENGTH(BTRIM(location_name)) BETWEEN 1 AND 150),

    CONSTRAINT ck_organization_location_address
        CHECK (LENGTH(BTRIM(address_line1)) BETWEEN 1 AND 255),

    CONSTRAINT ck_organization_location_postal
        CHECK (LENGTH(BTRIM(postal_code)) BETWEEN 1 AND 20),

    CONSTRAINT ck_organization_location_latitude
        CHECK (latitude IS NULL OR latitude BETWEEN -90.000000 AND 90.000000),

    CONSTRAINT ck_organization_location_longitude
        CHECK (longitude IS NULL OR longitude BETWEEN -180.000000 AND 180.000000)
);

-- At most one headquarters location per organization
CREATE UNIQUE INDEX uq_organization_location_headquarters
    ON recruitment.organization_location (organization_id)
    WHERE is_headquarters = TRUE;

CREATE INDEX idx_organization_location_org
    ON recruitment.organization_location (organization_id);

CREATE INDEX idx_organization_location_city
    ON recruitment.organization_location (city_id);

COMMENT ON TABLE recruitment.organization_location IS
    'Physical offices and branches for employer and recruitment organizations';


-- 2. Organization Tax and Registration Identifiers
CREATE TABLE recruitment.organization_identifier (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    organization_id BIGINT NOT NULL,
    country_id BIGINT NOT NULL,
    identifier_type VARCHAR(30) NOT NULL,
    identifier_value VARCHAR(100) NOT NULL,
    verification_status VARCHAR(20) NOT NULL DEFAULT 'unverified',
    verified_at TIMESTAMPTZ,
    verified_by_user_account_id BIGINT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_organization_identifier PRIMARY KEY (id),
    CONSTRAINT uq_organization_identifier_val
        UNIQUE (country_id, identifier_type, identifier_value),

    CONSTRAINT fk_organization_identifier_organization
        FOREIGN KEY (organization_id)
        REFERENCES recruitment.organization (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT fk_organization_identifier_country
        FOREIGN KEY (country_id)
        REFERENCES master.country (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT fk_organization_identifier_verified_by
        FOREIGN KEY (verified_by_user_account_id)
        REFERENCES core.user_account (id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,

    CONSTRAINT ck_organization_identifier_type
        CHECK (
            identifier_type IN (
                'gstin',
                'cin',
                'ein',
                'vat',
                'pan',
                'company_number',
                'other'
            )
        ),

    CONSTRAINT ck_organization_identifier_status
        CHECK (
            verification_status IN (
                'unverified',
                'pending',
                'verified',
                'rejected'
            )
        ),

    CONSTRAINT ck_organization_identifier_verification_consistency
        CHECK (
            (verification_status = 'verified' AND verified_at IS NOT NULL)
            OR
            (verification_status <> 'verified' AND verified_at IS NULL)
        )
);

CREATE INDEX idx_organization_identifier_org
    ON recruitment.organization_identifier (organization_id);

COMMENT ON TABLE recruitment.organization_identifier IS
    'Legal registration and tax identifiers per jurisdiction for employer verification';


-- 3. Organization Hierarchy (Parent-Subsidiary and Client Relations)
CREATE TABLE recruitment.organization_hierarchy (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    parent_organization_id BIGINT NOT NULL,
    child_organization_id BIGINT NOT NULL,
    relationship_type VARCHAR(30) NOT NULL DEFAULT 'subsidiary',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_organization_hierarchy PRIMARY KEY (id),
    CONSTRAINT uq_organization_hierarchy_parent_child
        UNIQUE (parent_organization_id, child_organization_id),

    CONSTRAINT fk_organization_hierarchy_parent
        FOREIGN KEY (parent_organization_id)
        REFERENCES recruitment.organization (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT fk_organization_hierarchy_child
        FOREIGN KEY (child_organization_id)
        REFERENCES recruitment.organization (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT ck_organization_hierarchy_not_self
        CHECK (parent_organization_id <> child_organization_id),

    CONSTRAINT ck_organization_hierarchy_type
        CHECK (
            relationship_type IN (
                'subsidiary',
                'branch',
                'client',
                'vendor',
                'franchise'
            )
        )
);

CREATE INDEX idx_organization_hierarchy_parent
    ON recruitment.organization_hierarchy (parent_organization_id);

CREATE INDEX idx_organization_hierarchy_child
    ON recruitment.organization_hierarchy (child_organization_id);

COMMENT ON TABLE recruitment.organization_hierarchy IS
    'Organizational hierarchy linking parent holding corporations, divisions, and client entities';


-- 4. Effective-Dated Recruiter Mapping
CREATE TABLE recruitment.recruiter_client_mapping (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    recruiter_user_account_id BIGINT NOT NULL,
    agency_organization_id BIGINT,
    client_organization_id BIGINT NOT NULL,
    effective_from DATE NOT NULL,
    effective_to DATE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_recruiter_client_mapping PRIMARY KEY (id),

    CONSTRAINT fk_recruiter_client_mapping_recruiter
        FOREIGN KEY (recruiter_user_account_id)
        REFERENCES core.user_account (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT fk_recruiter_client_mapping_agency
        FOREIGN KEY (agency_organization_id)
        REFERENCES recruitment.organization (id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,

    CONSTRAINT fk_recruiter_client_mapping_client
        FOREIGN KEY (client_organization_id)
        REFERENCES recruitment.organization (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT ck_recruiter_client_mapping_dates
        CHECK (effective_to IS NULL OR effective_to >= effective_from),

    CONSTRAINT ck_recruiter_client_mapping_different_orgs
        CHECK (
            agency_organization_id IS NULL
            OR agency_organization_id <> client_organization_id
        )
);

CREATE INDEX idx_recruiter_client_mapping_recruiter_active
    ON recruitment.recruiter_client_mapping (recruiter_user_account_id, is_active, effective_from);

CREATE INDEX idx_recruiter_client_mapping_client
    ON recruitment.recruiter_client_mapping (client_organization_id);

COMMENT ON TABLE recruitment.recruiter_client_mapping IS
    'Effective-dated mapping specifying which recruiters are authorized to act on behalf of client accounts';

COMMIT;
