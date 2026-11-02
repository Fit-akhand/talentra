-- 039: index the foreign keys that something looks up by, or that a parent delete has to check.
-- Found by scripts/lifecycle/gen_quality_scorecard.py (check 5). Not indexed on purpose (DEC-33):
--   * audit actor columns (created_by, updated_by, deleted_by, changed_by, decided_by, verified_by, allocated_by, submitted_by, impersonator):
--     user accounts are never hard-deleted (erasure anonymises them), so nothing checks these columns, and an index on every table costs a write each time;
--   * references to master data (reference rows are never deleted);
--   * the analytics star schema (reloaded wholesale and queried through the materialised views).
-- A nullable foreign key gets a partial index that skips the NULLs.

BEGIN;

DO $$
DECLARE
    r RECORD;
    v_null BOOLEAN;
BEGIN
    FOR r IN SELECT * FROM (VALUES
        ('commercial', 'invoice', 'payment_order_id'),
        ('commercial', 'payment_refund', 'payment_order_id'),
        ('commercial', 'payment_order', 'user_account_id'),
        ('commercial', 'subscription', 'subscription_plan_id'),
        ('commercial', 'wallet_ledger', 'correction_of_ledger_id'),
        ('commercial', 'candidate_profile_download_history', 'wallet_ledger_id'),
        ('commercial', 'candidate_profile_download_history', 'downloader_user_account_id'),
        ('gig', 'gig_worker_preference', 'gig_worker_profile_id'),
        ('gig', 'gig_rating', 'rater_user_account_id'),
        ('messaging', 'community_post', 'author_user_account_id'),
        ('messaging', 'job_alert_preference', 'user_account_id'),
        ('messaging', 'post_reaction', 'user_account_id'),
        ('messaging', 'referral_event', 'referred_user_account_id'),
        ('messaging', 'support_ticket', 'assigned_agent_user_id'),
        ('messaging', 'notification_delivery', 'notification_template_id'),
        ('profile', 'candidate_activity_log', 'candidate_profile_id'),
        ('profile', 'candidate_assessment_score', 'candidate_assessment_id'),
        ('profile', 'candidate_document', 'resume_template_id'),
        ('profile', 'profile_view_history', 'organization_id'),
        ('profile', 'recruiter_bookmark', 'user_account_id'),
        ('profile', 'recruiter_bookmark', 'candidate_profile_id'),
        ('recruitment', 'candidate_application', 'candidate_document_id'),
        ('recruitment', 'job_position', 'filled_by_candidate_profile_id'),
        ('recruitment', 'recruiter_client_mapping', 'agency_organization_id'),
        ('sourcing', 'outreach_batch', 'job_posting_id'),
        ('sourcing', 'sourcing_submission', 'candidate_application_id'),
        ('sourcing', 'sourcing_submission', 'candidate_profile_id'),
        ('audit', 'system_error_log', 'user_account_id')
    ) AS t(s, tbl, col)
    LOOP
        SELECT NOT a.attnotnull INTO v_null FROM pg_attribute a WHERE a.attrelid = format('%I.%I', r.s, r.tbl)::regclass AND a.attname = r.col;
        EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON %I.%I (%I)%s', 'idx_' || r.tbl || '_' || r.col, r.s, r.tbl, r.col,
                       CASE WHEN v_null THEN format(' WHERE %I IS NOT NULL', r.col) ELSE '' END);
    END LOOP;
END $$;

COMMIT;
