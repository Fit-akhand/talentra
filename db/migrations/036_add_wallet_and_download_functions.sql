-- 036: the credit workflow as database functions (WF-14; docket "wallet recharge and credit consumption for postings,
-- profile downloads and outreach"; Rule Group 10 append-only ledgers).
--
-- Before this migration the wallet balance and the ledger were two separate writes that the application had to keep equal
-- (EXC-39, ML-06). Now one function takes the row lock, refuses an overdraft, appends the ledger entry and moves the balance,
-- and the application role can no longer write either table directly.
--
-- Decision DEC-29 (Delegated, 2026-10-28): prices live in commercial.credit_price; the amounts seeded here are PLACEHOLDERS
-- for the commercial owner to replace. An organisation that has already downloaded a profile is not charged to download it again.

BEGIN;

CREATE TABLE commercial.credit_price (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    reference_type  VARCHAR(40)   NOT NULL,
    currency_code   CHAR(3)       NOT NULL,
    amount          NUMERIC(14,2) NOT NULL,
    is_active       BOOLEAN       NOT NULL DEFAULT TRUE,

    CONSTRAINT uq_credit_price UNIQUE (reference_type, currency_code),
    CONSTRAINT ck_credit_price_reference CHECK (reference_type IN ('profile_download', 'outreach_fee', 'job_posting_fee', 'gig_commission')),
    CONSTRAINT ck_credit_price_currency CHECK (currency_code ~ '^[A-Z]{3}$'),
    CONSTRAINT ck_credit_price_amount CHECK (amount > 0.00)
);
COMMENT ON TABLE commercial.credit_price IS 'What one unit of a chargeable action costs in each currency. Seed amounts are placeholders (DEC-29) for the commercial owner to replace.';
COMMENT ON COLUMN commercial.credit_price.id IS 'Surrogate primary key (64-bit identity). Never reused, never shown to users.';
COMMENT ON COLUMN commercial.credit_price.reference_type IS 'The chargeable action; one of the wallet ledger reference types that spend credit.';
COMMENT ON COLUMN commercial.credit_price.currency_code IS 'ISO 4217 currency of amount, three capital letters; the wallet charged must be in this currency.';
COMMENT ON COLUMN commercial.credit_price.amount IS 'Credit charged per action, in currency_code, greater than zero.';
COMMENT ON COLUMN commercial.credit_price.is_active IS 'False withdraws the price; the action then cannot be charged in that currency.';
SELECT audit.apply_standard_lifecycle('commercial', 'credit_price', 'reference');
COMMENT ON COLUMN commercial.credit_price.created_at IS 'When the row was created (UTC). Set by trigger and never changed.';
COMMENT ON COLUMN commercial.credit_price.updated_at IS 'When the row was last changed (UTC). Set by trigger.';
COMMENT ON COLUMN commercial.credit_price.created_by_user_account_id IS 'Account that created the row, taken from the session. NULL when the system created it (seed, migration, scheduled job).';
COMMENT ON COLUMN commercial.credit_price.updated_by_user_account_id IS 'Account that last changed the row, taken from the session. NULL when the system changed it.';

INSERT INTO commercial.credit_price (reference_type, currency_code, amount) VALUES
    ('profile_download', 'USD', 2.00), ('outreach_fee', 'USD', 0.50), ('job_posting_fee', 'USD', 10.00),
    ('profile_download', 'INR', 150.00), ('outreach_fee', 'INR', 40.00), ('job_posting_fee', 'INR', 800.00);

-- ---------------------------------------------------------------------------------------------------------------
-- One atomic wallet movement
-- ---------------------------------------------------------------------------------------------------------------
CREATE FUNCTION commercial.post_wallet_entry(
    p_wallet_id BIGINT, p_entry_type VARCHAR, p_amount NUMERIC, p_reference_type VARCHAR,
    p_reference_id BIGINT DEFAULT NULL, p_correction_of_ledger_id BIGINT DEFAULT NULL, p_notes VARCHAR DEFAULT NULL)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
DECLARE
    v_wallet commercial.wallet%ROWTYPE;
    v_user BIGINT := core.current_app_user_id();
    v_new NUMERIC(14,2);
    v_id BIGINT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'a wallet movement needs an acting user' USING ERRCODE = 'insufficient_privilege'; END IF;
    IF p_amount IS NULL OR p_amount <= 0 THEN RAISE EXCEPTION 'amount must be greater than zero' USING ERRCODE = 'check_violation'; END IF;
    IF p_entry_type NOT IN ('credit', 'debit', 'correction_credit', 'correction_debit') THEN
        RAISE EXCEPTION 'unknown entry type %', p_entry_type USING ERRCODE = 'check_violation';
    END IF;

    SELECT * INTO v_wallet FROM commercial.wallet WHERE id = p_wallet_id FOR UPDATE;      -- serialises movements on this wallet
    IF NOT FOUND THEN RAISE EXCEPTION 'wallet % does not exist', p_wallet_id USING ERRCODE = 'foreign_key_violation'; END IF;
    IF v_wallet.organization_id IS DISTINCT FROM core.current_org_id() AND NOT core.is_platform_admin() THEN
        RAISE EXCEPTION 'wallet % belongs to another organisation', p_wallet_id USING ERRCODE = 'insufficient_privilege';
    END IF;

    v_new := CASE WHEN p_entry_type IN ('credit', 'correction_credit') THEN v_wallet.balance + p_amount ELSE v_wallet.balance - p_amount END;
    IF v_new < 0 THEN
        RAISE EXCEPTION 'insufficient wallet balance: % available, % needed', v_wallet.balance, p_amount USING ERRCODE = 'check_violation';
    END IF;

    INSERT INTO commercial.wallet_ledger (wallet_id, entry_type, amount, currency_code, balance_after, reference_type, reference_id,
                                          correction_of_ledger_id, notes, created_by_user_account_id)
    VALUES (v_wallet.id, p_entry_type, p_amount, v_wallet.currency_code, v_new, p_reference_type, p_reference_id,
            p_correction_of_ledger_id, p_notes, v_user)
    RETURNING id INTO v_id;
    UPDATE commercial.wallet SET balance = v_new WHERE id = v_wallet.id;
    RETURN v_id;
END;
$$;
COMMENT ON FUNCTION commercial.post_wallet_entry(BIGINT, VARCHAR, NUMERIC, VARCHAR, BIGINT, BIGINT, VARCHAR) IS
    'The only way the application changes a wallet: locks the wallet, refuses an overdraft, appends the ledger entry and sets the balance in one transaction. Returns the ledger id.';

-- ---------------------------------------------------------------------------------------------------------------
-- Download a candidate profile: visibility, price, charge, history
-- ---------------------------------------------------------------------------------------------------------------
CREATE FUNCTION commercial.download_candidate_profile(p_candidate_profile_id BIGINT)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
DECLARE
    v_user BIGINT := core.current_app_user_id();
    v_org BIGINT := core.current_org_id();
    v_wallet_id BIGINT;
    v_amount NUMERIC(14,2);
    v_currency CHAR(3);
    v_ledger BIGINT;
    v_history BIGINT;
BEGIN
    IF v_user IS NULL OR v_org IS NULL THEN
        RAISE EXCEPTION 'downloading a profile needs a user acting for an organisation' USING ERRCODE = 'insufficient_privilege';
    END IF;
    IF NOT core.can_view_candidate(p_candidate_profile_id) THEN
        RAISE EXCEPTION 'candidate profile % is not visible to this user', p_candidate_profile_id USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- already downloaded by this organisation: recorded again, not charged again (DEC-29)
    IF EXISTS (SELECT 1 FROM commercial.candidate_profile_download_history
                WHERE organization_id = v_org AND candidate_profile_id = p_candidate_profile_id AND credit_deduction_amount > 0) THEN
        INSERT INTO commercial.candidate_profile_download_history (organization_id, downloader_user_account_id, candidate_profile_id, credit_deduction_amount, currency_code)
        SELECT v_org, v_user, p_candidate_profile_id, 0.00, h.currency_code
          FROM commercial.candidate_profile_download_history h
         WHERE h.organization_id = v_org AND h.candidate_profile_id = p_candidate_profile_id AND h.credit_deduction_amount > 0
         ORDER BY h.id DESC LIMIT 1
        RETURNING id INTO v_history;
        RETURN v_history;
    END IF;

    -- the cheapest priced wallet the organisation can afford, so a multi-currency organisation is not refused needlessly
    SELECT w.id, p.amount, p.currency_code
      INTO v_wallet_id, v_amount, v_currency
      FROM commercial.wallet w
      JOIN commercial.credit_price p ON p.currency_code = w.currency_code AND p.reference_type = 'profile_download' AND p.is_active
     WHERE w.organization_id = v_org AND w.balance >= p.amount
     ORDER BY p.amount, w.id
     LIMIT 1;
    IF NOT FOUND THEN
        IF NOT EXISTS (SELECT 1 FROM commercial.wallet w JOIN commercial.credit_price p ON p.currency_code = w.currency_code AND p.reference_type = 'profile_download' AND p.is_active
                        WHERE w.organization_id = v_org) THEN
            RAISE EXCEPTION 'organisation % has no wallet in a currency with a profile-download price', v_org USING ERRCODE = 'check_violation';
        END IF;
        RAISE EXCEPTION 'insufficient wallet balance for a profile download' USING ERRCODE = 'check_violation';
    END IF;

    v_ledger := commercial.post_wallet_entry(v_wallet_id, 'debit', v_amount, 'profile_download', p_candidate_profile_id, NULL, NULL);
    INSERT INTO commercial.candidate_profile_download_history (organization_id, downloader_user_account_id, candidate_profile_id, credit_deduction_amount, currency_code, wallet_ledger_id)
    VALUES (v_org, v_user, p_candidate_profile_id, v_amount, v_currency, v_ledger)
    RETURNING id INTO v_history;
    RETURN v_history;
END;
$$;
COMMENT ON FUNCTION commercial.download_candidate_profile(BIGINT) IS
    'WF-14 in one transaction: checks the candidate is visible to the acting organisation, finds the price, debits the wallet and records the download. A repeat download by the same organisation is recorded at zero cost. Returns the download-history id.';

REVOKE ALL ON FUNCTION commercial.post_wallet_entry(BIGINT, VARCHAR, NUMERIC, VARCHAR, BIGINT, BIGINT, VARCHAR) FROM PUBLIC;
REVOKE ALL ON FUNCTION commercial.download_candidate_profile(BIGINT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION commercial.post_wallet_entry(BIGINT, VARCHAR, NUMERIC, VARCHAR, BIGINT, BIGINT, VARCHAR) TO talentra_app;
GRANT EXECUTE ON FUNCTION commercial.download_candidate_profile(BIGINT) TO talentra_app;

-- from now on the application changes money only through these functions
REVOKE UPDATE, DELETE ON commercial.wallet FROM talentra_app;
REVOKE INSERT ON commercial.wallet_ledger FROM talentra_app;
REVOKE INSERT ON commercial.candidate_profile_download_history FROM talentra_app;
GRANT SELECT ON commercial.credit_price TO talentra_app, talentra_readonly, talentra_analyst;

SELECT * FROM master.sync_enumeration_values();
SELECT audit.sync_column_classification();
SELECT audit.refresh_protection();

COMMIT;
