-- 037: BR-021 "outreach recipients are filtered against candidate block state before dispatch" becomes a database rule.
-- It was a convention in a SELECT (db/queries/06); any writer could add a blocked candidate as a pending recipient.
--
-- A recipient the candidate has made unreachable (the candidate blocked the sender or the organisation, or the sender blocked the
-- candidate) is stored as 'blocked' instead of 'pending', and can never be moved to a delivered state.

BEGIN;

CREATE FUNCTION sourcing.enforce_outreach_block()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_sender BIGINT;
    v_org BIGINT;
BEGIN
    SELECT created_by_user_account_id, organization_id INTO v_sender, v_org FROM sourcing.outreach_batch WHERE id = NEW.outreach_batch_id;
    IF core.is_candidate_visible_to(NEW.candidate_profile_id, v_sender, v_org) THEN
        RETURN NEW;
    END IF;
    IF TG_OP = 'INSERT' THEN
        IF NEW.delivery_status IN ('pending', 'sent', 'delivered', 'opened', 'responded') THEN NEW.delivery_status := 'blocked'; END IF;
        NEW.sent_at := NULL; NEW.delivered_at := NULL;
    ELSIF NEW.delivery_status IN ('sent', 'delivered', 'opened', 'responded') THEN
        RAISE EXCEPTION 'candidate % cannot be contacted by batch % (block in force)', NEW.candidate_profile_id, NEW.outreach_batch_id
            USING ERRCODE = 'insufficient_privilege';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION sourcing.enforce_outreach_block() IS 'BR-021: a recipient the candidate has blocked is stored as blocked on insert and may not be moved to a delivered state.';

CREATE TRIGGER trg_outreach_recipient_block
    BEFORE INSERT OR UPDATE OF delivery_status ON sourcing.outreach_recipient
    FOR EACH ROW EXECUTE FUNCTION sourcing.enforce_outreach_block();

COMMIT;
