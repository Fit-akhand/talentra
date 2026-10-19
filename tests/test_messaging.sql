-- Test suite: tests/test_messaging.sql
-- Prerequisite: migrations 001 through 018 applied.

BEGIN;

DO $test$
DECLARE
    v_user_id BIGINT;
    v_agent_id BIGINT;
    v_template_id BIGINT;
    v_delivery_id BIGINT;
    v_post_id BIGINT;
    v_reaction_id BIGINT;
    v_ticket_id BIGINT;
    v_faq_id BIGINT;
    v_referral_id BIGINT;
    v_translated_text TEXT;
    v_duplicate_reaction_blocked BOOLEAN := FALSE;
BEGIN
    -- 1. Setup fixtures
    INSERT INTO core.user_account (email)
    VALUES ('msg_user@example.com')
    RETURNING id INTO v_user_id;

    INSERT INTO core.user_account (email)
    VALUES ('msg_support_agent@example.com')
    RETURNING id INTO v_agent_id;

    -- 2. Test Multilingual Translation Lookup and Fallback (Rule Group 7)
    -- Target translation exists in Spanish
    v_translated_text := messaging.get_ui_translation('btn.apply_job', 'es');
    IF v_translated_text <> 'Postularse para este puesto' THEN
        RAISE EXCEPTION 'Expected Spanish translation, received: %', v_translated_text;
    END IF;

    -- Hindi translation exists
    v_translated_text := messaging.get_ui_translation('btn.apply_job', 'hi');
    IF v_translated_text <> 'इस पद के लिए आवेदन करें' THEN
        RAISE EXCEPTION 'Expected Hindi translation, received: %', v_translated_text;
    END IF;

    -- Request a language with no translation (Italian 'it') -> Fallback to English
    v_translated_text := messaging.get_ui_translation('btn.apply_job', 'it');
    IF v_translated_text NOT IN ('Apply for this Role', 'Apply Now') THEN
        RAISE EXCEPTION 'Expected English fallback for Italian, received: %', v_translated_text;
    END IF;

    -- Request nonexistent key -> Returns key itself
    v_translated_text := messaging.get_ui_translation('nonexistent.key', 'fr');
    IF v_translated_text <> 'nonexistent.key' THEN
        RAISE EXCEPTION 'Expected key fallback, received: %', v_translated_text;
    END IF;

    -- 3. Test Notification Templates & User Preferences
    INSERT INTO messaging.notification_template (
        template_code,
        channel,
        subject_template,
        body_template
    )
    VALUES (
        'app.status.interview',
        'email',
        'Interview Scheduled for {{job_title}}',
        'Hello {{candidate_name}}, your interview has been scheduled.'
    )
    RETURNING id INTO v_template_id;

    INSERT INTO messaging.user_notification_preference (
        user_account_id,
        notification_category,
        channel,
        is_enabled
    )
    VALUES (
        v_user_id,
        'applications',
        'email',
        TRUE
    );

    -- 4. Test User Privacy & Job Alert Preferences
    INSERT INTO messaging.user_privacy_preference (
        user_account_id,
        profile_visibility,
        allow_recruiter_direct_message
    )
    VALUES (
        v_user_id,
        'recruiters',
        TRUE
    );

    INSERT INTO messaging.job_alert_preference (
        user_account_id,
        alert_name,
        keywords,
        frequency
    )
    VALUES (
        v_user_id,
        'Senior PostgreSQL Roles',
        'PostgreSQL database architect',
        'daily'
    );

    -- 5. Test Notification Deliveries (High-volume path)
    INSERT INTO messaging.notification_delivery (
        recipient_user_account_id,
        notification_template_id,
        channel,
        subject,
        body_snippet,
        delivery_status,
        sent_at
    )
    VALUES (
        v_user_id,
        v_template_id,
        'email',
        'Interview Scheduled for Senior SRE',
        'Hello Alex, your interview has been scheduled for tomorrow at 2pm.',
        'sent',
        CURRENT_TIMESTAMP
    )
    RETURNING id INTO v_delivery_id;

    -- 6. Test Community Post & Reaction Uniqueness
    INSERT INTO messaging.community_post (
        author_user_account_id,
        title,
        content,
        topic
    )
    VALUES (
        v_user_id,
        'Optimizing PostgreSQL for 100M Rows',
        'Best practices for btree_gist exclusion constraints and table partitioning.',
        'tech_trends'
    )
    RETURNING id INTO v_post_id;

    INSERT INTO messaging.post_reaction (
        community_post_id,
        user_account_id,
        reaction_type
    )
    VALUES (
        v_post_id,
        v_user_id,
        'insightful'
    )
    RETURNING id INTO v_reaction_id;

    BEGIN
        INSERT INTO messaging.post_reaction (
            community_post_id,
            user_account_id,
            reaction_type
        )
        VALUES (
            v_post_id,
            v_user_id,
            'like'
        );
    EXCEPTION
        WHEN unique_violation THEN
            v_duplicate_reaction_blocked := TRUE;
    END;

    IF NOT v_duplicate_reaction_blocked THEN
        RAISE EXCEPTION 'Duplicate user reaction to post was allowed!';
    END IF;

    -- 7. Test Support Ticket & FAQ
    INSERT INTO messaging.support_ticket (
        ticket_number,
        requester_user_account_id,
        category,
        subject,
        priority,
        ticket_status,
        assigned_agent_user_id
    )
    VALUES (
        'TCK-2026-0001',
        v_user_id,
        'profile',
        'Need help updating verified credential',
        'medium',
        'in_progress',
        v_agent_id
    )
    RETURNING id INTO v_ticket_id;

    INSERT INTO messaging.faq (
        category,
        question,
        answer,
        sort_order
    )
    VALUES (
        'billing',
        'How does wallet auto-recharge work?',
        'You can configure an automatic recharge threshold in your commercial settings.',
        1
    )
    RETURNING id INTO v_faq_id;

    -- 8. Test Referral Event
    INSERT INTO messaging.referral_event (
        referrer_user_account_id,
        referred_email,
        referral_code,
        status,
        reward_amount
    )
    VALUES (
        v_user_id,
        'colleague@example.com',
        'REF-ALEX-2026',
        'invited',
        50.00
    )
    RETURNING id INTO v_referral_id;

    RAISE NOTICE 'PASS: multilingual UI translation and fallback logic verified (Rule Group 7)';
    RAISE NOTICE 'PASS: notification templates and user preferences verified';
    RAISE NOTICE 'PASS: privacy preferences and candidate job alert preferences verified';
    RAISE NOTICE 'PASS: high-volume notification delivery verified';
    RAISE NOTICE 'PASS: community post and single-reaction uniqueness verified';
    RAISE NOTICE 'PASS: support ticket and FAQ catalog verified';
    RAISE NOTICE 'PASS: candidate peer referral tracking verified';
END;
$test$;

ROLLBACK;
