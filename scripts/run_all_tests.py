#!/usr/bin/env python3
"""Talentra automated test runner.

Runs every SQL suite in tests/, the concurrency suite, the golden-dataset KPI suite and the
benchmark-harness suite. The Python suites that write data build their own scratch database and
drop it, so the target database is left as it was found.

Connection (first match wins):
  1. Standard libpq variables: PGHOST, PGPORT, PGUSER, PGDATABASE, PGPASSWORD  -> uses local `psql`
  2. --docker [CONTAINER]  -> runs psql inside a container (default name: talentra-postgres)

Exit status is 0 only if every suite passes. A SQL suite passes when psql exits 0 and prints no
`ERROR:` and no `[FAIL]`/`FAIL:` marker.
"""
import argparse, glob, os, subprocess, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
TESTS = os.path.join(ROOT, "tests")

def psql_cmd(args):
    if args.docker:
        return ["docker", "exec", "-i", "-e", "PGCLIENTENCODING=UTF8", args.docker, "psql", "-v", "ON_ERROR_STOP=0",
                "-U", os.getenv("PGUSER", "talentra_admin"), "-d", os.getenv("PGDATABASE", "talentra")]
    return ["psql", "-v", "ON_ERROR_STOP=0", "-X", "-q"]

def run_sql(path, args):
    with open(path, "rb") as f:
        proc = subprocess.run(psql_cmd(args), input=f.read(), capture_output=True,
                              env={**os.environ, "PGCLIENTENCODING": "UTF8"})
    out = (proc.stdout + proc.stderr).decode("utf-8", errors="replace")
    bad = proc.returncode != 0 or "ERROR:" in out or "[FAIL]" in out or "FAIL:" in out
    return (not bad), out

def run_py(path):
    env = dict(os.environ)
    # python suites read POSTGRES_* / DB_*; map the libpq variables so one set works everywhere
    for src, dst in (("PGHOST", "POSTGRES_HOST"), ("PGPORT", "POSTGRES_PORT"), ("PGUSER", "POSTGRES_USER"),
                     ("PGDATABASE", "POSTGRES_DB"), ("PGPASSWORD", "POSTGRES_PASSWORD")):
        if src in env: env.setdefault(dst, env[src])
    proc = subprocess.run([sys.executable, path], capture_output=True, text=True, env=env)
    return proc.returncode == 0, proc.stdout + proc.stderr

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--docker", nargs="?", const="talentra-postgres", default=None, metavar="CONTAINER")
    ap.add_argument("--skip-db-python", action="store_true", help="skip suites that need a database connection from Python")
    args = ap.parse_args()

    sql = sorted(glob.glob(os.path.join(TESTS, "*.sql")))
    print("=" * 70 + "\n TALENTRA TEST RUN\n" + "=" * 70)
    results = []
    for p in sql:
        ok, out = run_sql(p, args); results.append((os.path.basename(p), ok, out))
        print(f" [{'PASS' if ok else 'FAIL'}] {os.path.basename(p)}")
    for name, needs_db in (("test_concurrency.py", True), ("test_golden_kpis.py", True), ("test_benchmark_harness.py", False), ("test_identifier_crypto.py", False)):
        p = os.path.join(TESTS, name)
        if not os.path.exists(p) or (needs_db and args.skip_db_python): continue
        ok, out = run_py(p); results.append((name, ok, out))
        print(f" [{'PASS' if ok else 'FAIL'}] {name}")

    if not args.skip_db_python and not args.docker:
        # NFR suite: write latency, 500-session concurrency, master lookups and a 50,000-application pipeline against the proposed targets
        nfr = os.path.join(os.path.dirname(os.path.abspath(__file__)), "run_nfr_checks.py")
        ok, out = run_py(nfr); results.append(("run_nfr_checks.py (NFR-003, 005, 006, 009)", ok, out))
        print(f" [{'PASS' if ok else 'FAIL'}] run_nfr_checks.py (NFR-003, 005, 006, 009)")

    failed = [r for r in results if not r[1]]
    print("=" * 70 + f"\n {len(results) - len(failed)}/{len(results)} suites passed\n" + "=" * 70)
    for name, _, out in failed:
        print(f"\n--- {name} ---\n{out[-1500:]}")
    sys.exit(1 if failed else 0)

if __name__ == "__main__":
    main()
