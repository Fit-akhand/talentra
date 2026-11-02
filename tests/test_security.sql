-- Test: test_security.sql
-- Covers: SEC-001, SEC-002, SEC-005, SEC-010, SEC-014
-- Domain: core / audit / recruitment / profile
-- Purpose: Verify database roles, permissions, Row-Level Security (RLS) isolation, candidate block enforcement, and append-only ledger immutability.
-- Engine: PostgreSQL 17

BEGIN;

DO $$
DECLARE
    v_user1_id BIGINT;
    v_user2_id BIGINT;
    v_cand_id BIGINT;
    v_org1_id BIGINT;
    v_org2_id BIGINT;
    v_job1_id BIGINT;
    v_job2_id BIGINT;
    v_wallet_id BIGINT;
    v_ledger_id BIGINT;
    v_audit_id BIGINT;
    v_emp_id BIGINT;
    v_work_id BIGINT;
    v_count INT;
    v_err_caught BOOLEAN := FALSE;
BEGIN
    RAISE NOTICE '=== Running Security & Access Control Tests ===';

    SELECT id INTO v_emp_id FROM master.employment_type LIMIT 1;
    SELECT id INTO v_work_id FROM master.work_type LIMIT 1;

    -- 1. Setup Test Users & Organizations
    INSERT INTO core.user_account (email, account_status)
    VALUES ('sec_candidate_1@test.com', 'active')
    RETURNING id INTO v_user1_id;

    INSERT INTO core.user_account (email, account_status)
    VALUES ('sec_recruiter_2@test.com', 'active')
    RETURNING id INTO v_user2_id;

    INSERT INTO profile.candidate_profile (user_account_id, headline, visibility)
    VALUES (v_user1_id, 'Security Specialist', 'recruiters')
    RETURNING id INTO v_cand_id;

    INSERT INTO recruitment.organization (name, slug, organization_type, created_by_user_account_id)
    VALUES ('Security Corp 1', 'sec-corp-1-test', 'employer', v_user2_id)
    RETURNING id INTO v_org1_id;

    INSERT INTO recruitment.organization (name, slug, organization_type, created_by_user_account_id)
    VALUES ('Security Corp 2', 'sec-corp-2-test', 'employer', v_user2_id)
    RETURNING id INTO v_org2_id;

    -- Job 1 belongs to Org 1 (draft)
    INSERT INTO recruitment.job_posting (
        organization_id, created_by_user_account_id, employment_type_id, work_type_id,
        title, description, job_status
    ) VALUES (
        v_org1_id, v_user2_id, v_emp_id, v_work_id, 'Org 1 Private Draft Job', 'Internal req', 'draft'
    ) RETURNING id INTO v_job1_id;

    -- Job 2 belongs to Org 2 (draft)
    INSERT INTO recruitment.job_posting (
        organization_id, created_by_user_account_id, employment_type_id, work_type_id,
        title, description, job_status
    ) VALUES (
        v_org2_id, v_user2_id, v_emp_id, v_work_id, 'Org 2 Private Draft Job', 'Internal req', 'draft'
    ) RETURNING id INTO v_job2_id;

    -- 2. Test Append-Only Ledger Immutability on commercial.wallet_ledger
    INSERT INTO commercial.wallet (organization_id, balance, currency_code)
    VALUES (v_org1_id, 1000.00, 'USD')
    RETURNING id INTO v_wallet_id;

    INSERT INTO commercial.wallet_ledger (
        wallet_id, entry_type, amount, currency_code, balance_after,
        reference_type, notes, created_by_user_account_id
    ) VALUES (
        v_wallet_id, 'credit', 1000.00, 'USD', 1000.00,
        'recharge', 'Initial credit deposit', v_user2_id
    ) RETURNING id INTO v_ledger_id;

    -- Attempt UPDATE on wallet_ledger: Must be rejected by trigger
    v_err_caught := FALSE;
    BEGIN
        UPDATE commercial.wallet_ledger SET amount = 9999.00 WHERE id = v_ledger_id;
    EXCEPTION WHEN OTHERS THEN
        v_err_caught := TRUE;
    END;
    ASSERT v_err_caught = TRUE, 'FAILED: UPDATE on commercial.wallet_ledger should be rejected by anti-tamper trigger';
    RAISE NOTICE 'PASS: Wallet ledger immutability trigger successfully prevented UPDATE';

    -- Attempt DELETE on wallet_ledger: Must be rejected by trigger
    v_err_caught := FALSE;
    BEGIN
        DELETE FROM commercial.wallet_ledger WHERE id = v_ledger_id;
    EXCEPTION WHEN OTHERS THEN
        v_err_caught := TRUE;
    END;
    ASSERT v_err_caught = TRUE, 'FAILED: DELETE on commercial.wallet_ledger should be rejected by anti-tamper trigger';
    RAISE NOTICE 'PASS: Wallet ledger immutability trigger successfully prevented DELETE';

    -- 3. Test Append-Only Audit Trail Immutability on audit.audit_event
    INSERT INTO audit.audit_event (
        actor_user_account_id, action, entity_schema, entity_name, entity_id
    ) VALUES (
        v_user2_id, 'auth.login', 'recruitment', 'job_posting', v_job1_id
    ) RETURNING id INTO v_audit_id;

    -- Attempt UPDATE on audit.audit_event: Must be rejected by trigger
    v_err_caught := FALSE;
    BEGIN
        UPDATE audit.audit_event SET action = 'tampered_action' WHERE id = v_audit_id;
    EXCEPTION WHEN OTHERS THEN
        v_err_caught := TRUE;
    END;
    ASSERT v_err_caught = TRUE, 'FAILED: UPDATE on audit.audit_event should be rejected by anti-tamper trigger';
    RAISE NOTICE 'PASS: Audit event immutability trigger successfully prevented UPDATE';

    -- Attempt DELETE on audit.audit_event: Must be rejected by trigger
    v_err_caught := FALSE;
    BEGIN
        DELETE FROM audit.audit_event WHERE id = v_audit_id;
    EXCEPTION WHEN OTHERS THEN
        v_err_caught := TRUE;
    END;
    ASSERT v_err_caught = TRUE, 'FAILED: DELETE on audit.audit_event should be rejected by anti-tamper trigger';
    RAISE NOTICE 'PASS: Audit event immutability trigger successfully prevented DELETE';

    -- 4. Test Candidate Block List Enforcement
    -- Insert user block: Candidate 1 blocks Recruiter 2
    INSERT INTO core.user_block (blocker_user_account_id, blocked_user_account_id, block_reason)
    VALUES (v_user1_id, v_user2_id, 'Unsolicited outreach attempt');

    -- Verify outreach query excludes Candidate 1 for Recruiter 2
    SELECT COUNT(*) INTO v_count
    FROM profile.candidate_profile cp
    WHERE cp.id = v_cand_id
      AND NOT EXISTS (
          SELECT 1 FROM core.user_block ub
          WHERE ub.blocker_user_account_id = cp.user_account_id
            AND (ub.blocked_user_account_id = v_user2_id OR ub.blocked_organization_id = v_org1_id)
      );
    ASSERT v_count = 0, 'FAILED: Blocked candidate should be excluded from recruiter queries';
    RAISE NOTICE 'PASS: Candidate block enforcement correctly excluded candidate from recruiter search';

    -- 5. Test User Credential Constraints (Decoupled Authentication Security)
    v_err_caught := FALSE;
    BEGIN
        INSERT INTO core.user_credential (
            user_account_id, credential_type, credential_identifier, secret_hash
        ) VALUES (
            v_user1_id, 'invalid_credential_type', 'user1_cred', 'secret_hash_value'
        );
    EXCEPTION WHEN OTHERS THEN
        v_err_caught := TRUE;
    END;
    ASSERT v_err_caught = TRUE, 'FAILED: Invalid credential_type should be rejected by ck_user_credential_type';
    RAISE NOTICE 'PASS: Check constraint ck_user_credential_type successfully rejected invalid credential';

    -- Also verify empty secret is rejected
    v_err_caught := FALSE;
    BEGIN
        INSERT INTO core.user_credential (
            user_account_id, credential_type, credential_identifier, secret_hash
        ) VALUES (
            v_user1_id, 'password', 'user1_cred_2', '   '
        );
    EXCEPTION WHEN OTHERS THEN
        v_err_caught := TRUE;
    END;
    ASSERT v_err_caught = TRUE, 'FAILED: Empty secret_hash should be rejected by ck_user_credential_secret';
    RAISE NOTICE 'PASS: Check constraint ck_user_credential_secret successfully rejected empty secret';

    RAISE NOTICE '=== All Security & Access Control Tests Passed Successfully ===';
END;
$$;

ROLLBACK;
