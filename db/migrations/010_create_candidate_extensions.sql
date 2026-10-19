-- Migration: 010_create_candidate_extensions.sql
-- Purpose: Add candidate languages, projects, assessments, profile completion, and view history.
-- Requires: 001_create_schemas.sql, 003_create_master_data.sql, 005_create_candidate_profile.sql, 007_create_organization.sql
-- Engine: PostgreSQL 17

BEGIN;

-- 1. Canonical Language Catalogue in master schema
CREATE TABLE IF NOT EXISTS master.language (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    code VARCHAR(10) NOT NULL,
    name VARCHAR(100) NOT NULL,
    native_name VARCHAR(100),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_language PRIMARY KEY (id),
    CONSTRAINT uq_language_code UNIQUE (code),
    CONSTRAINT uq_language_name UNIQUE (name),
    CONSTRAINT ck_language_code
        CHECK (code ~ '^[a-z]{2,3}(-[A-Za-z0-9]+)?$'),
    CONSTRAINT ck_language_name
        CHECK (LENGTH(BTRIM(name)) BETWEEN 1 AND 100)
);

COMMENT ON TABLE master.language IS
    'Canonical ISO language catalogue used across profiles, postings, and UI translations';

-- Seed core languages
INSERT INTO master.language (code, name, native_name)
VALUES
    ('en', 'English', 'English'),
    ('es', 'Spanish', 'Español'),
    ('fr', 'French', 'Français'),
    ('de', 'German', 'Deutsch'),
    ('hi', 'Hindi', 'हिन्दी'),
    ('zh', 'Mandarin Chinese', '中文'),
    ('ja', 'Japanese', '日本語'),
    ('ar', 'Arabic', 'العربية'),
    ('pt', 'Portuguese', 'Português'),
    ('ru', 'Russian', 'Русский')
ON CONFLICT (code) DO NOTHING;


-- 2. Candidate Languages
CREATE TABLE profile.candidate_language (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    candidate_profile_id BIGINT NOT NULL,
    language_id BIGINT NOT NULL,
    proficiency_level VARCHAR(20) NOT NULL DEFAULT 'conversational',
    can_read BOOLEAN NOT NULL DEFAULT TRUE,
    can_write BOOLEAN NOT NULL DEFAULT TRUE,
    can_speak BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_candidate_language PRIMARY KEY (id),
    CONSTRAINT uq_candidate_language_profile_language
        UNIQUE (candidate_profile_id, language_id),

    CONSTRAINT fk_candidate_language_candidate_profile
        FOREIGN KEY (candidate_profile_id)
        REFERENCES profile.candidate_profile (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT fk_candidate_language_language
        FOREIGN KEY (language_id)
        REFERENCES master.language (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT ck_candidate_language_proficiency
        CHECK (
            proficiency_level IN (
                'basic',
                'conversational',
                'professional',
                'fluent',
                'native'
            )
        )
);

CREATE INDEX idx_candidate_language_language_id
    ON profile.candidate_language (language_id);

CREATE INDEX idx_candidate_language_profile_id
    ON profile.candidate_language (candidate_profile_id);

COMMENT ON TABLE profile.candidate_language IS
    'Languages spoken/written by candidates with proficiency ratings';


-- 3. Candidate Projects (personal, academic, professional, and gig portfolio)
CREATE TABLE profile.candidate_project (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    candidate_profile_id BIGINT NOT NULL,
    title VARCHAR(200) NOT NULL,
    candidate_role VARCHAR(150) NOT NULL,
    project_type VARCHAR(20) NOT NULL DEFAULT 'personal',
    start_date DATE,
    end_date DATE,
    is_ongoing BOOLEAN NOT NULL DEFAULT FALSE,
    project_url VARCHAR(2048),
    description TEXT,
    outcome TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_candidate_project PRIMARY KEY (id),

    CONSTRAINT fk_candidate_project_candidate_profile
        FOREIGN KEY (candidate_profile_id)
        REFERENCES profile.candidate_profile (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT ck_candidate_project_title
        CHECK (LENGTH(BTRIM(title)) BETWEEN 1 AND 200),

    CONSTRAINT ck_candidate_project_role
        CHECK (LENGTH(BTRIM(candidate_role)) BETWEEN 1 AND 150),

    CONSTRAINT ck_candidate_project_type
        CHECK (
            project_type IN (
                'personal',
                'academic',
                'professional',
                'open_source',
                'gig'
            )
        ),

    CONSTRAINT ck_candidate_project_dates
        CHECK (
            start_date IS NULL
            OR end_date IS NULL
            OR end_date >= start_date
        ),

    CONSTRAINT ck_candidate_project_ongoing
        CHECK (NOT is_ongoing OR end_date IS NULL),

    CONSTRAINT ck_candidate_project_url
        CHECK (
            project_url IS NULL
            OR (
                LENGTH(BTRIM(project_url)) BETWEEN 1 AND 2048
                AND project_url ~ '^https?://[^[:space:]]+$'
            )
        )
);

CREATE INDEX idx_candidate_project_profile_date
    ON profile.candidate_project (candidate_profile_id, start_date DESC);

COMMENT ON TABLE profile.candidate_project IS
    'Candidate professional and gig projects, detailing their role, duration, and outcome';


-- 4. Candidate Self-Assessments Catalogue & Scores
CREATE TABLE profile.candidate_assessment (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    title VARCHAR(150) NOT NULL,
    assessment_provider VARCHAR(50) NOT NULL DEFAULT 'talentra',
    skill_id BIGINT,
    total_questions INTEGER NOT NULL DEFAULT 20,
    duration_minutes INTEGER NOT NULL DEFAULT 30,
    passing_percentage NUMERIC(5,2) NOT NULL DEFAULT 60.00,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_candidate_assessment PRIMARY KEY (id),
    CONSTRAINT uq_candidate_assessment_title UNIQUE (title),

    CONSTRAINT fk_candidate_assessment_skill
        FOREIGN KEY (skill_id)
        REFERENCES master.skill (id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,

    CONSTRAINT ck_candidate_assessment_title
        CHECK (LENGTH(BTRIM(title)) BETWEEN 1 AND 150),

    CONSTRAINT ck_candidate_assessment_total_questions
        CHECK (total_questions BETWEEN 1 AND 500),

    CONSTRAINT ck_candidate_assessment_duration
        CHECK (duration_minutes BETWEEN 1 AND 480),

    CONSTRAINT ck_candidate_assessment_passing_percentage
        CHECK (passing_percentage BETWEEN 0.00 AND 100.00)
);

CREATE INDEX idx_candidate_assessment_skill_id
    ON profile.candidate_assessment (skill_id);

CREATE TABLE profile.candidate_assessment_score (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    candidate_profile_id BIGINT NOT NULL,
    candidate_assessment_id BIGINT NOT NULL,
    score_obtained NUMERIC(5,2) NOT NULL,
    max_score NUMERIC(5,2) NOT NULL,
    percentile NUMERIC(5,2),
    is_passed BOOLEAN NOT NULL DEFAULT FALSE,
    attempted_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_candidate_assessment_score PRIMARY KEY (id),

    CONSTRAINT fk_candidate_assessment_score_candidate_profile
        FOREIGN KEY (candidate_profile_id)
        REFERENCES profile.candidate_profile (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT fk_candidate_assessment_score_assessment
        FOREIGN KEY (candidate_assessment_id)
        REFERENCES profile.candidate_assessment (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT ck_candidate_assessment_score_max
        CHECK (max_score > 0.00),

    CONSTRAINT ck_candidate_assessment_score_obtained
        CHECK (score_obtained >= 0.00 AND score_obtained <= max_score),

    CONSTRAINT ck_candidate_assessment_score_percentile
        CHECK (percentile IS NULL OR (percentile >= 0.00 AND percentile <= 100.00))
);

CREATE INDEX idx_candidate_assessment_score_profile
    ON profile.candidate_assessment_score (candidate_profile_id, attempted_at DESC);

COMMENT ON TABLE profile.candidate_assessment IS
    'Catalogue of platform and third-party standardized skill assessments';

COMMENT ON TABLE profile.candidate_assessment_score IS
    'Candidate performance and verified scores on standardized assessments';


-- 5. Profile Completion Scoring
CREATE TABLE profile.candidate_profile_completion (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    candidate_profile_id BIGINT NOT NULL,
    total_score_percentage NUMERIC(5,2) NOT NULL DEFAULT 0.00,
    has_headline BOOLEAN NOT NULL DEFAULT FALSE,
    has_summary BOOLEAN NOT NULL DEFAULT FALSE,
    has_skills BOOLEAN NOT NULL DEFAULT FALSE,
    has_education BOOLEAN NOT NULL DEFAULT FALSE,
    has_experience BOOLEAN NOT NULL DEFAULT FALSE,
    has_resume BOOLEAN NOT NULL DEFAULT FALSE,
    has_projects BOOLEAN NOT NULL DEFAULT FALSE,
    last_calculated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_candidate_profile_completion PRIMARY KEY (id),
    CONSTRAINT uq_candidate_profile_completion_profile
        UNIQUE (candidate_profile_id),

    CONSTRAINT fk_candidate_profile_completion_profile
        FOREIGN KEY (candidate_profile_id)
        REFERENCES profile.candidate_profile (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT ck_candidate_profile_completion_percentage
        CHECK (total_score_percentage BETWEEN 0.00 AND 100.00)
);

COMMENT ON TABLE profile.candidate_profile_completion IS
    'Computed profile completeness scores encouraging candidate profile richness';


-- 6. Profile View History (Append-only)
CREATE TABLE profile.profile_view_history (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    candidate_profile_id BIGINT NOT NULL,
    viewer_user_account_id BIGINT NOT NULL,
    organization_id BIGINT,
    view_source VARCHAR(30) NOT NULL DEFAULT 'search',
    credit_deducted NUMERIC(14,2) NOT NULL DEFAULT 0.00,
    viewed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_profile_view_history PRIMARY KEY (id),

    CONSTRAINT fk_profile_view_history_candidate_profile
        FOREIGN KEY (candidate_profile_id)
        REFERENCES profile.candidate_profile (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT fk_profile_view_history_viewer
        FOREIGN KEY (viewer_user_account_id)
        REFERENCES core.user_account (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT fk_profile_view_history_organization
        FOREIGN KEY (organization_id)
        REFERENCES recruitment.organization (id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,

    CONSTRAINT ck_profile_view_history_source
        CHECK (
            view_source IN (
                'search',
                'direct_link',
                'sourcing',
                'applicant_review'
            )
        ),

    CONSTRAINT ck_profile_view_history_credit
        CHECK (credit_deducted >= 0.00)
);

CREATE INDEX idx_profile_view_history_candidate
    ON profile.profile_view_history (candidate_profile_id, viewed_at DESC);

CREATE INDEX idx_profile_view_history_viewer
    ON profile.profile_view_history (viewer_user_account_id, viewed_at DESC);

COMMENT ON TABLE profile.profile_view_history IS
    'Append-only record of recruiters viewing candidate profiles, tracking actor, timestamp, and credit deduction';


-- 7. Recruiter Shortlist and Bookmark History
CREATE TABLE profile.recruiter_bookmark (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    organization_id BIGINT NOT NULL,
    user_account_id BIGINT NOT NULL,
    candidate_profile_id BIGINT NOT NULL,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_recruiter_bookmark PRIMARY KEY (id),
    CONSTRAINT uq_recruiter_bookmark_org_candidate
        UNIQUE (organization_id, candidate_profile_id),

    CONSTRAINT fk_recruiter_bookmark_organization
        FOREIGN KEY (organization_id)
        REFERENCES recruitment.organization (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT fk_recruiter_bookmark_user_account
        FOREIGN KEY (user_account_id)
        REFERENCES core.user_account (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT fk_recruiter_bookmark_candidate_profile
        FOREIGN KEY (candidate_profile_id)
        REFERENCES profile.candidate_profile (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE
);

CREATE INDEX idx_recruiter_bookmark_org
    ON profile.recruiter_bookmark (organization_id, created_at DESC);

COMMENT ON TABLE profile.recruiter_bookmark IS
    'Employer and recruiter candidate shortlists and bookmarks';

COMMIT;
