
BEGIN;

CREATE TABLE recruitment.job_posting (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    organization_id BIGINT NOT NULL,
    created_by_user_account_id BIGINT NOT NULL,

    job_role_id BIGINT,
    industry_id BIGINT,
    employment_type_id BIGINT NOT NULL,
    work_type_id BIGINT NOT NULL,
    city_id BIGINT,

    title VARCHAR(200) NOT NULL,
    description TEXT NOT NULL,
    responsibilities TEXT,
    qualifications TEXT,

    job_status VARCHAR(20) NOT NULL DEFAULT 'draft',
    workplace_location_text VARCHAR(200),

    currency_code CHAR(3),
    salary_min NUMERIC(14,2),
    salary_max NUMERIC(14,2),
    salary_period VARCHAR(20),

    minimum_experience_years NUMERIC(4,1),
    maximum_experience_years NUMERIC(4,1),
    vacancy_count INTEGER NOT NULL DEFAULT 1,

    published_at TIMESTAMPTZ,
    application_deadline TIMESTAMPTZ,
    closed_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_job_posting PRIMARY KEY (id),

    CONSTRAINT fk_job_posting_organization
        FOREIGN KEY (organization_id)
        REFERENCES recruitment.organization (id)
        ON UPDATE RESTRICT ON DELETE RESTRICT,

    CONSTRAINT fk_job_posting_created_by_user_account
        FOREIGN KEY (created_by_user_account_id)
        REFERENCES core.user_account (id)
        ON UPDATE RESTRICT ON DELETE RESTRICT,

    CONSTRAINT fk_job_posting_job_role
        FOREIGN KEY (job_role_id)
        REFERENCES master.job_role (id)
        ON UPDATE RESTRICT ON DELETE RESTRICT,

    CONSTRAINT fk_job_posting_industry
        FOREIGN KEY (industry_id)
        REFERENCES master.industry (id)
        ON UPDATE RESTRICT ON DELETE RESTRICT,

    CONSTRAINT fk_job_posting_employment_type
        FOREIGN KEY (employment_type_id)
        REFERENCES master.employment_type (id)
        ON UPDATE RESTRICT ON DELETE RESTRICT,

    CONSTRAINT fk_job_posting_work_type
        FOREIGN KEY (work_type_id)
        REFERENCES master.work_type (id)
        ON UPDATE RESTRICT ON DELETE RESTRICT,

    CONSTRAINT fk_job_posting_city
        FOREIGN KEY (city_id)
        REFERENCES master.city (id)
        ON UPDATE RESTRICT ON DELETE RESTRICT,

    CONSTRAINT ck_job_posting_title
        CHECK (LENGTH(BTRIM(title)) BETWEEN 1 AND 200),

    CONSTRAINT ck_job_posting_description
        CHECK (LENGTH(BTRIM(description)) > 0),

    CONSTRAINT ck_job_posting_status
        CHECK (
            job_status IN (
                'draft',
                'published',
                'paused',
                'closed',
                'filled',
                'cancelled'
            )
        ),

    CONSTRAINT ck_job_posting_location_text
        CHECK (
            workplace_location_text IS NULL
            OR LENGTH(BTRIM(workplace_location_text)) BETWEEN 1 AND 200
        ),

    CONSTRAINT ck_job_posting_salary_values
        CHECK (
            (salary_min IS NULL OR salary_min >= 0)
            AND (salary_max IS NULL OR salary_max >= 0)
            AND (
                salary_min IS NULL
                OR salary_max IS NULL
                OR salary_max >= salary_min
            )
        ),

    CONSTRAINT ck_job_posting_salary_currency
    CHECK (
        (
            salary_min IS NULL
            AND salary_max IS NULL
            AND currency_code IS NULL
            AND salary_period IS NULL
        )
        OR
        (
            (salary_min IS NOT NULL OR salary_max IS NOT NULL)
            AND currency_code IS NOT NULL
            AND currency_code ~ '^[A-Z]{3}$'
            AND salary_period IS NOT NULL
            AND salary_period IN (
                'hour', 'day', 'week', 'month', 'year'
            )
        )
    ),

    CONSTRAINT ck_job_posting_experience
        CHECK (
            (minimum_experience_years IS NULL
                OR minimum_experience_years BETWEEN 0 AND 80)
            AND
            (maximum_experience_years IS NULL
                OR maximum_experience_years BETWEEN 0 AND 80)
            AND
            (
                minimum_experience_years IS NULL
                OR maximum_experience_years IS NULL
                OR maximum_experience_years >= minimum_experience_years
            )
        ),

    CONSTRAINT ck_job_posting_vacancy_count
        CHECK (vacancy_count BETWEEN 1 AND 100000),

    CONSTRAINT ck_job_posting_published_at
        CHECK (
            job_status <> 'published'
            OR published_at IS NOT NULL
        ),

    CONSTRAINT ck_job_posting_closed_at
        CHECK (
            job_status NOT IN ('closed', 'filled', 'cancelled')
            OR closed_at IS NOT NULL
        )
);

COMMENT ON TABLE recruitment.job_posting IS
    'Organization-owned job advertisements and their hiring requirements';

COMMENT ON COLUMN recruitment.job_posting.salary_min IS
    'Lower compensation bound; requires currency and salary period when supplied';

COMMENT ON COLUMN recruitment.job_posting.salary_max IS
    'Upper compensation bound; requires currency and salary period when supplied';

CREATE INDEX idx_job_posting_org_status_created
    ON recruitment.job_posting
       (organization_id, job_status, created_at DESC);

CREATE INDEX idx_job_posting_status_published
    ON recruitment.job_posting
       (job_status, published_at DESC)
    WHERE job_status = 'published';

CREATE INDEX idx_job_posting_role_status
    ON recruitment.job_posting (job_role_id, job_status);

CREATE INDEX idx_job_posting_industry_status
    ON recruitment.job_posting (industry_id, job_status);

CREATE INDEX idx_job_posting_city_status
    ON recruitment.job_posting (city_id, job_status);

CREATE INDEX idx_job_posting_deadline
    ON recruitment.job_posting (application_deadline)
    WHERE job_status = 'published'
      AND application_deadline IS NOT NULL;


-- Normalized skill requirements per job posting.
CREATE TABLE recruitment.job_skill_requirement (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    job_posting_id BIGINT NOT NULL,
    skill_id BIGINT NOT NULL,

    is_required BOOLEAN NOT NULL DEFAULT TRUE,
    minimum_proficiency_level VARCHAR(20),
    minimum_experience_years NUMERIC(4,1),

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_job_skill_requirement
        PRIMARY KEY (id),

    CONSTRAINT uq_job_skill_requirement_job_skill
        UNIQUE (job_posting_id, skill_id),

    CONSTRAINT fk_job_skill_requirement_job_posting
        FOREIGN KEY (job_posting_id)
        REFERENCES recruitment.job_posting (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT fk_job_skill_requirement_skill
        FOREIGN KEY (skill_id)
        REFERENCES master.skill (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT ck_job_skill_requirement_proficiency
        CHECK (
            minimum_proficiency_level IS NULL
            OR minimum_proficiency_level IN (
                'beginner',
                'intermediate',
                'advanced',
                'expert'
            )
        ),

    CONSTRAINT ck_job_skill_requirement_experience
        CHECK (
            minimum_experience_years IS NULL
            OR minimum_experience_years BETWEEN 0 AND 80
        )
);

CREATE INDEX idx_job_skill_requirement_skill_id
    ON recruitment.job_skill_requirement (skill_id);

COMMENT ON TABLE recruitment.job_skill_requirement IS
    'Normalized required and optional skills associated with a job posting';

COMMIT;
