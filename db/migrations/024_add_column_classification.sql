-- =============================================================================
-- Migration 024: Column classification (docket Rule Group 6: Public / Internal / Personal / Sensitive)
-- Domain:        cross-cutting security metadata
-- Depends on:    001-023
--
-- Every column of every base table is classified, and says how it is protected. The classification is
-- data, so it can be queried and tested: tests/test_classification.sql fails when a column is added
-- without one, and when a Sensitive column has no protection.
--
-- Classes (docket):
--   public      may be shown without restriction
--   internal    staff and the owning organisation
--   personal    identifies a person: access control and audit
--   sensitive   national/tax identifiers, bank or payment references, credentials: encryption,
--               tokenisation or masking
--
-- Protection (what is actually in place today, not what is planned):
--   none                  nothing beyond schema grants
--   grants_only           reachable only by roles that hold a table grant
--   rls                   row-level security restricts rows to the owner/tenant (migration 021)
--   masked_view           staff see it only through a masking view (core.support_user_account)
--   hashed                stored only as a one-way hash
--   external_reference    an opaque reference to a record held by another system; no usable value
--   open_risk             Sensitive and NOT protected. Each row is a known risk and is listed in
--                         docs/phase-2-model/12-threat-model.md.
--
-- Rows are first written by name patterns (basis = 'pattern'). A person confirms a row by setting
-- basis = 'reviewed'; the pattern rules are a starting point, not a verdict.
-- =============================================================================

BEGIN;

CREATE TABLE audit.column_classification (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    schema_name     VARCHAR(63) NOT NULL,
    table_name      VARCHAR(63) NOT NULL,
    column_name     VARCHAR(63) NOT NULL,
    data_class      VARCHAR(10) NOT NULL,
    protection      VARCHAR(20) NOT NULL,
    basis           VARCHAR(10) NOT NULL DEFAULT 'pattern',
    note            VARCHAR(300),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by_user_account_id BIGINT,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by_user_account_id BIGINT,

    CONSTRAINT uq_column_classification_column UNIQUE (schema_name, table_name, column_name),
    CONSTRAINT ck_column_classification_class CHECK (data_class IN ('public', 'internal', 'personal', 'sensitive')),
    CONSTRAINT ck_column_classification_protection
        CHECK (protection IN ('none', 'grants_only', 'rls', 'masked_view', 'hashed', 'external_reference', 'open_risk')),
    CONSTRAINT ck_column_classification_basis CHECK (basis IN ('pattern', 'reviewed')),
    -- a Sensitive column must either be protected or be recorded as an open risk; 'none' is not an answer
    CONSTRAINT ck_column_classification_sensitive_protected
        CHECK (data_class <> 'sensitive' OR protection <> 'none'),
    CONSTRAINT fk_column_classification_created_by FOREIGN KEY (created_by_user_account_id)
        REFERENCES core.user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_column_classification_updated_by FOREIGN KEY (updated_by_user_account_id)
        REFERENCES core.user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT
);
COMMENT ON TABLE audit.column_classification IS 'Docket Rule Group 6: class and protection of every column. Completeness is asserted by tests/test_classification.sql.';
COMMENT ON COLUMN audit.column_classification.note IS 'Nullable: only rows that need an explanation carry one.';

-- -----------------------------------------------------------------------------
-- Classify every column that has no row yet. Call it at the end of any migration that adds columns.
-- -----------------------------------------------------------------------------
CREATE FUNCTION audit.sync_column_classification()
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_added INTEGER;
BEGIN
    INSERT INTO audit.column_classification (schema_name, table_name, column_name, data_class, protection, note)
    SELECT c.table_schema, c.table_name, c.column_name,
           cls.data_class,
           CASE
             WHEN cls.data_class = 'sensitive' AND c.column_name ~ '(secret_hash|token_hash|password_hash)$'      THEN 'hashed'
             WHEN cls.data_class = 'sensitive' AND c.column_name ~ '(gateway_order_id|gateway_refund_ref|external_provider_message_id|certificate_reference)$' THEN 'external_reference'
             WHEN cls.data_class = 'sensitive'                                                                    THEN 'open_risk'
             WHEN cls.data_class IN ('personal', 'internal') AND EXISTS (SELECT 1 FROM pg_class pc
                                                           WHERE pc.relname = c.table_name AND pc.relnamespace = c.table_schema::regnamespace
                                                             AND pc.relrowsecurity)                                THEN 'rls'
             WHEN cls.data_class = 'personal'                                                                     THEN 'grants_only'
             ELSE 'grants_only'
           END,
           CASE
             WHEN c.table_schema = 'core' AND c.table_name = 'user_account' AND cls.data_class = 'personal'
               THEN 'Raw table is readable by the application role (users look each other up). Staff use core.support_user_account, which masks it. No row-level security yet.'
             WHEN cls.data_class = 'sensitive' AND c.column_name ~ 'identifier_value'
               THEN 'Tax/registration identifier stored in clear text. Encryption design is in docs/phase-2-model/12-tax-id-security-design.md and is blocked on decisions D-1..D-10.'
           END
      FROM information_schema.columns c
      JOIN information_schema.tables t ON t.table_schema = c.table_schema AND t.table_name = c.table_name AND t.table_type = 'BASE TABLE'
     CROSS JOIN LATERAL (SELECT
           CASE
             WHEN c.table_schema = 'master'                                                                       THEN 'public'
             WHEN c.column_name ~ '(secret_hash|token_hash|password_hash|api_key|totp)'
               OR (c.table_name = 'organization_identifier' AND c.column_name = 'identifier_value')
               OR c.column_name IN ('gateway_order_id', 'gateway_refund_ref')                                    THEN 'sensitive'
             WHEN c.column_name ~ '(^|_)(email|phone_e164|phone_country_code|client_ip|user_agent|device_identifier|device_name)($|_)'
               OR c.column_name IN ('headline', 'professional_summary', 'cover_letter', 'pitch', 'review_text',
                                    'original_filename', 'storage_key', 'query_text', 'filters_json', 'body_snippet',
                                    'subject', 'message_body', 'preferred_language', 'consultant_notes', 'client_feedback',
                                    'proposal_notes', 'block_reason', 'change_reason', 'credential_identifier')    THEN 'personal'
             WHEN c.table_schema = 'profile' AND c.table_name IN ('course', 'resume_template')                    THEN 'internal'   -- catalogues, no person in them
             WHEN c.table_schema = 'profile'                                                                      THEN 'personal'
             WHEN c.table_schema = 'recruitment' AND c.table_name IN ('organization')
               AND c.column_name IN ('name', 'slug', 'description', 'website_url')                                THEN 'public'
             WHEN c.table_schema = 'recruitment' AND c.table_name = 'job_posting'
               AND c.column_name IN ('title', 'description', 'responsibilities', 'qualifications', 'published_at') THEN 'public'
             ELSE 'internal'
           END AS data_class) cls
     WHERE c.table_schema IN ('core','master','profile','recruitment','gig','commercial','sourcing','messaging','audit','analytics')
       AND NOT EXISTS (SELECT 1 FROM audit.column_classification x
                        WHERE x.schema_name = c.table_schema AND x.table_name = c.table_name AND x.column_name = c.column_name);
    GET DIAGNOSTICS v_added = ROW_COUNT;
    RETURN v_added;
END;
$$;

COMMENT ON FUNCTION audit.sync_column_classification() IS
    'Writes a pattern-based classification for every column that has none. Returns how many it added. Review the output; pattern rules are a starting point.';

SELECT audit.sync_column_classification();

-- the classification table is itself a table: register its columns and its lifecycle
SELECT audit.apply_standard_lifecycle('audit', 'column_classification', 'reference');

-- -----------------------------------------------------------------------------
-- Retention for every remaining table that holds a personal or sensitive column
-- (docket Rule Group 4; playbook gate G2). All periods are PROPOSALS and stay unapproved until the data
-- owner signs them off (is_retention_approved remains FALSE).
-- -----------------------------------------------------------------------------
UPDATE audit.entity_lifecycle_policy SET
    retention_days = 730,
    retention_basis = 'Proposed: free-text and contact data tied to a person, 24 months after last activity'
WHERE (schema_name, table_name) IN
      (('gig', 'gig_application'), ('gig', 'gig_rating'), ('gig', 'gig_worker_profile'), ('messaging', 'referral_event'),
       ('recruitment', 'candidate_application'), ('recruitment', 'candidate_application_partitioned'),
       ('sourcing', 'consultant_sourcing_request'), ('sourcing', 'outreach_batch'), ('sourcing', 'sourcing_submission'));
UPDATE audit.entity_lifecycle_policy SET
    retention_days = 1095, retention_basis = 'Proposed: support tickets, 3 years'
WHERE (schema_name, table_name) = ('messaging', 'support_ticket');
UPDATE audit.entity_lifecycle_policy SET
    retention_days = 1825, retention_basis = 'Proposed: organisation contact data, 5 years after the organisation closes'
WHERE (schema_name, table_name) = ('recruitment', 'organization');
UPDATE audit.entity_lifecycle_policy SET
    retention_days = 2555, retention_basis = 'Proposed: registration identifiers kept as long as statutory record-keeping requires, 7 years'
WHERE (schema_name, table_name) = ('recruitment', 'organization_identifier');
UPDATE audit.entity_lifecycle_policy SET
    retention_days = 2555, retention_basis = 'Proposed: stage history is part of the hiring record, 7 years'
WHERE (schema_name, table_name) = ('recruitment', 'application_status_history');

COMMIT;
