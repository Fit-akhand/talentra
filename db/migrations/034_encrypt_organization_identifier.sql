-- 034: registration and tax identifiers are stored encrypted (docket Rule Group 6; docs/phase-2-model/12-tax-id-security-design.md).
--
-- Design chosen (Delegated decision DEC-25, 2026-10-28; see docs/lifecycle/decision-log.md): the application encrypts with AES-256-GCM
-- and computes an HMAC-SHA-256 blind index over the canonical identifier; the database holds neither plaintext nor key.
-- Reference implementation: scripts/identifier_crypto.py. Uniqueness moves from the plaintext to the blind index.
--
-- Point of no return: the plaintext column is dropped. The migration refuses to run if any row exists, because the database
-- cannot encrypt (it has no key). A deployment that already holds identifiers follows the staged procedure in design section 6:
-- add the columns, encrypt each row with scripts/identifier_crypto.py encrypt(), verify, then drop the plaintext.

BEGIN;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM recruitment.organization_identifier) THEN
        RAISE EXCEPTION 'organization_identifier holds rows in clear text; follow the staged procedure in docs/phase-2-model/12-tax-id-security-design.md section 6 instead of this migration';
    END IF;
END $$;

ALTER TABLE recruitment.organization_identifier DROP CONSTRAINT uq_organization_identifier_val;
ALTER TABLE recruitment.organization_identifier DROP COLUMN identifier_value;

ALTER TABLE recruitment.organization_identifier
    ADD COLUMN identifier_ciphertext BYTEA NOT NULL,
    ADD COLUMN identifier_bidx BYTEA NOT NULL,
    ADD COLUMN identifier_key_version SMALLINT NOT NULL DEFAULT 1,
    ADD CONSTRAINT ck_organization_identifier_ciphertext CHECK (length(identifier_ciphertext) >= 29),   -- 12-byte nonce + 16-byte tag + at least 1 byte
    ADD CONSTRAINT ck_organization_identifier_bidx CHECK (length(identifier_bidx) = 32),                 -- full HMAC-SHA-256
    ADD CONSTRAINT ck_organization_identifier_key_version CHECK (identifier_key_version > 0),
    ADD CONSTRAINT uq_organization_identifier_bidx UNIQUE (country_id, identifier_type, identifier_bidx);

COMMENT ON COLUMN recruitment.organization_identifier.identifier_ciphertext IS
    'AES-256-GCM output: 12-byte random nonce, ciphertext, 16-byte tag. Sensitive. The key is never in the database. Bound by AAD to organization_id, country_id, identifier_type and key version, so a copy into another row fails to decrypt.';
COMMENT ON COLUMN recruitment.organization_identifier.identifier_bidx IS
    'HMAC-SHA-256 (32 bytes) of the canonical identifier under a key separate from the encryption key. Makes the identifier unique and findable by exact value without revealing it. Sensitive in the sense that it leaks equality within one country and type.';
COMMENT ON COLUMN recruitment.organization_identifier.identifier_key_version IS
    'Version of the key pair that produced the ciphertext and the blind index; lets keys be rotated row by row. Always set.';

-- the context the ciphertext is bound to must not drift
CREATE FUNCTION recruitment.protect_identifier_binding()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF (NEW.organization_id, NEW.country_id, NEW.identifier_type) IS DISTINCT FROM (OLD.organization_id, OLD.country_id, OLD.identifier_type)
       AND NEW.identifier_ciphertext IS NOT DISTINCT FROM OLD.identifier_ciphertext THEN
        RAISE EXCEPTION 'organization, country and type are bound into the ciphertext; re-encrypt the identifier to change them'
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION recruitment.protect_identifier_binding() IS 'Changing organisation, country or type without re-encrypting would leave a ciphertext that no longer decrypts.';

CREATE TRIGGER trg_organization_identifier_binding
    BEFORE UPDATE ON recruitment.organization_identifier
    FOR EACH ROW EXECUTE FUNCTION recruitment.protect_identifier_binding();

-- classification: the sensitive value is now protected by encryption instead of being an open risk
ALTER TABLE audit.column_classification DROP CONSTRAINT ck_column_classification_protection;
ALTER TABLE audit.column_classification ADD CONSTRAINT ck_column_classification_protection
    CHECK (protection IN ('none', 'grants_only', 'rls', 'masked_view', 'hashed', 'external_reference', 'encrypted', 'open_risk'));

DELETE FROM audit.column_classification WHERE (schema_name, table_name, column_name) = ('recruitment', 'organization_identifier', 'identifier_value');
SELECT audit.sync_column_classification();
UPDATE audit.column_classification SET data_class = 'sensitive', protection = 'encrypted', basis = 'reviewed',
       note = 'Encrypted by the application (AES-256-GCM); the database holds no key. Design: docs/phase-2-model/12-tax-id-security-design.md.'
 WHERE (schema_name, table_name) = ('recruitment', 'organization_identifier') AND column_name IN ('identifier_ciphertext', 'identifier_bidx');
UPDATE audit.column_classification SET data_class = 'internal', protection = 'grants_only', basis = 'reviewed'
 WHERE (schema_name, table_name, column_name) = ('recruitment', 'organization_identifier', 'identifier_key_version');
SELECT audit.refresh_protection();
SELECT audit.refresh_active_views();

COMMIT;
