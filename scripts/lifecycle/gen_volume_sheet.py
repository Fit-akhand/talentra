#!/usr/bin/env python3
"""Generate docs/phase-3-prove/13-volume-sheet.md (playbook step 13): per-table row counts at launch, one year and three years,
null rates, and an estimate of size, from a seeded database.

Method: the database in use is the measured base (medium seed: 10,000 candidates, 1,000 jobs, 50,000 applications, 200 organisations,
2,000 gig workers). Each table follows one driver (the entity whose growth it follows), inferred from its heaviest non-audit foreign key,
and is scaled by the driver's volume at each horizon. Null rates are read from pg_stats after ANALYZE. Size = rows x measured bytes per row
(table plus indexes, as measured on the base). The laptop dataset (1,000,000 candidates, measured at 11 GB) is the check on the model.
Usage: python3 scripts/lifecycle/gen_volume_sheet.py      (reads PG* variables; needs a seeded database)
"""
import os
import psycopg2

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
OUT = os.path.join(ROOT, "docs", "phase-3-prove", "13-volume-sheet.md")
SCHEMAS = ("core", "master", "profile", "recruitment", "gig", "commercial", "sourcing", "messaging", "audit", "analytics")
# driver table -> (label, launch, one year (the docket's laptop dataset), three years (the docket's target))
DRIVERS = {
    "profile.candidate_profile": ("candidates", 100_000, 1_000_000, 10_000_000),
    "recruitment.job_posting": ("jobs", 10_000, 100_000, 1_000_000),
    "recruitment.candidate_application": ("applications", 500_000, 5_000_000, 100_000_000),
    "recruitment.organization": ("organisations", 1_000, 10_000, 100_000),
    "gig.gig_worker_profile": ("gig workers", 10_000, 100_000, 1_000_000),
    "core.user_account": ("accounts", 102_000, 1_020_000, 10_200_000),
}
STATIC_SCHEMAS = ("master",)
AUDIT_FK = ("created_by_user_account_id", "updated_by_user_account_id", "deleted_by_user_account_id")


def human(n):
    for unit, k in (("B", 1), ("KB", 1e3), ("MB", 1e6), ("GB", 1e9), ("TB", 1e12)):
        if n < k * 1000 or unit == "TB": return f"{n / k:,.1f} {unit}" if unit != "B" else f"{n:,.0f} B"


def main():
    cx = psycopg2.connect(host=os.getenv("PGHOST", "127.0.0.1"), port=os.getenv("PGPORT", "5432"), user=os.getenv("PGUSER", "talentra_admin"),
                          dbname=os.getenv("PGDATABASE", "talentra"), password=os.getenv("PGPASSWORD"))
    cx.autocommit = True; cur = cx.cursor()
    cur.execute("ANALYZE")
    cur.execute("""SELECT n.nspname || '.' || c.relname, c.reltuples::bigint, pg_total_relation_size(c.oid), pg_relation_size(c.oid)
                     FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                    WHERE c.relkind IN ('r','p') AND NOT c.relispartition AND n.nspname = ANY(%s)""", (list(SCHEMAS),))
    info = {r[0]: r[1:] for r in cur.fetchall()}
    cur.execute("SELECT n.nspname || '.' || c.relname, count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE c.relkind IN ('r','p') AND n.nspname = ANY(%s) GROUP BY 1", (list(SCHEMAS),))
    for t in info:
        cur.execute(f"SELECT count(*) FROM {t}"); info[t] = (cur.fetchone()[0],) + tuple(info[t][1:])
    # foreign keys, minus audit-column references
    cur.execute("""SELECT k.conrelid::regclass::text, k.confrelid::regclass::text, a.attname
                     FROM pg_constraint k JOIN pg_attribute a ON a.attrelid = k.conrelid AND a.attnum = ANY(k.conkey) WHERE k.contype = 'f'""")
    parents = {}
    for child, parent, col in cur.fetchall():
        if col in AUDIT_FK: continue
        norm = lambda x: x if "." in x else "public." + x
        parents.setdefault(child, set()).add(parent)
    qual = {t.split(".")[1]: t for t in info}
    def full(x): return x if "." in x else qual.get(x, x)
    parents = {full(c): {full(p) for p in ps} for c, ps in parents.items()}

    driver_of = {}
    def resolve(t, seen=()):
        if t in driver_of: return driver_of[t]
        if t in DRIVERS: driver_of[t] = t; return t
        if t.split(".")[0] in STATIC_SCHEMAS: driver_of[t] = None; return None
        best, best_rows = None, -1
        for p in parents.get(t, ()):
            if p == t or p in seen or p not in info: continue
            d = resolve(p, seen + (t,))
            if d and info[p][0] > best_rows: best, best_rows = d, info[p][0]
        driver_of[t] = best
        return best
    for t in info: resolve(t)

    base = {d: info[d][0] for d in DRIVERS}
    cur.execute("SELECT schemaname || '.' || tablename, attname, null_frac, avg_width FROM pg_stats WHERE schemaname = ANY(%s)", (list(SCHEMAS),))
    stats = {}
    for t, col, nf, w in cur.fetchall(): stats.setdefault(t, []).append((col, nf, w))
    cur.execute("""SELECT n.nspname || '.' || c.relname, a.attname FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid JOIN pg_namespace n ON n.oid = c.relnamespace
                    WHERE a.attnum > 0 AND NOT a.attisdropped AND NOT a.attnotnull AND c.relkind IN ('r','p') AND NOT c.relispartition AND n.nspname = ANY(%s)""", (list(SCHEMAS),))
    nullable = {}
    for t, c in cur.fetchall(): nullable.setdefault(t, set()).add(c)

    rows_out, totals = [], [0.0, 0.0, 0.0]
    for t in sorted(info):
        n0, total_bytes, heap = info[t]
        d = driver_of.get(t)
        bytes_per_row = (total_bytes / n0) if n0 else 0
        if d is None or base[d] == 0 or n0 == 0:
            proj = [n0, n0, n0]; label = "static" if d is None else DRIVERS[d][0]
        else:
            ratio = n0 / base[d]; label = DRIVERS[d][0]
            proj = [int(ratio * DRIVERS[d][k]) for k in (1, 2, 3)]
        size = [p * bytes_per_row for p in proj]
        for k in range(3): totals[k] += size[k]
        nf = sorted(((c, f) for c, f, w in stats.get(t, []) if c in nullable.get(t, ()) and f >= 0.5), key=lambda x: -x[1])
        rows_out.append((t, label, n0, proj, size, nf))

    L = ["# Talentra: Data Volume Sheet (Step 13)\n",
         "**Phase:** 3 Prove | **Step:** 13 Data Volumetrics and Distribution Profile",
         "**Generated** by `scripts/lifecycle/gen_volume_sheet.py` from a seeded database. Do not hand-edit.\n",
         "## Method and limits\n",
         "- **Base:** the database this was generated from (medium seed: " + ", ".join(f"{base[d]:,} {DRIVERS[d][0]}" for d in DRIVERS) + ").",
         "- **Horizons:** *launch* is 10% of the docket's laptop dataset; *one year* is the laptop dataset itself (1,000,000 candidates, 5,000,000 applications); *three years* is the docket's target (10,000,000 candidates, 100,000,000 applications). Which year each is reached is a business forecast the assistant cannot make; the horizons are volumes, not dates.",
         "- **Scaling:** every table follows one driver, found from its heaviest non-audit foreign key, at the ratio measured on the base. Static tables (master data) do not grow. Ratios that drift with scale (applications per candidate is 5 at the base, 5 at the laptop dataset and 10 at the target) are carried by treating applications as their own driver.",
         "- **Size:** rows x the bytes per row measured on the base, indexes included. This is a model; the check on it is below.\n",
         "## Check against a measurement\n"]
    one_year = totals[1]
    L += [f"The laptop dataset was measured at **11 GB** on disk (PostgreSQL 16.15, before migrations 029 to 037). The model's one-year total is **{human(one_year)}**. "
          + ("Within 25% of the measurement." if 0.75 <= one_year / 11e9 <= 1.25 else f"That differs from the measurement by {abs(one_year / 11e9 - 1) * 100:.0f}%: treat the model as {'an over' if one_year > 11e9 else 'an under'}estimate and prefer the measured figure.")
          + " The measurement predates migrations 029 to 037, which add tables and indexes, so a small difference in either direction is expected.\n",
          "## Totals\n", "| Horizon | Estimated size (tables and indexes) |", "|:--|--:|",
          f"| Launch | {human(totals[0])} |", f"| One year (laptop dataset) | {human(totals[1])} |", f"| Three years (docket target) | {human(totals[2])} |", "",
          "## Per table\n", "Columns with a null rate of 50% or more are listed; a nullable column not listed is mostly filled.\n",
          "| Table | Driver | Base rows | Launch | One year | Three years | Size at 3 years | Mostly-null columns |", "|:--|:--|--:|--:|--:|--:|--:|:--|"]
    for t, label, n0, proj, size, nf in sorted(rows_out, key=lambda r: -r[4][2]):
        L.append(f"| `{t}` | {label} | {n0:,} | {proj[0]:,} | {proj[1]:,} | {proj[2]:,} | {human(size[2])} | {', '.join(f'`{c}` {f:.0%}' for c, f in nf[:4]) or '-'} |")
    L += ["", "## What the sheet shows\n"]
    top = sorted(rows_out, key=lambda r: -r[4][2])[:5]
    L += [f"- The five largest tables at three years: " + ", ".join(f"`{t}` ({human(s[2])})" for t, _, _, _, s, _ in top) + ".",
          f"- Static tables: {sum(1 for r in rows_out if r[1] == 'static')} of {len(rows_out)}.",
          "- Tables that hold history or events (`audit.audit_event`, application status history, view history, wallet ledger) grow with activity, not with the entity count, so the model understates them if usage per user rises. They are the ones to watch and the first candidates for partitioning (the application table already is)."]
    open(OUT, "w", encoding="utf-8").write("\n".join(L) + "\n")
    print(f"{len(rows_out)} tables; one-year estimate {human(one_year)}; three-year {human(totals[2])}; unresolved {sum(1 for t in info if driver_of.get(t) is None and t.split('.')[0] not in STATIC_SCHEMAS)}")


if __name__ == "__main__":
    main()
