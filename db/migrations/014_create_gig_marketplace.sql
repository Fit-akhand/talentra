-- Migration: 014_create_gig_marketplace.sql
-- Purpose: Implement the Gig marketplace subsystem: worker profiles, availability, requests, applications, assignments with non-overlap constraint, external earnings boundary, ratings, and requester preferences.
-- Requires: 001_create_schemas.sql, 002_create_identity.sql, 003_create_master_data.sql, 007_create_organization.sql
-- Engine: PostgreSQL 17

BEGIN;

CREATE EXTENSION IF NOT EXISTS btree_gist;

-- 1. Distinct Gig Worker Profile
CREATE TABLE gig.gig_worker_profile (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    user_account_id BIGINT NOT NULL,
    headline VARCHAR(150) NOT NULL,
    bio TEXT,
    hourly_rate NUMERIC(14,2),
    daily_rate NUMERIC(14,2),
    currency_code CHAR(3) NOT NULL DEFAULT 'USD',
    is_available BOOLEAN NOT NULL DEFAULT TRUE,
    total_completed_gigs INTEGER NOT NULL DEFAULT 0,
    average_rating NUMERIC(3,2),
    verification_status VARCHAR(20) NOT NULL DEFAULT 'unverified',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_gig_worker_profile PRIMARY KEY (id),
    CONSTRAINT uq_gig_worker_profile_user UNIQUE (user_account_id),

    CONSTRAINT fk_gig_worker_profile_user
        FOREIGN KEY (user_account_id)
        REFERENCES core.user_account (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT ck_gig_worker_profile_headline
        CHECK (LENGTH(BTRIM(headline)) BETWEEN 1 AND 150),

    CONSTRAINT ck_gig_worker_profile_rates
        CHECK (
            (hourly_rate IS NULL OR hourly_rate >= 0.00)
            AND
            (daily_rate IS NULL OR daily_rate >= 0.00)
        ),

    CONSTRAINT ck_gig_worker_profile_currency
        CHECK (currency_code ~ '^[A-Z]{3}$'),

    CONSTRAINT ck_gig_worker_profile_completed
        CHECK (total_completed_gigs >= 0),

    CONSTRAINT ck_gig_worker_profile_avg_rating
        CHECK (average_rating IS NULL OR average_rating BETWEEN 1.00 AND 5.00),

    CONSTRAINT ck_gig_worker_profile_verification
        CHECK (verification_status IN ('unverified', 'verified', 'suspended'))
);

CREATE INDEX idx_gig_worker_profile_available_rates
    ON gig.gig_worker_profile (is_available, hourly_rate, currency_code);

COMMENT ON TABLE gig.gig_worker_profile IS
    'Distinct gig worker profile containing charge rates, verification, and availability';


-- 2. Gig Worker Availability Windows
CREATE TABLE gig.gig_worker_availability (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    gig_worker_profile_id BIGINT NOT NULL,
    available_from DATE NOT NULL,
    available_to DATE NOT NULL,
    daily_available_hours NUMERIC(4,1) NOT NULL DEFAULT 8.0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_gig_worker_availability PRIMARY KEY (id),

    CONSTRAINT fk_gig_worker_availability_profile
        FOREIGN KEY (gig_worker_profile_id)
        REFERENCES gig.gig_worker_profile (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT ck_gig_worker_availability_dates
        CHECK (available_to >= available_from),

    CONSTRAINT ck_gig_worker_availability_hours
        CHECK (daily_available_hours BETWEEN 1.0 AND 24.0)
);

CREATE INDEX idx_gig_worker_availability_profile_dates
    ON gig.gig_worker_availability (gig_worker_profile_id, available_from, available_to);

COMMENT ON TABLE gig.gig_worker_availability IS
    'Calendar availability windows declared by gig workers';


-- 3. Gig Worker Service Offerings
CREATE TABLE gig.gig_worker_service (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    gig_worker_profile_id BIGINT NOT NULL,
    skill_id BIGINT NOT NULL,
    custom_title VARCHAR(150),
    rate_override NUMERIC(14,2),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_gig_worker_service PRIMARY KEY (id),
    CONSTRAINT uq_gig_worker_service_skill
        UNIQUE (gig_worker_profile_id, skill_id),

    CONSTRAINT fk_gig_worker_service_profile
        FOREIGN KEY (gig_worker_profile_id)
        REFERENCES gig.gig_worker_profile (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT fk_gig_worker_service_skill
        FOREIGN KEY (skill_id)
        REFERENCES master.skill (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT ck_gig_worker_service_rate
        CHECK (rate_override IS NULL OR rate_override >= 0.00)
);

COMMENT ON TABLE gig.gig_worker_service IS
    'Service offerings provided by a gig worker linked to canonical master skills';


-- 4. Gig Requests (Project-Based, Defined Price & Windows)
CREATE TABLE gig.gig_request (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    organization_id BIGINT NOT NULL,
    created_by_user_account_id BIGINT NOT NULL,
    title VARCHAR(200) NOT NULL,
    description TEXT NOT NULL,
    deliverables TEXT NOT NULL,
    pricing_type VARCHAR(20) NOT NULL DEFAULT 'fixed',
    budget_amount NUMERIC(14,2) NOT NULL,
    currency_code CHAR(3) NOT NULL DEFAULT 'USD',
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    request_status VARCHAR(20) NOT NULL DEFAULT 'open',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_gig_request PRIMARY KEY (id),

    CONSTRAINT fk_gig_request_organization
        FOREIGN KEY (organization_id)
        REFERENCES recruitment.organization (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT fk_gig_request_created_by
        FOREIGN KEY (created_by_user_account_id)
        REFERENCES core.user_account (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT ck_gig_request_title
        CHECK (LENGTH(BTRIM(title)) BETWEEN 1 AND 200),

    CONSTRAINT ck_gig_request_deliverables
        CHECK (LENGTH(BTRIM(deliverables)) > 0),

    CONSTRAINT ck_gig_request_pricing_type
        CHECK (pricing_type IN ('fixed', 'hourly_rate', 'daily_rate')),

    CONSTRAINT ck_gig_request_budget
        CHECK (budget_amount > 0.00),

    CONSTRAINT ck_gig_request_currency
        CHECK (currency_code ~ '^[A-Z]{3}$'),

    CONSTRAINT ck_gig_request_dates
        CHECK (end_date >= start_date),

    CONSTRAINT ck_gig_request_status
        CHECK (
            request_status IN (
                'open',
                'awarded',
                'in_progress',
                'completed',
                'cancelled'
            )
        )
);

CREATE INDEX idx_gig_request_status_dates
    ON gig.gig_request (request_status, start_date, end_date);

CREATE INDEX idx_gig_request_org
    ON gig.gig_request (organization_id, request_status);

COMMENT ON TABLE gig.gig_request IS
    'Short-duration project requirements with defined price and deliverables';


-- 5. Gig Applications (Unidirectional: Worker applies, Requester decides)
CREATE TABLE gig.gig_application (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    gig_request_id BIGINT NOT NULL,
    gig_worker_profile_id BIGINT NOT NULL,
    bid_amount NUMERIC(14,2) NOT NULL,
    currency_code CHAR(3) NOT NULL DEFAULT 'USD',
    proposed_duration_days INTEGER,
    pitch TEXT,
    application_status VARCHAR(20) NOT NULL DEFAULT 'submitted',
    applied_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    decided_at TIMESTAMPTZ,

    CONSTRAINT pk_gig_application PRIMARY KEY (id),
    CONSTRAINT uq_gig_application_worker
        UNIQUE (gig_request_id, gig_worker_profile_id),

    CONSTRAINT fk_gig_application_request
        FOREIGN KEY (gig_request_id)
        REFERENCES gig.gig_request (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT fk_gig_application_worker
        FOREIGN KEY (gig_worker_profile_id)
        REFERENCES gig.gig_worker_profile (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT ck_gig_application_bid
        CHECK (bid_amount > 0.00),

    CONSTRAINT ck_gig_application_currency
        CHECK (currency_code ~ '^[A-Z]{3}$'),

    CONSTRAINT ck_gig_application_duration
        CHECK (proposed_duration_days IS NULL OR proposed_duration_days > 0),

    CONSTRAINT ck_gig_application_status
        CHECK (
            application_status IN (
                'submitted',
                'accepted',
                'rejected',
                'withdrawn'
            )
        ),

    CONSTRAINT ck_gig_application_decided
        CHECK (
            (application_status IN ('accepted', 'rejected') AND decided_at IS NOT NULL)
            OR
            (application_status NOT IN ('accepted', 'rejected') AND decided_at IS NULL)
        )
);

CREATE INDEX idx_gig_application_request_status
    ON gig.gig_application (gig_request_id, application_status);

CREATE INDEX idx_gig_application_worker
    ON gig.gig_application (gig_worker_profile_id);

COMMENT ON TABLE gig.gig_application IS
    'Applications submitted by gig workers to gig requests';


-- 6. Gig Assignments (External Fulfilment Handoff & Non-Overlap Rule)
CREATE TABLE gig.gig_assignment (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    gig_request_id BIGINT NOT NULL,
    gig_application_id BIGINT NOT NULL,
    gig_worker_profile_id BIGINT NOT NULL,
    assigned_start_date DATE NOT NULL,
    assigned_end_date DATE NOT NULL,
    agreed_amount NUMERIC(14,2) NOT NULL,
    currency_code CHAR(3) NOT NULL DEFAULT 'USD',
    assignment_status VARCHAR(20) NOT NULL DEFAULT 'active',
    external_handoff_ref VARCHAR(255) NOT NULL,
    external_status VARCHAR(50) NOT NULL DEFAULT 'pending_handoff',
    last_reconciled_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_gig_assignment PRIMARY KEY (id),
    CONSTRAINT uq_gig_assignment_request UNIQUE (gig_request_id),
    CONSTRAINT uq_gig_assignment_application UNIQUE (gig_application_id),
    CONSTRAINT uq_gig_assignment_handoff UNIQUE (external_handoff_ref),

    CONSTRAINT fk_gig_assignment_request
        FOREIGN KEY (gig_request_id)
        REFERENCES gig.gig_request (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT fk_gig_assignment_application
        FOREIGN KEY (gig_application_id)
        REFERENCES gig.gig_application (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT fk_gig_assignment_worker
        FOREIGN KEY (gig_worker_profile_id)
        REFERENCES gig.gig_worker_profile (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT ck_gig_assignment_dates
        CHECK (assigned_end_date >= assigned_start_date),

    CONSTRAINT ck_gig_assignment_amount
        CHECK (agreed_amount > 0.00),

    CONSTRAINT ck_gig_assignment_status
        CHECK (assignment_status IN ('active', 'completed', 'terminated')),

    -- Milestone 10 (B35): Gig windows cannot overlap for the same gig worker
    CONSTRAINT ex_gig_assignment_no_overlap
        EXCLUDE USING gist (
            gig_worker_profile_id WITH =,
            daterange(assigned_start_date, assigned_end_date, '[]') WITH &&
        )
        WHERE (assignment_status = 'active')
);

CREATE INDEX idx_gig_assignment_worker_dates
    ON gig.gig_assignment (gig_worker_profile_id, assigned_start_date, assigned_end_date);

CREATE INDEX idx_gig_assignment_handoff
    ON gig.gig_assignment (external_handoff_ref);

COMMENT ON TABLE gig.gig_assignment IS
    'Accepted gig assignments storing external fulfilment references and enforcing non-overlapping active windows';


-- 7. External Earnings Reconciled from Fulfilment System (Integration Boundary)
CREATE TABLE gig.gig_external_earnings (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    gig_assignment_id BIGINT NOT NULL,
    estimated_earnings NUMERIC(14,2) NOT NULL DEFAULT 0.00,
    total_earnings NUMERIC(14,2) NOT NULL DEFAULT 0.00,
    projected_earnings NUMERIC(14,2) NOT NULL DEFAULT 0.00,
    currency_code CHAR(3) NOT NULL DEFAULT 'USD',
    reconciled_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    external_sync_hash VARCHAR(128),

    CONSTRAINT pk_gig_external_earnings PRIMARY KEY (id),
    CONSTRAINT uq_gig_external_earnings_assignment UNIQUE (gig_assignment_id),

    CONSTRAINT fk_gig_external_earnings_assignment
        FOREIGN KEY (gig_assignment_id)
        REFERENCES gig.gig_assignment (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT ck_gig_external_earnings_values
        CHECK (
            estimated_earnings >= 0.00
            AND total_earnings >= 0.00
            AND projected_earnings >= 0.00
        )
);

COMMENT ON TABLE gig.gig_external_earnings IS
    'Integration boundary table storing reconciled earnings sourced from external fulfilment engine';


-- 8. Requester Ratings for Completed Gigs
CREATE TABLE gig.gig_rating (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    gig_assignment_id BIGINT NOT NULL,
    rater_user_account_id BIGINT NOT NULL,
    rating_score NUMERIC(3,2) NOT NULL,
    quality_score NUMERIC(3,2),
    communication_score NUMERIC(3,2),
    review_text TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_gig_rating PRIMARY KEY (id),
    CONSTRAINT uq_gig_rating_assignment UNIQUE (gig_assignment_id),

    CONSTRAINT fk_gig_rating_assignment
        FOREIGN KEY (gig_assignment_id)
        REFERENCES gig.gig_assignment (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT fk_gig_rating_rater
        FOREIGN KEY (rater_user_account_id)
        REFERENCES core.user_account (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT ck_gig_rating_score
        CHECK (rating_score BETWEEN 1.00 AND 5.00),

    CONSTRAINT ck_gig_rating_quality
        CHECK (quality_score IS NULL OR quality_score BETWEEN 1.00 AND 5.00),

    CONSTRAINT ck_gig_rating_communication
        CHECK (communication_score IS NULL OR communication_score BETWEEN 1.00 AND 5.00)
);

COMMENT ON TABLE gig.gig_rating IS
    'Requester satisfaction rating and feedback on completed gigs';


-- 9. Requesters Favourite and Blacklisted Gig Workers List
CREATE TABLE gig.gig_worker_preference (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    organization_id BIGINT NOT NULL,
    gig_worker_profile_id BIGINT NOT NULL,
    preference_type VARCHAR(20) NOT NULL,
    reason VARCHAR(500),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_gig_worker_preference PRIMARY KEY (id),
    CONSTRAINT uq_gig_worker_preference
        UNIQUE (organization_id, gig_worker_profile_id),

    CONSTRAINT fk_gig_worker_preference_organization
        FOREIGN KEY (organization_id)
        REFERENCES recruitment.organization (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT fk_gig_worker_preference_worker
        FOREIGN KEY (gig_worker_profile_id)
        REFERENCES gig.gig_worker_profile (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT ck_gig_worker_preference_type
        CHECK (preference_type IN ('favourite', 'blacklisted'))
);

CREATE INDEX idx_gig_worker_preference_org_type
    ON gig.gig_worker_preference (organization_id, preference_type);

COMMENT ON TABLE gig.gig_worker_preference IS
    'Maintained list of favourite and blacklisted gig workers per organization';

COMMIT;
