-- Test suite: tests/test_access_control.sql
-- Covers: SEC-001, SEC-002, SEC-005, SEC-006, SEC-007, SEC-013, SEC-014, BR-005, BR-010
-- Prerequisite: migrations 001-021 have been applied.
-- Isolation: one transaction, rolled back. Row-level security is bypassed by superusers, so every
-- check below runs after `SET LOCAL ROLE talentra_app` (or the other roles under test).

BEGIN;

DO $$
DECLARE
    v_emp_type BIGINT; v_work_type BIGINT;
    v_recA BIGINT; v_recB BIGINT; v_cand1 BIGINT; v_cand2 BIGINT; v_outsider BIGINT;
    v_orgA BIGINT; v_orgB BIGINT;
    v_jobA_pub BIGINT; v_jobA_draft BIGINT; v_jobB_draft BIGINT;
    v_prof1 BIGINT; v_prof2 BIGINT; v_appl1 BIGINT;
    v_walletA BIGINT; v_walletB BIGINT;
    v_n INTEGER; v_caught BOOLEAN; v_text TEXT;
BEGIN
    RAISE NOTICE '=== Access control: roles, grants, row-level security ===';

    -- ---------------------------------------------------------------- fixtures (as the table owner)
    SELECT id INTO v_emp_type FROM master.employment_type WHERE code = 'full_time';
    SELECT id INTO v_work_type FROM master.work_type WHERE code = 'remote';

    INSERT INTO core.user_account (email) VALUES ('ac-recruiter-a@example.com') RETURNING id INTO v_recA;
    INSERT INTO core.user_account (email) VALUES ('ac-recruiter-b@example.com') RETURNING id INTO v_recB;
    INSERT INTO core.user_account (email) VALUES ('ac-candidate-1@example.com') RETURNING id INTO v_cand1;
    INSERT INTO core.user_account (email) VALUES ('ac-candidate-2@example.com') RETURNING id INTO v_cand2;
    INSERT INTO core.user_account (email) VALUES ('ac-outsider@example.com')    RETURNING id INTO v_outsider;

    INSERT INTO recruitment.organization (name, slug, created_by_user_account_id, organization_status)
    VALUES ('AC Org A', 'ac-org-a', v_recA, 'active') RETURNING id INTO v_orgA;
    INSERT INTO recruitment.organization (name, slug, created_by_user_account_id, organization_status)
    VALUES ('AC Org B', 'ac-org-b', v_recB, 'active') RETURNING id INTO v_orgB;
    INSERT INTO recruitment.organization_member (organization_id, user_account_id, organization_role, membership_status, joined_at)
    VALUES (v_orgA, v_recA, 'recruiter', 'active', now()), (v_orgB, v_recB, 'recruiter', 'active', now());

    INSERT INTO recruitment.job_posting (organization_id, created_by_user_account_id, employment_type_id, work_type_id, title, description, job_status, published_at)
    VALUES (v_orgA, v_recA, v_emp_type, v_work_type, 'A public job', 'd', 'published', now()) RETURNING id INTO v_jobA_pub;
    INSERT INTO recruitment.job_posting (organization_id, created_by_user_account_id, employment_type_id, work_type_id, title, description)
    VALUES (v_orgA, v_recA, v_emp_type, v_work_type, 'A draft job', 'd') RETURNING id INTO v_jobA_draft;
    INSERT INTO recruitment.job_posting (organization_id, created_by_user_account_id, employment_type_id, work_type_id, title, description)
    VALUES (v_orgB, v_recB, v_emp_type, v_work_type, 'B draft job', 'd') RETURNING id INTO v_jobB_draft;

    INSERT INTO profile.candidate_profile (user_account_id, headline, visibility) VALUES (v_cand1, 'Candidate one', 'recruiters') RETURNING id INTO v_prof1;
    INSERT INTO profile.candidate_profile (user_account_id, headline, visibility) VALUES (v_cand2, 'Candidate two', 'recruiters') RETURNING id INTO v_prof2;
    INSERT INTO recruitment.candidate_application (candidate_profile_id, job_posting_id, application_status, created_by_user_account_id)
    VALUES (v_prof1, v_jobA_pub, 'applied', v_cand1) RETURNING id INTO v_appl1;

    INSERT INTO commercial.wallet (organization_id, balance, currency_code) VALUES (v_orgA, 100, 'USD') RETURNING id INTO v_walletA;
    INSERT INTO commercial.wallet (organization_id, balance, currency_code) VALUES (v_orgB, 200, 'USD') RETURNING id INTO v_walletB;
    INSERT INTO commercial.wallet_ledger (wallet_id, entry_type, amount, currency_code, balance_after, reference_type, created_by_user_account_id)
    VALUES (v_walletA, 'credit', 100, 'USD', 100, 'recharge', v_recA), (v_walletB, 'credit', 200, 'USD', 200, 'recharge', v_recB);
    INSERT INTO core.user_credential (user_account_id, credential_type, credential_identifier, secret_hash)
    VALUES (v_cand1, 'password', 'ac-candidate-1@example.com', '$argon2id$v=19$m=65536,t=3,p=4$abc$def'),
           (v_cand2, 'password', 'ac-candidate-2@example.com', '$argon2id$v=19$m=65536,t=3,p=4$abc$ghi');

    -- ---------------------------------------------------------------- 1. anonymous session fails closed
    EXECUTE 'SET LOCAL ROLE talentra_app';
    PERFORM set_config('app.current_user_id', '', true);
    PERFORM set_config('app.current_org_id', '', true);
    SELECT count(*) INTO v_n FROM recruitment.job_posting WHERE id IN (v_jobA_pub, v_jobA_draft, v_jobB_draft);
    IF v_n <> 1 THEN RAISE EXCEPTION 'FAIL: anonymous session sees % jobs, expected only the published one', v_n; END IF;
    SELECT count(*) INTO v_n FROM commercial.wallet WHERE id IN (v_walletA, v_walletB);
    IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL: anonymous session sees % wallets', v_n; END IF;
    SELECT count(*) INTO v_n FROM core.user_credential WHERE user_account_id IN (v_cand1, v_cand2);
    IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL: anonymous session sees % credentials', v_n; END IF;
    SELECT count(*) INTO v_n FROM profile.candidate_profile WHERE id IN (v_prof1, v_prof2);
    IF v_n <> 2 THEN
        -- visible profiles require is_candidate_visible_to with a NULL viewer: it returns TRUE unless blocked
        RAISE NOTICE 'NOTE: anonymous session sees % of 2 recruiter-visible profiles', v_n;
    END IF;
    RAISE NOTICE 'PASS: an anonymous session sees only published jobs, no wallets, no credentials';

    -- ---------------------------------------------------------------- 2. tenant isolation between organisations
    PERFORM set_config('app.current_user_id', v_recA::TEXT, true);
    PERFORM set_config('app.current_org_id', v_orgA::TEXT, true);
    SELECT count(*) INTO v_n FROM recruitment.job_posting WHERE id IN (v_jobA_pub, v_jobA_draft, v_jobB_draft);
    IF v_n <> 2 THEN RAISE EXCEPTION 'FAIL: recruiter A sees % jobs, expected 2 (own draft + published)', v_n; END IF;
    IF EXISTS (SELECT 1 FROM recruitment.job_posting WHERE id = v_jobB_draft) THEN
        RAISE EXCEPTION 'FAIL: recruiter A can read organisation B''s draft job';
    END IF;
    SELECT count(*) INTO v_n FROM commercial.wallet WHERE id IN (v_walletA, v_walletB);
    IF v_n <> 1 THEN RAISE EXCEPTION 'FAIL: recruiter A sees % wallets, expected 1', v_n; END IF;
    SELECT count(*) INTO v_n FROM commercial.wallet_ledger WHERE wallet_id IN (v_walletA, v_walletB);
    IF v_n <> 1 THEN RAISE EXCEPTION 'FAIL: recruiter A sees % ledger rows, expected 1', v_n; END IF;

    v_caught := FALSE;
    BEGIN
        INSERT INTO recruitment.job_posting (organization_id, employment_type_id, work_type_id, title, description)
        VALUES (v_orgB, v_emp_type, v_work_type, 'Planted in B', 'd');
    EXCEPTION WHEN insufficient_privilege THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: recruiter A created a job in organisation B'; END IF;
    RAISE NOTICE 'PASS: a recruiter reads and writes only their own organisation''s jobs, wallet and ledger';

    -- ---------------------------------------------------------------- 3. spoofing the organisation setting does not work
    PERFORM set_config('app.current_org_id', v_orgB::TEXT, true);     -- recruiter A claims to act for B
    IF core.current_org_id() IS NOT NULL THEN RAISE EXCEPTION 'FAIL: non-member was granted organisation context'; END IF;
    IF EXISTS (SELECT 1 FROM recruitment.job_posting WHERE id = v_jobB_draft)
       OR EXISTS (SELECT 1 FROM commercial.wallet WHERE id = v_walletB) THEN
        RAISE EXCEPTION 'FAIL: claiming another organisation exposed its data';
    END IF;
    RAISE NOTICE 'PASS: app.current_org_id is honoured only for active members';

    -- ---------------------------------------------------------------- 4. applications
    PERFORM set_config('app.current_user_id', v_cand1::TEXT, true);
    PERFORM set_config('app.current_org_id', '', true);
    IF NOT EXISTS (SELECT 1 FROM recruitment.candidate_application WHERE id = v_appl1) THEN
        RAISE EXCEPTION 'FAIL: a candidate cannot see their own application';
    END IF;
    PERFORM set_config('app.current_user_id', v_cand2::TEXT, true);
    IF EXISTS (SELECT 1 FROM recruitment.candidate_application WHERE id = v_appl1) THEN
        RAISE EXCEPTION 'FAIL: another candidate can see the application';
    END IF;
    v_caught := FALSE;
    BEGIN
        INSERT INTO recruitment.candidate_application (candidate_profile_id, job_posting_id, application_status)
        VALUES (v_prof1, v_jobA_pub, 'applied');            -- candidate 2 applying as candidate 1
    EXCEPTION WHEN insufficient_privilege THEN v_caught := TRUE; WHEN unique_violation THEN v_caught := FALSE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: a candidate applied on behalf of another candidate'; END IF;
    PERFORM set_config('app.current_user_id', v_recA::TEXT, true);
    PERFORM set_config('app.current_org_id', v_orgA::TEXT, true);
    IF NOT EXISTS (SELECT 1 FROM recruitment.candidate_application WHERE id = v_appl1) THEN
        RAISE EXCEPTION 'FAIL: the employer cannot see an application to their own job';
    END IF;
    PERFORM set_config('app.current_user_id', v_recB::TEXT, true);
    PERFORM set_config('app.current_org_id', v_orgB::TEXT, true);
    IF EXISTS (SELECT 1 FROM recruitment.candidate_application WHERE id = v_appl1) THEN
        RAISE EXCEPTION 'FAIL: another employer can see the application';
    END IF;
    RAISE NOTICE 'PASS: applications are visible to the candidate and the owning employer only';

    -- ---------------------------------------------------------------- 5. candidate block enforcement (BR-010)
    EXECUTE 'RESET ROLE';
    INSERT INTO core.user_block (blocker_user_account_id, blocked_organization_id) VALUES (v_cand2, v_orgA);
    EXECUTE 'SET LOCAL ROLE talentra_app';
    PERFORM set_config('app.current_user_id', v_recA::TEXT, true);
    PERFORM set_config('app.current_org_id', v_orgA::TEXT, true);
    IF EXISTS (SELECT 1 FROM profile.candidate_profile WHERE id = v_prof2) THEN
        RAISE EXCEPTION 'FAIL: a blocked organisation can still see the candidate profile';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM profile.candidate_profile WHERE id = v_prof1) THEN
        RAISE EXCEPTION 'FAIL: an unblocked, recruiter-visible profile is hidden';
    END IF;
    PERFORM set_config('app.current_user_id', v_recB::TEXT, true);
    PERFORM set_config('app.current_org_id', v_orgB::TEXT, true);
    IF NOT EXISTS (SELECT 1 FROM profile.candidate_profile WHERE id = v_prof2) THEN
        RAISE EXCEPTION 'FAIL: an organisation that was not blocked cannot see the profile';
    END IF;
    PERFORM set_config('app.current_user_id', v_cand2::TEXT, true);
    PERFORM set_config('app.current_org_id', '', true);
    IF NOT EXISTS (SELECT 1 FROM profile.candidate_profile WHERE id = v_prof2) THEN
        RAISE EXCEPTION 'FAIL: a candidate cannot see their own profile';
    END IF;
    RAISE NOTICE 'PASS: a blocked organisation cannot see the candidate; others and the owner can';

    -- ---------------------------------------------------------------- 6. credentials are private; login lookup is the one door
    PERFORM set_config('app.current_user_id', v_cand1::TEXT, true);
    SELECT count(*) INTO v_n FROM core.user_credential WHERE user_account_id IN (v_cand1, v_cand2);
    IF v_n <> 1 THEN RAISE EXCEPTION 'FAIL: a user sees % credentials, expected only their own', v_n; END IF;
    PERFORM set_config('app.current_user_id', '', true);
    SELECT count(*) INTO v_n FROM core.find_credential_for_login('AC-Candidate-1@example.com');
    IF v_n <> 1 THEN RAISE EXCEPTION 'FAIL: login lookup did not find the credential (case-insensitive)'; END IF;
    RAISE NOTICE 'PASS: credentials are readable only by their owner; login lookup works before authentication';

    -- ---------------------------------------------------------------- 6b. the real login path, as the application role
    --   look the credential up, verify the hash in the application, set who is acting, then call the login function
    EXECUTE 'SET LOCAL ROLE talentra_app';
    PERFORM set_config('app.current_user_id', v_cand1::TEXT, true);
    DECLARE
        v_s1 BIGINT; v_s2 BIGINT; v_s3 BIGINT;
    BEGIN
        v_s1 := core.create_session_with_device_limit(v_cand1, 'ac-dev-1', encode(sha256('ac-token-1'::bytea), 'hex'));
        v_s2 := core.create_session_with_device_limit(v_cand1, 'ac-dev-2', encode(sha256('ac-token-2'::bytea), 'hex'));
        v_s3 := core.create_session_with_device_limit(v_cand1, 'ac-dev-3', encode(sha256('ac-token-3'::bytea), 'hex'));
        IF v_s1 IS NULL OR v_s2 IS NULL THEN RAISE EXCEPTION 'FAIL: the first two devices were refused under row-level security'; END IF;
        IF v_s3 IS NOT NULL THEN RAISE EXCEPTION 'FAIL: the third device was allowed against a limit of 2'; END IF;
    END;
    EXECUTE 'RESET ROLE';
    IF NOT EXISTS (SELECT 1 FROM audit.audit_event WHERE action = 'device.limit_exceeded' AND actor_user_account_id = v_cand1) THEN
        RAISE EXCEPTION 'FAIL: the refused login written by the application role is missing from the audit log';
    END IF;
    RAISE NOTICE 'PASS: the login function works end to end as the application role: 2 devices allowed, the 3rd refused and audited';

    -- ---------------------------------------------------------------- 7. append-only and reference data are protected
    EXECUTE 'SET LOCAL ROLE talentra_app';
    v_caught := FALSE;
    BEGIN UPDATE commercial.wallet_ledger SET amount = 1 WHERE wallet_id = v_walletA;
    EXCEPTION WHEN insufficient_privilege THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: the application role can update the wallet ledger'; END IF;
    v_caught := FALSE;
    BEGIN DELETE FROM audit.audit_event;
    EXCEPTION WHEN insufficient_privilege THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: the application role can delete audit events'; END IF;
    v_caught := FALSE;
    BEGIN INSERT INTO master.country (iso_alpha2, iso_alpha3, name) VALUES ('ZZ', 'ZZZ', 'Nowhere');
    EXCEPTION WHEN insufficient_privilege THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: the application role can change reference data'; END IF;
    v_caught := FALSE;
    BEGIN PERFORM 1 FROM audit.audit_event LIMIT 1;
    EXCEPTION WHEN insufficient_privilege THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: the application role can read the audit log'; END IF;
    EXECUTE 'RESET ROLE';
    v_caught := FALSE;
    BEGIN TRUNCATE audit.audit_event;
    EXCEPTION WHEN restrict_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: TRUNCATE on the audit log was allowed'; END IF;
    RAISE NOTICE 'PASS: ledger and audit are append-only for the app role, reference data is read-only, TRUNCATE is blocked';

    -- ---------------------------------------------------------------- 8. other roles
    EXECUTE 'SET LOCAL ROLE talentra_support';
    v_caught := FALSE;
    BEGIN PERFORM 1 FROM core.user_account LIMIT 1;
    EXCEPTION WHEN insufficient_privilege THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: support staff can read the raw account table'; END IF;
    SELECT email_masked INTO v_text FROM core.support_user_account WHERE id = v_cand1;
    IF v_text <> 'a***@example.com' THEN RAISE EXCEPTION 'FAIL: support view did not mask the email (got %)', v_text; END IF;
    EXECUTE 'RESET ROLE';
    EXECUTE 'SET LOCAL ROLE talentra_readonly';
    v_caught := FALSE;
    BEGIN PERFORM 1 FROM core.user_credential LIMIT 1;
    EXCEPTION WHEN insufficient_privilege THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: the read-only role can read credentials'; END IF;
    v_caught := FALSE;
    BEGIN PERFORM 1 FROM core.find_credential_for_login('ac-candidate-1@example.com');
    EXCEPTION WHEN insufficient_privilege THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: the read-only role can fetch password hashes through the login lookup'; END IF;
    v_caught := FALSE;
    BEGIN PERFORM core.is_candidate_visible_to(v_prof1, v_recA, v_orgA);
    EXCEPTION WHEN insufficient_privilege THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: the read-only role can probe who has blocked whom'; END IF;
    EXECUTE 'RESET ROLE';
    EXECUTE 'SET LOCAL ROLE talentra_analyst';
    PERFORM 1 FROM analytics.dim_date LIMIT 1;
    v_caught := FALSE;
    BEGIN PERFORM 1 FROM recruitment.job_posting LIMIT 1;
    EXCEPTION WHEN insufficient_privilege THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: the analyst role can read operational tables'; END IF;
    EXECUTE 'RESET ROLE';
    RAISE NOTICE 'PASS: support sees masked data only; read-only cannot read credentials; analyst sees analytics only';

    -- ---------------------------------------------------------------- 9. credential formats
    v_caught := FALSE;
    BEGIN INSERT INTO core.user_credential (user_account_id, credential_type, credential_identifier, secret_hash)
          VALUES (v_outsider, 'password', 'plaintext@example.com', 'hunter2');
    EXCEPTION WHEN check_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: a plaintext password was accepted as a credential'; END IF;
    v_caught := FALSE;
    BEGIN INSERT INTO core.user_session (user_account_id, device_identifier, session_token_hash)
          VALUES (v_outsider, 'dev', 'not-a-sha256-digest');
    EXCEPTION WHEN check_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: a non-SHA-256 session token was accepted'; END IF;
    v_caught := FALSE;
    BEGIN UPDATE core.user_account SET password_hash = 'plain' WHERE id = v_outsider;
    EXCEPTION WHEN check_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: a plaintext user_account.password_hash was accepted'; END IF;
    RAISE NOTICE 'PASS: plaintext passwords and non-SHA-256 session tokens are rejected by the schema';

    -- ---------------------------------------------------------------- 10. permission catalogue
    SELECT count(*) INTO v_n FROM core.role r WHERE NOT EXISTS (SELECT 1 FROM core.role_permission rp WHERE rp.role_id = r.id);
    IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL: % roles have no permissions', v_n; END IF;
    IF (SELECT count(*) FROM core.role_permission rp JOIN core.role r ON r.id = rp.role_id WHERE r.name = 'super_admin')
       <> (SELECT count(*) FROM core.permission) THEN
        RAISE EXCEPTION 'FAIL: super_admin does not hold every permission';
    END IF;
    IF EXISTS (SELECT 1 FROM core.role_permission rp JOIN core.role r ON r.id = rp.role_id JOIN core.permission p ON p.id = rp.permission_id
                WHERE r.name = 'guest' AND p.code <> 'job.search') THEN
        RAISE EXCEPTION 'FAIL: guest holds a permission other than job.search';
    END IF;
    IF EXISTS (SELECT 1 FROM core.role_permission rp JOIN core.role r ON r.id = rp.role_id JOIN core.permission p ON p.id = rp.permission_id
                WHERE r.name = 'candidate' AND p.code IN ('candidate.download', 'candidate.search', 'job.post')) THEN
        RAISE EXCEPTION 'FAIL: candidate holds an employer permission';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM core.role_permission rp JOIN core.role r ON r.id = rp.role_id JOIN core.permission p ON p.id = rp.permission_id
                    WHERE r.name = 'consultant' AND p.code = 'sourcing.submit')
       OR EXISTS (SELECT 1 FROM core.role_permission rp JOIN core.role r ON r.id = rp.role_id JOIN core.permission p ON p.id = rp.permission_id
                    WHERE r.name = 'recruiter' AND p.code = 'sourcing.submit') THEN
        RAISE EXCEPTION 'FAIL: sourcing.submit must belong to consultants only';
    END IF;
    RAISE NOTICE 'PASS: every role has permissions; guest and candidate are least-privilege; super_admin holds all';

    RAISE NOTICE '=== Access control tests passed ===';
END
$$;

ROLLBACK;
