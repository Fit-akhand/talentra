-- Test suite: tests/test_identifier_encryption.sql
-- Covers: BR-037, SEC-006, SEC-012 (docket Rule Group 6: sensitive data protected), docs/phase-2-model/12-tax-id-security-design.md section 7.1; migration 034
-- Isolation: runs in a transaction that is rolled back. Application-side behaviour (canonicalisation, AEAD) is tested by tests/test_identifier_crypto.py.

BEGIN;

DO $$
DECLARE
    v_org BIGINT; v_country BIGINT; v_other_org BIGINT; v_id BIGINT; v_caught BOOLEAN; v_user BIGINT;
BEGIN
    -- 1. no plaintext column survives
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'recruitment' AND table_name = 'organization_identifier' AND column_name = 'identifier_value') THEN
        RAISE EXCEPTION 'FAIL: the plaintext identifier column still exists';
    END IF;
    RAISE NOTICE 'PASS: no plaintext identifier column';

    SELECT id INTO v_country FROM master.country ORDER BY id LIMIT 1;
    SELECT id INTO v_user FROM core.user_account ORDER BY id LIMIT 1;
    INSERT INTO recruitment.organization (name, slug, organization_type, created_by_user_account_id) VALUES ('Enc Test A', 'enc-test-a-9', 'employer', v_user) RETURNING id INTO v_org;
    INSERT INTO recruitment.organization (name, slug, organization_type, created_by_user_account_id) VALUES ('Enc Test B', 'enc-test-b-9', 'employer', v_user) RETURNING id INTO v_other_org;

    INSERT INTO recruitment.organization_identifier (organization_id, country_id, identifier_type, identifier_ciphertext, identifier_bidx)
    VALUES (v_org, v_country, 'pan', decode(repeat('cd', 40), 'hex'), sha256('bidx-a')) RETURNING id INTO v_id;

    -- 2. the same identifier cannot be registered twice (uniqueness lives on the blind index)
    v_caught := FALSE;
    BEGIN
        INSERT INTO recruitment.organization_identifier (organization_id, country_id, identifier_type, identifier_ciphertext, identifier_bidx)
        VALUES (v_other_org, v_country, 'pan', decode(repeat('ef', 40), 'hex'), sha256('bidx-a'));
    EXCEPTION WHEN unique_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: a duplicate blind index was accepted'; END IF;
    RAISE NOTICE 'PASS: duplicate identifier rejected through the blind index';

    -- 3. malformed protected values are refused
    v_caught := FALSE;
    BEGIN
        INSERT INTO recruitment.organization_identifier (organization_id, country_id, identifier_type, identifier_ciphertext, identifier_bidx)
        VALUES (v_other_org, v_country, 'vat', decode('abcd', 'hex'), sha256('x'));
    EXCEPTION WHEN check_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: a too-short ciphertext (plaintext in disguise) was accepted'; END IF;
    v_caught := FALSE;
    BEGIN
        INSERT INTO recruitment.organization_identifier (organization_id, country_id, identifier_type, identifier_ciphertext, identifier_bidx)
        VALUES (v_other_org, v_country, 'vat', decode(repeat('ab', 40), 'hex'), decode('00ff', 'hex'));
    EXCEPTION WHEN check_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: a truncated blind index was accepted'; END IF;
    RAISE NOTICE 'PASS: malformed ciphertext and blind index refused';

    -- 4. the context the ciphertext is bound to cannot be changed without re-encrypting
    v_caught := FALSE;
    BEGIN
        UPDATE recruitment.organization_identifier SET organization_id = v_other_org WHERE id = v_id;
    EXCEPTION WHEN check_violation THEN v_caught := TRUE; END;
    IF NOT v_caught THEN RAISE EXCEPTION 'FAIL: moving a ciphertext to another organisation was accepted'; END IF;
    UPDATE recruitment.organization_identifier SET organization_id = v_other_org, identifier_ciphertext = decode(repeat('12', 40), 'hex'), identifier_bidx = sha256('bidx-b') WHERE id = v_id;
    RAISE NOTICE 'PASS: rebinding is allowed only together with a new ciphertext';

    -- 5. the protected columns are classified as encrypted, and nothing sensitive is left as an open risk
    IF (SELECT count(*) FROM audit.column_classification WHERE schema_name = 'recruitment' AND table_name = 'organization_identifier'
           AND column_name IN ('identifier_ciphertext', 'identifier_bidx') AND data_class = 'sensitive' AND protection = 'encrypted') <> 2 THEN
        RAISE EXCEPTION 'FAIL: ciphertext and blind index are not classified sensitive / encrypted';
    END IF;
    RAISE NOTICE 'PASS: classification records the protection';
END $$;

ROLLBACK;
