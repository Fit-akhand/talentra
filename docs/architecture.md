
# Talentra Database Architecture

## Database engine
PostgreSQL 17.

## Architecture
Database-first modular monolith using one PostgreSQL database
and ten domain-specific schemas.

## Primary keys
All entities use BIGINT GENERATED ALWAYS AS IDENTITY primary keys.
Natural identifiers are modelled separately with unique constraints.

## Naming
Singular snake_case table names, snake_case columns,
primary keys named id, and foreign keys named after the
referenced table followed by _id.

## Business domains
- core: identity and access
- master: reference data
- profile: candidate information
- recruitment: jobs and applications
- sourcing: consultant workflows
- gig: project-based work
- commercial: licences, subscriptions and financial records
- messaging: notifications and translations
- audit: security and history
- analytics: reporting dimensions and facts

## Integrity
Foreign keys, unique constraints, check constraints and
transactional enforcement protect business invariants.

## Financial history
Wallet and payment ledger entries are append-only.
Corrections are represented by new records.

## Security
Sensitive fields are classified in the data dictionary.
Access is restricted and sensitive operations are audited.

## Analytics
Reporting models are separated from operational transactions.

## Migration strategy
Ordered SQL migrations are applied and verified against
a clean PostgreSQL database.
