-- Test suite: tests/test_organization_extensions.sql
-- Prerequisite: migrations 001 through 013 applied.

BEGIN;

DO $test$
DECLARE
    v_user_id BIGINT;
    v_verifier_id BIGINT;
    v_parent_org_id BIGINT;
    v_child_org_id BIGINT;
    v_agency_org_id BIGINT;
    v_country_id BIGINT;
    v_city_id BIGINT;
    v_loc1_id BIGINT;
    v_loc2_id BIGINT;
    v_ident_id BIGINT;
    v_hier_id BIGINT;
    v_map_id BIGINT;
    v_duplicate_hq_blocked BOOLEAN := FALSE;
    v_invalid_verification_blocked BOOLEAN := FALSE;
    v_self_hierarchy_blocked BOOLEAN := FALSE;
    v_invalid_mapping_dates_blocked BOOLEAN := FALSE;
BEGIN
    -- 1. Setup fixtures
    INSERT INTO core.user_account (email)
    VALUES ('org_ext_user@example.com')
    RETURNING id INTO v_user_id;

    INSERT INTO core.user_account (email)
    VALUES ('org_verifier@example.com')
    RETURNING id INTO v_verifier_id;

    -- Country & city fixtures
    SELECT id INTO v_country_id FROM master.country WHERE iso_alpha2 = 'IN';
    IF v_country_id IS NULL THEN
        INSERT INTO master.country (iso_alpha2, iso_alpha3, name, phone_calling_code)
        VALUES ('IN', 'IND', 'India', '+91')
        RETURNING id INTO v_country_id;
    END IF;

    SELECT id INTO v_city_id FROM master.city LIMIT 1;
    IF v_city_id IS NULL THEN
        -- Create state and city if not present
        INSERT INTO master.state (country_id, name, subdivision_code)
        VALUES (v_country_id, 'Karnataka', 'KA')
        RETURNING id INTO v_city_id;

        INSERT INTO master.city (state_id, name)
        VALUES (v_city_id, 'Bengaluru')
        RETURNING id INTO v_city_id;
    END IF;

    INSERT INTO recruitment.organization (
        name,
        slug,
        organization_type,
        created_by_user_account_id
    )
    VALUES (
        'Parent Global Holding Corp',
        'parent-global-holding-corp',
        'employer',
        v_user_id
    )
    RETURNING id INTO v_parent_org_id;

    INSERT INTO recruitment.organization (
        name,
        slug,
        organization_type,
        created_by_user_account_id
    )
    VALUES (
        'Child Tech Subsidiary Ltd',
        'child-tech-subsidiary-ltd',
        'employer',
        v_user_id
    )
    RETURNING id INTO v_child_org_id;

    INSERT INTO recruitment.organization (
        name,
        slug,
        organization_type,
        created_by_user_account_id
    )
    VALUES (
        'Staffing Partner Agency',
        'staffing-partner-agency',
        'recruitment_agency',
        v_user_id
    )
    RETURNING id INTO v_agency_org_id;

    -- 2. Test Locations & Single Headquarters Rule
    INSERT INTO recruitment.organization_location (
        organization_id,
        city_id,
        location_name,
        address_line1,
        postal_code,
        is_headquarters,
        latitude,
        longitude
    )
    VALUES (
        v_parent_org_id,
        v_city_id,
        'Global HQ',
        '100 Tech Park, Whitefield',
        '560066',
        TRUE,
        12.9698,
        77.7499
    )
    RETURNING id INTO v_loc1_id;

    -- Second headquarters for same organization must be blocked
    BEGIN
        INSERT INTO recruitment.organization_location (
            organization_id,
            city_id,
            location_name,
            address_line1,
            postal_code,
            is_headquarters
        )
        VALUES (
            v_parent_org_id,
            v_city_id,
            'Secondary HQ',
            '200 Outer Ring Road',
            '560103',
            TRUE
        );
    EXCEPTION
        WHEN unique_violation THEN
            v_duplicate_hq_blocked := TRUE;
    END;

    IF NOT v_duplicate_hq_blocked THEN
        RAISE EXCEPTION 'Multiple headquarters allowed for same organization!';
    END IF;

    -- Branch location allowed
    INSERT INTO recruitment.organization_location (
        organization_id,
        city_id,
        location_name,
        address_line1,
        postal_code,
        is_headquarters
    )
    VALUES (
        v_parent_org_id,
        v_city_id,
        'Engineering Branch Office',
        '300 Indiranagar 100ft Rd',
        '560038',
        FALSE
    )
    RETURNING id INTO v_loc2_id;

    -- 3. Test Organization Identifiers & Verification Constraint
    -- Inconsistent verified state must be rejected
    BEGIN
        INSERT INTO recruitment.organization_identifier (
            organization_id,
            country_id,
            identifier_type,
            identifier_value,
            verification_status,
            verified_at
        )
        VALUES (
            v_parent_org_id,
            v_country_id,
            'gstin',
            '29AAAAA0000A1Z5',
            'verified',
            NULL -- Must fail: verified status requires verified_at timestamp
        );
    EXCEPTION
        WHEN check_violation THEN
            v_invalid_verification_blocked := TRUE;
    END;

    IF NOT v_invalid_verification_blocked THEN
        RAISE EXCEPTION 'Verified identifier without verified_at was accepted';
    END IF;

    -- Valid identifier insertion
    INSERT INTO recruitment.organization_identifier (
        organization_id,
        country_id,
        identifier_type,
        identifier_value,
        verification_status,
        verified_at,
        verified_by_user_account_id
    )
    VALUES (
        v_parent_org_id,
        v_country_id,
        'gstin',
        '29AAAAA0000A1Z5',
        'verified',
        CURRENT_TIMESTAMP,
        v_verifier_id
    )
    RETURNING id INTO v_ident_id;

    -- 4. Test Organization Hierarchy
    -- Self-hierarchy must be blocked
    BEGIN
        INSERT INTO recruitment.organization_hierarchy (
            parent_organization_id,
            child_organization_id,
            relationship_type
        )
        VALUES (
            v_parent_org_id,
            v_parent_org_id,
            'subsidiary'
        );
    EXCEPTION
        WHEN check_violation THEN
            v_self_hierarchy_blocked := TRUE;
    END;

    IF NOT v_self_hierarchy_blocked THEN
        RAISE EXCEPTION 'Self organization hierarchy was allowed';
    END IF;

    INSERT INTO recruitment.organization_hierarchy (
        parent_organization_id,
        child_organization_id,
        relationship_type
    )
    VALUES (
        v_parent_org_id,
        v_child_org_id,
        'subsidiary'
    )
    RETURNING id INTO v_hier_id;

    -- 5. Test Effective-Dated Recruiter Mapping
    -- Invalid date range must be blocked
    BEGIN
        INSERT INTO recruitment.recruiter_client_mapping (
            recruiter_user_account_id,
            agency_organization_id,
            client_organization_id,
            effective_from,
            effective_to
        )
        VALUES (
            v_user_id,
            v_agency_org_id,
            v_child_org_id,
            '2026-12-31',
            '2026-01-01'
        );
    EXCEPTION
        WHEN check_violation THEN
            v_invalid_mapping_dates_blocked := TRUE;
    END;

    IF NOT v_invalid_mapping_dates_blocked THEN
        RAISE EXCEPTION 'Recruiter mapping with effective_to earlier than effective_from was accepted';
    END IF;

    -- Valid mapping insertion
    INSERT INTO recruitment.recruiter_client_mapping (
        recruiter_user_account_id,
        agency_organization_id,
        client_organization_id,
        effective_from,
        effective_to
    )
    VALUES (
        v_user_id,
        v_agency_org_id,
        v_child_org_id,
        '2026-01-01',
        '2026-12-31'
    )
    RETURNING id INTO v_map_id;

    RAISE NOTICE 'PASS: single headquarters constraint verified';
    RAISE NOTICE 'PASS: branch locations and coordinates verified';
    RAISE NOTICE 'PASS: tax identifier verification constraints verified';
    RAISE NOTICE 'PASS: organization hierarchy parent-child constraints verified';
    RAISE NOTICE 'PASS: effective-dated recruiter mapping constraints verified';
END;
$test$;

ROLLBACK;
