-- 040: what the New Requirement screen asks for and the job posting could not hold (docs/phase-6-specify recruiter portal plan).
--   department list, several locations per job, show-salary and variable-pay flags, perks and relocation,
--   structured qualification requirements, and the recruiters assigned to a job.
-- Decision DEC-34 (Delegated, 2026-11-04; docs/lifecycle/decision-log.md): job_posting.city_id stays the primary location and
-- job_posting_location lists the other cities; show_salary defaults to FALSE (the salary is private until the recruiter ticks the box).

BEGIN;

-- ---------------------------------------------------------------------------------------------------------------
-- Master data: departments and perks
-- ---------------------------------------------------------------------------------------------------------------
CREATE TABLE master.department (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name            VARCHAR(100) NOT NULL,
    normalized_name VARCHAR(100) NOT NULL,
    is_active       BOOLEAN      NOT NULL DEFAULT TRUE,

    CONSTRAINT uq_department_normalized_name UNIQUE (normalized_name),
    CONSTRAINT ck_department_name CHECK (length(btrim(name)) BETWEEN 1 AND 100),
    CONSTRAINT ck_department_normalized CHECK (normalized_name = lower(btrim(normalized_name)) AND length(normalized_name) BETWEEN 1 AND 100)
);
COMMENT ON TABLE master.department IS 'Company departments a job or a work history belongs to (Engineering, Human Resources...). Reference data, read-only to the application.';
SELECT audit.apply_standard_lifecycle('master', 'department', 'reference');

INSERT INTO master.department (name, normalized_name) VALUES
    ('Engineering', 'engineering'), ('Information Technology', 'information technology'), ('Human Resources', 'human resources'),
    ('Finance and Accounts', 'finance and accounts'), ('Sales', 'sales'), ('Marketing', 'marketing'), ('Operations', 'operations'),
    ('Customer Support', 'customer support'), ('Product Management', 'product management'), ('Design', 'design'),
    ('Legal and Compliance', 'legal and compliance'), ('Administration', 'administration'), ('Procurement', 'procurement'),
    ('Quality Assurance', 'quality assurance'), ('Production and Manufacturing', 'production and manufacturing'), ('Logistics and Supply Chain', 'logistics and supply chain');

CREATE TABLE master.job_perk (
    id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code      VARCHAR(40)  NOT NULL,
    name      VARCHAR(100) NOT NULL,
    is_active BOOLEAN      NOT NULL DEFAULT TRUE,

    CONSTRAINT uq_job_perk_code UNIQUE (code),
    CONSTRAINT ck_job_perk_code CHECK (code ~ '^[a-z][a-z0-9_]+$'),
    CONSTRAINT ck_job_perk_name CHECK (length(btrim(name)) BETWEEN 1 AND 100)
);
COMMENT ON TABLE master.job_perk IS 'Benefits an employer can list on a job (provident fund, cab service, relocation benefits...). Reference data, read-only to the application.';
SELECT audit.apply_standard_lifecycle('master', 'job_perk', 'reference');

INSERT INTO master.job_perk (code, name) VALUES
    ('provident_fund', 'Provident Fund'), ('employee_state_insurance', 'Employees'' State Insurance'), ('cafeteria', 'Cafeteria'),
    ('cab_service', 'Cab Service'), ('work_from_home', 'Work From Home'), ('relocation_benefits', 'Relocation Benefits'),
    ('health_insurance', 'Health Insurance'), ('performance_bonus', 'Performance Bonus'), ('paid_time_off', 'Paid Time Off'),
    ('learning_budget', 'Learning Budget'), ('meal_vouchers', 'Meal Vouchers'), ('joining_bonus', 'Joining Bonus');

GRANT SELECT ON master.department, master.job_perk TO talentra_app, talentra_readonly, talentra_analyst;

-- ---------------------------------------------------------------------------------------------------------------
-- Job posting: department and the two flags
-- ---------------------------------------------------------------------------------------------------------------
ALTER TABLE recruitment.job_posting
    ADD COLUMN department_id     BIGINT,
    ADD COLUMN show_salary       BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN has_variable_pay  BOOLEAN NOT NULL DEFAULT FALSE,
    ADD CONSTRAINT fk_job_posting_department FOREIGN KEY (department_id) REFERENCES master.department (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    ADD CONSTRAINT ck_job_posting_show_salary CHECK (NOT show_salary OR salary_min IS NOT NULL OR salary_max IS NOT NULL);
COMMENT ON COLUMN recruitment.job_posting.department_id IS 'Reference to master.department (the hiring department). NULL when the employer did not say.';
COMMENT ON COLUMN recruitment.job_posting.show_salary IS 'True when candidates may see the salary range on the job. Default FALSE: the range stays private until the recruiter ticks "show CTC". A CHECK refuses TRUE when no salary is set.';
COMMENT ON COLUMN recruitment.job_posting.has_variable_pay IS 'True when part of the pay depends on incentives, so the range is not all fixed. Default FALSE.';

ALTER TABLE profile.candidate_work_experience
    ADD COLUMN department_id BIGINT,
    ADD CONSTRAINT fk_candidate_work_experience_department FOREIGN KEY (department_id) REFERENCES master.department (id) ON UPDATE RESTRICT ON DELETE RESTRICT;
COMMENT ON COLUMN profile.candidate_work_experience.department_id IS 'Reference to master.department (where the candidate worked in that company). NULL when not stated.';

-- ---------------------------------------------------------------------------------------------------------------
-- Who may be named as a recruiter for an organisation's job (used here and by migration 042)
-- ---------------------------------------------------------------------------------------------------------------
CREATE FUNCTION recruitment.is_recruiter_for_organization(p_user_account_id BIGINT, p_organization_id BIGINT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = pg_catalog
AS $$
    SELECT EXISTS (SELECT 1 FROM recruitment.organization_member m
                    WHERE m.user_account_id = p_user_account_id AND m.organization_id = p_organization_id AND m.membership_status = 'active'
                      AND m.organization_role IN ('recruiter', 'hiring_manager', 'owner', 'admin'))
        OR EXISTS (SELECT 1 FROM recruitment.recruiter_client_mapping r
                    WHERE r.recruiter_user_account_id = p_user_account_id AND r.client_organization_id = p_organization_id AND r.is_active
                      AND r.effective_from <= CURRENT_DATE AND (r.effective_to IS NULL OR r.effective_to >= CURRENT_DATE));
$$;
COMMENT ON FUNCTION recruitment.is_recruiter_for_organization(BIGINT, BIGINT) IS 'True when the user is an active recruiter, hiring manager, owner or admin of the organisation, or an agency recruiter mapped to it as a client today.';
REVOKE ALL ON FUNCTION recruitment.is_recruiter_for_organization(BIGINT, BIGINT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION recruitment.is_recruiter_for_organization(BIGINT, BIGINT) TO talentra_app;

CREATE FUNCTION recruitment.job_is_published(p_job_posting_id BIGINT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = pg_catalog
AS $$
    SELECT EXISTS (SELECT 1 FROM recruitment.job_posting WHERE id = p_job_posting_id AND job_status = 'published' AND deleted_at IS NULL);
$$;
COMMENT ON FUNCTION recruitment.job_is_published(BIGINT) IS 'True when the job is published and not deleted; lets the child tables of a job follow the same visibility as the job.';
REVOKE ALL ON FUNCTION recruitment.job_is_published(BIGINT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION recruitment.job_is_published(BIGINT) TO talentra_app;

-- ---------------------------------------------------------------------------------------------------------------
-- Several locations, perks, qualification requirements, assigned recruiters
-- ---------------------------------------------------------------------------------------------------------------
CREATE TABLE recruitment.job_posting_location (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_posting_id BIGINT NOT NULL REFERENCES recruitment.job_posting (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    city_id        BIGINT NOT NULL REFERENCES master.city (id) ON UPDATE RESTRICT ON DELETE RESTRICT,

    CONSTRAINT uq_job_posting_location UNIQUE (job_posting_id, city_id)
);
COMMENT ON TABLE recruitment.job_posting_location IS 'The cities a job is open in, besides the primary city on the job itself.';
CREATE INDEX idx_job_posting_location_city ON recruitment.job_posting_location (city_id, job_posting_id);
SELECT audit.apply_standard_lifecycle('recruitment', 'job_posting_location', 'hard');

CREATE TABLE recruitment.job_posting_perk (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_posting_id BIGINT NOT NULL REFERENCES recruitment.job_posting (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    job_perk_id    BIGINT NOT NULL REFERENCES master.job_perk (id) ON UPDATE RESTRICT ON DELETE RESTRICT,

    CONSTRAINT uq_job_posting_perk UNIQUE (job_posting_id, job_perk_id)
);
COMMENT ON TABLE recruitment.job_posting_perk IS 'The perks an employer lists on a job (provident fund, cab service, relocation benefits...).';
SELECT audit.apply_standard_lifecycle('recruitment', 'job_posting_perk', 'hard');

CREATE TABLE recruitment.job_qualification_requirement (
    id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_posting_id   BIGINT       NOT NULL REFERENCES recruitment.job_posting (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    qualification_id BIGINT       NOT NULL REFERENCES master.qualification (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    field_of_study   VARCHAR(100),
    is_mandatory     BOOLEAN      NOT NULL DEFAULT TRUE,

    CONSTRAINT ck_job_qualification_field CHECK (field_of_study IS NULL OR length(btrim(field_of_study)) BETWEEN 1 AND 100)
);
CREATE UNIQUE INDEX uq_job_qualification_requirement ON recruitment.job_qualification_requirement (job_posting_id, qualification_id, coalesce(lower(btrim(field_of_study)), ''));
COMMENT ON TABLE recruitment.job_qualification_requirement IS 'Education a job asks for, as a level from master.qualification with an optional field (B.Tech in Computer Science is Undergraduate + "Computer Science").';
SELECT audit.apply_standard_lifecycle('recruitment', 'job_qualification_requirement', 'hard');

CREATE TABLE recruitment.job_recruiter_assignment (
    id                          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_posting_id              BIGINT      NOT NULL REFERENCES recruitment.job_posting (id) ON UPDATE RESTRICT ON DELETE CASCADE,
    recruiter_user_account_id   BIGINT      NOT NULL REFERENCES core.user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    assigned_by_user_account_id BIGINT      REFERENCES core.user_account (id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    assigned_at                 TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_active                   BOOLEAN     NOT NULL DEFAULT TRUE,

    CONSTRAINT uq_job_recruiter_assignment UNIQUE (job_posting_id, recruiter_user_account_id)
);
COMMENT ON TABLE recruitment.job_recruiter_assignment IS 'Which recruiters work on a job ("Assign recruiters" on the New Requirement screen). A recruiter must belong to the job''s organisation or be mapped to it as a client.';
CREATE INDEX idx_job_recruiter_assignment_recruiter ON recruitment.job_recruiter_assignment (recruiter_user_account_id) WHERE is_active;
SELECT audit.apply_standard_lifecycle('recruitment', 'job_recruiter_assignment', 'hard');

CREATE FUNCTION recruitment.enforce_recruiter_assignment()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT recruitment.is_recruiter_for_organization(NEW.recruiter_user_account_id, recruitment.job_organization_id(NEW.job_posting_id)) THEN
        RAISE EXCEPTION 'user % is not a recruiter of the organisation that owns job %', NEW.recruiter_user_account_id, NEW.job_posting_id
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION recruitment.enforce_recruiter_assignment() IS 'Only an active recruiter, hiring manager, owner or admin of the job''s organisation, or an agency recruiter mapped to it, can be assigned to its jobs.';
CREATE TRIGGER trg_job_recruiter_assignment_member BEFORE INSERT OR UPDATE OF recruiter_user_account_id, job_posting_id ON recruitment.job_recruiter_assignment
    FOR EACH ROW EXECUTE FUNCTION recruitment.enforce_recruiter_assignment();

-- row-level security: a job's children follow the job (published = readable by anyone; the organisation writes)
DO $$
DECLARE t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY['job_posting_location', 'job_posting_perk', 'job_qualification_requirement'] LOOP
        EXECUTE format('ALTER TABLE recruitment.%I ENABLE ROW LEVEL SECURITY', t);
        EXECUTE format('CREATE POLICY %I ON recruitment.%I FOR SELECT TO talentra_app USING (recruitment.job_is_published(job_posting_id) OR recruitment.job_organization_id(job_posting_id) = core.current_org_id() OR core.is_platform_admin())', t || '_read', t);
        EXECUTE format('CREATE POLICY %I ON recruitment.%I FOR ALL TO talentra_app USING (recruitment.job_organization_id(job_posting_id) = core.current_org_id() OR core.is_platform_admin()) WITH CHECK (recruitment.job_organization_id(job_posting_id) = core.current_org_id() OR core.is_platform_admin())', t || '_write', t);
    END LOOP;
END $$;
ALTER TABLE recruitment.job_recruiter_assignment ENABLE ROW LEVEL SECURITY;
CREATE POLICY job_recruiter_assignment_read ON recruitment.job_recruiter_assignment FOR SELECT TO talentra_app
    USING (recruitment.job_organization_id(job_posting_id) = core.current_org_id() OR recruiter_user_account_id = core.current_app_user_id() OR core.is_platform_admin());
CREATE POLICY job_recruiter_assignment_write ON recruitment.job_recruiter_assignment FOR ALL TO talentra_app
    USING (recruitment.job_organization_id(job_posting_id) = core.current_org_id() OR core.is_platform_admin())
    WITH CHECK (recruitment.job_organization_id(job_posting_id) = core.current_org_id() OR core.is_platform_admin());

GRANT SELECT, INSERT, UPDATE, DELETE ON recruitment.job_posting_location, recruitment.job_posting_perk, recruitment.job_qualification_requirement, recruitment.job_recruiter_assignment TO talentra_app;
GRANT SELECT ON recruitment.job_posting_location, recruitment.job_posting_perk, recruitment.job_qualification_requirement, recruitment.job_recruiter_assignment TO talentra_readonly;

-- ---------------------------------------------------------------------------------------------------------------
-- Column definitions for the new tables
-- ---------------------------------------------------------------------------------------------------------------
DO $$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT * FROM (VALUES
        ('id',                          'Surrogate primary key (64-bit identity). Never reused, never shown to users.'),
        ('created_at',                  'When the row was created (UTC). Set by trigger and never changed.'),
        ('updated_at',                  'When the row was last changed (UTC). Set by trigger.'),
        ('created_by_user_account_id',  'Account that created the row, taken from the session. NULL when the system created it (seed, migration, scheduled job).'),
        ('updated_by_user_account_id',  'Account that last changed the row, taken from the session. NULL when the system changed it.')) AS v(c, d)
    LOOP
        EXECUTE format('COMMENT ON COLUMN master.department.%I IS %L', r.c, r.d);
        EXECUTE format('COMMENT ON COLUMN master.job_perk.%I IS %L', r.c, r.d);
        EXECUTE format('COMMENT ON COLUMN recruitment.job_posting_location.%I IS %L', r.c, r.d);
        EXECUTE format('COMMENT ON COLUMN recruitment.job_posting_perk.%I IS %L', r.c, r.d);
        EXECUTE format('COMMENT ON COLUMN recruitment.job_qualification_requirement.%I IS %L', r.c, r.d);
        EXECUTE format('COMMENT ON COLUMN recruitment.job_recruiter_assignment.%I IS %L', r.c, r.d);
    END LOOP;
END $$;
COMMENT ON COLUMN master.department.name IS 'Department name in English; the display name in other languages is a translation key in messaging.ui_translation.';
COMMENT ON COLUMN master.department.normalized_name IS 'Lower-case, trimmed form of name used for matching and uniqueness.';
COMMENT ON COLUMN master.department.is_active IS 'True while the department can be chosen. Default TRUE.';
COMMENT ON COLUMN master.job_perk.code IS 'Stable machine-readable code (lower case), unique within the table.';
COMMENT ON COLUMN master.job_perk.name IS 'Perk name in English, as shown on the job.';
COMMENT ON COLUMN master.job_perk.is_active IS 'True while the perk can be chosen. Default TRUE.';
COMMENT ON COLUMN recruitment.job_posting_location.job_posting_id IS 'Reference to recruitment.job_posting (the job). Required; the row is deleted with the job.';
COMMENT ON COLUMN recruitment.job_posting_location.city_id IS 'Reference to master.city (a city the job is open in). Required.';
COMMENT ON COLUMN recruitment.job_posting_perk.job_posting_id IS 'Reference to recruitment.job_posting (the job). Required; the row is deleted with the job.';
COMMENT ON COLUMN recruitment.job_posting_perk.job_perk_id IS 'Reference to master.job_perk (the benefit offered). Required.';
COMMENT ON COLUMN recruitment.job_qualification_requirement.job_posting_id IS 'Reference to recruitment.job_posting (the job). Required; the row is deleted with the job.';
COMMENT ON COLUMN recruitment.job_qualification_requirement.qualification_id IS 'Reference to master.qualification (the education level asked for). Required.';
COMMENT ON COLUMN recruitment.job_qualification_requirement.field_of_study IS 'Subject asked for, for example Computer Science. NULL when any subject will do.';
COMMENT ON COLUMN recruitment.job_qualification_requirement.is_mandatory IS 'True when a candidate without it does not qualify; false when it is only preferred. Default TRUE.';
COMMENT ON COLUMN recruitment.job_recruiter_assignment.job_posting_id IS 'Reference to recruitment.job_posting (the job). Required; the row is deleted with the job.';
COMMENT ON COLUMN recruitment.job_recruiter_assignment.recruiter_user_account_id IS 'Reference to core.user_account (the recruiter working on the job). Must be a recruiter of the job''s organisation or mapped to it as a client. Required.';
COMMENT ON COLUMN recruitment.job_recruiter_assignment.assigned_by_user_account_id IS 'Reference to core.user_account (who made the assignment). NULL when the system did.';
COMMENT ON COLUMN recruitment.job_recruiter_assignment.assigned_at IS 'When the recruiter was assigned (UTC).';
COMMENT ON COLUMN recruitment.job_recruiter_assignment.is_active IS 'True while the recruiter works on the job; false keeps the history after they are taken off it. Default TRUE.';

-- the legacy sync must say what happens to the new columns of the synchronised tables
INSERT INTO messaging.legacy_field_mapping (legacy_entity, legacy_field, talentra_table, talentra_column, direction, conflict_rule, owner_role, note) VALUES
 ('job', 'department', 'recruitment.job_posting', 'department_id', 'inbound', 'cutover_dependent', 'Product', 'Legacy owns the department until cut-over; Talentra after'),
 ('job', NULL, 'recruitment.job_posting', 'show_salary', 'not_synced', NULL, 'Finance', 'A Talentra privacy choice: the legacy systems always showed the salary or never did'),
 ('job', NULL, 'recruitment.job_posting', 'has_variable_pay', 'not_synced', NULL, 'Finance', 'No equivalent in the legacy systems; set by the recruiter in Talentra');

SELECT audit.refresh_active_views();
SELECT audit.sync_column_classification();
SELECT audit.refresh_protection();

COMMIT;
