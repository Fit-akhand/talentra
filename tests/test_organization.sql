
-- Covers: BR-011, REQ-015   (generated from the registers by scripts/lifecycle/tag_tests.py)
BEGIN;

DO $$
DECLARE
    v_user_id BIGINT;
    v_second_user_id BIGINT;
    v_organization_id BIGINT;
BEGIN
    INSERT INTO core.user_account (email)
    VALUES ('migration007-owner@example.invalid')
    RETURNING id INTO v_user_id;

    INSERT INTO core.user_account (email)
    VALUES ('migration007-member@example.invalid')
    RETURNING id INTO v_second_user_id;

    INSERT INTO recruitment.organization (
        name,
        slug,
        organization_type,
        organization_status,
        created_by_user_account_id
    )
    VALUES (
        'Migration Test Organization',
        'migration-test-organization',
        'employer',
        'active',
        v_user_id
    )
    RETURNING id INTO v_organization_id;

    INSERT INTO recruitment.organization_member (
        organization_id,
        user_account_id,
        organization_role,
        membership_status,
        invited_by_user_account_id,
        joined_at
    )
    VALUES (
        v_organization_id,
        v_user_id,
        'owner',
        'active',
        v_user_id,
        CURRENT_TIMESTAMP
    );

    RAISE NOTICE 'PASS: organization and active owner membership created';

    -- One organization slug cannot be reused.
    BEGIN
        INSERT INTO recruitment.organization (
            name, slug, created_by_user_account_id
        )
        VALUES (
            'Duplicate Slug Organization',
            'migration-test-organization',
            v_user_id
        );

        RAISE EXCEPTION 'FAIL: duplicate organization slug accepted';
    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE 'PASS: duplicate organization slug rejected';
    END;

    -- Invalid URL slug must fail.
    BEGIN
        INSERT INTO recruitment.organization (
            name, slug, created_by_user_account_id
        )
        VALUES (
            'Invalid Slug Organization',
            'Invalid Slug!',
            v_user_id
        );

        RAISE EXCEPTION 'FAIL: invalid organization slug accepted';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'PASS: invalid organization slug rejected';
    END;

    -- Duplicate organization membership must fail.
    BEGIN
        INSERT INTO recruitment.organization_member (
            organization_id, user_account_id, organization_role
        )
        VALUES (
            v_organization_id, v_user_id, 'admin'
        );

        RAISE EXCEPTION 'FAIL: duplicate organization membership accepted';
    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE 'PASS: duplicate organization membership rejected';
    END;

    -- An active membership must include joined_at.
    BEGIN
        INSERT INTO recruitment.organization_member (
            organization_id,
            user_account_id,
            organization_role,
            membership_status
        )
        VALUES (
            v_organization_id,
            v_second_user_id,
            'recruiter',
            'active'
        );

        RAISE EXCEPTION 'FAIL: active membership without joined_at accepted';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'PASS: active membership requires joined_at';
    END;

    -- A removed membership must include removed_at.
    BEGIN
        INSERT INTO recruitment.organization_member (
            organization_id,
            user_account_id,
            organization_role,
            membership_status
        )
        VALUES (
            v_organization_id,
            v_second_user_id,
            'recruiter',
            'removed'
        );

        RAISE EXCEPTION 'FAIL: removed membership without removed_at accepted';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'PASS: removed membership requires removed_at';
    END;

    -- A nonexistent user cannot own an organization.
    BEGIN
        INSERT INTO recruitment.organization (
            name, slug, created_by_user_account_id
        )
        VALUES (
            'Orphan Organization',
            'orphan-organization',
            -999999
        );

        RAISE EXCEPTION 'FAIL: orphan organization creator accepted';
    EXCEPTION
        WHEN foreign_key_violation THEN
            RAISE NOTICE 'PASS: invalid organization creator rejected';
    END;

    -- An unsupported membership role must fail.
    BEGIN
        INSERT INTO recruitment.organization_member (
            organization_id,
            user_account_id,
            organization_role
        )
        VALUES (
            v_organization_id,
            v_second_user_id,
            'superuser'
        );

        RAISE EXCEPTION 'FAIL: invalid organization role accepted';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'PASS: invalid organization role rejected';
    END;

    RAISE NOTICE 'PASS: organization constraint suite completed';
END
$$;

ROLLBACK;
