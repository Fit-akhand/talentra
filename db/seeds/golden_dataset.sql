-- =============================================================================
-- Golden dataset (lifecycle step 14: "a golden dataset whose query answers are known in advance")
--
-- A small, hand-built database state with exactly known contents. tests/test_golden_kpis.py loads it
-- into an EMPTY scratch database, runs every KPI in db/kpi/ and compares the result with
-- tests/golden_kpi_expected.json. If a KPI query is wrong, the expected number does not appear.
--
-- Do not load this into a database that holds other data: the KPI answers assume nothing else exists.
-- All dates are fixed so the answers never change.
-- =============================================================================
DO $golden$
DECLARE
    v_ua BIGINT; v_ra BIGINT; v_ub BIGINT; v_rb BIGINT;
    v_c1 BIGINT; v_c2 BIGINT; v_c3 BIGINT; v_c4 BIGINT; v_c5 BIGINT;
    v_cons BIGINT; v_dev BIGINT; v_w1 BIGINT; v_w2 BIGINT; v_w3 BIGINT;
    v_orgA BIGINT; v_orgB BIGINT;
    v_it BIGINT; v_fin BIGINT; v_emp BIGINT; v_work BIGINT; v_city BIGINT; v_skill BIGINT;
    v_j1 BIGINT; v_j2 BIGINT; v_j3 BIGINT;
    v_p1 BIGINT; v_p2 BIGINT; v_p3 BIGINT; v_p4 BIGINT; v_p5 BIGINT;
    v_a1 BIGINT; v_a2 BIGINT; v_a3 BIGINT; v_a4 BIGINT; v_a5 BIGINT; v_a6 BIGINT;
    v_walletA BIGINT; v_walletB BIGINT; v_debit BIGINT;
    v_gw1 BIGINT; v_gw2 BIGINT; v_gw3 BIGINT;
    v_g_open BIGINT; v_g_awarded BIGINT; v_g_done1 BIGINT; v_g_done2 BIGINT; v_g_cancel BIGINT; v_g_prog BIGINT;
    v_ga1 BIGINT; v_ga2 BIGINT; v_ga3 BIGINT; v_as1 BIGINT; v_as2 BIGINT; v_as3 BIGINT;
    v_req BIGINT; v_batch BIGINT;
BEGIN
    -- ------------------------------------------------------------------ people
    INSERT INTO core.user_account (email) VALUES ('golden-employer-a@example.com') RETURNING id INTO v_ua;
    INSERT INTO core.user_account (email) VALUES ('golden-recruiter-a@example.com') RETURNING id INTO v_ra;
    INSERT INTO core.user_account (email) VALUES ('golden-employer-b@example.com') RETURNING id INTO v_ub;
    INSERT INTO core.user_account (email) VALUES ('golden-recruiter-b@example.com') RETURNING id INTO v_rb;
    INSERT INTO core.user_account (email) VALUES ('golden-cand-1@example.com') RETURNING id INTO v_c1;
    INSERT INTO core.user_account (email) VALUES ('golden-cand-2@example.com') RETURNING id INTO v_c2;
    INSERT INTO core.user_account (email) VALUES ('golden-cand-3@example.com') RETURNING id INTO v_c3;
    INSERT INTO core.user_account (email) VALUES ('golden-cand-4@example.com') RETURNING id INTO v_c4;
    INSERT INTO core.user_account (email) VALUES ('golden-cand-5@example.com') RETURNING id INTO v_c5;
    INSERT INTO core.user_account (email) VALUES ('golden-consultant@example.com') RETURNING id INTO v_cons;
    INSERT INTO core.user_account (email) VALUES ('golden-device-user@example.com') RETURNING id INTO v_dev;
    INSERT INTO core.user_account (email) VALUES ('golden-gig-1@example.com') RETURNING id INTO v_w1;
    INSERT INTO core.user_account (email) VALUES ('golden-gig-2@example.com') RETURNING id INTO v_w2;
    INSERT INTO core.user_account (email) VALUES ('golden-gig-3@example.com') RETURNING id INTO v_w3;

    SELECT id INTO v_it  FROM master.industry WHERE name = 'Information Technology';
    SELECT id INTO v_fin FROM master.industry WHERE name = 'Finance and Banking';
    SELECT id INTO v_emp FROM master.employment_type WHERE code = 'full_time';
    SELECT id INTO v_work FROM master.work_type WHERE code = 'remote';
    SELECT id INTO v_skill FROM master.skill WHERE normalized_name = 'postgresql';
    INSERT INTO master.country (iso_alpha2, iso_alpha3, name) VALUES ('GD', 'GLD', 'Goldenland') ON CONFLICT DO NOTHING;
    INSERT INTO master.state (country_id, name, subdivision_code)
        SELECT id, 'Golden State', 'GD-01' FROM master.country WHERE iso_alpha2 = 'GD';
    INSERT INTO master.city (state_id, name) SELECT id, 'Golden City' FROM master.state WHERE subdivision_code = 'GD-01' RETURNING id INTO v_city;

    -- ------------------------------------------------------------------ organisations and jobs
    INSERT INTO recruitment.organization (name, slug, created_by_user_account_id, organization_status)
    VALUES ('Golden Org A', 'golden-org-a', v_ua, 'active') RETURNING id INTO v_orgA;
    INSERT INTO recruitment.organization (name, slug, created_by_user_account_id, organization_status)
    VALUES ('Golden Org B', 'golden-org-b', v_ub, 'active') RETURNING id INTO v_orgB;

    INSERT INTO recruitment.job_posting (organization_id, created_by_user_account_id, employment_type_id, work_type_id, industry_id, title, description, job_status, published_at)
    VALUES (v_orgA, v_ra, v_emp, v_work, v_it, 'Golden IT job', 'd', 'published', '2025-12-15 00:00:00+00') RETURNING id INTO v_j1;
    INSERT INTO recruitment.job_posting (organization_id, created_by_user_account_id, employment_type_id, work_type_id, industry_id, title, description, job_status, published_at)
    VALUES (v_orgB, v_rb, v_emp, v_work, v_fin, 'Golden finance job', 'd', 'published', '2026-01-20 00:00:00+00') RETURNING id INTO v_j2;
    INSERT INTO recruitment.job_posting (organization_id, created_by_user_account_id, employment_type_id, work_type_id, industry_id, title, description)
    VALUES (v_orgA, v_ra, v_emp, v_work, v_it, 'Golden draft job', 'd') RETURNING id INTO v_j3;

    -- ------------------------------------------------------------------ candidates (completeness 100, 100, 100, 50, 75)
    INSERT INTO profile.candidate_profile (user_account_id, headline, professional_summary) VALUES (v_c1, 'H1', 'S1') RETURNING id INTO v_p1;
    INSERT INTO profile.candidate_profile (user_account_id, headline, professional_summary) VALUES (v_c2, 'H2', 'S2') RETURNING id INTO v_p2;
    INSERT INTO profile.candidate_profile (user_account_id, headline, professional_summary) VALUES (v_c3, 'H3', 'S3') RETURNING id INTO v_p3;
    INSERT INTO profile.candidate_profile (user_account_id, headline, professional_summary) VALUES (v_c4, 'H4', NULL) RETURNING id INTO v_p4;
    INSERT INTO profile.candidate_profile (user_account_id, headline, professional_summary) VALUES (v_c5, 'H5', 'S5') RETURNING id INTO v_p5;
    INSERT INTO profile.candidate_location (candidate_profile_id, city_id, location_type) VALUES (v_p1, v_city, 'current'), (v_p2, v_city, 'current'), (v_p3, v_city, 'current');
    INSERT INTO profile.candidate_skill (candidate_profile_id, skill_id, proficiency_level, experience_years, is_primary)
    SELECT p, v_skill, 'intermediate', 3.0, TRUE FROM unnest(ARRAY[v_p1, v_p2, v_p3, v_p4, v_p5]) AS p;

    -- ------------------------------------------------------------------ applications with exact histories
    -- Triggers are off for these inserts: the history carries fixed dates, which the history trigger (it stamps "now") cannot give.
    ALTER TABLE recruitment.candidate_application DISABLE TRIGGER USER;
    INSERT INTO recruitment.candidate_application (candidate_profile_id, job_posting_id, application_status, applied_at, last_status_changed_at, created_by_user_account_id, updated_by_user_account_id)
    VALUES (v_p1, v_j1, 'joined',    '2026-01-01 00:00:00+00', '2026-01-21 00:00:00+00', v_c1, v_c1) RETURNING id INTO v_a1;
    INSERT INTO recruitment.candidate_application (candidate_profile_id, job_posting_id, application_status, applied_at, last_status_changed_at, created_by_user_account_id, updated_by_user_account_id)
    VALUES (v_p2, v_j1, 'rejected',  '2026-01-02 00:00:00+00', '2026-01-06 00:00:00+00', v_c2, v_c2) RETURNING id INTO v_a2;
    INSERT INTO recruitment.candidate_application (candidate_profile_id, job_posting_id, application_status, applied_at, last_status_changed_at, created_by_user_account_id, updated_by_user_account_id)
    VALUES (v_p3, v_j1, 'applied',   '2026-01-03 00:00:00+00', '2026-01-03 00:00:00+00', v_c3, v_c3) RETURNING id INTO v_a3;
    INSERT INTO recruitment.candidate_application (candidate_profile_id, job_posting_id, application_status, applied_at, last_status_changed_at, created_by_user_account_id, updated_by_user_account_id)
    VALUES (v_p4, v_j2, 'joined',    '2026-02-01 00:00:00+00', '2026-02-11 00:00:00+00', v_c4, v_c4) RETURNING id INTO v_a4;
    INSERT INTO recruitment.candidate_application (candidate_profile_id, job_posting_id, application_status, applied_at, last_status_changed_at, created_by_user_account_id, updated_by_user_account_id)
    VALUES (v_p5, v_j2, 'withdrawn', '2026-02-03 00:00:00+00', '2026-02-12 00:00:00+00', v_c5, v_c5) RETURNING id INTO v_a5;
    INSERT INTO recruitment.candidate_application (candidate_profile_id, job_posting_id, application_status, applied_at, last_status_changed_at, created_by_user_account_id, updated_by_user_account_id)
    VALUES (v_p1, v_j2, 'applied',   '2026-02-04 00:00:00+00', '2026-02-04 00:00:00+00', v_c1, v_c1) RETURNING id INTO v_a6;

    INSERT INTO recruitment.application_status_history (candidate_application_id, previous_status, new_status, changed_at) VALUES
        (v_a1, NULL, 'applied', '2026-01-01'), (v_a1, 'applied', 'shortlisted', '2026-01-03'), (v_a1, 'shortlisted', 'interviewed', '2026-01-08'),
        (v_a1, 'interviewed', 'offered', '2026-01-18'), (v_a1, 'offered', 'joined', '2026-01-21'),
        (v_a2, NULL, 'applied', '2026-01-02'), (v_a2, 'applied', 'shortlisted', '2026-01-04'), (v_a2, 'shortlisted', 'rejected', '2026-01-06'),
        (v_a3, NULL, 'applied', '2026-01-03'),
        (v_a4, NULL, 'applied', '2026-02-01'), (v_a4, 'applied', 'shortlisted', '2026-02-02'), (v_a4, 'shortlisted', 'interviewed', '2026-02-05'),
        (v_a4, 'interviewed', 'offered', '2026-02-08'), (v_a4, 'offered', 'joined', '2026-02-11'),
        (v_a5, NULL, 'applied', '2026-02-03'), (v_a5, 'applied', 'shortlisted', '2026-02-04'), (v_a5, 'shortlisted', 'interviewed', '2026-02-07'),
        (v_a5, 'interviewed', 'offered', '2026-02-10'), (v_a5, 'offered', 'withdrawn', '2026-02-12'),
        (v_a6, NULL, 'applied', '2026-02-04');
    ALTER TABLE recruitment.candidate_application ENABLE TRIGGER USER;

    -- ------------------------------------------------------------------ money: wallet A reconciles, wallet B does not (deliberately)
    INSERT INTO commercial.wallet (organization_id, balance, currency_code) VALUES (v_orgA, 990.00, 'USD') RETURNING id INTO v_walletA;
    INSERT INTO commercial.wallet (organization_id, balance, currency_code) VALUES (v_orgB, 500.00, 'USD') RETURNING id INTO v_walletB;
    INSERT INTO commercial.wallet_ledger (wallet_id, entry_type, amount, currency_code, balance_after, reference_type, created_by_user_account_id, recorded_at)
    VALUES (v_walletA, 'credit', 1000.00, 'USD', 1000.00, 'recharge', v_ua, '2026-03-01');
    INSERT INTO commercial.wallet_ledger (wallet_id, entry_type, amount, currency_code, balance_after, reference_type, created_by_user_account_id, recorded_at)
    VALUES (v_walletA, 'debit', 10.00, 'USD', 990.00, 'profile_download', v_ra, '2026-03-02') RETURNING id INTO v_debit;
    INSERT INTO commercial.wallet_ledger (wallet_id, entry_type, amount, currency_code, balance_after, reference_type, created_by_user_account_id, recorded_at)
    VALUES (v_walletB, 'credit', 400.00, 'USD', 400.00, 'recharge', v_ub, '2026-03-01');
    INSERT INTO commercial.candidate_profile_download_history (organization_id, downloader_user_account_id, candidate_profile_id, credit_deduction_amount, currency_code, wallet_ledger_id, downloaded_at)
    VALUES (v_orgA, v_ra, v_p1, 10.00, 'USD', v_debit, '2026-03-02');

    -- ------------------------------------------------------------------ gig: six requests, two completed with ratings 4 and 5
    INSERT INTO gig.gig_worker_profile (user_account_id, headline, hourly_rate, daily_rate, currency_code, is_available, verification_status) VALUES (v_w1, 'W1', 50, 400, 'USD', TRUE, 'verified') RETURNING id INTO v_gw1;
    INSERT INTO gig.gig_worker_profile (user_account_id, headline, hourly_rate, daily_rate, currency_code, is_available, verification_status) VALUES (v_w2, 'W2', 50, 400, 'USD', TRUE, 'verified') RETURNING id INTO v_gw2;
    INSERT INTO gig.gig_worker_profile (user_account_id, headline, hourly_rate, daily_rate, currency_code, is_available, verification_status) VALUES (v_w3, 'W3', 50, 400, 'USD', TRUE, 'verified') RETURNING id INTO v_gw3;
    INSERT INTO gig.gig_request (organization_id, created_by_user_account_id, title, description, deliverables, pricing_type, budget_amount, currency_code, start_date, end_date, request_status) VALUES (v_orgA, v_ua, 'G open', 'd', 'x', 'fixed', 1000, 'USD', '2026-12-01', '2026-12-10', 'open') RETURNING id INTO v_g_open;
    INSERT INTO gig.gig_request (organization_id, created_by_user_account_id, title, description, deliverables, pricing_type, budget_amount, currency_code, start_date, end_date, request_status) VALUES (v_orgA, v_ua, 'G awarded', 'd', 'x', 'fixed', 1000, 'USD', '2026-12-01', '2026-12-10', 'awarded') RETURNING id INTO v_g_awarded;
    INSERT INTO gig.gig_request (organization_id, created_by_user_account_id, title, description, deliverables, pricing_type, budget_amount, currency_code, start_date, end_date, request_status) VALUES (v_orgA, v_ua, 'G done 1', 'd', 'x', 'fixed', 1000, 'USD', '2026-03-01', '2026-03-10', 'completed') RETURNING id INTO v_g_done1;
    INSERT INTO gig.gig_request (organization_id, created_by_user_account_id, title, description, deliverables, pricing_type, budget_amount, currency_code, start_date, end_date, request_status) VALUES (v_orgA, v_ua, 'G done 2', 'd', 'x', 'fixed', 1000, 'USD', '2026-04-01', '2026-04-10', 'completed') RETURNING id INTO v_g_done2;
    INSERT INTO gig.gig_request (organization_id, created_by_user_account_id, title, description, deliverables, pricing_type, budget_amount, currency_code, start_date, end_date, request_status) VALUES (v_orgA, v_ua, 'G cancelled', 'd', 'x', 'fixed', 1000, 'USD', '2026-12-01', '2026-12-10', 'cancelled') RETURNING id INTO v_g_cancel;
    INSERT INTO gig.gig_request (organization_id, created_by_user_account_id, title, description, deliverables, pricing_type, budget_amount, currency_code, start_date, end_date, request_status) VALUES (v_orgA, v_ua, 'G in progress', 'd', 'x', 'fixed', 1000, 'USD', '2026-10-20', '2026-11-05', 'in_progress') RETURNING id INTO v_g_prog;
    INSERT INTO gig.gig_application (gig_request_id, gig_worker_profile_id, bid_amount, currency_code, proposed_duration_days, pitch, application_status, decided_at) VALUES (v_g_done1, v_gw1, 1000, 'USD', 10, 'p', 'accepted', '2026-02-20') RETURNING id INTO v_ga1;
    INSERT INTO gig.gig_application (gig_request_id, gig_worker_profile_id, bid_amount, currency_code, proposed_duration_days, pitch, application_status, decided_at) VALUES (v_g_done2, v_gw2, 1000, 'USD', 10, 'p', 'accepted', '2026-03-20') RETURNING id INTO v_ga2;
    INSERT INTO gig.gig_application (gig_request_id, gig_worker_profile_id, bid_amount, currency_code, proposed_duration_days, pitch, application_status, decided_at) VALUES (v_g_prog, v_gw3, 1000, 'USD', 10, 'p', 'accepted', '2026-10-10') RETURNING id INTO v_ga3;
    INSERT INTO gig.gig_assignment (gig_request_id, gig_application_id, gig_worker_profile_id, assigned_start_date, assigned_end_date, agreed_amount, currency_code, assignment_status, external_handoff_ref) VALUES (v_g_done1, v_ga1, v_gw1, '2026-03-01', '2026-03-10', 1000, 'USD', 'completed', 'GOLD-1') RETURNING id INTO v_as1;
    INSERT INTO gig.gig_assignment (gig_request_id, gig_application_id, gig_worker_profile_id, assigned_start_date, assigned_end_date, agreed_amount, currency_code, assignment_status, external_handoff_ref) VALUES (v_g_done2, v_ga2, v_gw2, '2026-04-01', '2026-04-10', 1000, 'USD', 'completed', 'GOLD-2') RETURNING id INTO v_as2;
    INSERT INTO gig.gig_assignment (gig_request_id, gig_application_id, gig_worker_profile_id, assigned_start_date, assigned_end_date, agreed_amount, currency_code, assignment_status, external_handoff_ref) VALUES (v_g_prog, v_ga3, v_gw3, '2026-10-20', '2026-11-05', 1000, 'USD', 'active', 'GOLD-3') RETURNING id INTO v_as3;
    INSERT INTO gig.gig_rating (gig_assignment_id, rater_user_account_id, rating_score, quality_score, communication_score) VALUES (v_as1, v_ua, 4.00, 4, 4), (v_as2, v_ua, 5.00, 5, 5);

    -- ------------------------------------------------------------------ messaging: 7 deliveries, 6 attempted, 4 delivered or read
    INSERT INTO messaging.notification_delivery (recipient_user_account_id, channel, subject, body_snippet, delivery_status, sent_at, delivered_at, read_at) VALUES
        (v_c1, 'email', 's', 'b', 'delivered', '2026-04-01 10:00:00+00', '2026-04-01 10:00:05+00', NULL),
        (v_c1, 'email', 's', 'b', 'delivered', '2026-04-01 10:00:00+00', '2026-04-01 10:00:05+00', NULL),
        (v_c1, 'email', 's', 'b', 'delivered', '2026-04-01 10:00:00+00', '2026-04-01 10:00:05+00', NULL),
        (v_c1, 'email', 's', 'b', 'read',      '2026-04-01 10:00:00+00', '2026-04-01 10:00:05+00', '2026-04-01 11:00:00+00'),
        (v_c1, 'email', 's', 'b', 'failed',    '2026-04-01 10:00:00+00', NULL, NULL),
        (v_c1, 'email', 's', 'b', 'sent',      '2026-04-01 10:00:00+00', NULL, NULL),
        (v_c1, 'email', 's', 'b', 'queued',    NULL, NULL, NULL);

    -- ------------------------------------------------------------------ sourcing: 4 submissions, 2 accepted or hired; 5 recipients, 2 responded
    INSERT INTO sourcing.job_consultant_policy (job_posting_id, is_open_to_consultants, max_consultants, bounty_amount, currency_code) VALUES (v_j1, TRUE, 3, 500, 'USD');
    INSERT INTO sourcing.consultant_sourcing_request (job_posting_id, consultant_user_account_id, request_status, decided_by_user_account_id, decided_at)
    VALUES (v_j1, v_cons, 'accepted', v_ra, '2026-01-02') RETURNING id INTO v_req;
    INSERT INTO sourcing.sourcing_submission (consultant_sourcing_request_id, job_posting_id, candidate_profile_id, submitted_by_user_account_id, submission_status) VALUES
        (v_req, v_j1, v_p1, v_cons, 'accepted'), (v_req, v_j1, v_p2, v_cons, 'hired'),
        (v_req, v_j1, v_p3, v_cons, 'rejected'), (v_req, v_j1, v_p4, v_cons, 'submitted');
    INSERT INTO sourcing.outreach_batch (organization_id, campaign_name, channel, subject, message_body, total_recipients, total_credits_deducted, status, completed_at, created_by_user_account_id)
    VALUES (v_orgA, 'Golden campaign', 'email', 's', 'm', 5, 2.50, 'completed', '2026-05-01', v_ra) RETURNING id INTO v_batch;
    INSERT INTO sourcing.outreach_recipient (outreach_batch_id, candidate_profile_id, delivery_status, sent_at, delivered_at, response_recorded_at) VALUES
        (v_batch, v_p1, 'responded', '2026-05-01', '2026-05-01', '2026-05-02'), (v_batch, v_p2, 'responded', '2026-05-01', '2026-05-01', '2026-05-03'),
        (v_batch, v_p3, 'delivered', '2026-05-01', '2026-05-01', NULL), (v_batch, v_p4, 'sent', '2026-05-01', NULL, NULL),
        (v_batch, v_p5, 'bounced', '2026-05-01', NULL, NULL);

    -- ------------------------------------------------------------------ support: 3 open-ish tickets (2 high, 1 low), 1 closed
    INSERT INTO messaging.support_ticket (ticket_number, requester_user_account_id, category, subject, priority, ticket_status) VALUES
        ('TCK-G1', v_c1, 'account', 's', 'high', 'open'), ('TCK-G2', v_c1, 'billing', 's', 'low', 'open'),
        ('TCK-G3', v_c1, 'technical', 's', 'high', 'in_progress'), ('TCK-G4', v_c1, 'other', 's', 'low', 'closed');

    -- ------------------------------------------------------------------ devices: the default limit is 2, so the third login is refused and audited once
    PERFORM core.create_session_with_device_limit(v_dev, 'golden-d1', encode(sha256('golden-1'::bytea), 'hex'));
    PERFORM core.create_session_with_device_limit(v_dev, 'golden-d2', encode(sha256('golden-2'::bytea), 'hex'));
    PERFORM core.create_session_with_device_limit(v_dev, 'golden-d3', encode(sha256('golden-3'::bytea), 'hex'));
END
$golden$;

CALL analytics.refresh_reporting_marts();
