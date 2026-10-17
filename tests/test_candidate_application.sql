    WHERE et.normalized_name = 'full_time'
      AND wt.normalized_name = 'remote'
    RETURNING id INTO v_job_posting_id;

    IF v_job_posting_id IS NULL THEN
        RAISE EXCEPTION
            'Required master data not found: employment_type=full_time and work_type=remote';
    END IF;

    ---------------------------------------------------------------------------
    -- 2. Create an application and verify the generated identifier.
    ---------------------------------------------------------------------------
    INSERT INTO recruitment.candidate_application (
        candidate_profile_id,
        job_posting_id,
        application_status,
        application_source,
        created_by_user_account_id,
        updated_by_user_account_id
    )
    VALUES (
        v_candidate_profile_id,
        v_job_posting_id,
        'applied',
        'direct',
        v_candidate_user_id,
        v_candidate_user_id
    )
    RETURNING id INTO v_application_id;

    IF v_application_id IS NULL THEN
        RAISE EXCEPTION 'Application insert did not return an ID';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM recruitment.candidate_application
        WHERE id = v_application_id
          AND candidate_profile_id = v_candidate_profile_id
          AND job_posting_id = v_job_posting_id
          AND application_status = 'applied'
    ) THEN
        RAISE EXCEPTION 'Application was not persisted with expected values';
    END IF;

    ---------------------------------------------------------------------------
    -- 3. Duplicate application for the same candidate/job pair must be blocked.
    ---------------------------------------------------------------------------
    BEGIN
        INSERT INTO recruitment.candidate_application (
            candidate_profile_id,
            job_posting_id,
            application_status,
            application_source,
            created_by_user_account_id,
            updated_by_user_account_id
        )
        VALUES (
            v_candidate_profile_id,
            v_job_posting_id,
            'applied',
            'direct',
            v_candidate_user_id,
            v_candidate_user_id
        );
    EXCEPTION
        WHEN unique_violation THEN
            v_duplicate_blocked := TRUE;
    END;

    IF NOT v_duplicate_blocked THEN
        RAISE EXCEPTION
            'Duplicate application was accepted; expected unique candidate/job constraint';
    END IF;

    ---------------------------------------------------------------------------
    -- 4. Change status and verify the application row is updated.
    -- The migration's status-history trigger should record this transition.
    ---------------------------------------------------------------------------
    UPDATE recruitment.candidate_application
    SET application_status = 'shortlisted',
        updated_by_user_account_id = v_recruiter_user_id,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = v_application_id;

    IF NOT EXISTS (
        SELECT 1
        FROM recruitment.candidate_application
        WHERE id = v_application_id
          AND application_status = 'shortlisted'
    ) THEN
        RAISE EXCEPTION 'Application status did not update to shortlisted';
    END IF;

    SELECT COUNT(*)
    INTO v_history_count
    FROM recruitment.application_status_history
    WHERE candidate_application_id = v_application_id;

    IF v_history_count < 2 THEN
        RAISE EXCEPTION
            'Expected initial application status plus status transition in history; found % row(s)',
            v_history_count;
    END IF;

    RAISE NOTICE 'PASS: fixture setup and application creation';
    RAISE NOTICE 'PASS: duplicate candidate/job application rejected';
    RAISE NOTICE 'PASS: application status update and history tracking';
END;
$test$;

-- Keep the database unchanged after the test run.
ROLLBACK;

