-- Migration: 016_create_sourcing_and_consultants.sql
-- Purpose: Implement consultant job openness policies, consultant sourcing requests with openness enforcement, candidate submissions, and bulk sourcing outreach campaigns.
-- Requires: 001_create_schemas.sql, 002_create_identity.sql, 007_create_organization.sql, 008_create_job_posting.sql, 005_create_candidate_profile.sql
-- Engine: PostgreSQL 17

BEGIN;

-- 1. Job Consultant Openness Policy
CREATE TABLE sourcing.job_consultant_policy (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    job_posting_id BIGINT NOT NULL,
    is_open_to_consultants BOOLEAN NOT NULL DEFAULT FALSE,
    max_consultants INTEGER,
    bounty_amount NUMERIC(14,2),
    currency_code CHAR(3) DEFAULT 'USD',
    terms_and_conditions TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_job_consultant_policy PRIMARY KEY (id),
    CONSTRAINT uq_job_consultant_policy_job UNIQUE (job_posting_id),

    CONSTRAINT fk_job_consultant_policy_job
        FOREIGN KEY (job_posting_id)
        REFERENCES recruitment.job_posting (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT ck_job_consultant_policy_max
        CHECK (max_consultants IS NULL OR max_consultants > 0),

    CONSTRAINT ck_job_consultant_policy_bounty
        CHECK (bounty_amount IS NULL OR bounty_amount >= 0.00),

    CONSTRAINT ck_job_consultant_policy_currency
        CHECK (currency_code IS NULL OR currency_code ~ '^[A-Z]{3}$')
);

CREATE INDEX idx_job_consultant_policy_open
    ON sourcing.job_consultant_policy (is_open_to_consultants)
    WHERE is_open_to_consultants = TRUE;

COMMENT ON TABLE sourcing.job_consultant_policy IS
    'Policy configuring whether external recruitment consultants may source candidates for a job requirement';


-- 2. Consultant Sourcing Requests (Employer Approval Workflow)
CREATE TABLE sourcing.consultant_sourcing_request (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    job_posting_id BIGINT NOT NULL,
    consultant_user_account_id BIGINT NOT NULL,
    request_status VARCHAR(20) NOT NULL DEFAULT 'requested',
    proposal_notes TEXT,
    decided_by_user_account_id BIGINT,
    decided_at TIMESTAMPTZ,
    decision_reason VARCHAR(500),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_consultant_sourcing_request PRIMARY KEY (id),
    CONSTRAINT uq_consultant_sourcing_request
        UNIQUE (job_posting_id, consultant_user_account_id),

    CONSTRAINT fk_consultant_sourcing_req_job
        FOREIGN KEY (job_posting_id)
        REFERENCES recruitment.job_posting (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT fk_consultant_sourcing_req_consultant
        FOREIGN KEY (consultant_user_account_id)
        REFERENCES core.user_account (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT fk_consultant_sourcing_req_decided_by
        FOREIGN KEY (decided_by_user_account_id)
        REFERENCES core.user_account (id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,

    CONSTRAINT ck_consultant_sourcing_req_status
        CHECK (
            request_status IN (
                'requested',
                'accepted',
                'declined',
                'revoked'
            )
        ),

    CONSTRAINT ck_consultant_sourcing_req_decision_consistency
        CHECK (
            (request_status IN ('accepted', 'declined') AND decided_at IS NOT NULL)
            OR
            (request_status NOT IN ('accepted', 'declined') AND decided_at IS NULL)
        )
);

CREATE INDEX idx_consultant_sourcing_req_status
    ON sourcing.consultant_sourcing_request (job_posting_id, request_status);

CREATE INDEX idx_consultant_sourcing_req_consultant
    ON sourcing.consultant_sourcing_request (consultant_user_account_id, request_status);

COMMENT ON TABLE sourcing.consultant_sourcing_request IS
    'Consultant requests to source for a specific job and employer acceptance/decline decisions';

-- Milestone 14 (B46): Rule that a consultant can act only on a requirement open to consultants
CREATE OR REPLACE FUNCTION sourcing.enforce_consultant_openness()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_is_open BOOLEAN;
BEGIN
    SELECT is_open_to_consultants INTO v_is_open
    FROM sourcing.job_consultant_policy
    WHERE job_posting_id = NEW.job_posting_id;

    IF v_is_open IS NOT TRUE THEN
        RAISE EXCEPTION 'Job posting % is not open to external consultants', NEW.job_posting_id;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_consultant_openness ON sourcing.consultant_sourcing_request;
CREATE TRIGGER trg_enforce_consultant_openness
BEFORE INSERT ON sourcing.consultant_sourcing_request
FOR EACH ROW
EXECUTE FUNCTION sourcing.enforce_consultant_openness();


-- 3. Sourcing Submissions & Shortlists
CREATE TABLE sourcing.sourcing_submission (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    consultant_sourcing_request_id BIGINT,
    job_posting_id BIGINT NOT NULL,
    candidate_profile_id BIGINT NOT NULL,
    submitted_by_user_account_id BIGINT NOT NULL,
    candidate_application_id BIGINT,
    submission_status VARCHAR(20) NOT NULL DEFAULT 'submitted',
    consultant_notes TEXT,
    client_feedback TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_sourcing_submission PRIMARY KEY (id),
    CONSTRAINT uq_sourcing_submission_job_candidate
        UNIQUE (job_posting_id, candidate_profile_id),

    CONSTRAINT fk_sourcing_submission_request
        FOREIGN KEY (consultant_sourcing_request_id)
        REFERENCES sourcing.consultant_sourcing_request (id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,

    CONSTRAINT fk_sourcing_submission_job
        FOREIGN KEY (job_posting_id)
        REFERENCES recruitment.job_posting (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT fk_sourcing_submission_candidate
        FOREIGN KEY (candidate_profile_id)
        REFERENCES profile.candidate_profile (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT fk_sourcing_submission_submitted_by
        FOREIGN KEY (submitted_by_user_account_id)
        REFERENCES core.user_account (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT fk_sourcing_submission_application
        FOREIGN KEY (candidate_application_id)
        REFERENCES recruitment.candidate_application (id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,

    CONSTRAINT ck_sourcing_submission_status
        CHECK (
            submission_status IN (
                'submitted',
                'shortlisted',
                'accepted',
                'rejected',
                'hired'
            )
        )
);

CREATE INDEX idx_sourcing_submission_job_status
    ON sourcing.sourcing_submission (job_posting_id, submission_status);

CREATE INDEX idx_sourcing_submission_consultant_req
    ON sourcing.sourcing_submission (consultant_sourcing_request_id);

COMMENT ON TABLE sourcing.sourcing_submission IS
    'Candidate submissions made by approved freelance recruiters or consultants';


-- 4. Bulk Outreach Campaigns
CREATE TABLE sourcing.outreach_batch (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    organization_id BIGINT NOT NULL,
    created_by_user_account_id BIGINT NOT NULL,
    campaign_name VARCHAR(150) NOT NULL,
    job_posting_id BIGINT,
    channel VARCHAR(20) NOT NULL DEFAULT 'email',
    subject VARCHAR(200),
    message_body TEXT NOT NULL,
    total_recipients INTEGER NOT NULL DEFAULT 0,
    total_credits_deducted NUMERIC(14,2) NOT NULL DEFAULT 0.00,
    status VARCHAR(20) NOT NULL DEFAULT 'draft',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMPTZ,

    CONSTRAINT pk_outreach_batch PRIMARY KEY (id),

    CONSTRAINT fk_outreach_batch_organization
        FOREIGN KEY (organization_id)
        REFERENCES recruitment.organization (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT fk_outreach_batch_created_by
        FOREIGN KEY (created_by_user_account_id)
        REFERENCES core.user_account (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT fk_outreach_batch_job
        FOREIGN KEY (job_posting_id)
        REFERENCES recruitment.job_posting (id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,

    CONSTRAINT ck_outreach_batch_channel
        CHECK (channel IN ('email', 'sms', 'in_app', 'whatsapp')),

    CONSTRAINT ck_outreach_batch_recipients
        CHECK (total_recipients >= 0),

    CONSTRAINT ck_outreach_batch_credits
        CHECK (total_credits_deducted >= 0.00),

    CONSTRAINT ck_outreach_batch_status
        CHECK (status IN ('draft', 'queued', 'processing', 'completed', 'cancelled'))
);

CREATE INDEX idx_outreach_batch_org_status
    ON sourcing.outreach_batch (organization_id, status);

COMMENT ON TABLE sourcing.outreach_batch IS
    'Bulk sourcing candidate outreach campaigns initiated by employers or agencies';


-- 5. Outreach Recipients
CREATE TABLE sourcing.outreach_recipient (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    outreach_batch_id BIGINT NOT NULL,
    candidate_profile_id BIGINT NOT NULL,
    delivery_status VARCHAR(20) NOT NULL DEFAULT 'pending',
    sent_at TIMESTAMPTZ,
    delivered_at TIMESTAMPTZ,
    response_recorded_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_outreach_recipient PRIMARY KEY (id),
    CONSTRAINT uq_outreach_recipient_batch_candidate
        UNIQUE (outreach_batch_id, candidate_profile_id),

    CONSTRAINT fk_outreach_recipient_batch
        FOREIGN KEY (outreach_batch_id)
        REFERENCES sourcing.outreach_batch (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT fk_outreach_recipient_candidate
        FOREIGN KEY (candidate_profile_id)
        REFERENCES profile.candidate_profile (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT ck_outreach_recipient_status
        CHECK (
            delivery_status IN (
                'pending',
                'sent',
                'delivered',
                'opened',
                'responded',
                'bounced',
                'blocked'
            )
        )
);

CREATE INDEX idx_outreach_recipient_candidate
    ON sourcing.outreach_recipient (candidate_profile_id, delivery_status);

COMMENT ON TABLE sourcing.outreach_recipient IS
    'Target candidate tracking per bulk outreach campaign';

COMMIT;
