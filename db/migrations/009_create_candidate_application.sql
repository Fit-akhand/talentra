
BEGIN;

CREATE TABLE recruitment.candidate_application (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    candidate_profile_id BIGINT NOT NULL,
    job_posting_id BIGINT NOT NULL,
    candidate_document_id BIGINT,

    application_status VARCHAR(20) NOT NULL DEFAULT 'applied',
    cover_letter TEXT,
    application_source VARCHAR(30) NOT NULL DEFAULT 'direct',

    applied_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_status_changed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by_user_account_id BIGINT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by_user_account_id BIGINT NOT NULL,

    CONSTRAINT fk_candidate_application_candidate
        FOREIGN KEY (candidate_profile_id)
        REFERENCES profile.candidate_profile(id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_candidate_application_job
        FOREIGN KEY (job_posting_id)
        REFERENCES recruitment.job_posting(id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_candidate_application_document
        FOREIGN KEY (candidate_document_id)
        REFERENCES profile.candidate_document(id)
        ON DELETE SET NULL,

    CONSTRAINT fk_candidate_application_created_by
        FOREIGN KEY (created_by_user_account_id)
        REFERENCES core.user_account(id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_candidate_application_updated_by
        FOREIGN KEY (updated_by_user_account_id)
        REFERENCES core.user_account(id)
        ON DELETE RESTRICT,

    CONSTRAINT uq_candidate_application_candidate_job
        UNIQUE (candidate_profile_id, job_posting_id),

    CONSTRAINT ck_candidate_application_status
        CHECK (
            application_status IN (
                'applied',
                'shortlisted',
                'interviewed',
                'offered',
                'joined',
                'rejected',
                'withdrawn'
            )
        ),

    CONSTRAINT ck_candidate_application_source
        CHECK (
            application_source IN (
                'direct',
                'job_alert',
                'referral',
                'campus',
                'other'
            )
        ),

    CONSTRAINT ck_candidate_application_cover_letter
        CHECK (
            cover_letter IS NULL
            OR char_length(cover_letter) <= 10000
        )
);

CREATE TABLE recruitment.application_status_history (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    candidate_application_id BIGINT NOT NULL,
    previous_status VARCHAR(20),
    new_status VARCHAR(20) NOT NULL,
    changed_by_user_account_id BIGINT,
    change_reason VARCHAR(1000),
    changed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_application_status_history_application
        FOREIGN KEY (candidate_application_id)
        REFERENCES recruitment.candidate_application(id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_application_status_history_changed_by
        FOREIGN KEY (changed_by_user_account_id)
        REFERENCES core.user_account(id)
        ON DELETE RESTRICT,

    CONSTRAINT ck_application_status_history_previous
        CHECK (
            previous_status IS NULL
            OR previous_status IN (
                'applied', 'shortlisted', 'interviewed',
                'offered', 'joined', 'rejected', 'withdrawn'
            )
        ),

    CONSTRAINT ck_application_status_history_new
        CHECK (
            new_status IN (
                'applied', 'shortlisted', 'interviewed',
                'offered', 'joined', 'rejected', 'withdrawn'
            )
        ),

    CONSTRAINT ck_application_status_history_change
        CHECK (
            previous_status IS NULL
            OR previous_status <> new_status
        ),

    CONSTRAINT ck_application_status_history_reason
        CHECK (
            change_reason IS NULL
            OR char_length(change_reason) <= 1000
        )
);

-- Candidate-facing application history and recruiter pipeline queries.
CREATE INDEX idx_candidate_application_candidate_applied
    ON recruitment.candidate_application
       (candidate_profile_id, applied_at DESC, id DESC);

CREATE INDEX idx_candidate_application_job_status
    ON recruitment.candidate_application
       (job_posting_id, application_status, applied_at DESC);

CREATE INDEX idx_candidate_application_status_applied
    ON recruitment.candidate_application
       (application_status, applied_at DESC);

CREATE INDEX idx_application_status_history_application_changed
    ON recruitment.application_status_history
       (candidate_application_id, changed_at DESC, id DESC);

COMMENT ON TABLE recruitment.candidate_application IS
    'A candidate application to a job posting; one application per candidate and job.';

COMMENT ON TABLE recruitment.application_status_history IS
    'Append-only record of application status transitions, including the initial status.';

COMMENT ON COLUMN recruitment.candidate_application.candidate_document_id IS
    'Optional resume/document snapshot reference supplied with the application.';

CREATE OR REPLACE FUNCTION recruitment.record_application_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO recruitment.application_status_history (
            candidate_application_id,
            previous_status,
            new_status,
            changed_by_user_account_id,
            changed_at
        )
        VALUES (
            NEW.id,
            NULL,
            NEW.application_status,
            NEW.created_by_user_account_id,
            NEW.applied_at
        );

        RETURN NEW;
    END IF;

    IF NEW.application_status IS DISTINCT FROM OLD.application_status THEN
        NEW.last_status_changed_at := CURRENT_TIMESTAMP;

        INSERT INTO recruitment.application_status_history (
            candidate_application_id,
            previous_status,
            new_status,
            changed_by_user_account_id,
            changed_at
        )
        VALUES (
            NEW.id,
            OLD.application_status,
            NEW.application_status,
            NEW.updated_by_user_account_id,
            CURRENT_TIMESTAMP
        );
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_candidate_application_status_history
AFTER INSERT OR UPDATE OF application_status
ON recruitment.candidate_application
FOR EACH ROW
EXECUTE FUNCTION recruitment.record_application_status_change();

COMMIT;
