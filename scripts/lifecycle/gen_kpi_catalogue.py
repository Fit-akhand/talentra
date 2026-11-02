#!/usr/bin/env python3
"""Generate docs/phase-5-insight/29-kpi-catalogue.md (step 29) from db/kpi/*.sql.

Each KPI is a SQL file with a metadata header. The generator RUNS every query against the
connected database, so 'computable from the schema' (gate G5) is a tested fact, not a claim.
Connection: PGHOST/PGPORT/PGUSER/PGDATABASE/PGPASSWORD.
"""
import glob, os, re, datetime, decimal
import psycopg2

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
OUT = os.path.join(ROOT, "docs", "phase-5-insight", "29-kpi-catalogue.md")

def meta(path):
    m, body = {}, []
    for line in open(path, encoding="utf-8"):
        h = re.match(r"-- (\w+): (.*)", line)
        if h and not body: m[h.group(1)] = h.group(2).strip()
        else: body.append(line)
    return m, "".join(body).strip()

def fmt(v):
    return str(v) if not isinstance(v, decimal.Decimal) else format(v, "f")

def main():
    cx = psycopg2.connect(host=os.getenv("PGHOST", "127.0.0.1"), port=os.getenv("PGPORT", "5432"),
                          user=os.getenv("PGUSER", "talentra_admin"), dbname=os.getenv("PGDATABASE", "talentra"),
                          password=os.getenv("PGPASSWORD"))
    cx.autocommit = True
    cur = cx.cursor()
    cur.execute("show server_version"); server = cur.fetchone()[0]
    rows, ok = [], 0
    for p in sorted(glob.glob(os.path.join(ROOT, "db", "kpi", "*.sql"))):
        m, sql = meta(p)
        try:
            cur.execute(sql); res = cur.fetchall(); cols = [d[0] for d in cur.description]
            has_value = any(v is not None for r in res for v in r) and len(res) > 0
            first = ", ".join(f"{c}={fmt(v)}" for c, v in zip(cols, res[0])) if res else "(no rows)"
            state = "yes" if has_value else "yes, no data in this dataset"
            ok += 1
        except Exception as e:
            cx.rollback() if not cx.autocommit else None
            res, first, state = [], str(e).splitlines()[0][:80], "**NO: " + str(e).splitlines()[0][:60] + "**"
        rows.append((m, os.path.relpath(p, ROOT), state, len(res), first))
    L = ["# Talentra: KPI Catalogue (Step 29)\n",
         "**Phase:** 5 Insight | **Step:** 29 KPI Discovery",
         f"**Generated** by `scripts/lifecycle/gen_kpi_catalogue.py`. Do not hand-edit; edit the SQL in [`db/kpi/`](../../db/kpi/).\n",
         f"**{ok} of {len(rows)} KPIs execute against the schema.** Each query is the definition: the formula, grain and sources below are read from its header.\n",
         "## Catalogue\n",
         "| ID | KPI | Persona | Type | Grain | Unit | Target | Refresh | Computable | Source tables | Query |",
         "|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|:--|"]
    for m, path, state, n, first in rows:
        L.append(f"| {m['kpi_id']} | {m['name']} | {m['persona']} | {m['type']} | {m['grain']} | {m['unit']} | *unset* | {m['refresh']} | {state} | {m['sources']} | [`{os.path.basename(path)}`](../../{path}) |")
    L += ["", "**Target** is *unset* for every KPI. No target was provided in the docket, and inventing one would be a guess. The owner named by *Persona* must approve a target before a KPI can be reported as red or green.\n",
          "## Values on the current dataset\n",
          "Example output from the run that generated this file. The dataset is the `dev` seed, so values show that a query works, not what the business looks like.\n",
          "| ID | First row |", "|:--|:--|"]
    for m, path, state, n, first in rows:
        L.append(f"| {m['kpi_id']} | {first.replace('|','/')[:160]} |")
    L += ["", "## KPI tree\n",
          "```",
          "Hiring outcome ........ KPI-003 time to hire <- KPI-004 offer-to-join <- KPI-002 stage mix <- KPI-001 applications per job",
          "Candidate supply ...... KPI-005 profile completeness, KPI-006 jobs by industry",
          "Marketplace quality ... KPI-009 gig award rate, KPI-010 gig rating, KPI-012 consultant acceptance, KPI-013 outreach response",
          "Money integrity ....... KPI-007 wallet reconciliation (target 0), KPI-008 credit movement, KPI-016 download spend",
          "Platform health ....... KPI-011 delivery success, KPI-014 support backlog, KPI-015 device-limit denials",
          "```\n",
          "## Gaps found while making the KPIs computable (return to Phase 3)\n",
          "1. **The star schema has no load process.** `analytics.refresh_reporting_marts()` only refreshes two materialised views. Nothing populates `dim_*` and `fact_*` from the operational tables except the data generator, and `fact_gig_performance` and `fact_wallet_transaction` are empty after seeding. Of the 16 KPIs, only KPI-005 reads the star schema; the rest read operational tables, because the mart cannot be trusted to be current.",
          "2. **Query 10 (`db/queries/10_analytics_time_to_hire_kpi.sql`) used to average the cycle time of the joined event only**, that is, time spent in the previous stage, not the time from application to joining, and re-aggregated every event on each call. It now reads `analytics.mv_hiring_funnel_by_industry` (migration 028), which measures the full interval and is rebuilt by `analytics.refresh_reporting_marts()`; KPI-003 and Query 10 agree.",
          "3. **KPIs on audit events depend on write sites that barely exist.** KPI-015 can only count what the schema writes to `audit.audit_event`, and the audit matrix records two write sites in the whole schema.",
          "4. **The dev seed is too flat to exercise the KPIs** (playbook anti-pattern: uniform test data). In the run above: all 100 jobs have a NULL `industry_id` (KPI-006 returns no rows); every gig request is `open` (KPI-009 is undefined); every application has `last_status_changed_at = applied_at`, so KPI-003 reads exactly 0.00 hours; there are no support tickets (KPI-014) and every notification is `sent` (KPI-011 reads 0%). Step 13 (volumetrics and distributions) and step 14 must fix the generator before the KPI values mean anything.\n",
          "## Gate G5\n",
          "- *Every KPI is computable from the schema:* " + ("**met** for all 16 (queries execute)." if ok == len(rows) else f"**not met**: {len(rows)-ok} fail."),
          "- *Every dashboard number reconciles with its source:* **not assessed.** There is no dashboard; reconciliation is step 30.\n"]
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    open(OUT, "w", encoding="utf-8").write("\n".join(L))
    print(f"{ok}/{len(rows)} KPIs execute")
    for m, path, state, n, first in rows:
        if not state.startswith("yes"): print("  FAIL", m["kpi_id"], state)
        elif "no data" in state: print("  nodata", m["kpi_id"])

if __name__ == "__main__":
    main()
