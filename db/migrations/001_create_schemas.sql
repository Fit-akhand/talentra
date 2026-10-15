
-- Migration: 001_create_schemas.sql
-- Purpose: Create the initial Talentra database namespaces.
-- Engine: PostgreSQL 17
-- Key strategy: BIGINT GENERATED ALWAYS AS IDENTITY
-- Note: This migration intentionally creates schemas only.

BEGIN;

CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS master;
CREATE SCHEMA IF NOT EXISTS profile;
CREATE SCHEMA IF NOT EXISTS recruitment;
CREATE SCHEMA IF NOT EXISTS sourcing;
CREATE SCHEMA IF NOT EXISTS gig;
CREATE SCHEMA IF NOT EXISTS commercial;
CREATE SCHEMA IF NOT EXISTS messaging;
CREATE SCHEMA IF NOT EXISTS audit;
CREATE SCHEMA IF NOT EXISTS analytics;

COMMENT ON SCHEMA core IS
    'Identity, accounts, roles, permissions, devices and sessions';

COMMENT ON SCHEMA master IS
    'Reusable reference data such as countries, cities, skills and qualifications';

COMMENT ON SCHEMA profile IS
    'Candidate profiles, education, experience, skills and resume versions';

COMMENT ON SCHEMA recruitment IS
    'Organisations, job requirements, applications and hiring pipeline';

COMMENT ON SCHEMA sourcing IS
    'Consultant sourcing requests, submissions and candidate shortlists';

COMMENT ON SCHEMA gig IS
    'Gig worker profiles, gig requests, applications and external fulfilment references';

COMMENT ON SCHEMA commercial IS
    'Plans, licences, subscriptions, payments, wallets and financial ledgers';

COMMENT ON SCHEMA messaging IS
    'Notifications, preferences, translations and delivery history';

COMMENT ON SCHEMA audit IS
    'Audit events, consent records, access history and system errors';

COMMENT ON SCHEMA analytics IS
    'Analytical dimensions, facts, reporting views and aggregates';

COMMIT;



