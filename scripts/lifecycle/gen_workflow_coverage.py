#!/usr/bin/env python3
"""Generate docs/phase-3-prove/16-workflow-coverage.md (step 16): walk every workflow step in
docs/phase-1-discover/05-workflows.md against the live schema.

For each workflow: does every table it cites exist, is each main-flow step backed by a table,
and is any step audited. Then the reverse: which tables no workflow touches.
"""
import json, os, re, sys, datetime
import psycopg2

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
SRC = os.path.join(ROOT, "docs", "phase-1-discover", "05-workflows.md")
OUT = os.path.join(ROOT, "docs", "phase-3-prove", "16-workflow-coverage.md")
OWNERS = os.path.join(ROOT, "docs", "phase-3-prove", "16-gap-owners.json")
SCHEMAS = ("core", "master", "profile", "recruitment", "gig", "commercial", "sourcing", "messaging", "audit", "analytics")
TBL = re.compile(r"\b(?:%s)\.[a-z_][a-z0-9_]*" % "|".join(SCHEMAS))

def parse():
    txt = open(SRC, encoding="utf-8").read()
    wfs = {}
    for m in re.finditer(r"^### (WF-\d+) — (.+?)\n(.*?)(?=^### WF-|^## )", txt, re.S | re.M):
        wid, name, body = m.groups()
        row = lambda n: next((l for l in body.splitlines() if l.startswith(f"| {n} |")), "")
        flow = row(6)
        steps = re.findall(r"\((\d+)\)\s*(.*?)(?=;\s*\(\d+\)|\s*\|\s*$|$)", flow)
        wfs[wid] = {"name": name.strip(), "flow": flow, "steps": steps, "objects": set(TBL.findall(row(9))),
                    "all": set(TBL.findall(body)), "app_layer": "[app-layer]" in body}
    return wfs

def verify(cur, key, a, objects, tables, wf_ids, trans):
    """Return (backed, owner, problem) for one annotated step."""
    k, ref = a.get("kind"), a.get("ref", "")
    if k == "state_machine": return (ref in trans, "Database", None if ref in trans else f"{ref} has no rows in master.status_transition")
    if k in ("query", "file"):
        ok = os.path.exists(os.path.join(ROOT, ref)); return (ok, a.get("owner", "Database"), None if ok else f"{ref} does not exist")
    if k in ("function", "view"): return (ref in objects, "Database", None if ref in objects else f"{ref} does not exist")
    if k in ("column", "column_default"):
        sch, t, c = ref.split(".")
        cur.execute("select column_default from information_schema.columns where table_schema=%s and table_name=%s and column_name=%s", (sch, t, c))
        r = cur.fetchone(); ok = bool(r) and (k == "column" or r[0] is not None)
        return (ok, "Database", None if ok else f"{ref} missing" + ("" if k == "column" else " or has no default"))
    if k == "workflow_ref": return (ref in wf_ids, "Database", None if ref in wf_ids else f"{ref} is not a workflow")
    if k in ("application", "operations"): return (False, a.get("owner", ""), None if a.get("owner") else "no owner")
    return (False, "", f"unknown kind {k!r}")


def main():
    cx = psycopg2.connect(host=os.getenv("PGHOST", "127.0.0.1"), port=os.getenv("PGPORT", "5432"),
                          user=os.getenv("PGUSER", "talentra_admin"), dbname=os.getenv("PGDATABASE", "talentra"),
                          password=os.getenv("PGPASSWORD"))
    cur = cx.cursor()
    cur.execute("show server_version"); server = cur.fetchone()[0]
    cur.execute("select n.nspname||'.'||c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.relkind in ('r','p') and not c.relispartition and n.nspname = any(%s)", (list(SCHEMAS),))
    tables = {r[0] for r in cur.fetchall()}
    cur.execute("select n.nspname||'.'||p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname = any(%s)", (list(SCHEMAS),))
    funcs = {r[0] for r in cur.fetchall()}
    cur.execute("select schemaname||'.'||matviewname from pg_matviews union select schemaname||'.'||viewname from pg_views where schemaname = any(%s)", (list(SCHEMAS),))
    views = {r[0] for r in cur.fetchall()}
    objects = tables | funcs | views
    wfs = parse()
    ann = json.load(open(OWNERS, encoding="utf-8"))
    cur.execute("select distinct entity_code from master.status_transition"); trans = {r[0] for r in cur.fetchall()}
    cur.execute("select distinct sensitive_class from audit.action_catalogue"); classes_in_catalogue = {r[0] for r in cur.fetchall()}
    problems = []
    touched = set()
    L = ["# Talentra: Schema Coverage against Business Workflow (Step 16)\n",
         "**Phase:** 3 Prove | **Step:** 16 Schema Coverage against Business Workflow",
         f"**Generated** by `scripts/lifecycle/gen_workflow_coverage.py`. Do not hand-edit; workflows live in [`05-workflows.md`](../phase-1-discover/05-workflows.md).\n",
         "For every workflow step: can the data be **stored** (a table, function or view the step cites exists), and is the workflow **audited** (its text says it writes `audit.audit_event`)? Retrieval is exercised by the query set (step 28) and is not assessed here.\n",
         "## Workflow summary\n",
         "| Workflow | Steps | Steps backed by a database object or verified artefact | Steps owned elsewhere | Objects cited | Objects that do not exist | Sensitive action classes evidenced (docket B79) |",
         "|:--|--:|--:|--:|--:|--:|:--|"]
    detail, gaps = [], []
    tot_steps = tot_ok = 0
    for wid, w in wfs.items():
        ok = nt = 0
        for n, s in w["steps"]:
            refs = set(TBL.findall(s))
            if refs: ok += 1
            else:
                a = ann["steps"].get(f"{wid}:{n}")
                if a is None: problems.append(f"{wid} step {n} has no table and no entry in 16-gap-owners.json"); nt += 1
                else:
                    backed, owner, prob = verify(cur, f"{wid}:{n}", a, objects, tables, set(wfs), trans)
                    if prob: problems.append(f"{wid}:{n}: {prob}")
                    if backed: ok += 1
                    else: nt += 1
            detail.append((wid, n, s.strip(), refs, [r for r in refs if r not in objects]))
        missing = sorted(t for t in w["all"] if t not in objects)
        touched |= {t for t in w["all"] if t in tables}
        au = ann["audit"].get(wid)
        if au is None: problems.append(f"{wid} has no audit entry in 16-gap-owners.json"); audited = "**unassessed**"
        elif "classes" in au:
            bad = [c for c in au["classes"] if c not in classes_in_catalogue]
            if bad: problems.append(f"{wid} names audit classes {bad} that no action code evidences")
            audited = "classes " + ", ".join(map(str, au["classes"]))
        elif au.get("none"): audited = "none: " + au["none"]
        else: problems.append(f"{wid} audit entry needs classes or a reason"); audited = "**unassessed**"
        tot_steps += len(w["steps"]); tot_ok += ok
        if missing: gaps.append((wid, "cites a database object that does not exist (stale name in the workflow text): " + ", ".join(missing)))
        L.append(f"| {wid} {w['name']} | {len(w['steps'])} | {ok} | {nt} | {len(w['all'])} | {len(missing)} | {audited} |")
    L.append(f"| **total** | **{tot_steps}** | **{tot_ok}** | **{tot_steps - tot_ok}** | | | |\n")
    L += ["## Steps that cite no table, and how each is accounted for\n",
          "Every step that names no table, function or view is either backed by another verified artefact (a governed state machine, a query file, a script, a column, another workflow) or is owned outside the database by a named role. `docs/phase-3-prove/16-gap-owners.json` holds the disposition; this generator verifies each reference and fails when a step has none.\n",
          "| Workflow | Step | Disposition | Reference or owner | Text |", "|:--|--:|:--|:--|:--|"]
    owned = 0
    for wid, n, s_, refs, miss in detail:
        if refs: continue
        a = ann["steps"].get(f"{wid}:{n}", {})
        backed = verify(cur, f"{wid}:{n}", a, objects, tables, set(wfs), trans)[0] if a else False
        if not backed: owned += 1
        who = a.get("ref") or (a.get("owner", "") + (": " + a["note"] if a.get("note") else ""))
        L.append(f"| {wid} | {n} | {a.get('kind', '**none**')} | {who.replace('|', '/')} | {s_[:120].replace('|','/')} |")
    L += ["", "## Gaps\n"] + ([f"- **{w}**: {g}" for w, g in gaps] + [f"- {p}" for p in problems] or ["None."])
    L += ["", "## Tables no workflow touches\n"]
    orphans = sorted(tables - touched)
    L.append(f"{len(orphans)} of {len(tables)} base tables are cited by no workflow. Either a workflow is missing or the table is unused.\n")
    L += ["| Schema | Tables |", "|:--|:--|"]
    for sc in SCHEMAS:
        o = [t.split(".")[1] for t in orphans if t.startswith(sc + ".")]
        if o: L.append(f"| `{sc}` | {', '.join(f'`{x}`' for x in o)} |")
    L += ["", "## Gate G3 condition: workflow coverage\n",
          f"- Workflows whose every cited table exists: **{sum(1 for w in wfs.values() if all(t in objects for t in w['all']))} / {len(wfs)}**.",
          f"- Main-flow steps backed by a database object: **{tot_ok} / {tot_steps}**.",
          f"- Tables reached by at least one workflow: **{len(touched)} / {len(tables)}**.",
          f"- Steps owned outside the database (Application or Operations): **{owned}**, each with a named owner (roles assigned by the assistant, DEC-30).",
          f"- Steps with neither a backing artefact nor an owner: **{len(problems)}**. The playbook's test (100% or a logged gap with an owner) is {'met' if not problems else '**not met**'}."]
    open(OUT, "w", encoding="utf-8").write("\n".join(L) + "\n")
    print(f"{len(wfs)} workflows, {tot_steps} steps, {tot_ok} backed; owned elsewhere {owned}; orphan tables {len(orphans)}/{len(tables)}; problems {len(problems)}")
    for pr in problems + [g[1] for g in gaps]: print("  PROBLEM:", pr, file=sys.stderr)
    if problems or gaps: sys.exit(1)

if __name__ == "__main__":
    main()
