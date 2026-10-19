-- Test suite: tests/test_sourcing.sql
-- Prerequisite: migrations 001 through 016 applied.

BEGIN;

DO $test$
DECLARE
    v_employer_user_id BIGINT;
    v_consultant_user_id BIGINT;
    v_candidate_user_id BIGINT;
    v_candidate_profile_id BIGINT;
    v_org_id BIGINT;
    v_job_closed_id BIGINT;
    v_job_open_id BIGINT;
    v_policy_id BIGINT;
    v_request_id BIGINT;
    v_submission_id BIGINT;
    v_batch_id BIGINT;
    v_recipient_id BIGINT;
    v_closed_consultant_blocked BOOLEAN := FALSE;
    v_duplicate_submission_blocked BOOLEAN := FALSE;
BEGIN
    -- 1. Setup fixtures
    INSERT INTO core.user_account (email)
    VALUES ('source_employer@example.com')
    RETURNING id INTO v_employer_user_id;

    INSERT INTO core.user_account (email)
    VALUES ('source_consultant@example.com')
    RETURNING id INTO v_consultant_user_id;

    INSERT INTO core.user_account (email)
    VALUES ('source_candidate@example.com')
    RETURNING id INTO v_candidate_user_id;

    INSERT INTO profile.candidate_profile (
        user_account_id,
        headline,
        total_experience_years,
        profile_status
    )
    VALUES (
        v_candidate_user_id,
        'Senior Distributed Systems Engineer',
        7.0,
        'active'
    )
    RETURNING id INTO v_candidate_profile_id;

    INSERT INTO recruitment.organization (
        name,
        slug,
        organization_type,
        created_by_user_account_id
    )
    VALUES (
        'Sourcing Hiring Corp',
        'sourcing-hiring-corp',
        'employer',
        v_employer_user_id
    )
    RETURNING id INTO v_org_id;

    -- Create Job 1: Closed to consultants
    INSERT INTO recruitment.job_posting (
        organization_id,
        created_by_user_account_id,
        employment_type_id,
        work_type_id,
        title,
        description,
        job_status,
        published_at
    )
    SELECT
        v_org_id,
        v_employer_user_id,
        et.id,
        wt.id,
        'Internal Staff Role (Not Open to Consultants)',
        'Internal hiring only',
        'published',
        CURRENT_TIMESTAMP
    FROM master.employment_type AS et
    CROSS JOIN master.work_type AS wt
    WHERE et.code = 'full_time'
      AND wt.code = 'on_site'
    RETURNING id INTO v_job_closed_id;

    -- Create Job 2: Open to consultants
    INSERT INTO recruitment.job_posting (
        organization_id,
        created_by_user_account_id,
        employment_type_id,
        work_type_id,
        title,
        description,
        job_status,
        published_at
    )
    SELECT
        v_org_id,
        v_employer_user_id,
        et.id,
        wt.id,
        'Staff Architect (Open to External Consultants)',
        'Open for external agency sourcing with bounty',
        'published',
        CURRENT_TIMESTAMP
    FROM master.employment_type AS et
    CROSS JOIN master.work_type AS wt
    WHERE et.code = 'full_time'
      AND wt.code = 'remote'
    RETURNING id INTO v_job_open_id;

    -- Set consultant policy for Job 2
    INSERT INTO sourcing.job_consultant_policy (
        job_posting_id,
        is_open_to_consultants,
        max_consultants,
        bounty_amount,
        currency_code
    )
    VALUES (
        v_job_open_id,
        TRUE,
        5,
        5000.00,
        'USD'
    )
    RETURNING id INTO v_policy_id;

    -- 2. Test Consultant Openness Enforcement Trigger (Milestone 14 / B46)
    -- Attempting to request sourcing for Job 1 (closed) MUST BE BLOCKED
    BEGIN
        INSERT INTO sourcing.consultant_sourcing_request (
            job_posting_id,
            consultant_user_account_id,
            proposal_notes
        )
        VALUES (
            v_job_closed_id,
            v_consultant_user_id,
            'I have candidate for this job'
        );
    EXCEPTION
        WHEN raise_exception THEN
            v_closed_consultant_blocked := TRUE;
    END;

    IF NOT v_closed_consultant_blocked THEN
        RAISE EXCEPTION 'Consultant request was allowed on a job closed to consultants!';
    END IF;

    -- Requesting sourcing for Job 2 (open) MUST SUCCEED
    INSERT INTO sourcing.consultant_sourcing_request (
        job_posting_id,
        consultant_user_account_id,
        proposal_notes,
        request_status,
        decided_by_user_account_id,
        decided_at,
        decision_reason
    )
    VALUES (
        v_job_open_id,
        v_consultant_user_id,
        'Elite candidate pool ready to deploy',
        'accepted',
        v_employer_user_id,
        CURRENT_TIMESTAMP,
        'Approved for 30-day sourcing window'
    )
    RETURNING id INTO v_request_id;

    -- 3. Test Sourcing Submission (Shortlist)
    INSERT INTO sourcing.sourcing_submission (
        consultant_sourcing_request_id,
        job_posting_id,
        candidate_profile_id,
        submitted_by_user_account_id,
        submission_status,
        consultant_notes
    )
    VALUES (
        v_request_id,
        v_job_open_id,
        v_candidate_profile_id,
        v_consultant_user_id,
        'submitted',
        'Top 1% engineer in distributed consensus'
    )
    RETURNING id INTO v_submission_id;

    -- Duplicate submission for same job and candidate must fail
    BEGIN
        INSERT INTO sourcing.sourcing_submission (
            consultant_sourcing_request_id,
            job_posting_id,
            candidate_profile_id,
            submitted_by_user_account_id
        )
        VALUES (
            v_request_id,
            v_job_open_id,
            v_candidate_profile_id,
            v_consultant_user_id
        );
    EXCEPTION
        WHEN unique_violation THEN
            v_duplicate_submission_blocked := TRUE;
    END;

    IF NOT v_duplicate_submission_blocked THEN
        RAISE EXCEPTION 'Duplicate candidate submission was accepted';
    END IF;

    -- 4. Test Bulk Outreach Campaign and Recipients
    INSERT INTO sourcing.outreach_batch (
        organization_id,
        created_by_user_account_id,
        campaign_name,
        job_posting_id,
        channel,
        subject,
        message_body,
        total_recipients,
        total_credits_deducted,
        status
    )
    VALUES (
        v_org_id,
        v_employer_user_id,
        'Q4 Staff SRE Targeted Outreach',
        v_job_open_id,
        'email',
        'Exciting Principal Systems Role',
        'We noticed your background and would love to connect.',
        1,
        2.50,
        'processing'
    )
    RETURNING id INTO v_batch_id;

    INSERT INTO sourcing.outreach_recipient (
        outreach_batch_id,
        candidate_profile_id,
        delivery_status,
        sent_at
    )
    VALUES (
        v_batch_id,
        v_candidate_profile_id,
        'sent',
        CURRENT_TIMESTAMP
    )
    RETURNING id INTO v_recipient_id;

    RAISE NOTICE 'PASS: consultant openness policy configured';
    RAISE NOTICE 'PASS: consultant blocked from jobs not open to consultants';
    RAISE NOTICE 'PASS: consultant sourcing request accepted for open job';
    RAISE NOTICE 'PASS: candidate sourcing submission and uniqueness verified';
    RAISE NOTICE 'PASS: bulk outreach campaign and recipient tracking verified';
END;
$test$;

ROLLBACK;
