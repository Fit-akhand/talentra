"""
Talentra Database Design — High-Concurrency Multi-Threaded Test Suite
Verifies:
1. Pessimistic concurrency & device limits under simultaneous logins (FOR UPDATE serialization).
2. btree_gist exclusion constraints on overlapping gig assignments under race conditions.
3. Transactional atomic balance updates & append-only wallet ledgers under concurrent debits.
"""

import os
import sys
import uuid
import random
import threading
import psycopg2
from psycopg2 import pool
from concurrent.futures import ThreadPoolExecutor, as_completed

DB_HOST = os.getenv("DB_HOST", "127.0.0.1")
DB_PORT = int(os.getenv("DB_PORT", "5432"))
DB_NAME = os.getenv("DB_NAME", "talentra")
DB_USER = os.getenv("DB_USER", "talentra_admin")
DB_PASS = os.getenv("DB_PASSWORD", "354vctrho9t769874t8B*^&$%&**tf2eej2rh")

def get_connection():
    return psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASS
    )

def test_concurrent_device_logins():
    print("\n--- Test 1: Concurrent Device Login Limit (Rule Group 9 & B45) ---")
    conn = get_connection()
    conn.autocommit = True
    cur = conn.cursor()

    # Create dedicated test user
    test_email = f"concurrency_user_{uuid.uuid4().hex[:8]}@example.com"
    cur.execute(
        "INSERT INTO core.user_account (email, account_status) VALUES (%s, 'active') RETURNING id;",
        (test_email,)
    )
    user_id = cur.fetchone()[0]

    # Create test org & licence with max_devices_per_user = 2
    cur.execute(
        "INSERT INTO recruitment.organization (name, slug, organization_type, created_by_user_account_id) "
        "VALUES (%s, %s, 'employer', %s) RETURNING id;",
        (f"Concurrency Org {uuid.uuid4().hex[:6]}", f"org-slug-{uuid.uuid4().hex[:8]}", user_id)
    )
    org_id = cur.fetchone()[0]

    cur.execute(
        """
        INSERT INTO commercial.subscription_licence (
            organization_id, licence_key, licence_name, max_users, max_devices_per_user,
            valid_from, valid_to, licence_status
        ) VALUES (
            %s, %s, 'Test Licence 2-Devices', 5, 2,
            CURRENT_TIMESTAMP - INTERVAL '1 day', CURRENT_TIMESTAMP + INTERVAL '1 year', 'active'
        ) RETURNING id;
        """,
        (org_id, f"LIC-{uuid.uuid4().hex[:12].upper()}")
    )
    licence_id = cur.fetchone()[0]

    cur.execute(
        "INSERT INTO commercial.licence_seat_allocation (subscription_licence_id, user_account_id) VALUES (%s, %s);",
        (licence_id, user_id)
    )
    conn.close()

    num_threads = 10
    results = []

    def attempt_login(thread_idx):
        t_conn = get_connection()
        t_conn.autocommit = True
        t_cur = t_conn.cursor()
        device_id = f"device_thread_{thread_idx}_{uuid.uuid4().hex[:6]}"
        token_hash = f"sess_token_hash_{thread_idx}_{uuid.uuid4().hex[:8]}"
        try:
            t_cur.execute(
                "SELECT core.create_session_with_device_limit(%s, %s, %s, %s, 'mobile', '127.0.0.1');",
                (user_id, device_id, token_hash, f"Device {thread_idx}")
            )
            session_id = t_cur.fetchone()[0]
            t_conn.close()
            return {"thread": thread_idx, "session_id": session_id, "success": session_id is not None}
        except Exception as e:
            t_conn.close()
            return {"thread": thread_idx, "error": str(e), "success": False}

    with ThreadPoolExecutor(max_workers=num_threads) as executor:
        futures = [executor.submit(attempt_login, i) for i in range(num_threads)]
        for f in as_completed(futures):
            results.append(f.result())

    success_count = sum(1 for r in results if r.get("success"))
    rejected_count = sum(1 for r in results if not r.get("success") and r.get("session_id") is None)

    print(f"Total concurrent login attempts: {num_threads}")
    print(f"Granted sessions: {success_count} (Expected: 2)")
    print(f"Rejected sessions (limit reached): {rejected_count} (Expected: {num_threads - 2})")

    assert success_count == 2, f"Expected exactly 2 sessions, got {success_count}"
    assert rejected_count == num_threads - 2, f"Expected {num_threads - 2} rejections, got {rejected_count}"

    # Verify audit events for rejected attempts
    v_conn = get_connection()
    v_cur = v_conn.cursor()
    v_cur.execute(
        "SELECT COUNT(*) FROM audit.audit_event WHERE actor_user_account_id = %s AND action = 'device.limit_exceeded';",
        (user_id,)
    )
    audit_count = v_cur.fetchone()[0]
    v_conn.close()

    print(f"Audit log events recorded for device limit breach: {audit_count} (Expected: {rejected_count})")
    assert audit_count == rejected_count, f"Audit event count {audit_count} does not match rejected count {rejected_count}"
    print("PASS: Concurrent device login limit verified under high-contention row-level locking!")


def test_concurrent_gig_assignments():
    print("\n--- Test 2: Concurrent Overlapping Gig Booking (btree_gist Exclusion) ---")
    conn = get_connection()
    conn.autocommit = True
    cur = conn.cursor()

    # Setup User, Gig Worker, Org, and Gig Requests
    test_email = f"gig_worker_{uuid.uuid4().hex[:8]}@example.com"
    cur.execute("INSERT INTO core.user_account (email, account_status) VALUES (%s, 'active') RETURNING id;", (test_email,))
    user_id = cur.fetchone()[0]

    cur.execute(
        "INSERT INTO gig.gig_worker_profile (user_account_id, headline, hourly_rate, currency_code, is_available) "
        "VALUES (%s, 'Senior DevOps Consultant', 120.00, 'USD', TRUE) RETURNING id;",
        (user_id,)
    )
    worker_id = cur.fetchone()[0]

    cur.execute(
        "INSERT INTO recruitment.organization (name, slug, organization_type, created_by_user_account_id) "
        "VALUES (%s, %s, 'employer', %s) RETURNING id;",
        (f"Gig Org {uuid.uuid4().hex[:6]}", f"gig-org-{uuid.uuid4().hex[:8]}", user_id)
    )
    org_id = cur.fetchone()[0]

    num_threads = 5
    req_and_app_ids = []

    for i in range(num_threads):
        cur.execute(
            """
            INSERT INTO gig.gig_request (
                organization_id, created_by_user_account_id, title, description, deliverables,
                pricing_type, budget_amount, currency_code, start_date, end_date, request_status
            ) VALUES (
                %s, %s, %s, 'Project Description', 'Milestone Deliverable',
                'fixed', 5000.00, 'USD', '2026-12-01', '2026-12-15', 'open'
            ) RETURNING id;
            """,
            (org_id, user_id, f"Sprint Gig Task {i}")
        )
        req_id = cur.fetchone()[0]

        cur.execute(
            """
            INSERT INTO gig.gig_application (
                gig_request_id, gig_worker_profile_id, bid_amount, currency_code, application_status, decided_at
            ) VALUES (%s, %s, 5000.00, 'USD', 'accepted', CURRENT_TIMESTAMP) RETURNING id;
            """,
            (req_id, worker_id)
        )
        app_id = cur.fetchone()[0]
        req_and_app_ids.append((req_id, app_id))

    conn.close()

    results = []

    def attempt_assignment(idx):
        req_id, app_id = req_and_app_ids[idx]
        t_conn = get_connection()
        t_conn.autocommit = True
        t_cur = t_conn.cursor()
        try:
            t_cur.execute(
                """
                INSERT INTO gig.gig_assignment (
                    gig_request_id, gig_application_id, gig_worker_profile_id,
                    assigned_start_date, assigned_end_date, agreed_amount, currency_code,
                    assignment_status, external_handoff_ref
                ) VALUES (
                    %s, %s, %s,
                    '2026-12-05', '2026-12-10', 5000.00, 'USD',
                    'active', %s
                ) RETURNING id;
                """,
                (req_id, app_id, worker_id, f"ext_ref_{uuid.uuid4().hex[:8]}")
            )
            assign_id = t_cur.fetchone()[0]
            t_conn.close()
            return {"thread": idx, "success": True, "assignment_id": assign_id}
        except psycopg2.errors.ExclusionViolation as ex:
            t_conn.close()
            return {"thread": idx, "success": False, "exclusion_caught": True}
        except Exception as e:
            t_conn.close()
            return {"thread": idx, "success": False, "other_error": str(e)}

    with ThreadPoolExecutor(max_workers=num_threads) as executor:
        futures = [executor.submit(attempt_assignment, i) for i in range(num_threads)]
        for f in as_completed(futures):
            results.append(f.result())

    successes = sum(1 for r in results if r.get("success"))
    exclusions = sum(1 for r in results if r.get("exclusion_caught"))

    print(f"Total concurrent assignment attempts on overlapping dates: {num_threads}")
    print(f"Successful bookings: {successes} (Expected: 1)")
    print(f"Blocked by ex_gig_assignment_no_overlap: {exclusions} (Expected: {num_threads - 1})")

    assert successes == 1, f"Expected exactly 1 assignment to succeed, got {successes}"
    assert exclusions == num_threads - 1, f"Expected {num_threads - 1} exclusion rejections, got {exclusions}"
    print("PASS: btree_gist exclusion constraint successfully prevented double booking under race conditions!")


def test_concurrent_wallet_debits():
    print("\n--- Test 3: Concurrent Wallet Debits & Ledger Integrity (Rule Group 10 & B47) ---")
    conn = get_connection()
    conn.autocommit = True
    cur = conn.cursor()

    test_email = f"wallet_user_{uuid.uuid4().hex[:8]}@example.com"
    cur.execute("INSERT INTO core.user_account (email, account_status) VALUES (%s, 'active') RETURNING id;", (test_email,))
    user_id = cur.fetchone()[0]

    cur.execute(
        "INSERT INTO recruitment.organization (name, slug, organization_type, created_by_user_account_id) "
        "VALUES (%s, %s, 'employer', %s) RETURNING id;",
        (f"Wallet Org {uuid.uuid4().hex[:6]}", f"wallet-org-{uuid.uuid4().hex[:8]}", user_id)
    )
    org_id = cur.fetchone()[0]

    # Initial wallet balance = 100.00
    cur.execute(
        "INSERT INTO commercial.wallet (organization_id, balance, currency_code) VALUES (%s, 100.00, 'USD') RETURNING id;",
        (org_id,)
    )
    wallet_id = cur.fetchone()[0]

    # Initial recharge ledger entry
    cur.execute(
        """
        INSERT INTO commercial.wallet_ledger (
            wallet_id, entry_type, amount, currency_code, balance_after,
            reference_type, notes, created_by_user_account_id
        ) VALUES (
            %s, 'credit', 100.00, 'USD', 100.00,
            'recharge', 'Initial seeding', %s
        );
        """,
        (wallet_id, user_id)
    )
    conn.close()

    # 10 threads trying to debit 15.00 each simultaneously
    # Total requested = 150.00, but only 100.00 is available
    # Exactly 6 debits can succeed (6 * 15 = 90.00, remaining = 10.00)
    # The 7th-10th must fail due to check constraint ck_wallet_balance (balance >= 0.00)
    num_threads = 10
    debit_amount = 15.00
    results = []

    def attempt_debit(idx):
        t_conn = get_connection()
        t_cur = t_conn.cursor()
        try:
            t_cur.execute("BEGIN;")
            # Pessimistic update with atomic constraint verification
            t_cur.execute(
                """
                UPDATE commercial.wallet
                SET balance = balance - %s
                WHERE id = %s
                RETURNING balance;
                """,
                (debit_amount, wallet_id)
            )
            new_balance = t_cur.fetchone()[0]

            t_cur.execute(
                """
                INSERT INTO commercial.wallet_ledger (
                    wallet_id, entry_type, amount, currency_code, balance_after,
                    reference_type, notes, created_by_user_account_id
                ) VALUES (
                    %s, 'debit', %s, 'USD', %s,
                    'profile_download', %s, %s
                );
                """,
                (wallet_id, debit_amount, new_balance, f"Download candidate #{idx}", user_id)
            )
            t_conn.commit()
            t_conn.close()
            return {"thread": idx, "success": True, "balance_after": float(new_balance)}
        except psycopg2.errors.CheckViolation as ex:
            t_conn.rollback()
            t_conn.close()
            return {"thread": idx, "success": False, "insufficient_balance": True}
        except Exception as e:
            t_conn.rollback()
            t_conn.close()
            return {"thread": idx, "success": False, "error": str(e)}

    with ThreadPoolExecutor(max_workers=num_threads) as executor:
        futures = [executor.submit(attempt_debit, i) for i in range(num_threads)]
        for f in as_completed(futures):
            results.append(f.result())

    success_debits = sum(1 for r in results if r.get("success"))
    rejected_debits = sum(1 for r in results if r.get("insufficient_balance"))

    print(f"Total concurrent debit attempts of ${debit_amount}: {num_threads}")
    print(f"Successful debits: {success_debits} (Expected: 6)")
    print(f"Rejected debits (insufficient balance): {rejected_debits} (Expected: 4)")

    assert success_debits == 6, f"Expected exactly 6 debits, got {success_debits}"
    assert rejected_debits == 4, f"Expected exactly 4 rejections, got {rejected_debits}"

    # Verify final wallet balance in DB
    v_conn = get_connection()
    v_cur = v_conn.cursor()
    v_cur.execute("SELECT balance FROM commercial.wallet WHERE id = %s;", (wallet_id,))
    final_balance = float(v_cur.fetchone()[0])

    # Verify ledger consistency: initial credit (100) - 6 debits (90) = 10
    v_cur.execute(
        """
        SELECT 
            COALESCE(SUM(CASE WHEN entry_type = 'credit' THEN amount ELSE -amount END), 0)
        FROM commercial.wallet_ledger
        WHERE wallet_id = %s;
        """,
        (wallet_id,)
    )
    ledger_sum = float(v_cur.fetchone()[0])
    v_conn.close()

    print(f"Final wallet balance in DB: ${final_balance:.2f} (Expected: $10.00)")
    print(f"Sum of append-only ledger entries: ${ledger_sum:.2f} (Expected: $10.00)")

    assert abs(final_balance - 10.00) < 0.001, f"Expected final balance 10.00, got {final_balance}"
    assert abs(ledger_sum - final_balance) < 0.001, f"Ledger sum {ledger_sum} does not match balance {final_balance}"
    print("PASS: Atomic debit serialization and append-only ledger consistency 100% verified!")


if __name__ == "__main__":
    print("======================================================================")
    print("   Talentra High-Concurrency Multi-Threaded Verification Harness")
    print("======================================================================")
    try:
        test_concurrent_device_logins()
        test_concurrent_gig_assignments()
        test_concurrent_wallet_debits()
        print("\n======================================================================")
        print("   ALL CONCURRENCY AND RACE-CONDITION TESTS PASSED (100% GREEN)       ")
        print("======================================================================")
        sys.exit(0)
    except AssertionError as ae:
        print(f"\n[FAIL] Assertion Failed: {ae}")
        sys.exit(1)
    except Exception as e:
        print(f"\n[ERROR] Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(2)
