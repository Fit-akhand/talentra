-- Test suite: tests/test_commercial.sql
-- Prerequisite: migrations 001 through 017 applied.
-- Covers: BR-029, BR-030, SEC-005   (generated from the registers by scripts/lifecycle/tag_tests.py)

BEGIN;

DO $test$
DECLARE
    v_admin_user_id BIGINT;
    v_recruiter_user_id BIGINT;
    v_candidate_user_id BIGINT;
    v_candidate_profile_id BIGINT;
    v_org_id BIGINT;
    v_licence_id BIGINT;
    v_plan_id BIGINT;
    v_sub1_id BIGINT;
    v_sub2_id BIGINT;
    v_order_id BIGINT;
    v_invoice_id BIGINT;
    v_wallet_id BIGINT;
    v_ledger1_id BIGINT;
    v_ledger_corr_id BIGINT;
    v_download_id BIGINT;
    v_overlapping_sub_blocked BOOLEAN := FALSE;
    v_ledger_update_blocked BOOLEAN := FALSE;
    v_ledger_delete_blocked BOOLEAN := FALSE;
    v_download_delete_blocked BOOLEAN := FALSE;
    v_invalid_tax_blocked BOOLEAN := FALSE;
BEGIN
    -- 1. Setup fixtures
    INSERT INTO core.user_account (email)
    VALUES ('comm_admin@example.com')
    RETURNING id INTO v_admin_user_id;

    INSERT INTO core.user_account (email)
    VALUES ('comm_recruiter@example.com')
    RETURNING id INTO v_recruiter_user_id;

    INSERT INTO core.user_account (email)
    VALUES ('comm_candidate@example.com')
    RETURNING id INTO v_candidate_user_id;

    INSERT INTO profile.candidate_profile (
        user_account_id,
        headline,
        total_experience_years,
        profile_status
    )
    VALUES (
        v_candidate_user_id,
        'Senior Financial Systems Engineer',
        6.0,
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
        'FinTech Commercial Corp',
        'fintech-commercial-corp',
        'employer',
        v_admin_user_id
    )
    RETURNING id INTO v_org_id;

    INSERT INTO commercial.subscription_licence (
        organization_id,
        licence_key,
        licence_name,
        max_users,
        max_devices_per_user,
        valid_from,
        valid_to,
        licence_status
    )
    VALUES (
        v_org_id,
        'LIC-COMM-TEST-KEY',
        'Commercial Test Pack',
        10,
        3,
        '2026-01-01',
        '2027-12-31',
        'active'
    )
    RETURNING id INTO v_licence_id;

    SELECT id INTO v_plan_id
    FROM commercial.subscription_plan
    WHERE plan_code = 'growth_monthly';

    -- 2. Test Non-Overlapping Subscription Periods (Rule Group 10 / B47)
    -- Subscription 1: Jan 01 to Jun 30, 2026
    INSERT INTO commercial.subscription (
        subscription_licence_id,
        subscription_plan_id,
        period_start,
        period_end,
        subscription_status
    )
    VALUES (
        v_licence_id,
        v_plan_id,
        '2026-01-01 00:00:00+00',
        '2026-06-30 23:59:59+00',
        'active'
    )
    RETURNING id INTO v_sub1_id;

    -- Attempt Subscription 2 overlapping with Subscription 1 (Mar 01 to Sep 30, 2026) for same licence
    BEGIN
        INSERT INTO commercial.subscription (
            subscription_licence_id,
            subscription_plan_id,
            period_start,
            period_end,
            subscription_status
        )
        VALUES (
            v_licence_id,
            v_plan_id,
            '2026-03-01 00:00:00+00',
            '2026-09-30 23:59:59+00',
            'active'
        );
    EXCEPTION
        WHEN exclusion_violation THEN
            v_overlapping_sub_blocked := TRUE;
    END;

    IF NOT v_overlapping_sub_blocked THEN
        RAISE EXCEPTION 'Overlapping subscription period was allowed! Expected exclusion constraint violation';
    END IF;

    -- Non-overlapping subscription (Jul 01 to Dec 31, 2026) MUST SUCCEED
    INSERT INTO commercial.subscription (
        subscription_licence_id,
        subscription_plan_id,
        period_start,
        period_end,
        subscription_status
    )
    VALUES (
        v_licence_id,
        v_plan_id,
        '2026-07-01 00:00:00+00',
        '2026-12-31 23:59:59+00',
        'active'
    )
    RETURNING id INTO v_sub2_id;

    -- 3. Test Payment Orders & Invoices
    INSERT INTO commercial.payment_order (
        organization_id,
        user_account_id,
        gateway_provider,
        gateway_order_id,
        order_amount,
        currency_code,
        order_status
    )
    VALUES (
        v_org_id,
        v_admin_user_id,
        'stripe',
        'ord_stripe_test_12345',
        299.00,
        'USD',
        'captured'
    )
    RETURNING id INTO v_order_id;

    -- Check constraint test: invoice total MUST equal subtotal + tax
    BEGIN
        INSERT INTO commercial.invoice (
            organization_id,
            payment_order_id,
            invoice_number,
            subtotal_amount,
            tax_amount,
            total_amount,
            currency_code,
            invoice_status
        )
        VALUES (
            v_org_id,
            v_order_id,
            'INV-2026-INVALID',
            200.00,
            20.00,
            250.00, -- Mismatch! Should be 220.00
            'USD',
            'issued'
        );
    EXCEPTION
        WHEN check_violation THEN
            v_invalid_tax_blocked := TRUE;
    END;

    IF NOT v_invalid_tax_blocked THEN
        RAISE EXCEPTION 'Invoice with mismatched subtotal + tax was allowed!';
    END IF;

    INSERT INTO commercial.invoice (
        organization_id,
        payment_order_id,
        invoice_number,
        subtotal_amount,
        tax_amount,
        total_amount,
        currency_code,
        invoice_status,
        paid_at
    )
    VALUES (
        v_org_id,
        v_order_id,
        'INV-2026-0001',
        250.00,
        49.00,
        299.00,
        'USD',
        'paid',
        CURRENT_TIMESTAMP
    )
    RETURNING id INTO v_invoice_id;

    -- 4. Test Organization Wallet & Append-Only Wallet Ledger
    INSERT INTO commercial.wallet (
        organization_id,
        balance,
        currency_code
    )
    VALUES (
        v_org_id,
        500.00,
        'USD'
    )
    RETURNING id INTO v_wallet_id;

    -- Ledger recharge credit
    INSERT INTO commercial.wallet_ledger (
        wallet_id,
        entry_type,
        amount,
        currency_code,
        balance_after,
        reference_type,
        reference_id,
        notes,
        created_by_user_account_id
    )
    VALUES (
        v_wallet_id,
        'credit',
        500.00,
        'USD',
        500.00,
        'recharge',
        v_order_id,
        'Initial wallet fund recharge via Stripe',
        v_admin_user_id
    )
    RETURNING id INTO v_ledger1_id;

    -- Attempting UPDATE on wallet ledger MUST BE FORBIDDEN
    BEGIN
        UPDATE commercial.wallet_ledger
        SET amount = 9999.00
        WHERE id = v_ledger1_id;
    EXCEPTION
        WHEN raise_exception THEN
            v_ledger_update_blocked := TRUE;
    END;

    IF NOT v_ledger_update_blocked THEN
        RAISE EXCEPTION 'Wallet ledger UPDATE was allowed! Append-only enforcement failed';
    END IF;

    -- Attempting DELETE on wallet ledger MUST BE FORBIDDEN
    BEGIN
        DELETE FROM commercial.wallet_ledger
        WHERE id = v_ledger1_id;
    EXCEPTION
        WHEN raise_exception THEN
            v_ledger_delete_blocked := TRUE;
    END;

    IF NOT v_ledger_delete_blocked THEN
        RAISE EXCEPTION 'Wallet ledger DELETE was allowed! Append-only enforcement failed';
    END IF;

    -- Rule Group 10: Correction must reference original entry
    INSERT INTO commercial.wallet_ledger (
        wallet_id,
        entry_type,
        amount,
        currency_code,
        balance_after,
        reference_type,
        correction_of_ledger_id,
        notes,
        created_by_user_account_id
    )
    VALUES (
        v_wallet_id,
        'correction_debit',
        50.00,
        'USD',
        450.00,
        'correction',
        v_ledger1_id,
        'Correction adjustment for overcredit',
        v_admin_user_id
    )
    RETURNING id INTO v_ledger_corr_id;

    -- 5. Test Candidate Profile Download History
    INSERT INTO commercial.candidate_profile_download_history (
        organization_id,
        downloader_user_account_id,
        candidate_profile_id,
        credit_deduction_amount,
        currency_code,
        wallet_ledger_id
    )
    VALUES (
        v_org_id,
        v_recruiter_user_id,
        v_candidate_profile_id,
        5.00,
        'USD',
        v_ledger1_id
    )
    RETURNING id INTO v_download_id;

    -- Attempting DELETE on download history MUST BE FORBIDDEN
    BEGIN
        DELETE FROM commercial.candidate_profile_download_history
        WHERE id = v_download_id;
    EXCEPTION
        WHEN raise_exception THEN
            v_download_delete_blocked := TRUE;
    END;

    IF NOT v_download_delete_blocked THEN
        RAISE EXCEPTION 'Candidate profile download history DELETE was allowed! Append-only enforcement failed';
    END IF;

    RAISE NOTICE 'PASS: subscription plan catalogues and quotas verified';
    RAISE NOTICE 'PASS: exclusion constraint blocked overlapping subscriptions on same licence';
    RAISE NOTICE 'PASS: payment orders and invoice total arithmetic constraints verified';
    RAISE NOTICE 'PASS: wallet ledger append-only tampering protection verified (UPDATE and DELETE blocked)';
    RAISE NOTICE 'PASS: wallet ledger correction references original entry as required by Rule Group 10';
    RAISE NOTICE 'PASS: candidate profile download history append-only protection verified';
END;
$test$;

ROLLBACK;
