
-- Covers: BR-005, REQ-009   (generated from the registers by scripts/lifecycle/tag_tests.py)
DO $$
BEGIN
    -- Employment types
    IF NOT EXISTS (
        SELECT 1
        FROM master.employment_type
        WHERE code = 'full_time'
    ) THEN
        RAISE EXCEPTION 'FAIL: full_time employment type missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM master.employment_type
        WHERE code = 'internship'
    ) THEN
        RAISE EXCEPTION 'FAIL: internship employment type missing';
    END IF;

    RAISE NOTICE 'PASS: employment types seeded';

    -- Work types
    IF NOT EXISTS (
        SELECT 1
        FROM master.work_type
        WHERE code = 'remote'
    ) THEN
        RAISE EXCEPTION 'FAIL: remote work type missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM master.work_type
        WHERE code = 'hybrid'
    ) THEN
        RAISE EXCEPTION 'FAIL: hybrid work type missing';
    END IF;

    RAISE NOTICE 'PASS: work types seeded';

    -- Qualification categories
    IF NOT EXISTS (
        SELECT 1
        FROM master.qualification
        WHERE name = 'Undergraduate'
          AND qualification_level = 'undergraduate'
    ) THEN
        RAISE EXCEPTION 'FAIL: undergraduate qualification missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM master.qualification
        WHERE name = 'Doctorate'
          AND qualification_level = 'doctorate'
    ) THEN
        RAISE EXCEPTION 'FAIL: doctorate qualification missing';
    END IF;

    RAISE NOTICE 'PASS: qualification categories seeded';

    -- Industries
    IF NOT EXISTS (
        SELECT 1
        FROM master.industry
        WHERE normalized_name = 'information technology'
    ) THEN
        RAISE EXCEPTION 'FAIL: information technology industry missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM master.industry
        WHERE normalized_name = 'healthcare'
    ) THEN
        RAISE EXCEPTION 'FAIL: healthcare industry missing';
    END IF;

    RAISE NOTICE 'PASS: industries seeded';

    -- Skills
    IF NOT EXISTS (
        SELECT 1
        FROM master.skill
        WHERE normalized_name = 'postgresql'
    ) THEN
        RAISE EXCEPTION 'FAIL: PostgreSQL skill missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM master.skill
        WHERE normalized_name = 'javascript'
    ) THEN
        RAISE EXCEPTION 'FAIL: JavaScript skill missing';
    END IF;

    RAISE NOTICE 'PASS: skills seeded';
END
$$;
