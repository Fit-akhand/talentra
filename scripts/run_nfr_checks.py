#!/usr/bin/env python3
"""Measure the NFRs that the benchmark queries do not cover (docs/phase-1-discover/04-nfr-register.md).

  NFR-003  single-row write latency (insert of an application, constraints and the stage-history trigger included, commit included)
  NFR-005  concurrent sessions: 500 logins by 500 users, and 500 attempts by one user with a 2-device limit
  NFR-006  master-data lookup latency
  NFR-009  pipeline aggregation over 50,000 applications to one job

It builds its own scratch database (migrations + dev seed), measures, writes benchmarks/results/nfr_results.json and .md, and drops it.
Latencies are client-side round trips on the connection used, so they include the network hop (loopback in practice).
Usage: python3 scripts/run_nfr_checks.py [--keep]      (reads PG* variables)
"""
import json, os, statistics, subprocess, sys, threading, time, uuid, hashlib
from concurrent.futures import ThreadPoolExecutor
import psycopg2

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
H, P, U, PW = os.getenv("PGHOST", "127.0.0.1"), int(os.getenv("PGPORT", "5432")), os.getenv("PGUSER", "talentra_admin"), os.getenv("PGPASSWORD")
TARGETS = {"NFR-003": 50.0, "NFR-006": 5.0, "NFR-009": 25.0}      # p95 ms, as proposed in the register
POOL_LIMIT = 80      # connections held at once; the server default is max_connections = 100


def connect(db, autocommit=True):
    c = psycopg2.connect(host=H, port=P, user=U, password=PW, dbname=db)
    c.autocommit = autocommit
    return c


def pct(xs, p):
    xs = sorted(xs); k = (len(xs) - 1) * p / 100
    lo, hi = int(k), min(int(k) + 1, len(xs) - 1)
    return xs[lo] + (xs[hi] - xs[lo]) * (k - lo)


def summarise(xs):
    return {"n": len(xs), "p50_ms": round(pct(xs, 50), 3), "p95_ms": round(pct(xs, 95), 3), "p99_ms": round(pct(xs, 99), 3), "max_ms": round(max(xs), 3)}


def build_scratch():
    name = f"talentra_nfr_{uuid.uuid4().hex[:8]}"
    a = connect("postgres"); a.cursor().execute(f'CREATE DATABASE "{name}"'); a.close()
    c = connect(name)
    mig = os.path.join(ROOT, "db", "migrations")
    for f in sorted(os.listdir(mig)):
        if f.endswith(".sql"):
            c.cursor().execute(open(os.path.join(mig, f), encoding="utf-8").read())
    c.close()
    env = {k: v for k, v in os.environ.items() if not k.startswith(("POSTGRES_", "DB_"))}      # the generator must see only the scratch database
    env.update(PGDATABASE=name, PGHOST=H, PGPORT=str(P), PGUSER=U)
    if PW: env["PGPASSWORD"] = PW
    subprocess.run([sys.executable, os.path.join(ROOT, "scripts", "generate_data.py"), "--scale", "dev"], env=env, check=True, capture_output=True)
    return name


def drop_scratch(name):
    a = connect("postgres"); cur = a.cursor()
    cur.execute("SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = %s AND pid <> pg_backend_pid()", (name,))
    cur.execute(f'DROP DATABASE IF EXISTS "{name}"'); a.close()


def nfr006(db):
    c = connect(db); cur = c.cursor()
    cur.execute("SELECT normalized_name FROM master.skill ORDER BY id LIMIT 200"); skills = [r[0] for r in cur.fetchall()]
    cur.execute("SELECT name FROM master.city ORDER BY id LIMIT 200"); cities = [r[0] for r in cur.fetchall()]
    cur.execute("SELECT iso_alpha3 FROM master.country ORDER BY id LIMIT 200"); countries = [r[0] for r in cur.fetchall()]
    qs = [("SELECT id FROM master.skill WHERE normalized_name = %s", skills), ("SELECT id FROM master.city WHERE name = %s", cities),
          ("SELECT id FROM master.country WHERE iso_alpha3 = %s", countries)]
    for sql, vals in qs:                       # warm-up
        for v in vals[:20]: cur.execute(sql, (v,)); cur.fetchall()
    ts = []
    for _ in range(5):
        for sql, vals in qs:
            for v in vals:
                t = time.perf_counter(); cur.execute(sql, (v,)); rows = cur.fetchall(); ts.append((time.perf_counter() - t) * 1000)
                assert rows, f"lookup of {v!r} returned nothing"
    c.close()
    return summarise(ts)


def nfr003(db):
    c = connect(db, autocommit=False); cur = c.cursor()
    cur.execute("SELECT min(id) FROM core.user_account"); uid = cur.fetchone()[0]
    cur.execute("SELECT id FROM recruitment.job_posting ORDER BY id LIMIT 1"); job = cur.fetchone()[0]
    cur.execute("SELECT id FROM profile.candidate_profile ORDER BY id LIMIT 300"); cands = [r[0] for r in cur.fetchall()]
    c.commit(); ts = []
    for cand in cands:
        t = time.perf_counter()
        cur.execute("INSERT INTO recruitment.candidate_application (candidate_profile_id, job_posting_id, created_by_user_account_id, updated_by_user_account_id) "
                    "VALUES (%s, %s, %s, %s) ON CONFLICT DO NOTHING RETURNING id", (cand, job, uid, uid))
        r = cur.fetchone(); c.commit(); dt = (time.perf_counter() - t) * 1000
        if r: ts.append(dt)
    cur.execute("SELECT count(*) FROM recruitment.application_status_history h JOIN recruitment.candidate_application a ON a.id = h.candidate_application_id WHERE a.job_posting_id = %s", (job,))
    hist = cur.fetchone()[0]; c.close()
    out = summarise(ts); out["history_rows_written_by_trigger"] = hist
    return out


def session_attempt(db, uid, i, tag):
    c = connect(db); cur = c.cursor()
    tok = hashlib.sha256(f"{tag}-{uid}-{i}".encode()).hexdigest()
    t = time.perf_counter()
    try:
        cur.execute("SELECT core.create_session_with_device_limit(%s, %s, %s, %s, 'mobile', '127.0.0.1')", (uid, f"dev-{tag}-{i}", tok, f"D{i}"))
        ok = cur.fetchone()[0] is not None; err = None
    except Exception as e:
        ok, err = False, getattr(e, "pgcode", None) or str(e)[:60]
    dt = (time.perf_counter() - t) * 1000; c.close()
    return ok, err, dt


def nfr005(db):
    c = connect(db); cur = c.cursor()
    cur.execute("INSERT INTO core.user_account (email, account_status) SELECT 'nfr005_' || g || '@example.com', 'active' FROM generate_series(1, 501) g RETURNING id")
    ids = [r[0] for r in cur.fetchall()]
    cur.execute("INSERT INTO recruitment.organization (name, slug, organization_type, created_by_user_account_id) VALUES ('NFR005 Org', 'nfr005-org', 'employer', %s) RETURNING id", (ids[0],))
    org = cur.fetchone()[0]
    cur.execute("INSERT INTO commercial.subscription_licence (organization_id, licence_key, licence_name, max_users, max_devices_per_user, valid_from, valid_to, licence_status) "
                "VALUES (%s, 'NFR005-LIC', 'NFR 005', 1000, 2, now() - interval '1 day', now() + interval '1 year', 'active') RETURNING id", (org,))
    lic = cur.fetchone()[0]
    cur.execute("INSERT INTO commercial.licence_seat_allocation (subscription_licence_id, user_account_id) SELECT %s, unnest(%s::bigint[])", (lic, ids))
    # (a) 500 different users log in at once
    t0 = time.perf_counter()
    with ThreadPoolExecutor(max_workers=POOL_LIMIT) as ex:
        a = list(ex.map(lambda i: session_attempt(db, ids[i], 0, "a"), range(500)))
    wall_a = time.perf_counter() - t0
    # (b) 500 attempts, one user, two devices allowed: exactly 2 may succeed
    hot = ids[500]
    t0 = time.perf_counter()
    with ThreadPoolExecutor(max_workers=POOL_LIMIT) as ex:
        b = list(ex.map(lambda i: session_attempt(db, hot, i, "b"), range(500)))
    wall_b = time.perf_counter() - t0
    cur.execute("SELECT count(*) FROM core.user_session WHERE user_account_id = %s AND revoked_at IS NULL", (hot,)); open_hot = cur.fetchone()[0]
    c.close()
    return {"max_connections_in_flight": POOL_LIMIT,
            "different_users": {"attempts": 500, "succeeded": sum(x[0] for x in a), "wall_seconds": round(wall_a, 2), "latency": summarise([x[2] for x in a])},
            "one_user_two_devices": {"attempts": 500, "succeeded": sum(x[0] for x in b), "open_sessions_in_database": open_hot, "wall_seconds": round(wall_b, 2),
                                     "rejection_codes": sorted({str(x[1]) for x in b if not x[0]}), "latency": summarise([x[2] for x in b])},
            "deadlocks": sum(1 for x in a + b if x[1] == "40P01")}


def nfr009(db):
    c = connect(db); cur = c.cursor()
    cur.execute("SELECT min(id) FROM core.user_account"); uid = cur.fetchone()[0]
    cur.execute("INSERT INTO core.user_account (email, account_status) SELECT 'nfr009_' || g || '@example.com', 'active' FROM generate_series(1, 50000) g RETURNING id")
    users = [r[0] for r in cur.fetchall()]
    cur.execute("INSERT INTO profile.candidate_profile (user_account_id) SELECT unnest(%s::bigint[]) RETURNING id", (users,))
    cands = [r[0] for r in cur.fetchall()]
    cur.execute("SELECT id FROM recruitment.job_posting ORDER BY id DESC LIMIT 1"); job = cur.fetchone()[0]
    statuses = ["applied", "shortlisted", "interviewed", "offered", "joined", "rejected"]
    t0 = time.perf_counter()
    cur.execute("INSERT INTO recruitment.candidate_application (candidate_profile_id, job_posting_id, application_status, created_by_user_account_id, updated_by_user_account_id) "
                "SELECT c, %s, (%s::text[])[1 + (c %% 6)], %s, %s FROM unnest(%s::bigint[]) c", (job, statuses, uid, uid, cands))
    load = time.perf_counter() - t0
    cur.execute("ANALYZE recruitment.candidate_application")
    cur.execute("SELECT count(*) FROM recruitment.candidate_application WHERE job_posting_id = %s", (job,)); n = cur.fetchone()[0]
    sql = open(os.path.join(ROOT, "db", "queries", "03_recruiter_pipeline_funnel.sql")).read() if os.path.exists(os.path.join(ROOT, "db", "queries", "03_recruiter_pipeline_funnel.sql")) else None
    if sql is None:
        f = [x for x in os.listdir(os.path.join(ROOT, "db", "queries")) if x.startswith("03")][0]
        sql = open(os.path.join(ROOT, "db", "queries", f)).read()
    sql = sql.replace("ca.job_posting_id = 1", f"ca.job_posting_id = {job}")
    for _ in range(3): cur.execute(sql); cur.fetchall()
    ts = []
    for _ in range(30):
        t = time.perf_counter(); cur.execute(sql); rows = cur.fetchall(); ts.append((time.perf_counter() - t) * 1000)
    c.close()
    out = summarise(ts); out.update({"applications_on_the_job": n, "stages_returned": len(rows), "bulk_load_seconds": round(load, 2)})
    return out


def main():
    keep = "--keep" in sys.argv
    t0 = time.time(); db = build_scratch(); print(f"scratch database {db} ready in {time.time() - t0:.0f}s")
    c = connect(db); cur = c.cursor(); cur.execute("SHOW server_version"); ver = cur.fetchone()[0]; cur.execute("SHOW max_connections"); maxc = cur.fetchone()[0]; c.close()
    res = {"measured_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "engine": f"PostgreSQL {ver}", "max_connections": int(maxc), "dataset": "dev seed plus the rows each check adds"}
    try:
        for k, fn in (("NFR-006", nfr006), ("NFR-003", nfr003), ("NFR-005", nfr005), ("NFR-009", nfr009)):
            print(f"{k} ...", flush=True); res[k] = fn(db); print("  ", json.dumps(res[k])[:300])
    finally:
        if not keep: drop_scratch(db)
    for k, tgt in TARGETS.items():
        res[k]["target_p95_ms"] = tgt; res[k]["met"] = res[k]["p95_ms"] <= tgt
    r5 = res["NFR-005"]
    res["NFR-005"]["met"] = (r5["different_users"]["succeeded"] == 500 and r5["one_user_two_devices"]["succeeded"] == 2
                              and r5["one_user_two_devices"]["open_sessions_in_database"] == 2 and r5["deadlocks"] == 0)
    out = os.path.join(ROOT, "benchmarks", "results"); os.makedirs(out, exist_ok=True)
    json.dump(res, open(os.path.join(out, "nfr_results.json"), "w"), indent=2)
    md = ["# NFR measurements", "", f"{res['engine']}, max_connections {res['max_connections']}, {res['measured_at']}. Generated by `scripts/run_nfr_checks.py`; latencies are client round trips.", "",
          "| NFR | Result | Target | Met |", "|:--|:--|:--|:--|"]
    for k in ("NFR-003", "NFR-006", "NFR-009"):
        r = res[k]; md.append(f"| {k} | n={r['n']}, p50 {r['p50_ms']} ms, p95 {r['p95_ms']} ms, p99 {r['p99_ms']} ms | p95 <= {r['target_p95_ms']} ms | {'yes' if r['met'] else '**NO**'} |")
    md.append(f"| NFR-005 | 500 users: {r5['different_users']['succeeded']}/500 succeeded in {r5['different_users']['wall_seconds']} s; one user, 500 attempts, 2 devices: {r5['one_user_two_devices']['succeeded']} succeeded, {r5['one_user_two_devices']['open_sessions_in_database']} open; deadlocks {r5['deadlocks']}; at most {POOL_LIMIT} connections in flight | 500 sessions, 0 breaches | {'yes' if r5['met'] else '**NO**'} |")
    open(os.path.join(out, "nfr_results.md"), "w").write("\n".join(md) + "\n")
    print("\n".join(md))
    sys.exit(0 if all(res[k]["met"] for k in ("NFR-003", "NFR-005", "NFR-006", "NFR-009")) else 1)


if __name__ == "__main__":
    main()
