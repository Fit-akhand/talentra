
BEGIN;

-- Countries
CREATE TABLE master.country (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    iso_alpha2 CHAR(2) NOT NULL,
    iso_alpha3 CHAR(3) NOT NULL,
    name VARCHAR(100) NOT NULL,
    phone_calling_code VARCHAR(8),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_country PRIMARY KEY (id),
    CONSTRAINT uq_country_iso_alpha2 UNIQUE (iso_alpha2),
    CONSTRAINT uq_country_iso_alpha3 UNIQUE (iso_alpha3),
    CONSTRAINT uq_country_name UNIQUE (name),
    CONSTRAINT ck_country_iso_alpha2
        CHECK (iso_alpha2 ~ '^[A-Z]{2}$'),
    CONSTRAINT ck_country_iso_alpha3
        CHECK (iso_alpha3 ~ '^[A-Z]{3}$'),
    CONSTRAINT ck_country_name
        CHECK (LENGTH(BTRIM(name)) BETWEEN 1 AND 100),
    CONSTRAINT ck_country_calling_code
        CHECK (
            phone_calling_code IS NULL
            OR phone_calling_code ~ '^\+[1-9][0-9]{0,3}$'
        )
);

-- First-level administrative divisions, such as states or provinces
CREATE TABLE master.state (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    country_id BIGINT NOT NULL,
    name VARCHAR(100) NOT NULL,
    subdivision_code VARCHAR(20),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_state PRIMARY KEY (id),
    CONSTRAINT fk_state_country
        FOREIGN KEY (country_id)
        REFERENCES master.country (id)
        ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_state_country_name UNIQUE (country_id, name),
    CONSTRAINT ck_state_name
        CHECK (LENGTH(BTRIM(name)) BETWEEN 1 AND 100),
    CONSTRAINT ck_state_subdivision_code
        CHECK (
            subdivision_code IS NULL
            OR LENGTH(BTRIM(subdivision_code)) BETWEEN 1 AND 20
        )
);

-- Cities are associated with a state/province in this initial model.
CREATE TABLE master.city (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    state_id BIGINT NOT NULL,
    name VARCHAR(100) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_city PRIMARY KEY (id),
    CONSTRAINT fk_city_state
        FOREIGN KEY (state_id)
        REFERENCES master.state (id)
        ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_city_state_name UNIQUE (state_id, name),
    CONSTRAINT ck_city_name
        CHECK (LENGTH(BTRIM(name)) BETWEEN 1 AND 100)
);

-- Normalized skill catalogue
CREATE TABLE master.skill (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    name VARCHAR(120) NOT NULL,
    normalized_name VARCHAR(120) NOT NULL,
    description VARCHAR(500),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_skill PRIMARY KEY (id),
    CONSTRAINT uq_skill_normalized_name UNIQUE (normalized_name),
    CONSTRAINT ck_skill_name
        CHECK (LENGTH(BTRIM(name)) BETWEEN 1 AND 120),
    CONSTRAINT ck_skill_normalized_name
        CHECK (
            normalized_name = LOWER(BTRIM(normalized_name))
            AND LENGTH(normalized_name) BETWEEN 1 AND 120
        ),
    CONSTRAINT ck_skill_description
        CHECK (
            description IS NULL
            OR LENGTH(BTRIM(description)) BETWEEN 1 AND 500
        )
);

-- Education/qualification catalogue
CREATE TABLE master.qualification (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    name VARCHAR(150) NOT NULL,
    qualification_level VARCHAR(30) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_qualification PRIMARY KEY (id),
    CONSTRAINT uq_qualification_name_level
        UNIQUE (name, qualification_level),
    CONSTRAINT ck_qualification_name
        CHECK (LENGTH(BTRIM(name)) BETWEEN 1 AND 150),
    CONSTRAINT ck_qualification_level
        CHECK (
            qualification_level IN (
                'secondary',
                'higher_secondary',
                'diploma',
                'undergraduate',
                'postgraduate',
                'doctorate',
                'professional',
                'other'
            )
        )
);

-- Industry catalogue
CREATE TABLE master.industry (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    name VARCHAR(120) NOT NULL,
    normalized_name VARCHAR(120) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_industry PRIMARY KEY (id),
    CONSTRAINT uq_industry_normalized_name UNIQUE (normalized_name),
    CONSTRAINT ck_industry_name
        CHECK (LENGTH(BTRIM(name)) BETWEEN 1 AND 120),
    CONSTRAINT ck_industry_normalized_name
        CHECK (
            normalized_name = LOWER(BTRIM(normalized_name))
            AND LENGTH(normalized_name) BETWEEN 1 AND 120
        )
);

-- Job role/title catalogue
CREATE TABLE master.job_role (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    industry_id BIGINT,
    name VARCHAR(120) NOT NULL,
    normalized_name VARCHAR(120) NOT NULL,
    description VARCHAR(500),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_job_role PRIMARY KEY (id),
    CONSTRAINT fk_job_role_industry
        FOREIGN KEY (industry_id)
        REFERENCES master.industry (id)
        ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT uq_job_role_industry_name
        UNIQUE (industry_id, normalized_name),
    CONSTRAINT ck_job_role_name
        CHECK (LENGTH(BTRIM(name)) BETWEEN 1 AND 120),
    CONSTRAINT ck_job_role_normalized_name
        CHECK (
            normalized_name = LOWER(BTRIM(normalized_name))
            AND LENGTH(normalized_name) BETWEEN 1 AND 120
        ),
    CONSTRAINT ck_job_role_description
        CHECK (
            description IS NULL
            OR LENGTH(BTRIM(description)) BETWEEN 1 AND 500
        )
);

-- Employment arrangement
CREATE TABLE master.employment_type (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    code VARCHAR(30) NOT NULL,
    name VARCHAR(80) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_employment_type PRIMARY KEY (id),
    CONSTRAINT uq_employment_type_code UNIQUE (code),
    CONSTRAINT uq_employment_type_name UNIQUE (name),
    CONSTRAINT ck_employment_type_code
        CHECK (code ~ '^[a-z][a-z0-9_]{1,29}$'),
    CONSTRAINT ck_employment_type_name
        CHECK (LENGTH(BTRIM(name)) BETWEEN 1 AND 80)
);

-- Work location arrangement, independent of employment type
CREATE TABLE master.work_type (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    code VARCHAR(30) NOT NULL,
    name VARCHAR(80) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_work_type PRIMARY KEY (id),
    CONSTRAINT uq_work_type_code UNIQUE (code),
    CONSTRAINT uq_work_type_name UNIQUE (name),
    CONSTRAINT ck_work_type_code
        CHECK (code ~ '^[a-z][a-z0-9_]{1,29}$'),
    CONSTRAINT ck_work_type_name
        CHECK (LENGTH(BTRIM(name)) BETWEEN 1 AND 80)
);

-- Foreign-key lookup and filtering indexes
CREATE INDEX idx_state_country_id
    ON master.state (country_id);

CREATE INDEX idx_city_state_id
    ON master.city (state_id);

CREATE INDEX idx_skill_active_name
    ON master.skill (is_active, normalized_name);

CREATE INDEX idx_qualification_level
    ON master.qualification (qualification_level);

CREATE INDEX idx_industry_active_name
    ON master.industry (is_active, normalized_name);

CREATE INDEX idx_job_role_industry_id
    ON master.job_role (industry_id);

CREATE INDEX idx_job_role_active_name
    ON master.job_role (is_active, normalized_name);

COMMENT ON SCHEMA master IS
    'Shared reference data and controlled vocabularies';

COMMENT ON TABLE master.country IS
    'Country catalogue using ISO alpha-2 and alpha-3 codes';

COMMENT ON TABLE master.state IS
    'First-level country administrative divisions';

COMMENT ON TABLE master.city IS
    'City catalogue associated with a state or province';

COMMENT ON TABLE master.skill IS
    'Canonical skill catalogue used by candidate profiles and job requirements';

COMMENT ON TABLE master.qualification IS
    'Canonical education and qualification catalogue';

COMMENT ON TABLE master.industry IS
    'Industry classification catalogue';

COMMENT ON TABLE master.job_role IS
    'Canonical job titles, optionally associated with an industry';

COMMENT ON TABLE master.employment_type IS
    'Employment arrangements such as full-time, contract, and internship';

COMMENT ON TABLE master.work_type IS
    'Work location arrangements such as remote, hybrid, and on-site';

CREATE UNIQUE INDEX uq_job_role_uncategorized_name
    ON master.job_role (normalized_name)
    WHERE industry_id IS NULL;    

COMMIT;
