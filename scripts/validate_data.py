#!/usr/bin/env python3
"""
Talentra Data Quality & Compliance Validator (Milestone 20: B65–B66)
Engine: PostgreSQL 17
Validates database schema, data integrity, and constraint adherence across all 10 Rule Groups:
1. Naming & Identifier Conventions
2. Surrogate & Primary Key Architecture
3. Domain & Formatting Constraints (E.164 phones, RFC emails, ISO codes)
4. Temporal & Chronological Range Integrity
5. Nullability Discipline & Zero-Sentinel Rule
6. Sensitive Data Classification & Hashing Standards
7. Append-Only Ledgers & Financial Balance Reconciliation
8. Multilingual UI & Fallback Logic
9. Licensing, Seat Allocations & Concurrent Session Device Limits
10. Partitioning & Exclusion Constraint Integrity
"""

import os
import re
import sys
import time
import psycopg2

DB_HOST = os.getenv("POSTGRES_HOST") or os.getenv("PGHOST", "127.0.0.1")
DB_PORT = int(os.getenv("POSTGRES_PORT") or os.getenv("PGPORT", "5432"))
DB_NAME = os.getenv("POSTGRES_DB") or os.getenv("PGDATABASE", "talentra")
DB_USER = os.getenv("POSTGRES_USER") or os.getenv("PGUSER", "talentra_admin")
DB_PASS = os.getenv("POSTGRES_PASSWORD") or os.getenv("PGPASSWORD")

def get_connection():
    return psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASS
    )

class DataValidator:
    def __init__(self, conn):
        self.conn = conn
        self.cur = conn.cursor()
        self.passed_checks = 0
        self.failed_checks = 0
        self.warnings = 0
        self.results = []

    def log_result(self, rule_group, check_name, status, details=""):
        if status == "PASS":
            self.passed_checks += 1
            icon = "[PASS]"
        elif status == "FAIL":
            self.failed_checks += 1
            icon = "[FAIL]"
        else:
            self.warnings += 1
            icon = "[WARN]"
        
        self.results.append({
            "rule_group": rule_group,
            "check_name": check_name,
            "status": status,
            "details": details
        })
        print(f" {icon} {rule_group} | {check_name}: {details}")

    def validate_rg1_naming_conventions(self):
        """Rule Group 1: Naming & Identifier Conventions (snake_case, boolean prefixes, foreign keys)"""
        # Check non-snake_case table names in application schemas
        self.cur.execute("""
            SELECT table_schema, table_name
            FROM information_schema.tables
            WHERE table_schema IN ('core', 'master', 'profile', 'recruitment', 'gig', 'commercial', 'sourcing', 'messaging', 'analytics', 'audit')
              AND table_type = 'BASE TABLE'
              AND table_name !~ '^[a-z][a-z0-9_]*$';
        """)
        bad_tables = self.cur.fetchall()
        if not bad_tables:
            self.log_result("RG1", "Table Naming (snake_case)", "PASS", "All tables adhere to snake_case naming")
        else:
            self.log_result("RG1", "Table Naming (snake_case)", "FAIL", f"Found invalid names: {bad_tables}")

        # Check boolean column prefixes (is_*, has_*, can_*, allow_*, show_*, auto_*, boolean_*)
        self.cur.execute("""
            SELECT table_schema, table_name, column_name
            FROM information_schema.columns
            WHERE table_schema IN ('core', 'master', 'profile', 'recruitment', 'gig', 'commercial', 'sourcing', 'messaging', 'analytics')
              AND data_type = 'boolean'
              AND column_name !~ '^(is_|has_|can_|allow_|show_|auto_|boolean_).*';
        """)
        bad_booleans = self.cur.fetchall()
        if not bad_booleans:
            self.log_result("RG1", "Boolean Column Prefixes (is_/has_/can_/allow_/show_/auto_)", "PASS", "All boolean columns adhere to semantic prefix standards")
        else:
            self.log_result("RG1", "Boolean Column Prefixes (is_/has_/can_/allow_/show_/auto_)", "WARN", f"Non-prefixed booleans: {bad_booleans}")

    def validate_rg2_surrogate_keys(self):
        """Rule Group 2: Surrogate & Primary Key Architecture"""
        # Check that operational tables have surrogate primary key including id or dimensional key
        self.cur.execute("""
            SELECT t.table_schema, t.table_name
            FROM information_schema.tables t
            WHERE t.table_schema IN ('core', 'profile', 'recruitment', 'gig', 'commercial', 'sourcing', 'messaging', 'audit')
              AND t.table_type = 'BASE TABLE'
              AND NOT EXISTS (
                  SELECT 1
                  FROM information_schema.table_constraints tc
                  JOIN information_schema.key_column_usage kcu
                    ON tc.constraint_name = kcu.constraint_name
                   AND tc.table_schema = kcu.table_schema
                  WHERE tc.constraint_type = 'PRIMARY KEY'
                    AND tc.table_schema = t.table_schema
                    AND tc.table_name = t.table_name
                    AND kcu.column_name IN ('id', 'date_key', 'job_posting_key', 'organization_key', 'candidate_key')
              );
        """)
        missing_pk = self.cur.fetchall()
        if not missing_pk:
            self.log_result("RG2", "Surrogate Primary Keys", "PASS", "All operational tables have standard surrogate primary keys")
        else:
            self.log_result("RG2", "Surrogate Primary Keys", "FAIL", f"Tables missing standard surrogate PK: {missing_pk}")

    def validate_rg3_domain_constraints(self):
        """Rule Group 3: Domain & Formatting Constraints (E.164, RFC emails, ISO country/currency)"""
        # 1. RFC Email Format Validation (lowercase and valid structure)
        self.cur.execute(r"""
            SELECT COUNT(*)
            FROM core.user_account
            WHERE email !~ '^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$';
        """)
        invalid_emails = self.cur.fetchone()[0]
        if invalid_emails == 0:
            self.log_result("RG3", "RFC Lowercase Email Validation", "PASS", "0 invalid email formats detected")
        else:
            self.log_result("RG3", "RFC Lowercase Email Validation", "FAIL", f"{invalid_emails} invalid email records found")

        # 2. E.164 Phone Format Validation (^\+[1-9]\d{1,14}$)
        self.cur.execute(r"""
            SELECT COUNT(*)
            FROM core.user_account
            WHERE phone_e164 IS NOT NULL AND phone_e164 !~ '^\+[1-9]\d{1,14}$';
        """)
        invalid_phones = self.cur.fetchone()[0]
        if invalid_phones == 0:
            self.log_result("RG3", "E.164 Phone Number Validation", "PASS", "0 non-compliant phone numbers detected")
        else:
            self.log_result("RG3", "E.164 Phone Number Validation", "FAIL", f"{invalid_phones} non-compliant phone numbers found")

        # 3. ISO Currency Code Validation (3 uppercase letters)
        self.cur.execute(r"""
            SELECT COUNT(*)
            FROM recruitment.job_posting
            WHERE currency_code !~ '^[A-Z]{3}$';
        """)
        invalid_currencies = self.cur.fetchone()[0]
        if invalid_currencies == 0:
            self.log_result("RG3", "ISO 4217 Currency Standards", "PASS", "All job postings use 3-letter uppercase ISO currency codes")
        else:
            self.log_result("RG3", "ISO 4217 Currency Standards", "FAIL", f"{invalid_currencies} invalid currency codes found")

    def validate_rg4_temporal_integrity(self):
        """Rule Group 4: Temporal & Chronological Range Integrity"""
        # Candidate Experience: start_date <= end_date
        self.cur.execute("""
            SELECT COUNT(*)
            FROM profile.candidate_work_experience
            WHERE start_date IS NOT NULL AND end_date IS NOT NULL AND end_date < start_date;
        """)
        bad_exp = self.cur.fetchone()[0]
        
        # Gig Worker Availability: available_from <= available_to
        self.cur.execute("""
            SELECT COUNT(*)
            FROM gig.gig_worker_availability
            WHERE available_to < available_from;
        """)
        bad_avail = self.cur.fetchone()[0]

        # Gig Assignment: assigned_start_date <= assigned_end_date
        self.cur.execute("""
            SELECT COUNT(*)
            FROM gig.gig_assignment
            WHERE assigned_end_date < assigned_start_date;
        """)
        bad_assign = self.cur.fetchone()[0]

        total_temporal_faults = bad_exp + bad_avail + bad_assign
        if total_temporal_faults == 0:
            self.log_result("RG4", "Chronological Range Consistency", "PASS", "All start/end dates across experience, availability, and assignments are valid")
        else:
            self.log_result("RG4", "Chronological Range Consistency", "FAIL", f"{total_temporal_faults} inverted date range records found")

    def validate_rg5_nullability_and_sentinels(self):
        """Rule Group 5: Nullability Discipline & Zero Sentinel Values"""
        # Search for string sentinel values ('NA', 'N/A', 'NONE', 'NULL', 'UNKNOWN', '?') in text columns
        self.cur.execute("""
            SELECT COUNT(*)
            FROM profile.candidate_profile
            WHERE headline IN ('NA', 'N/A', 'NONE', 'NULL', 'UNKNOWN', '?')
               OR professional_summary IN ('NA', 'N/A', 'NONE', 'NULL', 'UNKNOWN', '?');
        """)
        sentinel_count = self.cur.fetchone()[0]
        if sentinel_count == 0:
            self.log_result("RG5", "Zero-Sentinel Value Rule", "PASS", "Zero sentinel dummy strings ('NA', 'NONE', etc.) detected in profile text")
        else:
            self.log_result("RG5", "Zero-Sentinel Value Rule", "FAIL", f"{sentinel_count} sentinel dummy values found")

    def validate_rg6_sensitive_data_protection(self):
        """Rule Group 6: Sensitive Data Classification & Password Hashing"""
        self.cur.execute(r"""
            SELECT COUNT(*)
            FROM core.user_account
            WHERE password_hash IS NOT NULL
              AND password_hash !~ '^\$(argon2id|2b|2a)\$';
        """)
        unhashed = self.cur.fetchone()[0]
        if unhashed == 0:
            self.log_result("RG6", "Cryptographic Password Hashing", "PASS", "100% of user password hashes follow Argon2id/bcrypt standards")
        else:
            self.log_result("RG6", "Cryptographic Password Hashing", "FAIL", f"{unhashed} unhashed or non-compliant passwords detected")

    def validate_rg7_append_only_ledgers(self):
        """Rule Group 7: Append-Only Ledgers & Financial Balance Reconciliation"""
        # 1. Anti-tamper trigger verification on commercial.wallet_ledger
        self.cur.execute("""
            SELECT count(*)
            FROM information_schema.triggers
            WHERE trigger_schema = 'commercial'
              AND event_object_table = 'wallet_ledger'
              AND action_timing = 'BEFORE';
        """)
        trigger_count = self.cur.fetchone()[0]
        if trigger_count > 0:
            self.log_result("RG7", "Wallet Ledger Anti-Tamper Trigger", "PASS", f"Active immutability trigger attached ({trigger_count} found)")
        else:
            self.log_result("RG7", "Wallet Ledger Anti-Tamper Trigger", "FAIL", "Missing anti-tamper trigger on commercial.wallet_ledger")

        # 2. Financial Balance Reconciliation (Balance == sum(credits) - sum(debits))
        self.cur.execute("""
            SELECT
                w.id,
                w.balance,
                COALESCE(SUM(
                    CASE
                        WHEN wl.entry_type IN ('credit', 'correction_credit') THEN wl.amount
                        WHEN wl.entry_type IN ('debit', 'correction_debit') THEN -wl.amount
                        ELSE 0.00
                    END
                ), 0.00) AS ledger_sum
            FROM commercial.wallet w
            LEFT JOIN commercial.wallet_ledger wl ON w.id = wl.wallet_id
            GROUP BY w.id, w.balance;
        """)
        unreconciled = [r for r in self.cur.fetchall() if r[1] != r[2]]
        if not unreconciled:
            self.log_result("RG7", "Financial Balance Reconciliation", "PASS", "All corporate wallets reconcile perfectly with ledger entries")
        else:
            self.log_result("RG7", "Financial Balance Reconciliation", "FAIL", f"{len(unreconciled)} unreconciled wallets detected: {unreconciled}")

    def validate_rg8_multilingual_fallback(self):
        """Rule Group 8: Multilingual UI Translations & Fallback Resolution"""
        self.cur.execute("""
            SELECT messaging.get_ui_translation('btn.apply_job', 'es');
        """)
        es_val = self.cur.fetchone()[0]
        
        # Test fallback on missing language
        self.cur.execute("""
            SELECT messaging.get_ui_translation('btn.apply_job', 'ja');
        """)
        fallback_val = self.cur.fetchone()[0]

        if es_val and fallback_val and es_val != fallback_val:
            self.log_result("RG8", "Multilingual Translation & English Fallback", "PASS", f"Resolved 'es'='{es_val}', fallback 'ja'='{fallback_val}'")
        else:
            self.log_result("RG8", "Multilingual Translation & English Fallback", "FAIL", f"Unexpected translation behavior: es='{es_val}', fallback='{fallback_val}'")

    def validate_rg9_licences_and_device_limits(self):
        """Rule Group 9: Licensing, Seat Allocations & Concurrent Session Device Limits"""
        self.cur.execute("""
            SELECT
                u.id,
                sl.max_devices_per_user,
                COUNT(s.id) AS active_sessions
            FROM core.user_account u
            JOIN commercial.licence_seat_allocation lsa ON u.id = lsa.user_account_id
            JOIN commercial.subscription_licence sl ON lsa.subscription_licence_id = sl.id
            JOIN core.user_session s ON u.id = s.user_account_id
            WHERE s.ended_at IS NULL AND s.revoked_at IS NULL
            GROUP BY u.id, sl.max_devices_per_user
            HAVING COUNT(s.id) > sl.max_devices_per_user;
        """)
        breached = self.cur.fetchall()
        if not breached:
            self.log_result("RG9", "Concurrent Session Device Limit Enforcement", "PASS", "0 users exceed concurrent device allocation limits")
        else:
            self.log_result("RG9", "Concurrent Session Device Limit Enforcement", "FAIL", f"{len(breached)} users breached device limits: {breached}")

    def validate_rg10_partitioning_and_exclusions(self):
        """Rule Group 10: Partitioning & Exclusion Constraint Integrity"""
        # 1. Partitioned Candidate Applications check
        self.cur.execute("""
            SELECT count(*)
            FROM pg_inherits
            JOIN pg_class parent ON pg_inherits.inhparent = parent.oid
            JOIN pg_class child ON pg_inherits.inhrelid = child.oid
            WHERE parent.relname = 'candidate_application_partitioned';
        """)
        partition_count = self.cur.fetchone()[0]
        if partition_count >= 3:
            self.log_result("RG10", "Declarative Range Partitioning", "PASS", f"High-velocity table has {partition_count} active partitions")
        else:
            self.log_result("RG10", "Declarative Range Partitioning", "WARN", f"Expected >= 3 partitions, found {partition_count}")

        # 2. Gig Assignment Exclusion Constraint (btree_gist non-overlapping active windows)
        self.cur.execute("""
            SELECT conname
            FROM pg_constraint
            WHERE conname = 'ex_gig_assignment_no_overlap';
        """)
        ex_con = self.cur.fetchone()
        if ex_con:
            self.log_result("RG10", "Temporal Exclusion Constraints", "PASS", "Active btree_gist exclusion constraint enforces zero overlapping gig assignments")
        else:
            self.log_result("RG10", "Temporal Exclusion Constraints", "FAIL", "Missing ex_gig_assignment_no_overlap constraint")

    def run_all(self):
        print("================================================================")
        print(" Talentra Comprehensive Data Quality & Compliance Validator")
        print(" Rule Groups 1–10 Verification")
        print("================================================================")
        t0 = time.time()
        self.validate_rg1_naming_conventions()
        self.validate_rg2_surrogate_keys()
        self.validate_rg3_domain_constraints()
        self.validate_rg4_temporal_integrity()
        self.validate_rg5_nullability_and_sentinels()
        self.validate_rg6_sensitive_data_protection()
        self.validate_rg7_append_only_ledgers()
        self.validate_rg8_multilingual_fallback()
        self.validate_rg9_licences_and_device_limits()
        self.validate_rg10_partitioning_and_exclusions()
        
        elapsed = time.time() - t0
        print("\n----------------------------------------------------------------")
        print(f" Summary: Passed: {self.passed_checks} | Failed: {self.failed_checks} | Warnings: {self.warnings}")
        print(f" Execution completed in {elapsed:.2f} seconds.")
        print("================================================================")
        return self.failed_checks == 0

def main():
    conn = get_connection()
    try:
        validator = DataValidator(conn)
        success = validator.run_all()
        if not success:
            sys.exit(1)
    finally:
        conn.close()

if __name__ == "__main__":
    main()
