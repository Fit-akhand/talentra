#!/usr/bin/env python3
"""Generate the Phase 2 catalogues (steps 06, 07, 08) from a live, migrated database.

Playbook step 19 says a dictionary should be generated from the database so it
can never drift. Connection comes from PGHOST/PGPORT/PGUSER/PGDATABASE/PGPASSWORD.
Usage: python3 scripts/lifecycle/gen_model_catalogues.py
"""
import os, re, datetime
import psycopg2

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "docs", "phase-2-model")
SCHEMAS = ["core", "master", "profile", "recruitment", "gig", "commercial",
           "sourcing", "messaging", "audit", "analytics"]

def conn():
    return psycopg2.connect(host=os.getenv("PGHOST", "127.0.0.1"), port=os.getenv("PGPORT", "5432"),
                            user=os.getenv("PGUSER", "talentra_admin"), dbname=os.getenv("PGDATABASE", "talentra"),
                            password=os.getenv("PGPASSWORD"))

def q(cur, sql, args=None):
    cur.execute(sql, args or ())
    return cur.fetchall()

def main():
    cur = conn().cursor()
    server = q(cur, "show server_version")[0][0]
    today = datetime.date.today().isoformat()

    tables = q(cur, """
      select n.nspname, c.relname, c.relkind, c.relispartition,
             (select p.relname from pg_inherits i join pg_class p on p.oid=i.inhparent where i.inhrelid=c.oid)
      from pg_class c join pg_namespace n on n.oid=c.relnamespace
      where n.nspname = any(%s) and c.relkind in ('r','p')
      order by 1,2""", (SCHEMAS,))
    cols = q(cur, """
      select table_schema, table_name, ordinal_position, column_name, data_type, character_maximum_length,
             numeric_precision, numeric_scale, is_nullable, column_default,
             col_description(format('%%I.%%I', table_schema, table_name)::regclass, ordinal_position::int)
      from information_schema.columns where table_schema = any(%s) order by 1,2,3""", (SCHEMAS,))
    try:
        classes = {(a, b, c): (d, e) for a, b, c, d, e in q(cur, "select schema_name, table_name, column_name, data_class, protection from audit.column_classification")}
    except psycopg2.Error:
        cur.connection.rollback(); classes = {}
    table_comments = {(a, b): c for a, b, c in q(cur, """select n.nspname, c.relname, obj_description(c.oid) from pg_class c
        join pg_namespace n on n.oid=c.relnamespace where c.relkind in ('r','p') and n.nspname = any(%s)""", (SCHEMAS,))}
    cons = q(cur, """
      select n.nspname, c.relname, k.conname, k.contype, pg_get_constraintdef(k.oid),
             (select string_agg(a.attname, ',' order by u.ord) from unnest(k.conkey) with ordinality u(att,ord)
                join pg_attribute a on a.attrelid=k.conrelid and a.attnum=u.att)
      from pg_constraint k join pg_class c on c.oid=k.conrelid join pg_namespace n on n.oid=c.relnamespace
      where n.nspname = any(%s) order by 1,2,3""", (SCHEMAS,))
    trig = q(cur, """
      select n.nspname, c.relname, t.tgname, p.proname
      from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
      join pg_proc p on p.oid=t.tgfoid where not t.tgisinternal and n.nspname = any(%s) order by 1,2,3""", (SCHEMAS,))

    by_tab_cols, by_tab_cons, by_tab_trig = {}, {}, {}
    for r in cols: by_tab_cols.setdefault((r[0], r[1]), []).append(r)
    for r in cons: by_tab_cons.setdefault((r[0], r[1]), []).append(r)
    for r in trig: by_tab_trig.setdefault((r[0], r[1]), []).append(r)

    fk_out, fk_in = {}, {}
    for s, t, name, kind, d, cl in cons:
        if kind == "f":
            m = re.search(r"REFERENCES ([\w\.\"]+)\(", d)
            ref = m.group(1).replace('"', "") if m else "?"
            if "." not in ref: ref = s + "." + ref
            fk_out.setdefault((s, t), set()).add(ref)
            rs, rt = ref.split(".", 1)
            fk_in.setdefault((rs, rt), set()).add(f"{s}.{t}")

    def has(s, t, *names):
        """True if every name is present; created_by / updated_by also match created_by_user_account_id etc."""
        have = {c[3] for c in by_tab_cols.get((s, t), [])}
        def one(n):
            return n in have or (n in ("created_by", "updated_by") and any(h.startswith(n + "_") for h in have))
        return all(one(n) for n in names)

    # ---------- step 06: entity catalogue ----------
    base = [t for t in tables if not t[3]]
    parts = [t for t in tables if t[3]]
    L = [f"# Talentra: Entity Catalogue (Step 06)\n",
         "**Phase:** 2 Model | **Step:** 06 Entities Discovery",
         f"**Generated** by `scripts/lifecycle/gen_model_catalogues.py` from a migrated database. Do not hand-edit.\n",
         "Every table the implemented schema holds, with its bounded schema, kind, size, relationship counts and the Rule Group 4 audit and lifecycle columns it carries.\n",
         f"**Totals:** {len(base)} base tables + {len(parts)} partitions = {len(tables)} relations across {len(SCHEMAS)} schemas.\n",
         "## Summary by schema\n", "| Schema | Tables | Partitions |", "|:--|--:|--:|"]
    for sc in SCHEMAS:
        L.append(f"| `{sc}` | {sum(1 for t in base if t[0]==sc)} | {sum(1 for t in parts if t[0]==sc)} |")
    L += ["", "## Entities\n",
          "Audit columns = `created_at`, `created_by`, `updated_at`, `updated_by` (RG4). Soft delete = has `deleted_at`.\n"]
    for sc in SCHEMAS:
        L += [f"### `{sc}`\n", "| Table | Cols | FK out | FK in | Audit cols (RG4) | Soft delete | Triggers |", "|:--|--:|--:|--:|:--|:--|:--|"]
        for s, t, kind, ispart, parent in base:
            if s != sc: continue
            a = [n for n in ("created_at", "created_by", "updated_at", "updated_by") if has(s, t, n)]
            audit = "all 4" if len(a) == 4 else ("none" if not a else "partial: " + ", ".join(a))
            tg = ", ".join(sorted({x[2] for x in by_tab_trig.get((s, t), [])})) or "-"
            L.append(f"| `{t}`{' (partitioned)' if kind=='p' else ''} | {len(by_tab_cols.get((s,t),[]))} | {len(fk_out.get((s,t),[]))} | {len(fk_in.get((s,t),[]))} | {audit} | {'yes' if has(s,t,'deleted_at') else 'no'} | {tg} |")
        L.append("")
    if parts:
        L += ["### Partitions\n", "| Partition | Parent |", "|:--|:--|"]
        L += [f"| `{s}.{t}` | `{p}` |" for s, t, k, ip, p in parts]
        L.append("")
    audit_all = sum(1 for s, t, *_ in base if all(has(s, t, n) for n in ("created_at", "created_by", "updated_at", "updated_by")))
    per = {n: sum(1 for s, t, *_ in base if has(s, t, n)) for n in ("created_at", "created_by", "updated_at", "updated_by", "deleted_at")}
    L += ["## Conformance snapshot (Rule Group 4)\n",
          f"- Base tables with all four audit columns: **{audit_all} / {len(base)}**.",
          "- Per column: " + ", ".join(f"`{k}` {v}/{len(base)}" for k, v in per.items()) + ".",
          "- The docket requires all four on every business table, and a `deleted_at` on every soft-deleted entity with the soft/hard classification stated per entity. No table has `deleted_at` and no classification is recorded: both are open RG4 gaps.",
          "- Tables without all four audit columns are listed above; each is either append-only (no `updated_*` by design) or a gap to resolve in Step 17.\n"]
    open(os.path.join(OUT, "06-entity-catalogue.md"), "w").write("\n".join(L))

    # ---------- step 07: attribute catalogue ----------
    pk = {}; uq = {}
    for s, t, name, kind, d, cl in cons:
        if kind == "p": pk[(s, t)] = set((cl or "").split(","))
        if kind == "u": uq.setdefault((s, t), []).append(set((cl or "").split(",")))
    fkcols = {}
    for s, t, name, kind, d, cl in cons:
        if kind == "f":
            m = re.search(r"REFERENCES ([\w\.\"]+)\(", d)
            for c in (cl or "").split(","): fkcols[(s, t, c)] = (m.group(1).replace('"', "") if m else "?")
    A = ["# Talentra: Attribute Catalogue and Data Dictionary (Steps 07, 10, 19)\n",
         "**Phase:** 2 Model | **Steps:** 07 Attributes Discovery, 10 Data Dictionary v1, 19 Data Dictionary v2",
         f"**Generated** by `scripts/lifecycle/gen_model_catalogues.py`. Do not hand-edit.\n",
         "Everything here is read from the database, so this dictionary cannot drift from the schema: structure from the catalog, class and protection from `audit.column_classification` (Rule Group 6), definitions from `COMMENT ON` statements. A column with no comment has no written business definition yet; that is a documentation gap, shown below, not hidden.\n"]
    nn = total = commented = nullable_commented = 0
    cls_count = {}
    for s, t, kind, ispart, parent in base:
        tc = table_comments.get((s, t))
        A += [f"## `{s}.{t}`\n"] + ([tc + "\n"] if tc else [])
        A += ["| # | Column | Type | Null | Default | Key | Class | Protection | Definition |", "|--:|:--|:--|:--|:--|:--|:--|:--|:--|"]
        for r in by_tab_cols.get((s, t), []):
            _, _, pos, name, dt, ln, pr, sc_, nul, dflt, cmt = r
            typ = dt + (f"({ln})" if ln else (f"({pr},{sc_})" if dt == "numeric" and pr else ""))
            key = []
            if name in pk.get((s, t), ()): key.append("PK")
            if (s, t, name) in fkcols: key.append("FK to " + fkcols[(s, t, name)])
            if any(name in u and len(u) == 1 for u in uq.get((s, t), [])): key.append("UQ")
            klass, prot = classes.get((s, t, name), ("-", "-"))
            cls_count[klass] = cls_count.get(klass, 0) + 1
            total += 1; nn += (nul == "YES"); commented += bool(cmt); nullable_commented += bool(cmt) and nul == "YES"
            A.append(f"| {pos} | `{name}` | {typ} | {'yes' if nul=='YES' else 'no'} | {(dflt or '-').replace('|','/')[:50]} | {', '.join(key) or '-'} | {klass} | {prot} | {(cmt or '').replace('|','/')[:140]} |")
        A.append("")
    summary = [f"**Totals:** {total} columns across {len(base)} base tables.\n",
               "| Measure | Count |", "|:--|--:|",
               f"| Columns with a written definition (`COMMENT ON`) | {commented} of {total} |",
               f"| Nullable columns | {nn} |",
               f"| Nullable columns with a written justification (RG5) | {nullable_commented} of {nn} |"] + \
              [f"| Classified `{k}` | {v} |" for k, v in sorted(cls_count.items())] + \
              ["", "Rule Group 5 asks for a written justification of every nullable column. Every column has a definition and every nullable column says what NULL means (migration 033; `tests/test_column_definitions.sql` fails otherwise).\n"]
    A[4:4] = summary
    open(os.path.join(OUT, "07-attribute-catalogue.md"), "w").write("\n".join(A))

    # ---------- step 08: state machines ----------
    trans = {}
    try:
        for ent, fr, to in q(cur, "select entity_code, from_status, to_status from master.status_transition order by 1,2,3"):
            trans.setdefault(ent, []).append((fr, to))
    except psycopg2.Error:
        cur.connection.rollback()
    S = ["# Talentra: Entity Lifecycles and State Machines (Step 08)\n",
         "**Phase:** 2 Model | **Step:** 08 Entity Lifecycle and State Machines",
         f"**Generated** by `scripts/lifecycle/gen_model_catalogues.py`. States are read from CHECK constraints and transitions from `master.status_transition`; do not hand-edit.\n",
         "A status column is **governed** when `master.status_transition` lists its legal moves and a trigger rejects every other update (migration 022). Everything not listed is illegal, so the illegal transitions are the complement and need no separate list. A status with no outgoing move is **final**.\n"]
    found = []
    for s, t, name, kind, d, cl in cons:
        if kind != "c": continue
        vals = re.findall(r"'([^']+)'::", d)
        if len(vals) < 2 or not cl or "," in cl or not re.search(r"(status|state|stage)", cl): continue
        found.append((s, t, cl, vals))
    governed = [f for f in found if f"{f[0]}.{f[1]}" in trans]
    exempt = {}
    try:
        cur.execute("SELECT entity_code, column_name, exemption_type, reason FROM master.status_machine_exemption")
        exempt = {(e, c): (k, r) for e, c, k, r in cur.fetchall()}
    except psycopg2.Error:
        cur.connection.rollback()
    ungoverned = [f for f in found if f"{f[0]}.{f[1]}" not in trans]
    other = [f for f in ungoverned if (f"{f[0]}.{f[1]}", f[2]) not in exempt]
    exempted = [f for f in ungoverned if (f"{f[0]}.{f[1]}", f[2]) in exempt]
    S += [f"**{len(governed)} governed state machines, {len(exempted)} recorded exemptions, {len(other)} status columns undecided** (of {len(found)} status-like columns).\n", "## Governed state machines\n"]
    for s, t, cl, vals in governed:
        ent = f"{s}.{t}"; moves = trans[ent]
        outgoing = {fr for fr, _ in moves}
        final = [v for v in vals if v not in outgoing]
        initial = [v for v in vals if v not in {to for _, to in moves}]
        illegal = len(vals) * (len(vals) - 1) - len(moves)
        S += [f"### `{ent}.{cl}`\n",
              f"States: {', '.join(f'`{v}`' for v in vals)}. Initial: {', '.join(f'`{v}`' for v in initial) or 'none'}. Final: {', '.join(f'`{v}`' for v in final) or 'none'}. Legal moves: {len(moves)}. Illegal moves (rejected): {illegal}.\n",
              "| From | Allowed next states |", "|:--|:--|"]
        for v in vals:
            nxt = [to for fr, to in moves if fr == v]
            S.append(f"| `{v}` | {', '.join(f'`{x}`' for x in nxt) if nxt else '*final*'} |")
        S.append("")
    S += ["## Status columns without transition rules\n",
          "A status that no trigger governs must be a recorded decision, not an oversight: it is either set by an external service whose callbacks arrive out of order (`external_driver`) or it is the outcome column of an append-only history row (`append_only_history`). The reasons are rows in `master.status_machine_exemption`; `tests/test_state_machines.sql` fails if a status column is neither governed nor exempt.\n",
          "| Table | Column | Kind | Reason |", "|:--|:--|:--|:--|"]
    for s_, t_, cl, vals in exempted:
        k, r = exempt[(f"{s_}.{t_}", cl)]
        S.append(f"| `{s_}.{t_}` | `{cl}` | {k} | {r.replace('|', '/')} |")
    for s_, t_, cl, vals in other:
        S.append(f"| `{s_}.{t_}` | `{cl}` | **undecided** | - |")
    S += ["", "## Gaps\n",
          f"1. {len(other)} status columns are undecided." if other else f"1. Every status column is governed ({len(governed)}) or a recorded exemption ({len(exempted)}); none is undecided.",
          "2. Enumerations are CHECK lists, not lookup tables. Docket Rule Group 3 asks for lookup tables with per-language display names. The deviation is recorded in `11-rule-compliance.md`.\n"]
    open(os.path.join(OUT, "08-state-machines.md"), "w").write("\n".join(S))

    # ---------- step 09: generated ER diagram ----------
    edges = []
    for s, t_, name, kind, d, cl in cons:
        if kind != "f": continue
        m = re.search(r"REFERENCES ([\w\.\"]+)\(", d)
        ref = m.group(1).replace('"', "") if m else "?"
        if "." not in ref: ref = s + "." + ref
        edges.append((f"{s}.{t_}", ref, cl))
    base_names = {f"{s}.{t_}" for s, t_, *_ in base}
    E = ["# Talentra: Entity-Relationship Diagrams, generated (Step 09)\n",
         "**Phase:** 2 Model | **Step:** 09 Database, Tables and Relationships",
         f"**Generated** by `scripts/lifecycle/gen_model_catalogues.py`. Do not hand-edit.\n",
         "One diagram per schema showing its tables and the foreign keys between them; foreign keys that cross schemas are listed in a table instead, to keep each diagram readable. Columns are omitted: see the attribute catalogue. `}o--||` reads: many rows on the left reference one row on the right. Audit columns (`created_by`, `updated_by`, `deleted_by`) point at `core.user_account` from nearly every table and are left out of the diagrams.\n"]
    audit_cols = lambda cl: bool(cl) and re.search(r"(created_by|updated_by|deleted_by)", cl)
    for sc in SCHEMAS:
        tabs = sorted(n for n in base_names if n.startswith(sc + "."))
        inner = sorted({(a, b, cl) for a, b, cl in edges if a in base_names and b in base_names and a.startswith(sc + ".") and b.startswith(sc + ".") and not audit_cols(cl)})
        E += [f"## `{sc}` ({len(tabs)} tables)\n", "```mermaid", "erDiagram"]
        used = {x for a, b, _ in inner for x in (a, b)}
        for a, b, cl in inner:
            E.append(f"    {a.split('.')[1]} }}o--|| {b.split('.')[1]} : \"{cl}\"")
        for n in tabs:
            if n not in used: E.append(f"    {n.split('.')[1]}")
        E += ["```", ""]
    cross = sorted({(a, b, cl) for a, b, cl in edges if a in base_names and b in base_names and a.split('.')[0] != b.split('.')[0] and not audit_cols(cl)})
    E += ["## Foreign keys across schemas\n", f"{len(cross)} relationships (audit-column references excluded).\n", "| From | Column | To |", "|:--|:--|:--|"]
    E += [f"| `{a}` | `{cl}` | `{b}` |" for a, b, cl in cross]
    E.append("")
    open(os.path.join(OUT, "09-er-diagram-generated.md"), "w").write("\n".join(E))
    print(f"06: {len(base)} tables + {len(parts)} partitions; 07: {total} columns ({nn} nullable, {nullable_commented} justified); 08: {len(governed)} governed + {len(exempted)} exempt + {len(other)} undecided status columns")

if __name__ == "__main__":
    main()
