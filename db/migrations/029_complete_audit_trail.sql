BEGIN;
-- =============================================================================
-- Migration 029: Complete the audit trail (docket section 3: "Every sensitive action must be recorded in an audit trail")
-- Domain:        audit / security (SEC-003, NFR-016; audit matrix gaps AG-01 to AG-11)
-- Depends on:    001-028
--
-- The audit matrix (docs/phase-1-discover/05-audit-event-matrix.md) found 2 of 14 sensitive action classes covered.
-- This migration covers the rest:
--
--   AG-01/02  every class writes an event at the point of the action: row triggers for data changes, and the
--             login / login-failure / impersonation functions for actions that are not data changes
--   AG-03     audit_event gains organization_id, and audit.org_audit_event lets an organisation read its own events
--   AG-04     actions come from a catalogue (audit.action_catalogue), enforced by foreign key, mapped to the 14 classes
--   AG-08     the actor foreign key is RESTRICT, so deleting a user cannot orphan their history
--   AG-09     impersonation has a write path and is recorded on every event made while impersonating
--
-- Classes 11 (profile view/download), 12 (application stage change) and 13 (wallet transaction) are already
-- recorded in append-only domain ledgers that carry actor, subject and time (made tamper-proof in migrations 017 and 022).
-- Writing them a second time into audit_event would double the volume of the busiest tables for no gain, so the
-- catalogue lists them with trail = 'domain_ledger' and names the table. This is decision DEC-14.
--
-- Secrets and personal data never enter the log: each trigger names the columns it leaves out.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Action catalogue
-- -----------------------------------------------------------------------------
CREATE TABLE audit.action_catalogue (
    id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code             VARCHAR(80)  NOT NULL,
    sensitive_class  INTEGER      NOT NULL,
    trail            VARCHAR(14)  NOT NULL DEFAULT 'audit_event',
    trail_table      VARCHAR(100),
    description      VARCHAR(300) NOT NULL,

    CONSTRAINT uq_action_catalogue_code UNIQUE (code),
    CONSTRAINT ck_action_catalogue_class CHECK (sensitive_class BETWEEN 1 AND 14),
    CONSTRAINT ck_action_catalogue_trail CHECK (trail IN ('audit_event', 'domain_ledger')),
    CONSTRAINT ck_action_catalogue_ledger CHECK ((trail = 'domain_ledger') = (trail_table IS NOT NULL))
);
COMMENT ON TABLE audit.action_catalogue IS 'Every action code that may appear in audit.audit_event, with the sensitive-action class (1-14) it evidences. Domain-ledger rows name the append-only table that already records the action.';
COMMENT ON COLUMN audit.action_catalogue.trail_table IS 'Nullable: set only when trail = domain_ledger, naming the append-only table that is the trail.';
SELECT audit.apply_standard_lifecycle('audit', 'action_catalogue', 'reference');

INSERT INTO audit.action_catalogue (code, sensitive_class, trail, trail_table, description) VALUES
 ('auth.login',                     1, 'audit_event',   NULL, 'A session was created after a successful login'),
 ('auth.failed',                    2, 'audit_event',   NULL, 'A login attempt failed (unknown account, wrong password, locked)'),
 ('session.revoked',                3, 'audit_event',   NULL, 'A session or device was revoked'),
 ('device.limit_exceeded',          4, 'audit_event',   NULL, 'A login was refused because the device entitlement was reached'),
 ('credential.changed',             5, 'audit_event',   NULL, 'A credential was set, rotated, deactivated or expired'),
 ('role.assigned',                  6, 'audit_event',   NULL, 'A user was given a platform or organisation role'),
 ('role.removed',                   6, 'audit_event',   NULL, 'A user lost a platform or organisation role'),
 ('role_permission.changed',        6, 'audit_event',   NULL, 'A permission was granted to or removed from a role'),
 ('account.status_changed',         7, 'audit_event',   NULL, 'An account or organisation status changed (suspend, close, reactivate)'),
 ('user.erased',                    7, 'audit_event',   NULL, 'An account was erased on request or after inactivity'),
 ('admin.impersonation_started',    8, 'audit_event',   NULL, 'An administrator began acting as another user'),
 ('admin.impersonation_ended',      8, 'audit_event',   NULL, 'An administrator stopped acting as another user'),
 ('consent.changed',                9, 'audit_event',   NULL, 'Consent was granted, changed or withdrawn'),
 ('block.changed',                 10, 'audit_event',   NULL, 'A user or organisation was blocked or unblocked'),
 ('profile.viewed',                11, 'domain_ledger', 'profile.profile_view_history', 'A candidate profile was viewed'),
 ('profile.downloaded',            11, 'domain_ledger', 'commercial.candidate_profile_download_history', 'A candidate profile was downloaded'),
 ('application.stage_changed',     12, 'domain_ledger', 'recruitment.application_status_history', 'An application moved to another stage'),
 ('wallet.transaction',            13, 'domain_ledger', 'commercial.wallet_ledger', 'Credit was added, spent or corrected'),
 ('payment.changed',               14, 'audit_event',   NULL, 'A payment order was created or changed state'),
 ('refund.issued',                 14, 'audit_event',   NULL, 'A refund was issued'),
 ('licence.changed',               14, 'audit_event',   NULL, 'A licence, seat or subscription was created or changed');

CREATE VIEW audit.sensitive_class_coverage AS
SELECT c AS sensitive_class,
       COUNT(a.id) AS action_codes,
       COUNT(a.id) FILTER (WHERE a.trail = 'audit_event')   AS in_audit_event,
       COUNT(a.id) FILTER (WHERE a.trail = 'domain_ledger') AS in_domain_ledger
  FROM generate_series(1, 14) AS c
  LEFT JOIN audit.action_catalogue a ON a.sensitive_class = c
 GROUP BY c;
COMMENT ON VIEW audit.sensitive_class_coverage IS 'For each of the 14 sensitive action classes, how many action codes evidence it and where they are recorded. A class with zero codes is uncovered.';

-- -----------------------------------------------------------------------------
-- 2. audit_event: organisation scope, vocabulary, actor attribution that survives deletion
-- -----------------------------------------------------------------------------
ALTER TABLE audit.audit_event ADD COLUMN organization_id BIGINT;
COMMENT ON COLUMN audit.audit_event.organization_id IS 'Nullable: the organisation the event belongs to, when it belongs to one. Platform-level events (a login, a role change) have none.';
ALTER TABLE audit.audit_event
    ADD CONSTRAINT fk_audit_event_organization FOREIGN KEY (organization_id)
        REFERENCES recruitment.organization (id) ON UPDATE RESTRICT ON DELETE RESTRICT;
CREATE INDEX idx_audit_event_organization_recorded ON audit.audit_event (organization_id, recorded_at DESC)
    WHERE organization_id IS NOT NULL;

ALTER TABLE audit.audit_event
    ADD CONSTRAINT fk_audit_event_action FOREIGN KEY (action)
        REFERENCES audit.action_catalogue (code) ON UPDATE RESTRICT ON DELETE RESTRICT;

-- AG-08: deleting a user must not erase who did what. SET NULL would also fail against the append-only trigger.
ALTER TABLE audit.audit_event DROP CONSTRAINT fk_audit_event_actor;
ALTER TABLE audit.audit_event ADD CONSTRAINT fk_audit_event_actor FOREIGN KEY (actor_user_account_id)
    REFERENCES core.user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT;
ALTER TABLE audit.audit_event DROP CONSTRAINT fk_audit_event_impersonator;
ALTER TABLE audit.audit_event ADD CONSTRAINT fk_audit_event_impersonator FOREIGN KEY (impersonator_user_account_id)
    REFERENCES core.user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT;

COMMENT ON TABLE audit.audit_event IS
    'Append-only trail of sensitive actions. Actions come from audit.action_catalogue (14 classes). Written by audit.log_change() triggers and by the login, revocation, erasure and impersonation functions. Never UPDATE or DELETE; TRUNCATE is blocked.';

-- Organisation administrators read their own organisation's events, without payloads, addresses or user agents.
CREATE VIEW audit.org_audit_event WITH (security_barrier = true) AS
SELECT e.id, e.recorded_at, e.action, e.actor_user_account_id, e.entity_schema, e.entity_name, e.entity_id, e.organization_id
  FROM audit.audit_event e
 WHERE e.organization_id = core.current_org_id();
COMMENT ON VIEW audit.org_audit_event IS 'The tenant-scoped audit surface (threat model: Organization Admin, own organisation only). Payloads and client details are withheld.';
GRANT SELECT ON audit.org_audit_event TO talentra_app;
GRANT SELECT ON audit.action_catalogue, audit.sensitive_class_coverage TO talentra_auditor, talentra_readonly;
SELECT audit.sync_column_classification();

-- -----------------------------------------------------------------------------
-- 3. One trigger function for data changes
--    TG_ARGV[0]  action code, or 'insert_code|update_code|delete_code'
--    TG_ARGV[1]  comma list of columns never written to the log (secrets, personal data)
--    TG_ARGV[2]  comma list of columns; when given, an UPDATE is logged only if one of them changed
--    TG_ARGV[3]  column holding the organisation id, if the row belongs to one
-- -----------------------------------------------------------------------------
CREATE FUNCTION audit.log_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_codes   TEXT[] := string_to_array(TG_ARGV[0], '|');
    v_exclude TEXT[] := string_to_array(COALESCE(TG_ARGV[1], ''), ',');
    v_watch   TEXT[] := string_to_array(COALESCE(TG_ARGV[2], ''), ',');
    v_org_col TEXT   := NULLIF(COALESCE(TG_ARGV[3], ''), '');
    v_action  TEXT;
    v_old     JSONB;
    v_new     JSONB;
    v_row     JSONB;
    v_col     TEXT;
    v_changed BOOLEAN := TRUE;
BEGIN
    v_action := CASE TG_OP WHEN 'INSERT' THEN v_codes[1]
                           WHEN 'UPDATE' THEN COALESCE(v_codes[2], v_codes[1])
                           ELSE COALESCE(v_codes[3], v_codes[1]) END;
    IF TG_OP <> 'INSERT' THEN v_old := to_jsonb(OLD) - v_exclude; END IF;
    IF TG_OP <> 'DELETE' THEN v_new := to_jsonb(NEW) - v_exclude; END IF;

    IF TG_OP = 'UPDATE' AND array_length(v_watch, 1) IS NOT NULL AND v_watch[1] <> '' THEN
        v_changed := FALSE;
        FOREACH v_col IN ARRAY v_watch LOOP
            IF (to_jsonb(OLD) -> v_col) IS DISTINCT FROM (to_jsonb(NEW) -> v_col) THEN v_changed := TRUE; END IF;
        END LOOP;
    END IF;

    IF v_changed THEN
        v_row := COALESCE(to_jsonb(NEW), to_jsonb(OLD));
        INSERT INTO audit.audit_event (actor_user_account_id, impersonator_user_account_id, action, entity_schema, entity_name,
                                       entity_id, old_values_json, new_values_json, organization_id)
        VALUES (core.current_app_user_id(),
                NULLIF(current_setting('app.impersonator_user_id', true), '')::BIGINT,
                v_action, TG_TABLE_SCHEMA, TG_TABLE_NAME,
                (v_row ->> 'id')::BIGINT, v_old, v_new,
                CASE WHEN v_org_col IS NULL THEN NULL ELSE (v_row ->> v_org_col)::BIGINT END);
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;
COMMENT ON FUNCTION audit.log_change() IS 'AFTER row trigger: writes one audit.audit_event per change. Arguments: action code(s), columns to leave out, columns to watch on UPDATE, organisation column.';

-- class 5: credentials (the secret and the login identifier never enter the log)
CREATE TRIGGER trg_user_credential_audit AFTER INSERT OR UPDATE ON core.user_credential
    FOR EACH ROW EXECUTE FUNCTION audit.log_change('credential.changed', 'secret_hash,credential_identifier', 'secret_hash,is_active,expires_at', '');
-- class 6: platform roles, role permissions and organisation roles
CREATE TRIGGER trg_user_role_audit AFTER INSERT OR DELETE ON core.user_role
    FOR EACH ROW EXECUTE FUNCTION audit.log_change('role.assigned||role.removed', '', '', '');
CREATE TRIGGER trg_role_permission_audit AFTER INSERT OR DELETE ON core.role_permission
    FOR EACH ROW EXECUTE FUNCTION audit.log_change('role_permission.changed', '', '', '');
CREATE TRIGGER trg_organization_member_audit AFTER INSERT OR UPDATE OR DELETE ON recruitment.organization_member
    FOR EACH ROW EXECUTE FUNCTION audit.log_change('role.assigned|role.assigned|role.removed', '', 'organization_role,membership_status', 'organization_id');
-- class 7: account and organisation status (contact details and password hash stay out)
CREATE TRIGGER trg_user_account_status_audit AFTER UPDATE ON core.user_account
    FOR EACH ROW EXECUTE FUNCTION audit.log_change('account.status_changed', 'email,phone_e164,phone_country_code,password_hash', 'account_status', '');
CREATE TRIGGER trg_organization_status_audit AFTER UPDATE ON recruitment.organization
    FOR EACH ROW EXECUTE FUNCTION audit.log_change('account.status_changed', 'contact_email,contact_phone_e164', 'organization_status', 'id');
-- class 9: consent (address and user agent stay in the consent row itself)
CREATE TRIGGER trg_consent_record_audit AFTER INSERT OR UPDATE ON core.consent_record
    FOR EACH ROW EXECUTE FUNCTION audit.log_change('consent.changed', 'client_ip,user_agent', 'is_granted,revoked_at,consent_version', '');
-- class 10: blocks
CREATE TRIGGER trg_user_block_audit AFTER INSERT OR DELETE ON core.user_block
    FOR EACH ROW EXECUTE FUNCTION audit.log_change('block.changed', 'block_reason', '', '');
-- class 14: payments, refunds, licences and subscriptions (gateway references stay out)
CREATE TRIGGER trg_payment_order_audit AFTER INSERT OR UPDATE ON commercial.payment_order
    FOR EACH ROW EXECUTE FUNCTION audit.log_change('payment.changed', 'gateway_order_id', 'order_status,order_amount', 'organization_id');
CREATE TRIGGER trg_payment_refund_audit AFTER INSERT ON commercial.payment_refund
    FOR EACH ROW EXECUTE FUNCTION audit.log_change('refund.issued', 'gateway_refund_ref,refund_reason', '', '');
CREATE TRIGGER trg_subscription_licence_audit AFTER INSERT OR UPDATE ON commercial.subscription_licence
    FOR EACH ROW EXECUTE FUNCTION audit.log_change('licence.changed', 'licence_key', 'licence_status,max_users,max_devices_per_user,valid_from,valid_to', 'organization_id');
CREATE TRIGGER trg_licence_seat_audit AFTER INSERT OR UPDATE ON commercial.licence_seat_allocation
    FOR EACH ROW EXECUTE FUNCTION audit.log_change('licence.changed', '', 'revoked_at', '');
CREATE TRIGGER trg_subscription_audit AFTER INSERT OR UPDATE ON commercial.subscription
    FOR EACH ROW EXECUTE FUNCTION audit.log_change('licence.changed', 'cancellation_reason', 'subscription_status,period_end,auto_renew', '');

-- -----------------------------------------------------------------------------
-- 4. Class 1: record the successful login inside the login function
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    v_def TEXT := pg_get_functiondef('core.create_session_with_device_limit(bigint, character varying, character varying, character varying, character varying, character varying)'::regprocedure);
    v_patched TEXT;
BEGIN
    v_patched := replace(v_def,
        'RETURNING id INTO v_new_session_id;',
        E'RETURNING id INTO v_new_session_id;\n\n    INSERT INTO audit.audit_event (actor_user_account_id, action, entity_schema, entity_name, entity_id, new_values_json, client_ip)\n    VALUES (p_user_account_id, ''auth.login'', ''core'', ''user_session'', v_new_session_id,\n            jsonb_build_object(''device_identifier'', p_device_identifier, ''device_type'', p_device_type), p_client_ip);');
    IF v_patched = v_def THEN
        RAISE EXCEPTION 'create_session_with_device_limit changed shape: the login audit insert could not be added';
    END IF;
    EXECUTE v_patched;
END;
$$;

-- -----------------------------------------------------------------------------
-- 5. Class 2: failed logins, and a lockout rule built on them
-- -----------------------------------------------------------------------------
CREATE FUNCTION core.record_login_failure(p_identifier TEXT, p_client_ip VARCHAR DEFAULT NULL, p_reason VARCHAR DEFAULT 'bad_credentials')
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_user BIGINT;
BEGIN
    SELECT f.user_account_id INTO v_user FROM core.find_credential_for_login(p_identifier) f LIMIT 1;   -- NULL for an unknown account
    INSERT INTO audit.audit_event (actor_user_account_id, action, entity_schema, entity_name, new_values_json, client_ip)
    VALUES (v_user, 'auth.failed', 'core', 'user_account',
            jsonb_build_object('identifier_sha256', encode(sha256(convert_to(lower(p_identifier), 'UTF8')), 'hex'), 'reason', p_reason),
            p_client_ip);
END;
$$;
COMMENT ON FUNCTION core.record_login_failure(TEXT, VARCHAR, VARCHAR) IS 'Call after a bad password or unknown account. Stores a hash of the identifier, never the identifier.';

CREATE FUNCTION core.is_login_locked(p_identifier TEXT, p_max_failures INTEGER DEFAULT 5, p_window INTERVAL DEFAULT INTERVAL '15 minutes')
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
    SELECT COUNT(*) >= p_max_failures
      FROM audit.audit_event e
     WHERE e.action = 'auth.failed'
       AND e.recorded_at > CURRENT_TIMESTAMP - p_window
       AND e.new_values_json ->> 'identifier_sha256' = encode(sha256(convert_to(lower(p_identifier), 'UTF8')), 'hex');
$$;
COMMENT ON FUNCTION core.is_login_locked(TEXT, INTEGER, INTERVAL) IS 'True after p_max_failures failed logins for the identifier within the window. The lock lifts when the window passes.';

REVOKE EXECUTE ON FUNCTION core.is_login_locked(TEXT, INTEGER, INTERVAL) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION core.is_login_locked(TEXT, INTEGER, INTERVAL) TO talentra_app;

-- -----------------------------------------------------------------------------
-- 6. Class 8: administrative impersonation
-- -----------------------------------------------------------------------------
CREATE FUNCTION core.begin_impersonation(p_target_user_account_id BIGINT, p_reason TEXT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_admin BIGINT := core.current_app_user_id();
BEGIN
    IF v_admin IS NULL THEN RAISE EXCEPTION 'Impersonation needs an authenticated administrator (app.current_user_id is not set)' USING ERRCODE = 'insufficient_privilege'; END IF;
    IF NOT core.is_platform_admin() THEN RAISE EXCEPTION 'User % is not a platform administrator', v_admin USING ERRCODE = 'insufficient_privilege'; END IF;
    IF p_reason IS NULL OR length(btrim(p_reason)) < 10 THEN RAISE EXCEPTION 'Impersonation needs a reason of at least 10 characters'; END IF;
    IF EXISTS (SELECT 1 FROM core.user_role ur JOIN core.role r ON r.id = ur.role_id
                WHERE ur.user_account_id = p_target_user_account_id AND r.name IN ('super_admin', 'admin')) THEN
        RAISE EXCEPTION 'An administrator cannot impersonate another administrator' USING ERRCODE = 'insufficient_privilege';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM core.user_account WHERE id = p_target_user_account_id AND deleted_at IS NULL) THEN
        RAISE EXCEPTION 'User % does not exist', p_target_user_account_id;
    END IF;
    INSERT INTO audit.audit_event (actor_user_account_id, action, entity_schema, entity_name, entity_id, new_values_json)
    VALUES (v_admin, 'admin.impersonation_started', 'core', 'user_account', p_target_user_account_id, jsonb_build_object('reason', p_reason));
    PERFORM set_config('app.impersonator_user_id', v_admin::TEXT, true);
    PERFORM set_config('app.current_user_id', p_target_user_account_id::TEXT, true);
END;
$$;
COMMENT ON FUNCTION core.begin_impersonation(BIGINT, TEXT) IS 'Administrator acts as another user for the rest of the transaction. Needs a reason; refuses other administrators; every audit event written meanwhile carries the impersonator.';

CREATE FUNCTION core.end_impersonation()
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_admin  BIGINT := NULLIF(current_setting('app.impersonator_user_id', true), '')::BIGINT;
    v_target BIGINT := core.current_app_user_id();
BEGIN
    IF v_admin IS NULL THEN RAISE EXCEPTION 'No impersonation is in progress'; END IF;
    INSERT INTO audit.audit_event (actor_user_account_id, impersonator_user_account_id, action, entity_schema, entity_name, entity_id)
    VALUES (v_target, v_admin, 'admin.impersonation_ended', 'core', 'user_account', v_target);
    PERFORM set_config('app.current_user_id', v_admin::TEXT, true);
    PERFORM set_config('app.impersonator_user_id', '', true);
END;
$$;

-- -----------------------------------------------------------------------------
-- 7. Idempotency for payments (docket section 6: "Idempotency: how duplicate events are prevented", EXC-29)
-- -----------------------------------------------------------------------------
ALTER TABLE commercial.payment_order ADD COLUMN idempotency_key VARCHAR(100);
COMMENT ON COLUMN commercial.payment_order.idempotency_key IS 'Nullable: a key the caller supplies so that retrying the same request cannot create a second order. Unique per organisation when present.';
CREATE UNIQUE INDEX uq_payment_order_idempotency ON commercial.payment_order (organization_id, idempotency_key) WHERE idempotency_key IS NOT NULL;
SELECT audit.sync_column_classification();

COMMIT;
