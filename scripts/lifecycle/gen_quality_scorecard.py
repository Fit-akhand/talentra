#!/usr/bin/env python3
"""Generate docs/phase-4-platform/26-table-quality.md: a quality score for every base table (playbook step 26).

Seven checks per table, all read from the catalog and the seeded data:
  1 primary key            2 every column defined (COMMENT)     3 every column classified (audit.column_classification)
  4 lifecycle policy row   5 every foreign key column leads an index (joins and cascades do not scan)
  6 rows present in the seeded database  7 no unexplained nullable column (the definition says what NULL means)
A table that fails a check is listed with the reason; the generator exits non-zero when any table scores below 7 without an exemption
recorded in EXEMPT. Needs a seeded database.
"""
import os, sys
import psycopg2

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
OUT = os.path.join(ROOT, "docs", "phase-4-platform", "26-table-quality.md")
SCHEMAS = ("core", "master", "profile", "recruitment", "gig", "commercial", "sourcing", "messaging", "audit", "analytics")
# (table, check number) -> reason it is acceptable
EXEMPT = {
    ("audit.system_error_log", 6): "written by the application at run time; the database seed does not fabricate errors",
    ("audit.maintenance_run", 6): "written by the scheduled maintenance job; running it during a seed could erase seeded accounts",
    ("messaging.sync_conflict", 6): "written by the migration tooling when a legacy sync finds a conflict; no sync is run by the seed",
}


def main():
    cx = psycopg2.connect(host=os.getenv("PGHOST", "127.0.0.1"), port=os.getenv("PGPORT", "5432"), user=os.getenv("PGUSER", "talentra_admin"),
                          dbname=os.getenv("PGDATABASE", "talentra"), password=os.getenv("PGPASSWORD"))
    cur = cx.cursor()
    cur.execute("""SELECT n.nspname, c.relname, c.oid FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                    WHERE c.relkind IN ('r','p') AND NOT c.relispartition AND n.nspname = ANY(%s) ORDER BY 1, 2""", (list(SCHEMAS),))
    tables = cur.fetchall()
    rows = []
    for s, t, oid in tables:
        q = f"{s}.{t}"; fails = {}
        cur.execute("SELECT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = %s AND contype = 'p')", (oid,))
        if not cur.fetchone()[0]: fails[1] = "no primary key"
        cur.execute("""SELECT string_agg(a.attname, ', ') FROM pg_attribute a WHERE a.attrelid = %s AND a.attnum > 0 AND NOT a.attisdropped
                          AND coalesce(length(col_description(a.attrelid, a.attnum)), 0) < 10""", (oid,))
        r = cur.fetchone()[0]
        if r: fails[2] = f"undefined: {r}"
        cur.execute("""SELECT string_agg(a.attname, ', ') FROM pg_attribute a WHERE a.attrelid = %s AND a.attnum > 0 AND NOT a.attisdropped
                          AND NOT EXISTS (SELECT 1 FROM audit.column_classification x WHERE x.schema_name = %s AND x.table_name = %s AND x.column_name = a.attname)""", (oid, s, t))
        r = cur.fetchone()[0]
        if r: fails[3] = f"unclassified: {r}"
        cur.execute("SELECT EXISTS (SELECT 1 FROM audit.entity_lifecycle_policy WHERE schema_name = %s AND table_name = %s)", (s, t))
        if not cur.fetchone()[0]: fails[4] = "no lifecycle policy row"
        cur.execute("""SELECT string_agg(a.attname, ', ') FROM pg_constraint k JOIN pg_attribute a ON a.attrelid = k.conrelid AND a.attnum = k.conkey[1]
                        WHERE k.conrelid = %s AND k.contype = 'f'
                          AND a.attname !~ '(by_user_account_id$|^impersonator_user_account_id$)'
                          AND k.connamespace::regnamespace::text <> 'analytics'
                          AND k.confrelid::regclass::text NOT LIKE 'master.%%'
                          AND NOT EXISTS (SELECT 1 FROM pg_index i WHERE i.indrelid = k.conrelid AND i.indkey[0] = k.conkey[1])""", (oid,))
        r = cur.fetchone()[0]
        if r: fails[5] = f"foreign key not leading any index: {r}"
        cur.execute(f"SELECT EXISTS (SELECT 1 FROM {q})")
        if not cur.fetchone()[0]: fails[6] = "empty in the seeded database"
        cur.execute("""SELECT string_agg(a.attname, ', ') FROM pg_attribute a WHERE a.attrelid = %s AND a.attnum > 0 AND NOT a.attisdropped AND NOT a.attnotnull
                          AND col_description(a.attrelid, a.attnum) !~ 'NULL|Nullable|Optional'""", (oid,))
        r = cur.fetchone()[0]
        if r: fails[7] = f"nullable without a reason: {r}"
        waived = {k: EXEMPT[(q, k)] for k in list(fails) if (q, k) in EXEMPT}
        real = {k: v for k, v in fails.items() if k not in waived}
        rows.append((q, 7 - len(real), real, waived))
    bad = [r for r in rows if r[2]]
    L = ["# Table Quality Scorecard (Step 26)\n", "**Phase:** 4 Platform | **Step:** 26 Test Automation (Data Quality)",
         "**Generated** by `scripts/lifecycle/gen_quality_scorecard.py` from the catalog and the seeded database. Do not hand-edit.\n",
         "Seven checks per table: (1) primary key, (2) every column defined, (3) every column classified, (4) lifecycle policy row, (5) every foreign key leads an index (audit actor columns, references to master data and the analytics schema are exempt, DEC-33), (6) rows present in the seed, (7) every nullable column says what NULL means. The data-level checks (formats, references, reconciliation) are the validator's fifteen (`scripts/validate_data.py`).\n",
         f"**{len(rows) - len(bad)} of {len(rows)} tables score 7 of 7.** Mean score {sum(r[1] for r in rows) / len(rows):.2f}.\n"]
    if bad:
        L += ["## Tables below 7\n", "| Table | Score | Failed checks |", "|:--|--:|:--|"]
        for q, sc, real, w in sorted(bad, key=lambda r: r[1]):
            L.append(f"| `{q}` | {sc} | " + "; ".join(f"({k}) {v}" for k, v in real.items()) + " |")
        L.append("")
    waived = [(q, w) for q, sc, real, w in rows if w]
    if waived:
        L += ["## Waived checks\n", "| Table | Check | Reason |", "|:--|--:|:--|"] + [f"| `{q}` | {k} | {v} |" for q, w in waived for k, v in w.items()] + [""]
    L += ["## All tables\n", "| Table | Score |", "|:--|--:|"] + [f"| `{q}` | {sc} |" for q, sc, _, _ in rows]
    open(OUT, "w", encoding="utf-8").write("\n".join(L) + "\n")
    print(f"{len(rows)} tables; {len(rows) - len(bad)} score 7/7; below 7: {len(bad)}")
    for q, sc, real, w in bad: print(f"  {q} {sc}/7: {real}", file=sys.stderr)
    if bad: sys.exit(1)


if __name__ == "__main__":
    main()
