-- Migration: 018_create_messaging_and_translations.sql
-- Purpose: Implement multilingual UI translations with fallback, notification templates, preferences, high-volume delivery tracking, community posts/reactions, support tickets, FAQs, and referrals.
-- Requires: 001_create_schemas.sql, 002_create_identity.sql, 003_create_master_data.sql, 010_create_candidate_extensions.sql
-- Engine: PostgreSQL 17

BEGIN;

-- 1. Multilingual UI Translations (Rule Group 7)
CREATE TABLE messaging.ui_translation (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    string_key VARCHAR(150) NOT NULL,
    language_code VARCHAR(10) NOT NULL,
    translated_text TEXT NOT NULL,
    is_verified BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_ui_translation PRIMARY KEY (id),
    CONSTRAINT uq_ui_translation_key_lang UNIQUE (string_key, language_code),

    CONSTRAINT fk_ui_translation_language
        FOREIGN KEY (language_code)
        REFERENCES master.language (code)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT ck_ui_translation_key
        CHECK (string_key ~ '^[a-z][a-z0-9_.]+[a-z0-9]$'),

    CONSTRAINT ck_ui_translation_text
        CHECK (LENGTH(BTRIM(translated_text)) > 0)
);

CREATE INDEX idx_ui_translation_key
    ON messaging.ui_translation (string_key);

COMMENT ON TABLE messaging.ui_translation IS
    'Multilingual UI strings by key and ISO language code';

-- Seed foundational UI translations
INSERT INTO messaging.ui_translation (string_key, language_code, translated_text)
VALUES
    ('btn.apply_job',       'en', 'Apply for this Role'),
    ('btn.apply_job',       'es', 'Postularse para este puesto'),
    ('btn.apply_job',       'hi', 'इस पद के लिए आवेदन करें'),
    ('btn.apply_job',       'fr', 'Postuler pour ce poste'),
    ('nav.job_search',      'en', 'Find Opportunities'),
    ('nav.job_search',      'es', 'Buscar Oportunidades'),
    ('nav.job_search',      'hi', 'अवसर खोजें'),
    ('label.welcome_back',  'en', 'Welcome back to Talentra'),
    ('label.welcome_back',  'es', 'Bienvenido de nuevo a Talentra'),
    ('label.welcome_back',  'hi', 'टैलेंट्रा में आपका स्वागत है')
ON CONFLICT (string_key, language_code) DO NOTHING;

-- Translation retrieval function with fallback (Rule Group 7)
CREATE OR REPLACE FUNCTION messaging.get_ui_translation(
    p_key VARCHAR(150),
    p_language_code VARCHAR(10) DEFAULT 'en'
)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_translation TEXT;
BEGIN
    -- 1. Try target language
    SELECT translated_text INTO v_translation
    FROM messaging.ui_translation
    WHERE string_key = p_key
      AND language_code = p_language_code;

    IF v_translation IS NOT NULL THEN
        RETURN v_translation;
    END IF;

    -- 2. Fallback to English default
    IF p_language_code <> 'en' THEN
        SELECT translated_text INTO v_translation
        FROM messaging.ui_translation
        WHERE string_key = p_key
          AND language_code = 'en';

        IF v_translation IS NOT NULL THEN
            RETURN v_translation;
        END IF;
    END IF;

    -- 3. Return key as final fallback
    RETURN p_key;
END;
$$;


-- 2. Notification Templates
CREATE TABLE messaging.notification_template (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    template_code VARCHAR(80) NOT NULL,
    channel VARCHAR(20) NOT NULL DEFAULT 'in_app',
    default_language_code VARCHAR(10) NOT NULL DEFAULT 'en',
    subject_template VARCHAR(255),
    body_template TEXT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_notification_template PRIMARY KEY (id),
    CONSTRAINT uq_notification_template_code UNIQUE (template_code),

    CONSTRAINT ck_notification_template_channel
        CHECK (channel IN ('in_app', 'email', 'sms', 'whatsapp', 'push')),

    CONSTRAINT ck_notification_template_body
        CHECK (LENGTH(BTRIM(body_template)) > 0)
);

COMMENT ON TABLE messaging.notification_template IS
    'Reusable templates for email, SMS, push, and in-app notifications';


-- 3. User Notification Preferences
CREATE TABLE messaging.user_notification_preference (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    user_account_id BIGINT NOT NULL,
    notification_category VARCHAR(40) NOT NULL,
    channel VARCHAR(20) NOT NULL,
    is_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_user_notification_preference PRIMARY KEY (id),
    CONSTRAINT uq_user_notification_pref
        UNIQUE (user_account_id, notification_category, channel),

    CONSTRAINT fk_user_notif_pref_user
        FOREIGN KEY (user_account_id)
        REFERENCES core.user_account (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT ck_user_notif_pref_category
        CHECK (
            notification_category IN (
                'applications',
                'job_alerts',
                'gig_opportunities',
                'marketing',
                'security_alerts'
            )
        ),

    CONSTRAINT ck_user_notif_pref_channel
        CHECK (channel IN ('in_app', 'email', 'sms', 'whatsapp', 'push'))
);

CREATE INDEX idx_user_notif_pref_user
    ON messaging.user_notification_preference (user_account_id);

COMMENT ON TABLE messaging.user_notification_preference IS
    'Granular delivery channel toggles configured by users per notification category';


-- 4. User Privacy Preferences
CREATE TABLE messaging.user_privacy_preference (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    user_account_id BIGINT NOT NULL,
    profile_visibility VARCHAR(20) NOT NULL DEFAULT 'recruiters',
    allow_recruiter_direct_message BOOLEAN NOT NULL DEFAULT TRUE,
    show_salary_expectations BOOLEAN NOT NULL DEFAULT FALSE,
    show_current_employer BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_user_privacy_preference PRIMARY KEY (id),
    CONSTRAINT uq_user_privacy_pref UNIQUE (user_account_id),

    CONSTRAINT fk_user_privacy_pref_user
        FOREIGN KEY (user_account_id)
        REFERENCES core.user_account (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT ck_user_privacy_pref_visibility
        CHECK (profile_visibility IN ('private', 'recruiters', 'public'))
);

COMMENT ON TABLE messaging.user_privacy_preference IS
    'Candidate privacy and confidentiality controls';


-- 5. Candidate Job Alert Preferences
CREATE TABLE messaging.job_alert_preference (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    user_account_id BIGINT NOT NULL,
    alert_name VARCHAR(100) NOT NULL,
    keywords VARCHAR(255),
    job_role_id BIGINT,
    city_id BIGINT,
    work_type_id BIGINT,
    minimum_salary NUMERIC(14,2),
    frequency VARCHAR(20) NOT NULL DEFAULT 'daily',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    last_dispatched_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_job_alert_preference PRIMARY KEY (id),

    CONSTRAINT fk_job_alert_pref_user
        FOREIGN KEY (user_account_id)
        REFERENCES core.user_account (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT fk_job_alert_pref_role
        FOREIGN KEY (job_role_id)
        REFERENCES master.job_role (id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,

    CONSTRAINT fk_job_alert_pref_city
        FOREIGN KEY (city_id)
        REFERENCES master.city (id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,

    CONSTRAINT fk_job_alert_pref_work_type
        FOREIGN KEY (work_type_id)
        REFERENCES master.work_type (id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,

    CONSTRAINT ck_job_alert_pref_freq
        CHECK (frequency IN ('instant', 'daily', 'weekly')),

    CONSTRAINT ck_job_alert_pref_salary
        CHECK (minimum_salary IS NULL OR minimum_salary >= 0.00)
);

CREATE INDEX idx_job_alert_pref_active_freq
    ON messaging.job_alert_preference (is_active, frequency);

COMMENT ON TABLE messaging.job_alert_preference IS
    'Candidate saved job searches and notification alert frequencies';


-- 6. Notification Deliveries (High-Volume Write Path, Milestone 18 / B57)
CREATE TABLE messaging.notification_delivery (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    recipient_user_account_id BIGINT NOT NULL,
    notification_template_id BIGINT,
    channel VARCHAR(20) NOT NULL DEFAULT 'in_app',
    subject VARCHAR(255),
    body_snippet VARCHAR(500),
    external_provider_message_id VARCHAR(255),
    delivery_status VARCHAR(20) NOT NULL DEFAULT 'queued',
    sent_at TIMESTAMPTZ,
    delivered_at TIMESTAMPTZ,
    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_notification_delivery PRIMARY KEY (id),

    CONSTRAINT fk_notification_delivery_recipient
        FOREIGN KEY (recipient_user_account_id)
        REFERENCES core.user_account (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT fk_notification_delivery_template
        FOREIGN KEY (notification_template_id)
        REFERENCES messaging.notification_template (id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,

    CONSTRAINT ck_notification_delivery_channel
        CHECK (channel IN ('in_app', 'email', 'sms', 'whatsapp', 'push')),

    CONSTRAINT ck_notification_delivery_status
        CHECK (delivery_status IN ('queued', 'sent', 'delivered', 'failed', 'read'))
);

CREATE INDEX idx_notification_delivery_recipient_status
    ON messaging.notification_delivery (recipient_user_account_id, delivery_status, created_at DESC);

CREATE INDEX idx_notification_delivery_channel_created
    ON messaging.notification_delivery (channel, created_at DESC);

COMMENT ON TABLE messaging.notification_delivery IS
    'High-volume record of notification deliveries across all external and internal channels';


-- 7. Community Posts & Reactions (Tier 2 Expected)
CREATE TABLE messaging.community_post (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    author_user_account_id BIGINT NOT NULL,
    title VARCHAR(200) NOT NULL,
    content TEXT NOT NULL,
    topic VARCHAR(50) NOT NULL DEFAULT 'general',
    likes_count INTEGER NOT NULL DEFAULT 0,
    is_pinned BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_community_post PRIMARY KEY (id),

    CONSTRAINT fk_community_post_author
        FOREIGN KEY (author_user_account_id)
        REFERENCES core.user_account (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT ck_community_post_title
        CHECK (LENGTH(BTRIM(title)) BETWEEN 1 AND 200),

    CONSTRAINT ck_community_post_content
        CHECK (LENGTH(BTRIM(content)) > 0),

    CONSTRAINT ck_community_post_likes
        CHECK (likes_count >= 0)
);

CREATE INDEX idx_community_post_topic_created
    ON messaging.community_post (topic, created_at DESC);

COMMENT ON TABLE messaging.community_post IS
    'Developer and job seeker community discussion posts';

CREATE TABLE messaging.post_reaction (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    community_post_id BIGINT NOT NULL,
    user_account_id BIGINT NOT NULL,
    reaction_type VARCHAR(20) NOT NULL DEFAULT 'like',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_post_reaction PRIMARY KEY (id),
    CONSTRAINT uq_post_reaction_user UNIQUE (community_post_id, user_account_id),

    CONSTRAINT fk_post_reaction_post
        FOREIGN KEY (community_post_id)
        REFERENCES messaging.community_post (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT fk_post_reaction_user
        FOREIGN KEY (user_account_id)
        REFERENCES core.user_account (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT ck_post_reaction_type
        CHECK (reaction_type IN ('like', 'celebrate', 'support', 'insightful'))
);

COMMENT ON TABLE messaging.post_reaction IS
    'User reactions to community posts';


-- 8. Support Tickets and Helpdesk
CREATE TABLE messaging.support_ticket (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    ticket_number VARCHAR(50) NOT NULL,
    requester_user_account_id BIGINT NOT NULL,
    category VARCHAR(40) NOT NULL,
    subject VARCHAR(200) NOT NULL,
    priority VARCHAR(20) NOT NULL DEFAULT 'medium',
    ticket_status VARCHAR(20) NOT NULL DEFAULT 'open',
    assigned_agent_user_id BIGINT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_support_ticket PRIMARY KEY (id),
    CONSTRAINT uq_support_ticket_number UNIQUE (ticket_number),

    CONSTRAINT fk_support_ticket_requester
        FOREIGN KEY (requester_user_account_id)
        REFERENCES core.user_account (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT fk_support_ticket_agent
        FOREIGN KEY (assigned_agent_user_id)
        REFERENCES core.user_account (id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,

    CONSTRAINT ck_support_ticket_priority
        CHECK (priority IN ('low', 'medium', 'high', 'urgent')),

    CONSTRAINT ck_support_ticket_status
        CHECK (ticket_status IN ('open', 'in_progress', 'waiting_on_user', 'resolved', 'closed'))
);

CREATE INDEX idx_support_ticket_requester
    ON messaging.support_ticket (requester_user_account_id, ticket_status);

COMMENT ON TABLE messaging.support_ticket IS
    'Helpdesk support tickets logged by platform candidates or employers';


-- 9. Frequently Asked Questions (FAQ) Catalogue
CREATE TABLE messaging.faq (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    category VARCHAR(50) NOT NULL,
    question TEXT NOT NULL,
    answer TEXT NOT NULL,
    sort_order INTEGER NOT NULL DEFAULT 1,
    is_published BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_faq PRIMARY KEY (id),
    CONSTRAINT ck_faq_sort CHECK (sort_order >= 0)
);

CREATE INDEX idx_faq_category_sort
    ON messaging.faq (category, sort_order ASC);

COMMENT ON TABLE messaging.faq IS
    'Self-service frequently asked questions';


-- 10. Referral Tracking
CREATE TABLE messaging.referral_event (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    referrer_user_account_id BIGINT NOT NULL,
    referred_email VARCHAR(254) NOT NULL,
    referral_code VARCHAR(50) NOT NULL,
    referred_user_account_id BIGINT,
    status VARCHAR(20) NOT NULL DEFAULT 'invited',
    reward_amount NUMERIC(14,2) DEFAULT 0.00,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    qualified_at TIMESTAMPTZ,

    CONSTRAINT pk_referral_event PRIMARY KEY (id),

    CONSTRAINT fk_referral_event_referrer
        FOREIGN KEY (referrer_user_account_id)
        REFERENCES core.user_account (id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE,

    CONSTRAINT fk_referral_event_referred
        FOREIGN KEY (referred_user_account_id)
        REFERENCES core.user_account (id)
        ON UPDATE RESTRICT
        ON DELETE SET NULL,

    CONSTRAINT ck_referral_event_email
        CHECK (referred_email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'),

    CONSTRAINT ck_referral_event_status
        CHECK (status IN ('invited', 'registered', 'qualified_hire', 'reward_paid')),

    CONSTRAINT ck_referral_event_reward
        CHECK (reward_amount >= 0.00)
);

CREATE INDEX idx_referral_event_referrer
    ON messaging.referral_event (referrer_user_account_id);

COMMENT ON TABLE messaging.referral_event IS
    'Candidate and recruiter peer referral invitations and compensation tracking';

COMMIT;
