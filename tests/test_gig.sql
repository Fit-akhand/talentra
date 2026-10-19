-- Test suite: tests/test_gig.sql
-- Prerequisite: migrations 001 through 014 applied.

BEGIN;

DO $test$
DECLARE
    v_worker_user_id BIGINT;
    v_requester_user_id BIGINT;
    v_org_id BIGINT;
    v_worker_profile_id BIGINT;
    v_skill_id BIGINT;
    v_request1_id BIGINT;
    v_request2_id BIGINT;
    v_app1_id BIGINT;
    v_app2_id BIGINT;
    v_assign1_id BIGINT;
    v_assign2_id BIGINT;
    v_earnings_id BIGINT;
    v_rating_id BIGINT;
    v_pref_id BIGINT;
    v_overlapping_gig_blocked BOOLEAN := FALSE;
    v_duplicate_application_blocked BOOLEAN := FALSE;
BEGIN
    -- 1. Fixture setup
    INSERT INTO core.user_account (email)
    VALUES ('gig_worker@example.com')
    RETURNING id INTO v_worker_user_id;

    INSERT INTO core.user_account (email)
    VALUES ('gig_requester@example.com')
    RETURNING id INTO v_requester_user_id;

    INSERT INTO recruitment.organization (
        name,
        slug,
        organization_type,
        created_by_user_account_id
    )
    VALUES (
        'Gig Client Ventures',
        'gig-client-ventures',
        'employer',
        v_requester_user_id
    )
    RETURNING id INTO v_org_id;

    SELECT id INTO v_skill_id FROM master.skill WHERE normalized_name = 'python';

    -- 2. Create distinct Gig Worker Profile
    INSERT INTO gig.gig_worker_profile (
        user_account_id,
        headline,
        hourly_rate,
        daily_rate,
        currency_code,
        bio
    )
    VALUES (
        v_worker_user_id,
        'Senior Python & Data Pipeline Contractor',
        75.00,
        550.00,
        'USD',
        'Expert in high-throughput ETL and PostgreSQL optimization'
    )
    RETURNING id INTO v_worker_profile_id;

    -- 3. Gig Worker Availability & Service Offerings
    INSERT INTO gig.gig_worker_availability (
        gig_worker_profile_id,
        available_from,
        available_to,
        daily_available_hours
    )
    VALUES (
        v_worker_profile_id,
        '2026-11-01',
        '2026-12-31',
        8.0
    );

    INSERT INTO gig.gig_worker_service (
        gig_worker_profile_id,
        skill_id,
        custom_title,
        rate_override
    )
    VALUES (
        v_worker_profile_id,
        v_skill_id,
        'PostgreSQL Query Tuning Consultation',
        100.00
    );

    -- 4. Create Gig Requests
    INSERT INTO gig.gig_request (
        organization_id,
        created_by_user_account_id,
        title,
        description,
        deliverables,
        pricing_type,
        budget_amount,
        currency_code,
        start_date,
        end_date,
        request_status
    )
    VALUES (
        v_org_id,
        v_requester_user_id,
        'Optimize High Volume Financial Ledger Queries',
        'Analyze query execution plans and add partial indexes',
        'EXPLAIN ANALYZE report and migration script',
        'fixed',
        3000.00,
        'USD',
        '2026-11-01',
        '2026-11-15',
        'open'
    )
    RETURNING id INTO v_request1_id;

    INSERT INTO gig.gig_request (
        organization_id,
        created_by_user_account_id,
        title,
        description,
        deliverables,
        pricing_type,
        budget_amount,
        currency_code,
        start_date,
        end_date,
        request_status
    )
    VALUES (
        v_org_id,
        v_requester_user_id,
        'Build Synthetic Data Generator Script',
        'Create Python script streaming 1M candidate profiles into DB',
        'Validated python generator with benchmarks',
        'fixed',
        2500.00,
        'USD',
        '2026-11-10', -- Note: overlaps with Request 1 (Nov 1 to Nov 15)
        '2026-11-20',
        'open'
    )
    RETURNING id INTO v_request2_id;

    -- 5. Gig Applications (Unidirectional)
    INSERT INTO gig.gig_application (
        gig_request_id,
        gig_worker_profile_id,
        bid_amount,
        currency_code,
        proposed_duration_days,
        pitch,
        application_status,
        decided_at
    )
    VALUES (
        v_request1_id,
        v_worker_profile_id,
        2800.00,
        'USD',
        10,
        'I have 8+ years tuning PostgreSQL schemas and ledgers',
        'accepted',
        CURRENT_TIMESTAMP
    )
    RETURNING id INTO v_app1_id;

    INSERT INTO gig.gig_application (
        gig_request_id,
        gig_worker_profile_id,
        bid_amount,
        currency_code,
        proposed_duration_days,
        pitch,
        application_status,
        decided_at
    )
    VALUES (
        v_request2_id,
        v_worker_profile_id,
        2500.00,
        'USD',
        8,
        'Proficient with bulk COPY and multiprocessing data generators',
        'accepted',
        CURRENT_TIMESTAMP
    )
    RETURNING id INTO v_app2_id;

    -- Duplicate application by same worker to same request must be blocked
    BEGIN
        INSERT INTO gig.gig_application (
            gig_request_id,
            gig_worker_profile_id,
            bid_amount,
            currency_code
        )
        VALUES (
            v_request1_id,
            v_worker_profile_id,
            3000.00,
            'USD'
        );
    EXCEPTION
        WHEN unique_violation THEN
            v_duplicate_application_blocked := TRUE;
    END;

    IF NOT v_duplicate_application_blocked THEN
        RAISE EXCEPTION 'Duplicate gig application was accepted';
    END IF;

    -- 6. Gig Assignment & Non-Overlap Constraint
    -- Assignment 1: Nov 01 to Nov 15
    INSERT INTO gig.gig_assignment (
        gig_request_id,
        gig_application_id,
        gig_worker_profile_id,
        assigned_start_date,
        assigned_end_date,
        agreed_amount,
        currency_code,
        assignment_status,
        external_handoff_ref
    )
    VALUES (
        v_request1_id,
        v_app1_id,
        v_worker_profile_id,
        '2026-11-01',
        '2026-11-15',
        2800.00,
        'USD',
        'active',
        'EXT-FULFILL-2026-001'
    )
    RETURNING id INTO v_assign1_id;

    -- Attempting Assignment 2 during overlapping dates (Nov 10 to Nov 20) for SAME worker MUST BE REJECTED
    BEGIN
        INSERT INTO gig.gig_assignment (
            gig_request_id,
            gig_application_id,
            gig_worker_profile_id,
            assigned_start_date,
            assigned_end_date,
            agreed_amount,
            currency_code,
            assignment_status,
            external_handoff_ref
        )
        VALUES (
            v_request2_id,
            v_app2_id,
            v_worker_profile_id,
            '2026-11-10',
            '2026-11-20',
            2500.00,
            'USD',
            'active',
            'EXT-FULFILL-2026-002'
        );
    EXCEPTION
        WHEN exclusion_violation THEN
            v_overlapping_gig_blocked := TRUE;
    END;

    IF NOT v_overlapping_gig_blocked THEN
        RAISE EXCEPTION 'Overlapping gig assignment was allowed! Expected exclusion constraint violation';
    END IF;

    -- 7. External Reconciled Earnings (Integration Boundary)
    INSERT INTO gig.gig_external_earnings (
        gig_assignment_id,
        estimated_earnings,
        total_earnings,
        projected_earnings,
        currency_code,
        external_sync_hash
    )
    VALUES (
        v_assign1_id,
        2800.00,
        1400.00,
        2800.00,
        'USD',
        'sha256_mock_hash_sync_001'
    )
    RETURNING id INTO v_earnings_id;

    -- 8. Requester Rating for Gig
    INSERT INTO gig.gig_rating (
        gig_assignment_id,
        rater_user_account_id,
        rating_score,
        quality_score,
        communication_score,
        review_text
    )
    VALUES (
        v_assign1_id,
        v_requester_user_id,
        4.95,
        5.00,
        4.90,
        'Outstanding database optimization expertise and delivered before deadline.'
    )
    RETURNING id INTO v_rating_id;

    -- 9. Requester Favourite Preference List
    INSERT INTO gig.gig_worker_preference (
        organization_id,
        gig_worker_profile_id,
        preference_type,
        reason
    )
    VALUES (
        v_org_id,
        v_worker_profile_id,
        'favourite',
        'Go-to contractor for PostgreSQL tuning'
    )
    RETURNING id INTO v_pref_id;

    RAISE NOTICE 'PASS: gig worker profile, availability, and service offerings created';
    RAISE NOTICE 'PASS: gig request created with budget and date constraints';
    RAISE NOTICE 'PASS: gig application unique constraint verified';
    RAISE NOTICE 'PASS: gig assignment exclusion constraint blocked overlapping active windows';
    RAISE NOTICE 'PASS: external earnings integration boundary record created';
    RAISE NOTICE 'PASS: completed gig rating and feedback recorded';
    RAISE NOTICE 'PASS: favourite gig worker preference saved';
END;
$test$;

ROLLBACK;
