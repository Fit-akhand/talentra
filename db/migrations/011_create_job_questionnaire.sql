-- Migration: 011_create_job_questionnaire.sql
-- Purpose: Add screening questionnaires, questions, application candidate responses, and position tracking.
-- Requires: 001_create_schemas.sql, 002_create_identity.sql, 008_create_job_posting.sql, 009_create_candidate_application.sql
-- Engine: PostgreSQL 17

BEGIN;

-- 1. Screening Questionnaires attached to Job Requirements
CREATE TABLE recruitment.job_questionnaire (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    job_posting_id BIGINT NOT NULL,
    created_by_user_account_id BIGINT NOT NULL,
    title VARCHAR(200) NOT NULL,
    instructions TEXT,
    is_mandatory BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_job_questionnaire PRIMARY KEY (id),
    CONSTRAINT uq_job_questionnaire_job UNIQUE (job_posting_id),

    CONSTRAINT fk_job_questionnaire_job_posting
        FOREIGN KEY (job_posting_id)
        REFERENCES recruitment.job_posting (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT fk_job_questionnaire_created_by
        FOREIGN KEY (created_by_user_account_id)
        REFERENCES core.user_account (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT ck_job_questionnaire_title
        CHECK (LENGTH(BTRIM(title)) BETWEEN 1 AND 200)
);

COMMENT ON TABLE recruitment.job_questionnaire IS
    'Screening questionnaire configured by employers for job applications';


-- 2. Questionnaire Questions
CREATE TABLE recruitment.job_questionnaire_question (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    job_questionnaire_id BIGINT NOT NULL,
    question_text TEXT NOT NULL,
    question_type VARCHAR(30) NOT NULL DEFAULT 'text',
    options_json JSONB,
    is_required BOOLEAN NOT NULL DEFAULT TRUE,
    sort_order INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_job_questionnaire_question PRIMARY KEY (id),

    CONSTRAINT fk_job_questionnaire_question_questionnaire
        FOREIGN KEY (job_questionnaire_id)
        REFERENCES recruitment.job_questionnaire (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT ck_job_questionnaire_question_text
        CHECK (LENGTH(BTRIM(question_text)) > 0),

    CONSTRAINT ck_job_questionnaire_question_type
        CHECK (
            question_type IN (
                'text',
                'single_choice',
                'multiple_choice',
                'boolean',
                'numeric'
            )
        ),

    CONSTRAINT ck_job_questionnaire_question_sort
        CHECK (sort_order >= 0)
);

CREATE INDEX idx_job_questionnaire_question_sort
    ON recruitment.job_questionnaire_question (job_questionnaire_id, sort_order ASC);

COMMENT ON TABLE recruitment.job_questionnaire_question IS
    'Individual questions within an application screening questionnaire';


-- 3. Application Question Responses
CREATE TABLE recruitment.application_question_response (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    candidate_application_id BIGINT NOT NULL,
    job_questionnaire_question_id BIGINT NOT NULL,
    response_text TEXT,
    selected_options_json JSONB,
    numeric_response NUMERIC(14,2),
    boolean_response BOOLEAN,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_application_question_response PRIMARY KEY (id),
    CONSTRAINT uq_application_question_response_app_question
        UNIQUE (candidate_application_id, job_questionnaire_question_id),

    CONSTRAINT fk_app_question_response_application
        FOREIGN KEY (candidate_application_id)
        REFERENCES recruitment.candidate_application (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT fk_app_question_response_question
        FOREIGN KEY (job_questionnaire_question_id)
        REFERENCES recruitment.job_questionnaire_question (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT
);

CREATE INDEX idx_application_question_response_app
    ON recruitment.application_question_response (candidate_application_id);

CREATE INDEX idx_application_question_response_question
    ON recruitment.application_question_response (job_questionnaire_question_id);

COMMENT ON TABLE recruitment.application_question_response IS
    'Candidate answers provided to screening questions at application time';


-- 4. Individual Position Tracking under Job Requirements
CREATE TABLE recruitment.job_position (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    job_posting_id BIGINT NOT NULL,
    position_reference_code VARCHAR(50) NOT NULL,
    position_status VARCHAR(20) NOT NULL DEFAULT 'open',
    filled_by_candidate_profile_id BIGINT,
    filled_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_job_position PRIMARY KEY (id),
    CONSTRAINT uq_job_position_code UNIQUE (job_posting_id, position_reference_code),

    CONSTRAINT fk_job_position_job_posting
        FOREIGN KEY (job_posting_id)
        REFERENCES recruitment.job_posting (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT fk_job_position_candidate_profile
        FOREIGN KEY (filled_by_candidate_profile_id)
        REFERENCES profile.candidate_profile (id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,

    CONSTRAINT ck_job_position_code
        CHECK (LENGTH(BTRIM(position_reference_code)) BETWEEN 1 AND 50),

    CONSTRAINT ck_job_position_status
        CHECK (
            position_status IN (
                'open',
                'offered',
                'filled',
                'cancelled'
            )
        ),

    CONSTRAINT ck_job_position_filled
        CHECK (
            (position_status <> 'filled' AND filled_at IS NULL)
            OR
            (position_status = 'filled' AND filled_at IS NOT NULL AND filled_by_candidate_profile_id IS NOT NULL)
        )
);

CREATE INDEX idx_job_position_posting_status
    ON recruitment.job_position (job_posting_id, position_status);

COMMENT ON TABLE recruitment.job_position IS
    'Granular position seats under a job requirement tracking individual openings to fulfillment';

COMMIT;
