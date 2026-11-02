#!/usr/bin/env python3
"""Golden-dataset KPI reconciliation (lifecycle steps 14, 29, 30; gate G5).

Creates an empty scratch database, applies every migration, loads db/seeds/golden_dataset.sql
(a hand-built state whose answers are known), runs each query in db/kpi/ and compares the rows with
tests/golden_kpi_expected.json. A KPI that computes the wrong number fails here, which a test that
only checks "the query runs" would never notice.

Needs permission to CREATE DATABASE. Connection: PGHOST, PGPORT, PGUSER, PGPASSWORD.
"""
# Covers: BR-017, OPS-005, REQ-024   (generated from the registers by scripts/lifecycle/tag_tests.py)
import glob
import json
import os
import re
import sys
import uuid
from decimal import Decimal

import psycopg2

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
HOST = os.getenv("POSTGRES_HOST") or os.getenv("PGHOST", "127.0.0.1")
PORT = int(os.getenv("POSTGRES_PORT") or os.getenv("PGPORT", "5432"))
USER = os.getenv("POSTGRES_USER") or os.getenv("PGUSER", "talentra_admin")
PASSWORD = os.getenv("POSTGRES_PASSWORD") or os.getenv("PGPASSWORD")


def connect(dbname):
    return psycopg2.connect(host=HOST, port=PORT, user=USER, password=PASSWORD, dbname=dbname)


def norm(value):
    if isinstance(value, Decimal):
        return format(value.quantize(Decimal("0.01")), "f")
    return value


def canonical(rows):
    return sorted((tuple(sorted((k, norm(v)) for k, v in r.items())) for r in rows), key=repr)


def main():
    scratch = f"talentra_golden_{uuid.uuid4().hex[:8]}"
    admin = connect("postgres"); admin.autocommit = True
    admin.cursor().execute(f'CREATE DATABASE "{scratch}"')
    failures = []
    try:
        cx = connect(scratch); cx.autocommit = True
        cur = cx.cursor()
        for f in sorted(glob.glob(os.path.join(ROOT, "db", "migrations", "*.sql"))):
            cur.execute(open(f, encoding="utf-8").read())
        cur.execute(open(os.path.join(ROOT, "db", "seeds", "golden_dataset.sql"), encoding="utf-8").read())

        expected = json.load(open(os.path.join(ROOT, "tests", "golden_kpi_expected.json")))
        files = sorted(glob.glob(os.path.join(ROOT, "db", "kpi", "*.sql")))
        seen = set()
        for f in files:
            text = open(f, encoding="utf-8").read()
            kpi_id = re.search(r"-- kpi_id: (KPI-\d+)", text).group(1)
            seen.add(kpi_id)
            cur.execute("\n".join(l for l in text.splitlines() if not l.startswith("--")))
            cols = [d[0] for d in cur.description]
            got = [dict(zip(cols, r)) for r in cur.fetchall()]
            want = expected.get(kpi_id)
            if want is None:
                failures.append(f"{kpi_id}: no expected answer in golden_kpi_expected.json")
            elif canonical(got) != canonical(want):
                failures.append(f"{kpi_id}: expected {want} but the query returned {[{k: norm(v) for k, v in r.items()} for r in got]}")
            else:
                print(f" [PASS] {kpi_id}")
        # fixed benchmark queries whose answer on the golden data is also known (read through a summary, so this guards the refresh too)
        for qid, qfile in (("Q10", "10_analytics_time_to_hire_kpi.sql"),):
            text = open(os.path.join(ROOT, "db", "queries", qfile), encoding="utf-8").read()
            cur.execute("\n".join(l for l in text.splitlines() if not l.startswith("--")))
            cols = [d[0] for d in cur.description]
            got = [dict(zip(cols, r)) for r in cur.fetchall()]
            if canonical(got) != canonical(expected[qid]):
                failures.append(f"{qid}: expected {expected[qid]} but the query returned {[{k: norm(v) for k, v in r.items()} for r in got]}")
            else:
                print(f" [PASS] {qid} ({qfile})")
            seen.add(qid)
        for missing in sorted(set(expected) - seen):
            failures.append(f"{missing}: expected answer has no KPI file")
        cx.close()
    finally:
        cur2 = admin.cursor()
        cur2.execute("SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = %s AND pid <> pg_backend_pid()", (scratch,))
        cur2.execute(f'DROP DATABASE IF EXISTS "{scratch}"')
        admin.close()

    if failures:
        print("\n[FAIL] Golden dataset reconciliation:")
        for f in failures:
            print("  -", f)
        sys.exit(1)
    print(f"\nALL {len(seen)} CHECKS RECONCILE WITH THE GOLDEN DATASET (16 KPIs and fixed query Q10)")


if __name__ == "__main__":
    main()
