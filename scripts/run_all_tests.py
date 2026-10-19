#!/usr/bin/env python3
"""
Talentra Automated Test Runner
Discovers and executes all 21 SQL test suites and the multi-threaded concurrency suite.
Reports status, error details, and cumulative summary.
"""

import os
import sys
import subprocess
import glob

def run_all_tests():
    test_dir = os.path.join(os.path.dirname(__file__), "..", "tests")
    sql_files = sorted(glob.glob(os.path.join(test_dir, "*.sql")))

    print("======================================================================")
    print("           TALENTRA AUTOMATED TEST SUITE EXECUTION                    ")
    print("======================================================================")
    print(f"Discovered {len(sql_files)} SQL test suites + 1 Concurrency test suite.\n")

    passed_count = 0
    failed_count = 0
    failures = []

    # 1. Run all SQL test suites
    for sql_file in sql_files:
        test_name = os.path.basename(sql_file)
        try:
            with open(sql_file, "r", encoding="utf-8") as f:
                content = f.read()

            proc = subprocess.run(
                ["docker", "exec", "-i", "-e", "PGCLIENTENCODING=UTF8", "talentra-postgres", "psql", "-U", "talentra_admin", "-d", "talentra"],
                input=content.encode("utf-8"),
                capture_output=True,
                check=False
            )

            output = (proc.stdout + proc.stderr).decode("utf-8", errors="replace")
            if "ERROR:" in output or proc.returncode != 0:
                print(f" [FAIL] {test_name}")
                failed_count += 1
                failures.append((test_name, output))
            else:
                print(f" [PASS] {test_name}")
                passed_count += 1
        except Exception as e:
            print(f" [ERROR] {test_name}: {e}")
            failed_count += 1
            failures.append((test_name, str(e)))

    # 2. Run Concurrency Suite
    print("\n--- Running Multi-Threaded Concurrency Test Suite ---")
    py_concurrency = os.path.join(test_dir, "test_concurrency.py")
    if os.path.exists(py_concurrency):
        proc_py = subprocess.run(
            [sys.executable, py_concurrency],
            capture_output=True,
            text=True,
            check=False
        )
        if proc_py.returncode == 0:
            print(" [PASS] test_concurrency.py (Multi-threaded race conditions)")
            passed_count += 1
        else:
            print(" [FAIL] test_concurrency.py")
            print(proc_py.stdout + proc_py.stderr)
            failed_count += 1
            failures.append(("test_concurrency.py", proc_py.stdout + proc_py.stderr))

    total = passed_count + failed_count
    print("\n======================================================================")
    print(f" TEST RUN SUMMARY: {passed_count}/{total} Passed ({(passed_count/total)*100:.1f}%)")
    print("======================================================================")

    if failures:
        print("\nFailures:")
        for name, err in failures:
            print(f"\n--- Failure in {name} ---")
            print(err[:500])
        sys.exit(1)
    else:
        print("\nAll tests executed with 100% green status across all schemas and rules!")
        sys.exit(0)

if __name__ == "__main__":
    run_all_tests()
