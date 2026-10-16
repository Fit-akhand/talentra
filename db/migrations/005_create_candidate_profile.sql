
BEGIN;

-- One candidate profile per shared user account.
CREATE TABLE profile.candidate_profile (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    user_account_id BIGINT NOT NULL,
    headline VARCHAR(150),
    professional_summary TEXT,
    total_experience_years NUMERIC(4,1) NOT NULL DEFAULT 0,
    profile_status VARCHAR(20) NOT NULL DEFAULT 'draft',
    visibility VARCHAR(20) NOT NULL DEFAULT 'recruiters',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_candidate_profile PRIMARY KEY (id),
    CONSTRAINT uq_candidate_profile_user_account_id
        UNIQUE (user_account_id),
    CONSTRAINT fk_candidate_profile_user_account
        FOREIGN KEY (user_account_id)
        REFERENCES core.user_account (id)
        ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT ck_candidate_profile_headline
        CHECK (
            headline IS NULL
            OR LENGTH(BTRIM(headline)) BETWEEN 1 AND 150
        ),
    CONSTRAINT ck_candidate_profile_experience
        CHECK (total_experience_years BETWEEN 0 AND 80),
    CONSTRAINT ck_candidate_profile_status
        CHECK (profile_status IN ('draft', 'active', 'paused')),
    CONSTRAINT ck_candidate_profile_visibility
        CHECK (visibility IN ('private', 'recruiters', 'public'))
);

COMMENT ON TABLE profile.candidate_profile IS
    'Candidate-specific professional profile linked to a shared user account';

COMMENT ON COLUMN profile.candidate_profile.professional_summary IS
    'Candidate-provided professional summary; treat as personal data';

-- Canonical skills associated with a candidate.
CREATE TABLE profile.candidate_skill (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    candidate_profile_id BIGINT NOT NULL,
    skill_id BIGINT NOT NULL,
    proficiency_level VARCHAR(20),
    experience_years NUMERIC(4,1),
    is_primary BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_candidate_skill PRIMARY KEY (id),
    CONSTRAINT uq_candidate_skill_profile_skill
        UNIQUE (candidate_profile_id, skill_id),
    CONSTRAINT fk_candidate_skill_candidate_profile
        FOREIGN KEY (candidate_profile_id)
        REFERENCES profile.candidate_profile (id)
        ON UPDATE RESTRICT ON DELETE CASCADE,
    CONSTRAINT fk_candidate_skill_skill
        FOREIGN KEY (skill_id)
        REFERENCES master.skill (id)
        ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT ck_candidate_skill_proficiency
        CHECK (
            proficiency_level IS NULL
            OR proficiency_level IN (
                'beginner', 'intermediate', 'advanced', 'expert'
            )
        ),
    CONSTRAINT ck_candidate_skill_experience
        CHECK (
            experience_years IS NULL
            OR experience_years BETWEEN 0 AND 80
        )
);

CREATE INDEX idx_candidate_skill_skill_id
    ON profile.candidate_skill (skill_id);

CREATE INDEX idx_candidate_skill_profile_primary
    ON profile.candidate_skill (candidate_profile_id, is_primary DESC);

-- Candidate education history.
CREATE TABLE profile.candidate_education (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    candidate_profile_id BIGINT NOT NULL,
    qualification_id BIGINT NOT NULL,
    institution_name VARCHAR(200) NOT NULL,
    field_of_study VARCHAR(150),
    start_date DATE,
    end_date DATE,
    grade_value VARCHAR(30),
    grade_scale VARCHAR(30),
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_candidate_education PRIMARY KEY (id),
    CONSTRAINT fk_candidate_education_candidate_profile
        FOREIGN KEY (candidate_profile_id)
        REFERENCES profile.candidate_profile (id)
        ON UPDATE RESTRICT ON DELETE CASCADE,
    CONSTRAINT fk_candidate_education_qualification
        FOREIGN KEY (qualification_id)
        REFERENCES master.qualification (id)
        ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT ck_candidate_education_institution
        CHECK (LENGTH(BTRIM(institution_name)) BETWEEN 1 AND 200),
    CONSTRAINT ck_candidate_education_field
        CHECK (
            field_of_study IS NULL
            OR LENGTH(BTRIM(field_of_study)) BETWEEN 1 AND 150
        ),
    CONSTRAINT ck_candidate_education_dates
        CHECK (
            start_date IS NULL
            OR end_date IS NULL
            OR end_date >= start_date
        ),
    CONSTRAINT ck_candidate_education_grade_value
        CHECK (
            grade_value IS NULL
            OR LENGTH(BTRIM(grade_value)) BETWEEN 1 AND 30
        ),
    CONSTRAINT ck_candidate_education_grade_scale
        CHECK (
            grade_scale IS NULL
            OR LENGTH(BTRIM(grade_scale)) BETWEEN 1 AND 30
        )
);

CREATE INDEX idx_candidate_education_profile
    ON profile.candidate_education
       (candidate_profile_id, start_date DESC);

CREATE INDEX idx_candidate_education_qualification
    ON profile.candidate_education (qualification_id);

-- Candidate work history.
CREATE TABLE profile.candidate_work_experience (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    candidate_profile_id BIGINT NOT NULL,
    job_role_id BIGINT,
    employer_name VARCHAR(200) NOT NULL,
    job_title VARCHAR(150) NOT NULL,
    employment_type_id BIGINT,
    start_date DATE NOT NULL,
    end_date DATE,
    is_current BOOLEAN NOT NULL DEFAULT FALSE,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_candidate_work_experience PRIMARY KEY (id),
    CONSTRAINT fk_candidate_work_experience_candidate_profile
        FOREIGN KEY (candidate_profile_id)
        REFERENCES profile.candidate_profile (id)
        ON UPDATE RESTRICT ON DELETE CASCADE,
    CONSTRAINT fk_candidate_work_experience_job_role
        FOREIGN KEY (job_role_id)
        REFERENCES master.job_role (id)
        ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_candidate_work_experience_employment_type
        FOREIGN KEY (employment_type_id)
        REFERENCES master.employment_type (id)
        ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT ck_candidate_work_experience_employer
        CHECK (LENGTH(BTRIM(employer_name)) BETWEEN 1 AND 200),
    CONSTRAINT ck_candidate_work_experience_title
        CHECK (LENGTH(BTRIM(job_title)) BETWEEN 1 AND 150),
    CONSTRAINT ck_candidate_work_experience_dates
        CHECK (end_date IS NULL OR end_date >= start_date),
    CONSTRAINT ck_candidate_work_experience_current
        CHECK (NOT is_current OR end_date IS NULL)
);

CREATE INDEX idx_candidate_work_experience_profile
    ON profile.candidate_work_experience
       (candidate_profile_id, start_date DESC);

CREATE INDEX idx_candidate_work_experience_job_role
    ON profile.candidate_work_experience (job_role_id);

-- Current and preferred candidate locations.
CREATE TABLE profile.candidate_location (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    candidate_profile_id BIGINT NOT NULL,
    city_id BIGINT NOT NULL,
    location_type VARCHAR(20) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_candidate_location PRIMARY KEY (id),
    CONSTRAINT uq_candidate_location_profile_city_type
        UNIQUE (candidate_profile_id, city_id, location_type),
    CONSTRAINT fk_candidate_location_candidate_profile
        FOREIGN KEY (candidate_profile_id)
        REFERENCES profile.candidate_profile (id)
        ON UPDATE RESTRICT ON DELETE CASCADE,
    CONSTRAINT fk_candidate_location_city
        FOREIGN KEY (city_id)
        REFERENCES master.city (id)
        ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT ck_candidate_location_type
        CHECK (location_type IN ('current', 'preferred'))
);

-- At most one current city per candidate; multiple preferred cities allowed.
CREATE UNIQUE INDEX uq_candidate_location_current
    ON profile.candidate_location (candidate_profile_id)
    WHERE location_type = 'current';

CREATE INDEX idx_candidate_location_city
    ON profile.candidate_location (city_id, location_type);

COMMENT ON TABLE profile.candidate_skill IS
    'Candidate skill claims linked to canonical master skills';

COMMENT ON TABLE profile.candidate_education IS
    'Candidate education history; institution and grade details are personal data';

COMMENT ON TABLE profile.candidate_work_experience IS
    'Candidate employment history; employer and career details are personal data';

COMMENT ON TABLE profile.candidate_location IS
    'Candidate current location and preferred work locations';

COMMIT;
