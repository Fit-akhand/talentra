#!/usr/bin/env python3
"""Generate docs/phase-3-prove/18-business-rules-catalogue.md (step 18) from the BR rows of the
requirement register, checking every database object a rule cites against the live catalog.

Enforcement point = where the rule is actually enforced: database (a named constraint, index,
trigger or function that exists), database-inferred (cites migration DDL but no named object),
query-only (only a SELECT filters it) or documentation-only.
"""
import json, os, re, sys, glob, datetime, importlib.util
import psycopg2

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
OUT = os.path.join(ROOT, "docs", "phase-3-prove", "18-business-rules-catalogue.md")
spec = importlib.util.spec_from_file_location("trace", os.path.join(os.path.dirname(__file__), "gen_traceability.py"))
trace = importlib.util.module_from_spec(spec); spec.loader.exec_module(trace)

EXT = json.load(open(os.path.join(ROOT, 'docs', 'phase-3-prove', '18-rule-extensions.json'), encoding='utf-8'))
DECISION_TABLE = [  # BR-002, read from core.create_session_with_device_limit
    ("N", "N", "Allow: register the device and create the session", "tests/test_licences.sql (sessions 1 and 2)"),
    ("N", "Y", "Reject: return NULL and write audit action `device.limit_exceeded`", "tests/test_licences.sql, tests/test_business_rules.sql, tests/test_concurrency.py"),
    ("Y", "N", "Allow: device already active, create the session", "tests/test_br_decision_and_outreach.sql (row 3)"),
    ("Y", "Y", "Allow: device already active, so the limit is not applied", "tests/test_br_decision_and_outreach.sql (row 4)"),
]

def main():
    cx = psycopg2.connect(host=os.getenv("PGHOST", "127.0.0.1"), port=os.getenv("PGPORT", "5432"),
                          user=os.getenv("PGUSER", "talentra_admin"), dbname=os.getenv("PGDATABASE", "talentra"),
                          password=os.getenv("PGPASSWORD"))
    cur = cx.cursor()
    cur.execute("show server_version"); server = cur.fetchone()[0]
    cur.execute("select conname, contype from pg_constraint c join pg_namespace n on n.oid=c.connamespace where n.nspname in ('core','master','profile','recruitment','gig','commercial','sourcing','messaging','audit','analytics')")
    cons = {n: t for n, t in cur.fetchall()}
    cur.execute("select indexname from pg_indexes where schemaname in ('core','master','profile','recruitment','gig','commercial','sourcing','messaging','audit','analytics')")
    idx = {r[0] for r in cur.fetchall()}
    cur.execute("select tgname from pg_trigger where not tgisinternal"); trg = {r[0] for r in cur.fetchall()}
    cur.execute("select n.nspname||'.'||p.proname, p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('core','master','profile','recruitment','gig','commercial','sourcing','messaging','audit','analytics')")
    fn = {a: b for a, b in cur.fetchall()}
    cur.execute("select contype, count(*) from pg_constraint c join pg_namespace n on n.oid=c.connamespace where n.nspname in ('core','master','profile','recruitment','gig','commercial','sourcing','messaging','audit','analytics') group by 1")
    ctype = dict(cur.fetchall())
    cur.execute("select count(*) from pg_indexes where schemaname in ('core','master','profile','recruitment','gig','commercial','sourcing','messaging','audit','analytics')"); n_idx = cur.fetchone()[0]

    reg = {r["ID"]: r for r in trace.rows()}
    tests_of_req = {i: sorted(set(re.findall(r"tests/[\w\-.]+", r.get("Verification", "")))) for i, r in reg.items() if i.startswith("REQ")}
    out = []; counts = {}; problems = []
    for i, r in reg.items():
        if not i.startswith("BR-"): continue
        src = r["Source"]
        toks = set(re.findall(r"`([A-Za-z_][\w.]*)`", src))
        found = []
        for mnum, a, b in re.findall(r"(\d{3})(?:_\w+\.sql)?:(\d+)(?:-(\d+))?", src):
            files = glob.glob(os.path.join(ROOT, "db", "migrations", mnum + "_*.sql"))
            if not files: continue
            lines = open(files[0], encoding="utf-8").read().splitlines()[int(a) - 1:int(b or a)]
            blob = "\n".join(lines)
            toks |= set(re.findall(r"CONSTRAINT\s+(\w+)", blob, re.I))
            toks |= set(re.findall(r"CREATE\s+(?:UNIQUE\s+)?INDEX\s+(?:IF NOT EXISTS\s+)?(\w+)", blob, re.I))
            toks |= set(re.findall(r"CREATE\s+(?:CONSTRAINT\s+)?TRIGGER\s+(\w+)", blob, re.I))
            toks |= set(re.findall(r"CREATE\s+(?:OR REPLACE\s+)?(?:FUNCTION|PROCEDURE)\s+([\w.]+)", blob, re.I))
        for t in toks:
            if t in cons: found.append(("constraint " + {"c": "CHECK", "u": "UNIQUE", "p": "PRIMARY KEY", "f": "FOREIGN KEY", "x": "EXCLUDE"}.get(cons[t], cons[t]), t))
            elif t in idx: found.append(("index", t))
            elif t in trg: found.append(("trigger", t))
            elif t in fn or t in fn.values(): found.append(("function", t))
        if found: point, mech = "database", "; ".join(f"{k} `{n}`" for k, n in sorted(found))
        elif "db/migrations" in src: point, mech = "database (inferred)", "migration DDL cited, no named object"
        elif "db/queries" in src: point, mech = "query only", "a SELECT filters it; nothing prevents the data from existing"
        else: point, mech = "documentation only", "no database object cited"
        reqs = re.findall(r"REQ-\d{3}", r.get("REQ", ""))
        tests = sorted({t for q in reqs for t in tests_of_req.get(q, [])})
        ov = EXT["overrides"].get(i)
        if ov:
            missing = [o for o in ov["objects"] if o not in trg and o not in idx and o not in cons and o not in fn and o not in fn.values()]
            if missing: problems.append(f"{i}: override names objects that do not exist: {missing}")
            point, mech = ov["point"], ov["mechanism"]
            tests = sorted({"tests/" + t for t in ov["tests"]} | set(tests))
        counts[point] = counts.get(point, 0) + 1
        out.append((i, r["Rule"], point, mech, tests, r.get("Priority", ""), EXT["owners"].get(i, "**none**")))
        if i not in EXT["owners"]: problems.append(f"{i} has no owner")

    for e in EXT["extensions"]:
        found = [o for o in e["objects"] if o in trg or o in idx or o in cons or o in fn or o in fn.values()]
        miss = [o for o in e["objects"] if o not in found]
        notf = [t for t in e["tests"] if not os.path.exists(os.path.join(ROOT, "tests", t))]
        if miss: problems.append(f"{e['id']}: objects not found {miss}")
        if notf: problems.append(f"{e['id']}: tests not found {notf}")
        mech = "; ".join(f"`{o}`" for o in e["objects"])
        counts["database"] = counts.get("database", 0) + 1
        out.append((e["id"], e["rule"], "database", mech, ["tests/" + t for t in e["tests"]], "Must", e["owner"]))
    L = ["# Talentra: Business Rules Catalogue v2 (Step 18)\n",
         "**Phase:** 3 Prove | **Step:** 18 Business Rules and Data Constraints v2",
         f"**Generated** by `scripts/lifecycle/gen_rules_catalogue.py`. Do not hand-edit; rule text lives in [`01-requirements.md`](../phase-1-discover/01-requirements.md).\n",
         "Every rule has an ID, an owner (a role, DEC-30), an enforcement point and a named test. BR-001 to BR-027 come from the requirement register; BR-028 to BR-040 are docket and later rules that the register did not carry (`docs/phase-3-prove/18-rule-extensions.json`). Named objects are looked up in the live catalog, so a renamed or dropped constraint shows up here as a downgrade.\n",
         "## Enforcement summary\n", "| Enforcement point | Rules |", "|:--|--:|"]
    for k in ("database", "database (inferred)", "reconciled", "query only", "documentation only"):
        L.append(f"| {k} | {counts.get(k, 0)} |")
    L.append(f"| **total** | **{len(out)}** |\n")
    L += ["## Rules\n", "| ID | Rule | Owner | Enforced in | Mechanism | Test files |", "|:--|:--|:--|:--|:--|:--|"]
    for i, rule, point, mech, tests, pr, owner in out:
        L.append(f"| {i} | {rule.replace('|','/')} | {owner} | **{point}** | {mech} | {', '.join(t[6:] for t in tests) or '**none named**'} |")
    weak = [o for o in out if o[2] in ("query only", "documentation only")]
    notest = [o[0] for o in out if not o[4]]
    L += ["", "## Rules the database does not enforce\n"]
    L += [f"- **{o[0]}** ({o[2]}): {o[1]}" for o in weak] or ["None."]
    L += ["", "A *query only* rule is a convention: any writer can create data that breaks it. Each needs a constraint, a trigger or a documented decision to leave it to the application.\n",
          f"Rules with no named test: **{', '.join(notest) if notest else 'none'}**.\n",
          "## Database-wide enforcement inventory\n", "| Object | Count |", "|:--|--:|",
          f"| PRIMARY KEY | {ctype.get('p', 0)} |", f"| FOREIGN KEY | {ctype.get('f', 0)} |", f"| UNIQUE | {ctype.get('u', 0)} |",
          f"| CHECK | {ctype.get('c', 0)} |", f"| EXCLUDE | {ctype.get('x', 0)} |", f"| Triggers (non-internal) | {len(trg)} |",
          f"| Indexes | {n_idx} |",
          "", "## Decision table: BR-002 device limit at login\n",
          "Source: `core.create_session_with_device_limit`. The user row is locked (`FOR UPDATE`) so concurrent logins serialise. Allowed devices = the largest `max_devices_per_user` among the user's active, unexpired licence seats, or **2** if there is none. Sessions that have ended or been revoked are not counted, and the count is of distinct devices.\n",
          "| Device already has an active session | Active devices >= allowed | Outcome | Test |", "|:--|:--|:--|:--|"]
    L += [f"| {a} | {b} | {c} | {d} |" for a, b, c, d in DECISION_TABLE]
    L += ["", "All four rows are tested. The earlier gap (two rows with no test) is closed by `tests/test_br_decision_and_outreach.sql`.\n",
          "## Rules checked against the live catalog\n",
          f"Objects and test files named by BR-028 to BR-040 and by the overrides: **{len(problems)} not found**." + ("" if not problems else " " + "; ".join(problems)),
          "\n`reconciled` means the rule is a statement about derived data (BR-017); the evidence is a reconciliation test, not a constraint.\n"]
    open(OUT, "w", encoding="utf-8").write("\n".join(L) + "\n")
    print(counts, "no-test:", notest, "problems:", len(problems))
    for p_ in problems: print("  PROBLEM:", p_, file=sys.stderr)
    if problems: sys.exit(1)

if __name__ == "__main__":
    main()
