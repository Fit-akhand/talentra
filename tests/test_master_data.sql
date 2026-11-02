
-- Covers: BR-005, REQ-009   (generated from the registers by scripts/lifecycle/tag_tests.py)
BEGIN;

DO $$
DECLARE
    v_country_id BIGINT;
    v_state_id BIGINT;
    v_industry_id BIGINT;
    v_role_id BIGINT;
BEGIN
    INSERT INTO master.country (
        iso_alpha2, iso_alpha3, name, phone_calling_code
    )
    VALUES ('ZZ', 'ZZZ', 'Talentra Test Country', '+999')
    RETURNING id INTO v_country_id;

    INSERT INTO master.state (country_id, name, subdivision_code)
    VALUES (v_country_id, 'Talentra Test State', 'ZZ-01')
    RETURNING id INTO v_state_id;

    INSERT INTO master.city (state_id, name)
    VALUES (v_state_id, 'Talentra Test City');

    INSERT INTO master.skill (name, normalized_name)
    VALUES ('PostgreSQL Test Skill', 'postgresql test skill');

    INSERT INTO master.qualification (name, qualification_level)
    VALUES ('Test Bachelor Degree', 'undergraduate');

    INSERT INTO master.industry (name, normalized_name)
    VALUES ('Talentra Test Industry', 'talentra test industry')
    RETURNING id INTO v_industry_id;

    INSERT INTO master.job_role (
        industry_id, name, normalized_name
    )
    VALUES (
        v_industry_id, 'Test Database Engineer', 'test database engineer'
    )
    RETURNING id INTO v_role_id;

    INSERT INTO master.employment_type (code, name)
    VALUES ('test_contract', 'Test Contract');

    INSERT INTO master.work_type (code, name)
    VALUES ('test_remote', 'Test Remote');

    RAISE NOTICE 'PASS: valid reference records inserted';

    -- Duplicate country code must fail.
    BEGIN
        INSERT INTO master.country (iso_alpha2, iso_alpha3, name)
        VALUES ('ZZ', 'ZZY', 'Duplicate Test Country');

        RAISE EXCEPTION 'FAIL: duplicate country code was accepted';
    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE 'PASS: duplicate country code rejected';
    END;

    -- Invalid country code must fail.
    BEGIN
        INSERT INTO master.country (iso_alpha2, iso_alpha3, name)
        VALUES ('z1', 'ABC', 'Invalid Test Country');

        RAISE EXCEPTION 'FAIL: invalid country code was accepted';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'PASS: invalid country code rejected';
    END;

    -- A state cannot reference a nonexistent country.
    BEGIN
        INSERT INTO master.state (country_id, name)
        VALUES (-999999, 'Orphan Test State');

        RAISE EXCEPTION 'FAIL: orphan state was accepted';
    EXCEPTION
        WHEN foreign_key_violation THEN
            RAISE NOTICE 'PASS: invalid state country FK rejected';
    END;

    -- Duplicate canonical skill must fail.
    BEGIN
        INSERT INTO master.skill (name, normalized_name)
        VALUES ('PostgreSQL Another Label', 'postgresql test skill');

        RAISE EXCEPTION 'FAIL: duplicate skill was accepted';
    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE 'PASS: duplicate normalized skill rejected';
    END;

    -- Unsupported qualification level must fail.
    BEGIN
        INSERT INTO master.qualification (name, qualification_level)
        VALUES ('Invalid Test Degree', 'made_up_level');

        RAISE EXCEPTION 'FAIL: invalid qualification level was accepted';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'PASS: invalid qualification level rejected';
    END;

    -- Job role must reference a real industry when one is provided.
    BEGIN
        INSERT INTO master.job_role (
            industry_id, name, normalized_name
        )
        VALUES (-999999, 'Orphan Test Role', 'orphan test role');

        RAISE EXCEPTION 'FAIL: orphan job role was accepted';
    EXCEPTION
        WHEN foreign_key_violation THEN
            RAISE NOTICE 'PASS: invalid job role industry FK rejected';
    END;

    -- Same uncategorized normalized role must fail.
    INSERT INTO master.job_role (name, normalized_name)
    VALUES ('Test General Role', 'test general role');

    BEGIN
        INSERT INTO master.job_role (name, normalized_name)
        VALUES ('Test General Role Duplicate', 'test general role');

        RAISE EXCEPTION 'FAIL: duplicate uncategorized role was accepted';
    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE 'PASS: duplicate uncategorized role rejected';
    END;
END $$;

ROLLBACK;
