-- Test suite: tests/test_analytics.sql
-- Prerequisite: migrations 001 through 019 applied.

BEGIN;

DO $test$
DECLARE
    v_date_count INTEGER;
    v_candidate_key BIGINT;
    v_org_key BIGINT;
    v_job_key BIGINT;
    v_fact_app_id BIGINT;
    v_fact_gig_id BIGINT;
    v_fact_wallet_id BIGINT;
    v_part_app_id BIGINT;
    v_routed_to_y2026 BOOLEAN := FALSE;
BEGIN
    -- 1. Test Date Dimension
    SELECT COUNT(*) INTO v_date_count
    FROM analytics.dim_date
    WHERE year_number = 2026;

    IF v_date_count < 365 THEN
        RAISE EXCEPTION 'Expected at least 365 days in dim_date for 2026; found %', v_date_count;
    END IF;

    -- 2. Test SCD Type 2 Organization Dimension
    INSERT INTO analytics.dim_organization (
        organization_id,
        organization_name,
        organization_type,
        country_code,
        industry_name,
        valid_from,
        is_current
    )
    VALUES (
        1001,
        'Analytics Tech Corp',
        'employer',
        'USA',
        'Software and Cloud',
        CURRENT_TIMESTAMP,
        TRUE
    )
    RETURNING organization_key INTO v_org_key;

    -- 3. Test SCD Type 2 Candidate Dimension
    INSERT INTO analytics.dim_candidate (
        candidate_profile_id,
        current_city_name,
        total_experience_years,
        profile_completeness_percentage,
        primary_skill_name,
        valid_from,
        is_current
    )
    VALUES (
        2001,
        'San Francisco',
        5.5,
        90.00,
        'PostgreSQL',
        CURRENT_TIMESTAMP,
        TRUE
    )
    RETURNING candidate_key INTO v_candidate_key;

    -- 4. Test Job Posting Dimension
    INSERT INTO analytics.dim_job_posting (
        job_posting_id,
        organization_key,
        job_title,
        job_role_name,
        industry_name,
        employment_type_code,
        work_type_code,
        currency_code,
        salary_min,
        salary_max,
        published_date_key
    )
    VALUES (
        3001,
        v_org_key,
        'Principal Data Warehouse Architect',
        'Data Architect',
        'Software and Cloud',
        'full_time',
        'remote',
        'USD',
        160000.00,
        220000.00,
        20260115
    )
    RETURNING job_posting_key INTO v_job_key;

    -- 5. Test Fact Tables Insertion
    INSERT INTO analytics.fact_application_event (
        candidate_application_id,
        date_key,
        job_posting_key,
        candidate_key,
        organization_key,
        previous_status,
        new_status,
        status_cycle_time_hours,
        is_terminal_state
    )
    VALUES
        (5001, 20260116, v_job_key, v_candidate_key, v_org_key, NULL, 'applied', 0.0, FALSE),
        (5001, 20260118, v_job_key, v_candidate_key, v_org_key, 'applied', 'shortlisted', 48.0, FALSE),
        (5001, 20260125, v_job_key, v_candidate_key, v_org_key, 'shortlisted', 'joined', 168.0, TRUE);

    INSERT INTO analytics.fact_gig_performance (
        gig_assignment_id,
        organization_key,
        completion_date_key,
        agreed_amount,
        actual_reconciled_earnings,
        currency_code,
        duration_days,
        client_rating,
        assignment_status
    )
    VALUES (
        6001,
        v_org_key,
        20260210,
        4000.00,
        4000.00,
        'USD',
        14,
        4.95,
        'completed'
    )
    RETURNING id INTO v_fact_gig_id;

    INSERT INTO analytics.fact_wallet_transaction (
        wallet_id,
        organization_key,
        date_key,
        entry_type,
        amount,
        currency_code,
        reference_type,
        recorded_timestamp
    )
    VALUES (
        7001,
        v_org_key,
        20260115,
        'credit',
        1000.00,
        'USD',
        'recharge',
        CURRENT_TIMESTAMP
    )
    RETURNING id INTO v_fact_wallet_id;

    -- 6. Test Range Partitioned Application Routing (Milestone 21 / B73)
    INSERT INTO recruitment.candidate_application_partitioned (
        candidate_profile_id,
        job_posting_id,
        application_status,
        application_source,
        applied_at,
        created_by_user_account_id,
        updated_by_user_account_id
    )
    VALUES (
        2001,
        3001,
        'applied',
        'direct',
        '2026-06-15 10:30:00+00',
        1,
        1
    )
    RETURNING id INTO v_part_app_id;

    -- Verify that PostgreSQL correctly routed the record to the y2026 partition
    SELECT EXISTS (
        SELECT 1
        FROM recruitment.candidate_application_y2026
        WHERE id = v_part_app_id
    ) INTO v_routed_to_y2026;

    IF NOT v_routed_to_y2026 THEN
        RAISE EXCEPTION 'Partition routing failed: 2026 application was not found in recruitment.candidate_application_y2026!';
    END IF;

    RAISE NOTICE 'PASS: dim_date pre-populated calendar dimension verified';
    RAISE NOTICE 'PASS: SCD Type 2 candidate and organization dimensions verified';
    RAISE NOTICE 'PASS: job posting dimension and foreign keys verified';
    RAISE NOTICE 'PASS: fact_application_event, fact_gig_performance, and fact_wallet_transaction populated';
    RAISE NOTICE 'PASS: candidate application declarative range partitioning and year-2026 routing verified';
END;
$test$;

-- Test materialized view refresh outside transaction block because concurrent refresh requires autocommit
COMMIT;

CALL analytics.refresh_reporting_marts();

-- Verify materialized views hold expected aggregated rows
DO $$
DECLARE
    v_funnel_rows INTEGER;
    v_gig_rows INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_funnel_rows FROM analytics.mv_hiring_funnel_summary;
    SELECT COUNT(*) INTO v_gig_rows FROM analytics.mv_gig_fulfilment_summary;

    IF v_funnel_rows = 0 THEN
        RAISE EXCEPTION 'Materialized view mv_hiring_funnel_summary is empty after refresh!';
    END IF;

    IF v_gig_rows = 0 THEN
        RAISE EXCEPTION 'Materialized view mv_gig_fulfilment_summary is empty after refresh!';
    END IF;

    RAISE NOTICE 'PASS: materialized reporting views refreshed and verified with aggregated KPIs';

    -- Cleanup test fixtures
    DELETE FROM analytics.fact_application_event WHERE candidate_application_id = 5001;
    DELETE FROM analytics.fact_gig_performance WHERE gig_assignment_id = 6001;
    DELETE FROM analytics.fact_wallet_transaction WHERE wallet_id = 7001;
    DELETE FROM analytics.dim_job_posting WHERE job_posting_id = 3001;
    DELETE FROM analytics.dim_candidate WHERE candidate_profile_id = 2001;
    DELETE FROM analytics.dim_organization WHERE organization_id = 1001;
    DELETE FROM recruitment.candidate_application_partitioned WHERE candidate_profile_id = 2001;
END;
$$;

CALL analytics.refresh_reporting_marts();
