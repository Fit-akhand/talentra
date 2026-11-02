-- =============================================================================
-- Migration 027: Reference job roles
-- Domain:        master (docket section 4 Tier 1 "job roles"; BR-005 reference data is read-only after seeding)
-- Depends on:    001-026
--
-- master.job_role was created in migration 003 but never populated, so every job posting had a NULL role and
-- the analytics dimension had no role names. This seeds a starter catalogue across the twelve industries.
-- Re-runnable: existing (industry, name) pairs are left alone.
-- =============================================================================
BEGIN;

INSERT INTO master.job_role (industry_id, name, normalized_name)
SELECT i.id, v.role_name, lower(v.role_name)
  FROM (VALUES
    ('Information Technology', 'Backend Engineer'),         ('Information Technology', 'Frontend Engineer'),
    ('Information Technology', 'DevOps Engineer'),          ('Information Technology', 'Data Engineer'),
    ('Information Technology', 'Database Administrator'),   ('Information Technology', 'Security Analyst'),
    ('Information Technology', 'QA Engineer'),              ('Information Technology', 'Product Manager'),
    ('Finance and Banking',    'Financial Analyst'),        ('Finance and Banking',    'Accountant'),
    ('Finance and Banking',    'Risk Analyst'),             ('Healthcare',             'Registered Nurse'),
    ('Healthcare',             'Medical Coder'),            ('Education',              'Teacher'),
    ('Education',              'Academic Counsellor'),      ('Manufacturing',          'Production Supervisor'),
    ('Manufacturing',          'Quality Inspector'),        ('Retail and E-commerce',  'Store Manager'),
    ('Retail and E-commerce',  'Category Manager'),         ('Consulting',             'Management Consultant'),
    ('Telecommunications',     'Network Engineer'),         ('Media and Entertainment','Content Producer'),
    ('Transportation and Logistics', 'Logistics Coordinator'), ('Construction and Real Estate', 'Site Engineer'),
    ('Hospitality and Tourism', 'Front Office Manager')
  ) AS v (industry_name, role_name)
  JOIN master.industry i ON i.name = v.industry_name
ON CONFLICT (industry_id, normalized_name) DO NOTHING;

SELECT audit.sync_column_classification();

COMMIT;
