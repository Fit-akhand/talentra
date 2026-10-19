-- Migration: 017_create_commercial_ledgers.sql
-- Purpose: Implement commercial subscription plans, non-overlapping subscription periods, payment orders, invoices, refunds, wallets, strictly append-only wallet ledgers, and candidate profile download history.
-- Requires: 001_create_schemas.sql, 002_create_identity.sql, 007_create_organization.sql, 005_create_candidate_profile.sql, 015_create_licences_and_device_limits.sql
-- Engine: PostgreSQL 17

BEGIN;

CREATE EXTENSION IF NOT EXISTS btree_gist;

-- 1. Subscription Plans
CREATE TABLE commercial.subscription_plan (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    plan_code VARCHAR(50) NOT NULL,
    name VARCHAR(100) NOT NULL,
    tier VARCHAR(30) NOT NULL DEFAULT 'standard',
    billing_interval VARCHAR(20) NOT NULL DEFAULT 'monthly',
    price_amount NUMERIC(14,2) NOT NULL,
    currency_code CHAR(3) NOT NULL DEFAULT 'USD',
    job_postings_quota INTEGER NOT NULL DEFAULT 5,
    profile_downloads_quota INTEGER NOT NULL DEFAULT 50,
    outreach_credits_quota INTEGER NOT NULL DEFAULT 100,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_subscription_plan PRIMARY KEY (id),
    CONSTRAINT uq_subscription_plan_code UNIQUE (plan_code),

    CONSTRAINT ck_subscription_plan_price
        CHECK (price_amount >= 0.00),

    CONSTRAINT ck_subscription_plan_currency
        CHECK (currency_code ~ '^[A-Z]{3}$'),

    CONSTRAINT ck_subscription_plan_interval
        CHECK (billing_interval IN ('monthly', 'quarterly', 'semi_annual', 'annual')),

    CONSTRAINT ck_subscription_plan_tier
        CHECK (tier IN ('free', 'standard', 'premium', 'enterprise')),

    CONSTRAINT ck_subscription_plan_quotas
        CHECK (
            job_postings_quota >= 0
            AND profile_downloads_quota >= 0
            AND outreach_credits_quota >= 0
        )
);

COMMENT ON TABLE commercial.subscription_plan IS
    'Catalog of commercial subscription plans, tiers, and entitled quotas';

-- Seed standard plans
INSERT INTO commercial.subscription_plan (
    plan_code, name, tier, billing_interval, price_amount, currency_code,
    job_postings_quota, profile_downloads_quota, outreach_credits_quota
)
VALUES
    ('growth_monthly',     'Growth Monthly Pack',     'standard',   'monthly', 299.00,  'USD', 10,  100, 250),
    ('enterprise_annual',  'Enterprise Scale Annual', 'enterprise', 'annual',  4999.00, 'USD', 100, 2000, 10000)
ON CONFLICT (plan_code) DO NOTHING;


-- 2. Subscriptions (with non-overlapping period exclusion constraint per licence)
CREATE TABLE commercial.subscription (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    subscription_licence_id BIGINT NOT NULL,
    subscription_plan_id BIGINT NOT NULL,
    period_start TIMESTAMPTZ NOT NULL,
    period_end TIMESTAMPTZ NOT NULL,
    auto_renew BOOLEAN NOT NULL DEFAULT TRUE,
    subscription_status VARCHAR(20) NOT NULL DEFAULT 'active',
    cancelled_at TIMESTAMPTZ,
    cancellation_reason VARCHAR(500),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_subscription PRIMARY KEY (id),

    CONSTRAINT fk_subscription_licence
        FOREIGN KEY (subscription_licence_id)
        REFERENCES commercial.subscription_licence (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT fk_subscription_plan
        FOREIGN KEY (subscription_plan_id)
        REFERENCES commercial.subscription_plan (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT ck_subscription_dates
        CHECK (period_end > period_start),

    CONSTRAINT ck_subscription_status
        CHECK (subscription_status IN ('active', 'cancelled', 'expired')),

    -- Milestone 14 (B47) & Rule Group 10: Non-overlapping subscription periods for same licence
    CONSTRAINT ex_subscription_no_overlap
        EXCLUDE USING gist (
            subscription_licence_id WITH =,
            tstzrange(period_start, period_end, '[)') WITH &&
        )
        WHERE (subscription_status = 'active')
);

CREATE INDEX idx_subscription_licence_dates
    ON commercial.subscription (subscription_licence_id, period_start, period_end);

COMMENT ON TABLE commercial.subscription IS
    'Active subscription periods per licence enforcing strictly non-overlapping active ranges';


-- 3. Payment Orders (Gateway boundary)
CREATE TABLE commercial.payment_order (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    organization_id BIGINT NOT NULL,
    user_account_id BIGINT NOT NULL,
    gateway_provider VARCHAR(50) NOT NULL DEFAULT 'stripe',
    gateway_order_id VARCHAR(255) NOT NULL,
    order_amount NUMERIC(14,2) NOT NULL,
    currency_code CHAR(3) NOT NULL DEFAULT 'USD',
    order_status VARCHAR(20) NOT NULL DEFAULT 'created',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_payment_order PRIMARY KEY (id),
    CONSTRAINT uq_payment_order_gateway_id UNIQUE (gateway_order_id),

    CONSTRAINT fk_payment_order_organization
        FOREIGN KEY (organization_id)
        REFERENCES recruitment.organization (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT fk_payment_order_user
        FOREIGN KEY (user_account_id)
        REFERENCES core.user_account (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT ck_payment_order_amount
        CHECK (order_amount > 0.00),

    CONSTRAINT ck_payment_order_currency
        CHECK (currency_code ~ '^[A-Z]{3}$'),

    CONSTRAINT ck_payment_order_status
        CHECK (
            order_status IN (
                'created',
                'authorized',
                'captured',
                'failed',
                'cancelled',
                'refunded'
            )
        )
);

CREATE INDEX idx_payment_order_org_status
    ON commercial.payment_order (organization_id, order_status);

COMMENT ON TABLE commercial.payment_order IS
    'Payment gateway transactions and references; never stores card or bank numbers';


-- 4. Invoices
CREATE TABLE commercial.invoice (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    organization_id BIGINT NOT NULL,
    payment_order_id BIGINT,
    invoice_number VARCHAR(60) NOT NULL,
    subtotal_amount NUMERIC(14,2) NOT NULL,
    tax_amount NUMERIC(14,2) NOT NULL DEFAULT 0.00,
    total_amount NUMERIC(14,2) NOT NULL,
    currency_code CHAR(3) NOT NULL DEFAULT 'USD',
    invoice_status VARCHAR(20) NOT NULL DEFAULT 'issued',
    issued_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    paid_at TIMESTAMPTZ,

    CONSTRAINT pk_invoice PRIMARY KEY (id),
    CONSTRAINT uq_invoice_number UNIQUE (invoice_number),

    CONSTRAINT fk_invoice_organization
        FOREIGN KEY (organization_id)
        REFERENCES recruitment.organization (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT fk_invoice_payment_order
        FOREIGN KEY (payment_order_id)
        REFERENCES commercial.payment_order (id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,

    CONSTRAINT ck_invoice_amounts
        CHECK (
            subtotal_amount >= 0.00
            AND tax_amount >= 0.00
            AND total_amount = (subtotal_amount + tax_amount)
        ),

    CONSTRAINT ck_invoice_currency
        CHECK (currency_code ~ '^[A-Z]{3}$'),

    CONSTRAINT ck_invoice_status
        CHECK (invoice_status IN ('draft', 'issued', 'paid', 'void', 'uncollectible'))
);

CREATE INDEX idx_invoice_org_status
    ON commercial.invoice (organization_id, invoice_status);

COMMENT ON TABLE commercial.invoice IS
    'Billing invoices with verifiable subtotal and tax amounts';


-- 5. Payment Refunds
CREATE TABLE commercial.payment_refund (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    payment_order_id BIGINT NOT NULL,
    refund_amount NUMERIC(14,2) NOT NULL,
    currency_code CHAR(3) NOT NULL DEFAULT 'USD',
    gateway_refund_ref VARCHAR(255) NOT NULL,
    refund_reason VARCHAR(500),
    refund_status VARCHAR(20) NOT NULL DEFAULT 'completed',
    processed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_payment_refund PRIMARY KEY (id),
    CONSTRAINT uq_payment_refund_gateway_ref UNIQUE (gateway_refund_ref),

    CONSTRAINT fk_payment_refund_order
        FOREIGN KEY (payment_order_id)
        REFERENCES commercial.payment_order (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT ck_payment_refund_amount
        CHECK (refund_amount > 0.00),

    CONSTRAINT ck_payment_refund_currency
        CHECK (currency_code ~ '^[A-Z]{3}$')
);

COMMENT ON TABLE commercial.payment_refund IS
    'Partial or full refunds referencing original payment orders';


-- 6. Organization Wallets
CREATE TABLE commercial.wallet (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    organization_id BIGINT NOT NULL,
    balance NUMERIC(14,2) NOT NULL DEFAULT 0.00,
    currency_code CHAR(3) NOT NULL DEFAULT 'USD',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_wallet PRIMARY KEY (id),
    CONSTRAINT uq_wallet_org_currency UNIQUE (organization_id, currency_code),

    CONSTRAINT fk_wallet_organization
        FOREIGN KEY (organization_id)
        REFERENCES recruitment.organization (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT ck_wallet_balance
        CHECK (balance >= 0.00),

    CONSTRAINT ck_wallet_currency
        CHECK (currency_code ~ '^[A-Z]{3}$')
);

CREATE INDEX idx_wallet_org
    ON commercial.wallet (organization_id);

COMMENT ON TABLE commercial.wallet IS
    'Prepaid credit wallet held by organizations for postings, downloads, and outreach';


-- 7. Strictly Append-Only Wallet Ledger (Rule Group 10)
CREATE TABLE commercial.wallet_ledger (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    wallet_id BIGINT NOT NULL,
    entry_type VARCHAR(20) NOT NULL,
    amount NUMERIC(14,2) NOT NULL,
    currency_code CHAR(3) NOT NULL DEFAULT 'USD',
    balance_after NUMERIC(14,2) NOT NULL,
    reference_type VARCHAR(40) NOT NULL,
    reference_id BIGINT,
    correction_of_ledger_id BIGINT,
    notes VARCHAR(500),
    created_by_user_account_id BIGINT NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_wallet_ledger PRIMARY KEY (id),

    CONSTRAINT fk_wallet_ledger_wallet
        FOREIGN KEY (wallet_id)
        REFERENCES commercial.wallet (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT fk_wallet_ledger_correction
        FOREIGN KEY (correction_of_ledger_id)
        REFERENCES commercial.wallet_ledger (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT fk_wallet_ledger_created_by
        FOREIGN KEY (created_by_user_account_id)
        REFERENCES core.user_account (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT ck_wallet_ledger_entry_type
        CHECK (
            entry_type IN (
                'credit',
                'debit',
                'correction_credit',
                'correction_debit'
            )
        ),

    CONSTRAINT ck_wallet_ledger_amount
        CHECK (amount > 0.00),

    CONSTRAINT ck_wallet_ledger_balance_after
        CHECK (balance_after >= 0.00),

    CONSTRAINT ck_wallet_ledger_currency
        CHECK (currency_code ~ '^[A-Z]{3}$'),

    CONSTRAINT ck_wallet_ledger_reference_type
        CHECK (
            reference_type IN (
                'recharge',
                'profile_download',
                'outreach_fee',
                'job_posting_fee',
                'gig_commission',
                'correction'
            )
        ),

    -- Rule Group 10: Corrections must explicitly reference the original ledger entry
    CONSTRAINT ck_wallet_ledger_correction_reference
        CHECK (
            (reference_type = 'correction' AND correction_of_ledger_id IS NOT NULL)
            OR
            (reference_type <> 'correction' AND correction_of_ledger_id IS NULL)
        )
);

CREATE INDEX idx_wallet_ledger_wallet_recorded
    ON commercial.wallet_ledger (wallet_id, recorded_at DESC);

CREATE INDEX idx_wallet_ledger_reference
    ON commercial.wallet_ledger (reference_type, reference_id);

COMMENT ON TABLE commercial.wallet_ledger IS
    'Strictly append-only financial ledger tracking credit and debit movements with explicit correction references';

-- Enforce append-only nature: forbid UPDATE and DELETE
CREATE OR REPLACE FUNCTION commercial.prevent_ledger_tampering()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'Financial ledger is strictly append-only: % operation forbidden on commercial.wallet_ledger', TG_OP;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_wallet_ledger_tampering ON commercial.wallet_ledger;
CREATE TRIGGER trg_prevent_wallet_ledger_tampering
BEFORE UPDATE OR DELETE ON commercial.wallet_ledger
FOR EACH ROW
EXECUTE FUNCTION commercial.prevent_ledger_tampering();


-- 8. Candidate Profile Download History (Rule Group 10 & Tier 1 Mandatory)
CREATE TABLE commercial.candidate_profile_download_history (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    organization_id BIGINT NOT NULL,
    downloader_user_account_id BIGINT NOT NULL,
    candidate_profile_id BIGINT NOT NULL,
    credit_deduction_amount NUMERIC(14,2) NOT NULL DEFAULT 0.00,
    currency_code CHAR(3) NOT NULL DEFAULT 'USD',
    wallet_ledger_id BIGINT,
    downloaded_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_candidate_profile_download_history PRIMARY KEY (id),

    CONSTRAINT fk_profile_download_org
        FOREIGN KEY (organization_id)
        REFERENCES recruitment.organization (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT fk_profile_download_user
        FOREIGN KEY (downloader_user_account_id)
        REFERENCES core.user_account (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT fk_profile_download_candidate
        FOREIGN KEY (candidate_profile_id)
        REFERENCES profile.candidate_profile (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT fk_profile_download_ledger
        FOREIGN KEY (wallet_ledger_id)
        REFERENCES commercial.wallet_ledger (id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,

    CONSTRAINT ck_profile_download_amount
        CHECK (credit_deduction_amount >= 0.00),

    CONSTRAINT ck_profile_download_currency
        CHECK (currency_code ~ '^[A-Z]{3}$')
);

CREATE INDEX idx_profile_download_org_downloaded
    ON commercial.candidate_profile_download_history (organization_id, downloaded_at DESC);

CREATE INDEX idx_profile_download_candidate
    ON commercial.candidate_profile_download_history (candidate_profile_id, downloaded_at DESC);

COMMENT ON TABLE commercial.candidate_profile_download_history IS
    'Append-only record of recruiters downloading candidate profiles with associated credit deductions';

-- Enforce append-only nature: forbid UPDATE and DELETE
CREATE OR REPLACE FUNCTION commercial.prevent_download_history_tampering()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'Download history is append-only: % operation forbidden on commercial.candidate_profile_download_history', TG_OP;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_download_history_tampering ON commercial.candidate_profile_download_history;
CREATE TRIGGER trg_prevent_download_history_tampering
BEFORE UPDATE OR DELETE ON commercial.candidate_profile_download_history
FOR EACH ROW
EXECUTE FUNCTION commercial.prevent_download_history_tampering();

COMMIT;
