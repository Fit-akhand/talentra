-- Test: test_business_rules.sql
-- Domain: Cross-Schema / Rules Group 9 & 10
-- Purpose: Verify advanced multi-entity business rule constraints (consultant policy enforcement, exclusion constraints, concurrent session limits, and wallet reconciliation).
-- Engine: PostgreSQL 17

BEGIN;

DO $$
DECLARE
    v_user1_id BIGINT;
    v_user2_id BIGINT;
    v_cand_id BIGINT;
    v_emp_id BIGINT;
    v_work_id BIGINT;
    v_org_id BIGINT;
    v_job_id BIGINT;
    v_worker_id BIGINT;
    v_req1_id BIGINT;
    v_req2_id BIGINT;
    v_app1_id BIGINT;
    v_app2_id BIGINT;
    v_lic_id BIGINT;
    v_plan_id BIGINT;
    v_sess_token VARCHAR(255);
    v_err_caught BOOLEAN := FALSE;
BEGIN
    RAISE NOTICE '=== Running Cross-Entity Business Rule Tests ===';

    SELECT id INTO v_emp_id FROM master.employment_type LIMIT 1;
    SELECT id INTO v_work_id FROM master.work_type LIMIT 1;

    -- Setup Users & Org
    INSERT INTO core.user_account (email, account_status)
    VALUES ('biz_rules_user1@test.com', 'active')
    RETURNING id INTO v_user1_id;

    INSERT INTO core.user_account (email, account_status)
    VALUES ('biz_rules_user2@test.com', 'active')
    RETURNING id INTO v_user2_id;

    INSERT INTO profile.candidate_profile (user_account_id, headline, visibility)
    VALUES (v_user1_id, 'Full Stack Architect', 'recruiters')
    RETURNING id INTO v_cand_id;

    INSERT INTO recruitment.organization (name, slug, organization_type, created_by_user_account_id)
    VALUES ('Enterprise Rules Corp', 'ent-rules-corp-slug', 'employer', v_user2_id)
    RETURNING id INTO v_org_id;

    INSERT INTO recruitment.job_posting (
        organization_id, created_by_user_account_id, employment_type_id, work_type_id,
        title, description, job_status, published_at
    ) VALUES (
        v_org_id, v_user2_id, v_emp_id, v_work_id, 'Lead Systems Engineer', 'Desc', 'published', CURRENT_TIMESTAMP
    ) RETURNING id INTO v_job_id;

    -- 1. Test Consultant Sourcing Policy Trigger
    -- Configure job consultant policy: NOT open to consultants
    INSERT INTO sourcing.job_consultant_policy (job_posting_id, is_open_to_consultants)
    VALUES (v_job_id, FALSE);

    v_err_caught := FALSE;
    BEGIN
        INSERT INTO sourcing.consultant_sourcing_request (
            job_posting_id, consultant_user_account_id, request_status
        ) VALUES (
            v_job_id, v_user2_id, 'requested'
        );
    EXCEPTION WHEN OTHERS THEN
        v_err_caught := TRUE;
    END;
    ASSERT v_err_caught = TRUE, 'FAILED: Agency request should be rejected when is_open_to_consultants = FALSE';
    RAISE NOTICE 'PASS: Consultant policy trigger correctly rejected unauthorized agency request';

    -- Now allow consultants and verify request succeeds
    UPDATE sourcing.job_consultant_policy
    SET is_open_to_consultants = TRUE
    WHERE job_posting_id = v_job_id;

    INSERT INTO sourcing.consultant_sourcing_request (
        job_posting_id, consultant_user_account_id, request_status
    ) VALUES (
        v_job_id, v_user2_id, 'requested'
    );
    RAISE NOTICE 'PASS: Consultant request accepted after policy enabled';

    -- 2. Test Non-Overlapping Gig Assignment Exclusion Constraint (btree_gist)
    INSERT INTO gig.gig_worker_profile (user_account_id, headline, hourly_rate, currency_code, is_available)
    VALUES (v_user1_id, 'Contract Cloud Architect', 95.00, 'USD', TRUE)
    RETURNING id INTO v_worker_id;

    INSERT INTO gig.gig_request (
        organization_id, created_by_user_account_id, title, description, deliverables,
        pricing_type, budget_amount, currency_code, start_date, end_date
    ) VALUES
        (v_org_id, v_user2_id, 'Sprint Project Alpha', 'Description 1', 'Deliverable 1', 'fixed', 5000, 'USD', '2026-11-01', '2026-11-15')
    RETURNING id INTO v_req1_id;

    INSERT INTO gig.gig_request (
        organization_id, created_by_user_account_id, title, description, deliverables,
        pricing_type, budget_amount, currency_code, start_date, end_date
    ) VALUES
        (v_org_id, v_user2_id, 'Sprint Project Beta', 'Description 2', 'Deliverable 2', 'fixed', 4000, 'USD', '2026-11-10', '2026-11-25')
    RETURNING id INTO v_req2_id;

    INSERT INTO gig.gig_application (
        gig_request_id, gig_worker_profile_id, bid_amount, currency_code, application_status, decided_at
    ) VALUES
        (v_req1_id, v_worker_id, 5000, 'USD', 'accepted', CURRENT_TIMESTAMP)
    RETURNING id INTO v_app1_id;

    INSERT INTO gig.gig_application (
        gig_request_id, gig_worker_profile_id, bid_amount, currency_code, application_status, decided_at
    ) VALUES
        (v_req2_id, v_worker_id, 4000, 'USD', 'accepted', CURRENT_TIMESTAMP)
    RETURNING id INTO v_app2_id;

    -- First assignment succeeds: 2026-11-01 to 2026-11-15
    INSERT INTO gig.gig_assignment (
        gig_request_id, gig_application_id, gig_worker_profile_id,
        assigned_start_date, assigned_end_date, agreed_amount, currency_code,
        assignment_status, external_handoff_ref
    ) VALUES (
        v_req1_id, v_app1_id, v_worker_id,
        '2026-11-01', '2026-11-15', 5000, 'USD',
        'active', 'ext_ref_alpha_1'
    );
    RAISE NOTICE 'PASS: First active gig assignment created successfully';

    -- Second assignment overlaps (2026-11-10 to 2026-11-20): MUST be rejected by exclusion constraint
    v_err_caught := FALSE;
    BEGIN
        INSERT INTO gig.gig_assignment (
            gig_request_id, gig_application_id, gig_worker_profile_id,
            assigned_start_date, assigned_end_date, agreed_amount, currency_code,
            assignment_status, external_handoff_ref
        ) VALUES (
            v_req2_id, v_app2_id, v_worker_id,
            '2026-11-10', '2026-11-20', 4000, 'USD',
            'active', 'ext_ref_beta_2'
        );
    EXCEPTION WHEN OTHERS THEN
        v_err_caught := TRUE;
    END;
    ASSERT v_err_caught = TRUE, 'FAILED: Overlapping active gig assignment should violate ex_gig_assignment_no_overlap';
    RAISE NOTICE 'PASS: ex_gig_assignment_no_overlap successfully prevented double-booked gig assignment';

    -- 3. Test Subscription Exclusion Constraint (btree_gist non-overlapping subscription periods)
    INSERT INTO commercial.subscription_licence (
        organization_id, licence_key, licence_name, max_users, max_devices_per_user,
        valid_from, valid_to, licence_status
    ) VALUES (
        v_org_id, 'LIC-BIZ-RULES-KEY-001', 'Enterprise Suite', 10, 2,
        '2026-01-01 00:00:00+00', '2027-01-01 00:00:00+00', 'active'
    ) RETURNING id INTO v_lic_id;

    INSERT INTO commercial.subscription_plan (plan_code, name, tier, billing_interval, price_amount, currency_code)
    VALUES ('PRO-ANNUAL-TEST', 'Professional Annual', 'standard', 'annual', 1200.00, 'USD')
    RETURNING id INTO v_plan_id;

    -- First subscription: 2026-01-01 to 2026-06-30
    INSERT INTO commercial.subscription (
        subscription_licence_id, subscription_plan_id, period_start, period_end, subscription_status
    ) VALUES (
        v_lic_id, v_plan_id, '2026-01-01 00:00:00+00', '2026-06-30 23:59:59+00', 'active'
    );

    -- Overlapping subscription: 2026-05-01 to 2026-12-31 MUST be rejected by ex_subscription_no_overlap
    v_err_caught := FALSE;
    BEGIN
        INSERT INTO commercial.subscription (
            subscription_licence_id, subscription_plan_id, period_start, period_end, subscription_status
        ) VALUES (
            v_lic_id, v_plan_id, '2026-05-01 00:00:00+00', '2026-12-31 23:59:59+00', 'active'
        );
    EXCEPTION WHEN OTHERS THEN
        v_err_caught := TRUE;
    END;
    ASSERT v_err_caught = TRUE, 'FAILED: Overlapping subscription periods should violate ex_subscription_no_overlap';
    RAISE NOTICE 'PASS: ex_subscription_no_overlap successfully prevented overlapping subscription periods';

    -- 4. Test Concurrent Session Device Limit Enforcement (Rule Group 9)
    -- Allocate seat to user 2 with max_devices_per_user = 2
    INSERT INTO commercial.licence_seat_allocation (subscription_licence_id, user_account_id)
    VALUES (v_lic_id, v_user2_id);

    -- Session 1: device_laptop (succeeds)
    SELECT core.create_session_with_device_limit(v_user2_id, 'device_laptop', 'sess_hash_1') INTO v_sess_token;
    ASSERT v_sess_token IS NOT NULL, 'FAILED: First valid device session should be granted';

    -- Session 2: device_phone (succeeds)
    SELECT core.create_session_with_device_limit(v_user2_id, 'device_phone', 'sess_hash_2') INTO v_sess_token;
    ASSERT v_sess_token IS NOT NULL, 'FAILED: Second valid device session should be granted';

    -- Session 3: device_tablet (exceeds limit 2: must return NULL and log audit breach)
    SELECT core.create_session_with_device_limit(v_user2_id, 'device_tablet', 'sess_hash_3') INTO v_sess_token;
    ASSERT v_sess_token IS NULL, 'FAILED: Third device session should be rejected when max_devices_per_user = 2';
    RAISE NOTICE 'PASS: create_session_with_device_limit successfully enforced device limit and rejected 3rd session';

    RAISE NOTICE '=== All Cross-Entity Business Rule Tests Passed Successfully ===';
END;
$$;

ROLLBACK;
