-- Test suite: tests/test_wallet_functions.sql
-- Covers: WF-14 (profile download and credit consumption), NFR-012, Rule Group 10, migration 036, DEC-29
-- Isolation: runs in a transaction that is rolled back. Fixture ids come from rows created here.

BEGIN;

DO $$
DECLARE
    v_admin BIGINT; v_rec BIGINT; v_cand_user BIGINT; v_org BIGINT; v_wallet BIGINT; v_inr_wallet BIGINT;
    v_cand_pub BIGINT; v_cand_priv BIGINT; v_ledger BIGINT; v_hist BIGINT; v_hist2 BIGINT;
    v_n INTEGER; v_bal NUMERIC; v_caught BOOLEAN;
BEGIN
    SELECT id INTO v_admin FROM core.user_account ORDER BY id LIMIT 1;
    INSERT INTO core.user_account (email, account_status) VALUES ('wf14_rec@example.com', 'active') RETURNING id INTO v_rec;
    INSERT INTO core.user_account (email, account_status) VALUES ('wf14_cand@example.com', 'active') RETURNING id INTO v_cand_user;
    INSERT INTO recruitment.organization (name, slug, organization_type, created_by_user_account_id) VALUES ('WF14 Org', 'wf14-org', 'employer', v_admin) RETURNING id INTO v_org;
    INSERT INTO recruitment.organization_member (organization_id, user_account_id, organization_role, membership_status, joined_at) VALUES (v_org, v_rec, 'recruiter', 'active', now());
    INSERT INTO commercial.wallet (organization_id, balance, currency_code) VALUES (v_org, 5.00, 'USD') RETURNING id INTO v_wallet;
    INSERT INTO profile.candidate_profile (user_account_id, visibility) VALUES (v_cand_user, 'public') RETURNING id INTO v_cand_pub;
    INSERT INTO core.user_account (email, account_status) VALUES ('wf14_cand2@example.com', 'active') RETURNING id INTO v_n;
    INSERT INTO profile.candidate_profile (user_account_id, visibility) VALUES (v_n, 'private') RETURNING id INTO v_cand_priv;

    EXECUTE 'SET LOCAL ROLE talentra_app';
    PERFORM set_config('app.current_user_id', v_rec::TEXT, true);
    PERFORM set_config('app.current_org_id', v_org::TEXT, true);

    -- 1. a credit raises the balance and leaves one ledger row whose balance_after matches
    v_ledger := commercial.post_wallet_entry(v_wallet, 'credit', 10.00, 'recharge');
    SELECT balance INTO v_bal FROM commercial.wallet WHERE id = v_wallet;
    IF v_bal <> 15.00 THEN RAISE EXCEPTION 'FAIL: credit of 10 on 5 gave %', v_bal; END IF;
    IF (SELECT balance_after FROM commercial.wallet_ledger WHERE id = v_ledger) <> 15.00 THEN RAISE EXCEPTION 'FAIL: balance_after does not match the wallet'; END IF;
    RAISE NOTICE 'PASS: a credit moves the balance and the ledger together';

    -- 2. an overdraft is refused and leaves nothing behind
    SELECT count(*) INTO v_n FROM commercial.wallet_ledger WHERE wallet_id = v_wallet;
    v_caught := FALSE;
    BEGIN PERFORM commercial.post_wallet_entry(v_wallet, 'debit', 15.01, 'profile_download', 1);
    EXCEPTION WHEN check_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: an overdraft was accepted'; END IF;
    IF (SELECT count(*) FROM commercial.wallet_ledger WHERE wallet_id = v_wallet) <> v_n THEN RAISE EXCEPTION 'FAIL: a refused debit left a ledger row'; END IF;
    RAISE NOTICE 'PASS: an overdraft is refused and writes nothing';

    -- 3. the application role cannot write the wallet or the ledger directly, only through the function
    v_caught := FALSE;
    BEGIN UPDATE commercial.wallet SET balance = 1000 WHERE id = v_wallet; EXCEPTION WHEN insufficient_privilege THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: the application role updated a wallet balance directly'; END IF;
    v_caught := FALSE;
    BEGIN INSERT INTO commercial.wallet_ledger (wallet_id, entry_type, amount, balance_after, reference_type, created_by_user_account_id) VALUES (v_wallet, 'credit', 1, 16, 'recharge', v_rec);
    EXCEPTION WHEN insufficient_privilege THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: the application role inserted a ledger row directly'; END IF;
    RAISE NOTICE 'PASS: money moves only through post_wallet_entry';

    -- 4. another organisation's wallet cannot be moved
    PERFORM set_config('app.current_org_id', (v_org + 1000000)::TEXT, true);
    v_caught := FALSE;
    BEGIN PERFORM commercial.post_wallet_entry(v_wallet, 'credit', 1.00, 'recharge'); EXCEPTION WHEN insufficient_privilege THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: a wallet of another organisation was moved'; END IF;
    PERFORM set_config('app.current_org_id', v_org::TEXT, true);
    RAISE NOTICE 'PASS: wallets are tenant-isolated';

    -- 5. a download of a visible profile charges the listed price and records the ledger link
    v_hist := commercial.download_candidate_profile(v_cand_pub);
    SELECT balance INTO v_bal FROM commercial.wallet WHERE id = v_wallet;
    IF v_bal <> 13.00 THEN RAISE EXCEPTION 'FAIL: a 2.00 download left %', v_bal; END IF;
    IF (SELECT (credit_deduction_amount, wallet_ledger_id IS NOT NULL) FROM commercial.candidate_profile_download_history WHERE id = v_hist) IS DISTINCT FROM ROW(2.00::NUMERIC, TRUE) THEN
        RAISE EXCEPTION 'FAIL: download history does not record the charge and the ledger entry';
    END IF;
    RAISE NOTICE 'PASS: a download debits the price and records it';

    -- 6. the same organisation downloading the same profile again is recorded but not charged
    v_hist2 := commercial.download_candidate_profile(v_cand_pub);
    SELECT balance INTO v_bal FROM commercial.wallet WHERE id = v_wallet;
    IF v_bal <> 13.00 OR v_hist2 = v_hist THEN RAISE EXCEPTION 'FAIL: a repeat download was charged or not recorded (balance %)', v_bal; END IF;
    RAISE NOTICE 'PASS: a repeat download is free and recorded';

    -- 7. a private profile cannot be downloaded
    v_caught := FALSE;
    BEGIN PERFORM commercial.download_candidate_profile(v_cand_priv); EXCEPTION WHEN insufficient_privilege THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: a private profile was downloaded'; END IF;
    RAISE NOTICE 'PASS: invisible profiles are refused';

    -- 8. insufficient balance refuses the download and charges nothing
    EXECUTE 'RESET ROLE';
    UPDATE commercial.wallet SET balance = 1.00 WHERE id = v_wallet;
    EXECUTE 'SET LOCAL ROLE talentra_app';
    SELECT id INTO v_n FROM profile.candidate_profile WHERE visibility = 'public' AND id <> v_cand_pub AND id NOT IN (SELECT candidate_profile_id FROM commercial.candidate_profile_download_history WHERE organization_id = v_org) ORDER BY id LIMIT 1;
    v_caught := FALSE;
    BEGIN PERFORM commercial.download_candidate_profile(v_n); EXCEPTION WHEN check_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: a download with 1.00 credit was accepted at a 2.00 price'; END IF;
    SELECT balance INTO v_bal FROM commercial.wallet WHERE id = v_wallet;
    IF v_bal <> 1.00 THEN RAISE EXCEPTION 'FAIL: a refused download changed the balance to %', v_bal; END IF;
    RAISE NOTICE 'PASS: a download without enough credit is refused and free';

    EXECUTE 'RESET ROLE';
END $$;

ROLLBACK;
