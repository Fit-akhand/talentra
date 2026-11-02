#!/usr/bin/env python3
"""Mixed-workload load test (playbook step 28; NFR-001 to 006, 009 under concurrency; NFR-005).

Builds a scratch database (migrations + medium seed), then runs a realistic mix from N concurrent clients for a fixed time at each of
several concurrency levels, and reports throughput, errors and per-operation latency at each level, to show where latency starts to rise.

Mix: candidate search 25%, job feed 25%, pipeline funnel 10%, application insert 15%, wallet debit through commercial.post_wallet_entry 10%,
login through core.create_session_with_device_limit 15%.
Limits: the client is Python threads on one machine against a default-configuration server, so absolute numbers include client overhead;
the shape (flat, then rising) is what matters. The queries run as the table owner, so row-level security cost is not included.
Usage: python3 scripts/run_load_test.py [--seconds 8] [--levels 1,8,32,64] [--keep]      (reads PG* variables)
"""
import argparse, hashlib, json, os, random, subprocess, sys, threading, time, uuid
import psycopg2

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
H, P, U, PW = os.getenv("PGHOST", "127.0.0.1"), int(os.getenv("PGPORT", "5432")), os.getenv("PGUSER", "talentra_admin"), os.getenv("PGPASSWORD")
OPS = [("search", 25), ("feed", 25), ("funnel", 10), ("apply", 15), ("wallet_debit", 10), ("login", 15)]
TARGET_P95 = {"search": 50.0, "feed": 20.0, "funnel": 25.0, "apply": 50.0, "wallet_debit": 50.0, "login": 50.0}   # NFR-001, 002, 009, 003; the last two are proposed here


def connect(db):
    c = psycopg2.connect(host=H, port=P, user=U, password=PW, dbname=db); c.autocommit = True; return c


def pct(xs, p):
    xs = sorted(xs); k = (len(xs) - 1) * p / 100; lo = int(k); hi = min(lo + 1, len(xs) - 1)
    return xs[lo] + (xs[hi] - xs[lo]) * (k - lo)


def build():
    name = f"talentra_load_{uuid.uuid4().hex[:8]}"
    a = connect("postgres"); a.cursor().execute(f'CREATE DATABASE "{name}"'); a.close()
    c = connect(name); mig = os.path.join(ROOT, "db", "migrations")
    for f in sorted(os.listdir(mig)):
        if f.endswith(".sql"): c.cursor().execute(open(os.path.join(mig, f), encoding="utf-8").read())
    c.close()
    env = {k: v for k, v in os.environ.items() if not k.startswith(("POSTGRES_", "DB_"))}
    env.update(PGDATABASE=name, PGHOST=H, PGPORT=str(P), PGUSER=U)
    if PW: env["PGPASSWORD"] = PW
    subprocess.run([sys.executable, os.path.join(ROOT, "scripts", "generate_data.py"), "--scale", "medium"], env=env, check=True, capture_output=True)
    return name


def drop(name):
    a = connect("postgres"); cur = a.cursor()
    cur.execute("SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = %s AND pid <> pg_backend_pid()", (name,))
    cur.execute(f'DROP DATABASE IF EXISTS "{name}"'); a.close()


def prepare(db, maxclients):
    c = connect(db); cur = c.cursor()
    cur.execute("SELECT min(id) FROM core.user_account"); admin = cur.fetchone()[0]
    cur.execute("SELECT array_agg(id) FROM (SELECT id FROM profile.candidate_profile ORDER BY id LIMIT 5000) x"); cands = cur.fetchone()[0]
    cur.execute("SELECT array_agg(id) FROM (SELECT id FROM recruitment.job_posting ORDER BY id LIMIT 1000) x"); jobs = cur.fetchone()[0]
    tenants = []      # one recruiter, organisation and funded wallet per client, as in production where organisations do not share a wallet
    for k in range(maxclients):
        cur.execute("INSERT INTO core.user_account (email, account_status) VALUES (%s, 'active') RETURNING id", (f"load_recruiter_{k}@example.com",)); rec = cur.fetchone()[0]
        cur.execute("INSERT INTO recruitment.organization (name, slug, organization_type, created_by_user_account_id) VALUES (%s, %s, 'employer', %s) RETURNING id", (f"Load Org {k}", f"load-org-{k}", admin)); org = cur.fetchone()[0]
        cur.execute("INSERT INTO recruitment.organization_member (organization_id, user_account_id, organization_role, membership_status, joined_at) VALUES (%s, %s, 'recruiter', 'active', now())", (org, rec))
        cur.execute("INSERT INTO commercial.wallet (organization_id, balance, currency_code) VALUES (%s, 1000000, 'USD') RETURNING id", (org,)); wallet = cur.fetchone()[0]
        cur.execute("INSERT INTO commercial.wallet_ledger (wallet_id, entry_type, amount, balance_after, reference_type, created_by_user_account_id) VALUES (%s, 'credit', 1000000, 1000000, 'recharge', %s)", (wallet, rec))
        tenants.append((rec, org, wallet))
    cur.execute("INSERT INTO core.user_account (email, account_status) SELECT 'load_user_' || g || '@example.com', 'active' FROM generate_series(1, 60000) g RETURNING id"); users = [r[0] for r in cur.fetchall()]
    c.close()
    sql = {k: open(os.path.join(ROOT, "db", "queries", f), encoding="utf-8").read() for k, f in
           (("search", "01_candidate_multicriteria_search.sql"), ("feed", "02_job_feed_matching.sql"), ("funnel", "03_recruiter_pipeline_funnel.sql"))}
    return dict(admin=admin, tenants=tenants, users=users, cands=cands, jobs=jobs, sql=sql)


def worker(db, ctx, deadline, results, errors, seed, run):
    rnd = random.Random(seed); c = connect(db); cur = c.cursor(); lat = []
    rec, org, wallet = ctx["tenants"][seed % len(ctx["tenants"])]
    cur.execute("SELECT set_config('app.current_user_id', %s, false), set_config('app.current_org_id', %s, false)", (str(rec), str(org)))
    names = [n for n, w in OPS for _ in range(w)]
    i = 0
    while time.perf_counter() < deadline:
        op = rnd.choice(names); i += 1
        t = time.perf_counter()
        try:
            if op in ("search", "feed"): cur.execute(ctx["sql"][op]); cur.fetchall()
            elif op == "funnel": cur.execute(ctx["sql"]["funnel"].replace("ca.job_posting_id = 1", f"ca.job_posting_id = {rnd.choice(ctx['jobs'])}")); cur.fetchall()
            elif op == "apply":
                cur.execute("INSERT INTO recruitment.candidate_application (candidate_profile_id, job_posting_id, created_by_user_account_id, updated_by_user_account_id) VALUES (%s, %s, %s, %s) ON CONFLICT DO NOTHING",
                            (rnd.choice(ctx["cands"]), rnd.choice(ctx["jobs"]), ctx["admin"], ctx["admin"]))
            elif op == "wallet_debit": cur.execute("SELECT commercial.post_wallet_entry(%s, 'debit', 0.01, 'profile_download', %s)", (wallet, i)); cur.fetchone()
            else:
                u = rnd.choice(ctx["users"])
                cur.execute("SELECT core.create_session_with_device_limit(%s, %s, %s, 'load', 'desktop', '127.0.0.1')", (u, f"d-{run}-{seed}-{i}", hashlib.sha256(f"{run}-{seed}-{i}".encode()).hexdigest()))
                cur.fetchone()
            lat.append((op, (time.perf_counter() - t) * 1000))
        except Exception as e:
            errors.append((op, getattr(e, "pgcode", None) or type(e).__name__, str(e)[:100]))
    c.close(); results.extend(lat)


def run_level(db, ctx, n, seconds):
    results, errors, threads = [], [], []
    deadline = time.perf_counter() + seconds
    for k in range(n):
        th = threading.Thread(target=worker, args=(db, ctx, deadline, results, errors, k, f"{n}-{uuid.uuid4().hex[:6]}")); th.start(); threads.append(th)
    for th in threads: th.join()
    per = {}
    for op, ms in results: per.setdefault(op, []).append(ms)
    out = {"clients": n, "seconds": seconds, "operations": len(results), "per_second": round(len(results) / seconds, 1), "errors": len(errors),
           "error_codes": sorted({f"{o}:{c}" for o, c, _ in errors}), "ops": {}}
    for op, xs in per.items():
        out["ops"][op] = {"n": len(xs), "p50_ms": round(pct(xs, 50), 2), "p95_ms": round(pct(xs, 95), 2), "p99_ms": round(pct(xs, 99), 2)}
    return out


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--seconds", type=int, default=8); ap.add_argument("--levels", default="1,8,32,64"); ap.add_argument("--keep", action="store_true")
    args = ap.parse_args(); levels = [int(x) for x in args.levels.split(",")]
    t0 = time.time(); db = build(); print(f"scratch database {db} with the medium seed in {time.time() - t0:.0f}s", flush=True)
    c = connect(db); cur = c.cursor(); cur.execute("SHOW server_version"); ver = cur.fetchone()[0]; cur.execute("SHOW max_connections"); maxc = int(cur.fetchone()[0]); c.close()
    res = {"measured_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "engine": f"PostgreSQL {ver}", "max_connections": maxc, "cpus": os.cpu_count(),
           "dataset": "medium seed (10,000 candidates, 1,000 jobs, 50,000 applications)", "mix": dict(OPS), "levels": []}
    try:
        ctx = prepare(db, max(levels))
        for n in levels:
            if n > maxc - 15: print(f"skipping {n} clients: server allows {maxc} connections"); continue
            r = run_level(db, ctx, n, args.seconds); res["levels"].append(r)
            worst = max((v["p95_ms"] for v in r["ops"].values()), default=0)
            print(f"{n:>3} clients: {r['per_second']:>8} ops/s, {r['errors']} errors, worst p95 {worst} ms", flush=True)
        c = connect(db); cur = c.cursor()
        cur.execute("""SELECT coalesce(max(abs(w.balance - l.s)), 0) FROM commercial.wallet w
                         JOIN (SELECT wallet_id, sum(CASE WHEN entry_type IN ('credit','correction_credit') THEN amount ELSE -amount END) AS s FROM commercial.wallet_ledger GROUP BY 1) l ON l.wallet_id = w.id""")
        drift = float(cur.fetchone()[0]); cur.execute("SELECT count(*) FROM core.user_session"); sessions = cur.fetchone()[0]
        cur.execute("""SELECT count(*) FROM (SELECT user_account_id FROM core.user_session WHERE ended_at IS NULL AND revoked_at IS NULL
                        GROUP BY user_account_id HAVING count(DISTINCT device_identifier) > 2) x"""); breaches = cur.fetchone()[0]; c.close()
        res["integrity_after"] = {"largest_wallet_minus_ledger_difference": drift, "sessions_written": sessions, "users_over_device_limit": breaches}
    finally:
        if not args.keep: drop(db)
    ok = all(l["errors"] == 0 for l in res["levels"]) and res["integrity_after"]["largest_wallet_minus_ledger_difference"] == 0 and res["integrity_after"]["users_over_device_limit"] == 0
    knee = None
    base = {op: v["p95_ms"] for op, v in res["levels"][0]["ops"].items()} if res["levels"] else {}
    for l in res["levels"][1:]:
        if any(v["p95_ms"] > max(3 * base.get(op, 0), 2.0) for op, v in l["ops"].items()): knee = l["clients"]; break
    res["latency_rises_at_clients"] = knee; res["clean"] = ok
    out = os.path.join(ROOT, "benchmarks", "results"); os.makedirs(out, exist_ok=True)
    json.dump(res, open(os.path.join(out, "load_test.json"), "w"), indent=2)
    md = ["# Mixed-workload load test", "", f"{res['engine']}, max_connections {maxc}, {res['cpus']} CPUs, {res['measured_at']}. `scripts/run_load_test.py`. {res['dataset']}. Mix: " + ", ".join(f"{k} {v}%" for k, v in OPS) + ".", "",
          "Client: Python threads on the same machine as the server, default server configuration. Absolute numbers include client overhead.", "",
          "| Clients | ops/s | errors | " + " | ".join(f"{op} p95" for op, _ in OPS) + " |", "|--:|--:|--:|" + "--:|" * len(OPS)]
    for l in res["levels"]:
        md.append(f"| {l['clients']} | {l['per_second']} | {l['errors']} | " + " | ".join(f"{l['ops'].get(op, {}).get('p95_ms', '-')} ms" for op, _ in OPS) + " |")
    md += ["", f"After the run: largest difference between a wallet balance and its ledger sum = **{res['integrity_after']['largest_wallet_minus_ledger_difference']}**; {res['integrity_after']['sessions_written']} sessions written; users over the device limit: **{res['integrity_after']['users_over_device_limit']}**.",
           f"Latency (p95 more than 3x the single-client figure) first rises at **{knee if knee else 'no tested level'}** clients."]
    open(os.path.join(out, "load_test.md"), "w").write("\n".join(md) + "\n")
    print("\n".join(md)); sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
