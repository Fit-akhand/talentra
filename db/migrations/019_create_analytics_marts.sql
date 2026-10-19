-- Migration: 019_create_analytics_marts.sql
-- Purpose: Implement Analytics Star Schema, SCD Type 2 dimensions, pipeline facts, KPI reporting aggregates, and partitioning strategies.
-- Requires: 001_create_schemas.sql, 002_create_identity.sql, 003_create_master_data.sql, 005_create_candidate_profile.sql, 007_create_organization.sql, 008_create_job_posting.sql, 009_create_candidate_application.sql, 014_create_gig_marketplace.sql, 017_create_commercial_ledgers.sql
-- Engine: PostgreSQL 17

BEGIN;

-- 1. Date Dimension (Standard analytical dimension)
CREATE TABLE analytics.dim_date (
    date_key INTEGER NOT NULL,
    calendar_date DATE NOT NULL,
    day_of_month INTEGER NOT NULL,
    day_name VARCHAR(10) NOT NULL,
    day_of_week INTEGER NOT NULL,
    month_number INTEGER NOT NULL,
    month_name VARCHAR(15) NOT NULL,
    quarter_number INTEGER NOT NULL,
    year_number INTEGER NOT NULL,
    is_weekend BOOLEAN NOT NULL,

    CONSTRAINT pk_dim_date PRIMARY KEY (date_key),
    CONSTRAINT uq_dim_date_calendar UNIQUE (calendar_date)
);

COMMENT ON TABLE analytics.dim_date IS
    'Pre-populated calendar date dimension for analytical slice-and-dice';

-- Seed calendar dates for 2025–2027
INSERT INTO analytics.dim_date (
    date_key, calendar_date, day_of_month, day_name, day_of_week,
    month_number, month_name, quarter_number, year_number, is_weekend
)
SELECT
    TO_CHAR(d, 'YYYYMMDD')::INTEGER,
    d::DATE,
    EXTRACT(DAY FROM d)::INTEGER,
    TO_CHAR(d, 'Day'),
    EXTRACT(ISODOW FROM d)::INTEGER,
    EXTRACT(MONTH FROM d)::INTEGER,
    TO_CHAR(d, 'Month'),
    EXTRACT(QUARTER FROM d)::INTEGER,
    EXTRACT(YEAR FROM d)::INTEGER,
    CASE WHEN EXTRACT(ISODOW FROM d) IN (6, 7) THEN TRUE ELSE FALSE END
FROM generate_series(
    '2025-01-01'::DATE,
    '2027-12-31'::DATE,
    '1 day'::INTERVAL
) AS d
ON CONFLICT (date_key) DO NOTHING;


-- 2. Slowly Changing Candidate Dimension (SCD Type 2)
CREATE TABLE analytics.dim_candidate (
    candidate_key BIGINT GENERATED ALWAYS AS IDENTITY,
    candidate_profile_id BIGINT NOT NULL,
    current_city_name VARCHAR(100),
    total_experience_years NUMERIC(4,1),
    profile_completeness_percentage NUMERIC(5,2),
    primary_skill_name VARCHAR(120),
    valid_from TIMESTAMPTZ NOT NULL,
    valid_to TIMESTAMPTZ,
    is_current BOOLEAN NOT NULL DEFAULT TRUE,

    CONSTRAINT pk_dim_candidate PRIMARY KEY (candidate_key),
    CONSTRAINT ck_dim_candidate_dates
        CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE INDEX idx_dim_candidate_profile_current
    ON analytics.dim_candidate (candidate_profile_id, is_current);

COMMENT ON TABLE analytics.dim_candidate IS
    'Candidate dimension with Type-2 slowly changing tracking of career experience and locations';


-- 3. Slowly Changing Organization Dimension (SCD Type 2)
CREATE TABLE analytics.dim_organization (
    organization_key BIGINT GENERATED ALWAYS AS IDENTITY,
    organization_id BIGINT NOT NULL,
    organization_name VARCHAR(200) NOT NULL,
    organization_type VARCHAR(30) NOT NULL,
    country_code VARCHAR(3),
    industry_name VARCHAR(120),
    valid_from TIMESTAMPTZ NOT NULL,
    valid_to TIMESTAMPTZ,
    is_current BOOLEAN NOT NULL DEFAULT TRUE,

    CONSTRAINT pk_dim_organization PRIMARY KEY (organization_key),
    CONSTRAINT ck_dim_organization_dates
        CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE INDEX idx_dim_organization_org_current
    ON analytics.dim_organization (organization_id, is_current);

COMMENT ON TABLE analytics.dim_organization IS
    'Organization dimension tracking corporate profile shifts over time';


-- 4. Job Posting Dimension
CREATE TABLE analytics.dim_job_posting (
    job_posting_key BIGINT GENERATED ALWAYS AS IDENTITY,
    job_posting_id BIGINT NOT NULL,
    organization_key BIGINT NOT NULL,
    job_title VARCHAR(200) NOT NULL,
    job_role_name VARCHAR(120),
    industry_name VARCHAR(120),
    employment_type_code VARCHAR(30),
    work_type_code VARCHAR(30),
    currency_code CHAR(3),
    salary_min NUMERIC(14,2),
    salary_max NUMERIC(14,2),
    published_date_key INTEGER,

    CONSTRAINT pk_dim_job_posting PRIMARY KEY (job_posting_key),
    CONSTRAINT uq_dim_job_posting_id UNIQUE (job_posting_id),

    CONSTRAINT fk_dim_job_posting_org
        FOREIGN KEY (organization_key)
        REFERENCES analytics.dim_organization (organization_key)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT fk_dim_job_posting_published_date
        FOREIGN KEY (published_date_key)
        REFERENCES analytics.dim_date (date_key)
        ON UPDATE RESTRICT
        ON DELETE SET NULL
);

CREATE INDEX idx_dim_job_posting_role_industry
    ON analytics.dim_job_posting (job_role_name, industry_name);

COMMENT ON TABLE analytics.dim_job_posting IS
    'Analytical job posting dimension incorporating role, arrangement, and salary tiers';


-- 5. Fact Table: Application Pipeline Funnel Events
CREATE TABLE analytics.fact_application_event (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    candidate_application_id BIGINT NOT NULL,
    date_key INTEGER NOT NULL,
    job_posting_key BIGINT NOT NULL,
    candidate_key BIGINT NOT NULL,
    organization_key BIGINT NOT NULL,
    previous_status VARCHAR(20),
    new_status VARCHAR(20) NOT NULL,
    status_cycle_time_hours NUMERIC(10,2),
    is_terminal_state BOOLEAN NOT NULL DEFAULT FALSE,
    event_timestamp TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_fact_application_event PRIMARY KEY (id),

    CONSTRAINT fk_fact_app_event_date
        FOREIGN KEY (date_key)
        REFERENCES analytics.dim_date (date_key)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT fk_fact_app_event_job
        FOREIGN KEY (job_posting_key)
        REFERENCES analytics.dim_job_posting (job_posting_key)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT fk_fact_app_event_candidate
        FOREIGN KEY (candidate_key)
        REFERENCES analytics.dim_candidate (candidate_key)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT fk_fact_app_event_organization
        FOREIGN KEY (organization_key)
        REFERENCES analytics.dim_organization (organization_key)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT
);

CREATE INDEX idx_fact_app_event_status_date
    ON analytics.fact_application_event (new_status, date_key);

CREATE INDEX idx_fact_app_event_org_job
    ON analytics.fact_application_event (organization_key, job_posting_key);

COMMENT ON TABLE analytics.fact_application_event IS
    'Fact table tracking hiring pipeline state changes and stage cycle times';


-- 6. Fact Table: Gig Performance & Fulfilment
CREATE TABLE analytics.fact_gig_performance (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    gig_assignment_id BIGINT NOT NULL,
    organization_key BIGINT NOT NULL,
    completion_date_key INTEGER,
    agreed_amount NUMERIC(14,2) NOT NULL,
    actual_reconciled_earnings NUMERIC(14,2) NOT NULL,
    currency_code CHAR(3) NOT NULL,
    duration_days INTEGER NOT NULL,
    client_rating NUMERIC(3,2),
    assignment_status VARCHAR(20) NOT NULL,

    CONSTRAINT pk_fact_gig_performance PRIMARY KEY (id),

    CONSTRAINT fk_fact_gig_org
        FOREIGN KEY (organization_key)
        REFERENCES analytics.dim_organization (organization_key)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT fk_fact_gig_completion_date
        FOREIGN KEY (completion_date_key)
        REFERENCES analytics.dim_date (date_key)
        ON UPDATE RESTRICT
        ON DELETE SET NULL
);

CREATE INDEX idx_fact_gig_perf_org
    ON analytics.fact_gig_performance (organization_key);

COMMENT ON TABLE analytics.fact_gig_performance IS
    'Fact table tracking completed gig assignments, earnings reconciliation, and satisfaction';


-- 7. Fact Table: Platform Wallet Transactions & Velocity
CREATE TABLE analytics.fact_wallet_transaction (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    wallet_id BIGINT NOT NULL,
    organization_key BIGINT NOT NULL,
    date_key INTEGER NOT NULL,
    entry_type VARCHAR(20) NOT NULL,
    amount NUMERIC(14,2) NOT NULL,
    currency_code CHAR(3) NOT NULL,
    reference_type VARCHAR(40) NOT NULL,
    recorded_timestamp TIMESTAMPTZ NOT NULL,

    CONSTRAINT pk_fact_wallet_transaction PRIMARY KEY (id),

    CONSTRAINT fk_fact_wallet_org
        FOREIGN KEY (organization_key)
        REFERENCES analytics.dim_organization (organization_key)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT fk_fact_wallet_date
        FOREIGN KEY (date_key)
        REFERENCES analytics.dim_date (date_key)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT
);

CREATE INDEX idx_fact_wallet_tx_date_type
    ON analytics.fact_wallet_transaction (date_key, reference_type);

COMMENT ON TABLE analytics.fact_wallet_transaction IS
    'Fact table analyzing credit spend velocity, recharge rates, and monetized features';


-- 8. Materialized Reporting Views for Core Hackathon KPIs (Section 8)
-- KPI 1: Hiring Funnel Conversion Rates & Time to Hire
CREATE MATERIALIZED VIEW analytics.mv_hiring_funnel_summary AS
SELECT
    j.job_posting_id,
    j.job_title,
    o.organization_name,
    COUNT(CASE WHEN f.new_status = 'applied' THEN 1 END) AS total_applied,
    COUNT(CASE WHEN f.new_status = 'shortlisted' THEN 1 END) AS total_shortlisted,
    COUNT(CASE WHEN f.new_status = 'interviewed' THEN 1 END) AS total_interviewed,
    COUNT(CASE WHEN f.new_status = 'offered' THEN 1 END) AS total_offered,
    COUNT(CASE WHEN f.new_status = 'joined' THEN 1 END) AS total_joined,
    ROUND(
        AVG(CASE WHEN f.new_status = 'joined' THEN f.status_cycle_time_hours END),
        2
    ) AS avg_time_to_hire_hours
FROM analytics.fact_application_event f
JOIN analytics.dim_job_posting j ON f.job_posting_key = j.job_posting_key
JOIN analytics.dim_organization o ON f.organization_key = o.organization_key
GROUP BY j.job_posting_id, j.job_title, o.organization_name;

CREATE UNIQUE INDEX uq_mv_hiring_funnel_job
    ON analytics.mv_hiring_funnel_summary (job_posting_id);

COMMENT ON MATERIALIZED VIEW analytics.mv_hiring_funnel_summary IS
    'Pre-aggregated hiring funnel metrics and time-to-hire by job requirement';


-- KPI 2: Gig Fulfilment Revenue and Ratings
CREATE MATERIALIZED VIEW analytics.mv_gig_fulfilment_summary AS
SELECT
    o.organization_name,
    g.currency_code,
    COUNT(*) AS total_gigs_completed,
    ROUND(SUM(g.actual_reconciled_earnings), 2) AS total_reconciled_revenue,
    ROUND(AVG(g.client_rating), 2) AS average_requester_rating,
    ROUND(AVG(g.duration_days), 1) AS average_duration_days
FROM analytics.fact_gig_performance g
JOIN analytics.dim_organization o ON g.organization_key = o.organization_key
WHERE g.assignment_status = 'completed'
GROUP BY o.organization_name, g.currency_code;

CREATE UNIQUE INDEX uq_mv_gig_fulfilment_org_curr
    ON analytics.mv_gig_fulfilment_summary (organization_name, currency_code);

COMMENT ON MATERIALIZED VIEW analytics.mv_gig_fulfilment_summary IS
    'Aggregated gig revenue, completion rates, and client satisfaction metrics';


-- Refresh procedure for analytical marts
CREATE OR REPLACE PROCEDURE analytics.refresh_reporting_marts()
LANGUAGE plpgsql
AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY analytics.mv_hiring_funnel_summary;
    REFRESH MATERIALIZED VIEW CONCURRENTLY analytics.mv_gig_fulfilment_summary;
END;
$$;


-- 9. Table Partitioning Architecture (Milestone 21 / B73)
-- Declarative Range Partitioned Candidate Application Table for 100M Scale
CREATE TABLE recruitment.candidate_application_partitioned (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
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

    CONSTRAINT pk_candidate_app_partitioned
        PRIMARY KEY (id, applied_at)
) PARTITION BY RANGE (applied_at);

-- Partitions by year
CREATE TABLE recruitment.candidate_application_y2025
    PARTITION OF recruitment.candidate_application_partitioned
    FOR VALUES FROM ('2025-01-01 00:00:00+00') TO ('2026-01-01 00:00:00+00');

CREATE TABLE recruitment.candidate_application_y2026
    PARTITION OF recruitment.candidate_application_partitioned
    FOR VALUES FROM ('2026-01-01 00:00:00+00') TO ('2027-01-01 00:00:00+00');

CREATE TABLE recruitment.candidate_application_y2027
    PARTITION OF recruitment.candidate_application_partitioned
    FOR VALUES FROM ('2027-01-01 00:00:00+00') TO ('2028-01-01 00:00:00+00');

CREATE INDEX idx_candidate_app_part_job_status
    ON recruitment.candidate_application_partitioned (job_posting_id, application_status);

COMMENT ON TABLE recruitment.candidate_application_partitioned IS
    'Range-partitioned candidate application table designed for high throughput at 100M application scale';

COMMIT;
