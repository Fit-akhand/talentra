#!/usr/bin/env python3
"""Propose COMMENT ON COLUMN text for every column that has none, from facts the database already holds.

A definition is only useful if it tells a query-writer something the column name does not: what the key points to,
which values are allowed, the unit, the format, what NULL means. This script writes those facts down. Columns for which
it has nothing to add beyond the name are listed as 'fallback' so a person (or the assistant) writes them by hand.

Usage: python3 scripts/lifecycle/propose_definitions.py [--fallback]     (reads PG* variables; prints a TSV)
"""
import os, re, sys
import psycopg2

SCHEMAS = ("core", "master", "profile", "recruitment", "gig", "commercial", "sourcing", "messaging", "audit", "analytics")


AUDIT_TEXT = {
    "created_at": "When the row was created (UTC). Set by trigger and never changed.",
    "updated_at": "When the row was last changed (UTC). Set by trigger.",
    "deleted_at": "When the row was soft-deleted (UTC). NULL while the row is live.",
    "created_by_user_account_id": "Account that created the row, taken from the session. NULL when the system created it (seed, migration, scheduled job).",
    "updated_by_user_account_id": "Account that last changed the row, taken from the session. NULL when the system changed it.",
    "deleted_by_user_account_id": "Account that soft-deleted the row. NULL while the row is live, or when the system deleted it.",
}


def humanise(s):
    return s.replace("_", " ")


def main():
    cx = psycopg2.connect(host=os.getenv("PGHOST", "127.0.0.1"), port=os.getenv("PGPORT", "5432"), user=os.getenv("PGUSER", "talentra_admin"),
                          dbname=os.getenv("PGDATABASE", "talentra"), password=os.getenv("PGPASSWORD"))
    cur = cx.cursor()
    cur.execute("""
      SELECT n.nspname, c.relname, a.attnum, a.attname, format_type(a.atttypid, a.atttypmod), a.attnotnull,
             pg_get_expr(d.adbin, d.adrelid), obj_description(c.oid)
        FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid AND c.relkind IN ('r','p') AND NOT c.relispartition
        JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = ANY(%s)
        LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
       WHERE a.attnum > 0 AND NOT a.attisdropped AND col_description(c.oid, a.attnum) IS NULL
       ORDER BY 1, 2, 3""", (list(SCHEMAS),))
    cols = cur.fetchall()
    cur.execute("""SELECT k.conrelid::regclass::text, k.contype, a.attname, k.confrelid::regclass::text, pg_get_constraintdef(k.oid), k.conkey
                     FROM pg_constraint k JOIN pg_attribute a ON a.attrelid = k.conrelid AND a.attnum = ANY(k.conkey)
                    WHERE k.contype IN ('p','f','c','u')""")
    cons = cur.fetchall()
    pk, fk, checks = set(), {}, {}
    for rel, kind, col, ref, d, _ in cons:
        if kind == "p": pk.add((rel, col))
        elif kind == "f": fk[(rel, col)] = ref
        elif kind == "c": checks.setdefault((rel, col), []).append(d)
    out = []
    for s, t, num, col, typ, notnull, default, tcmt in cols:
        rel = f"{s}.{t}"
        # relation name as regclass prints it (no schema when on search_path); normalise
        keyrel = next((r for r in {k[0] for k in list(fk) + list(pk) + list(checks)} if r == rel or r == t), rel)
        text, rule = None, "fallback"
        vals = None
        for d in checks.get((keyrel, col), []):
            m = [x for x in re.findall(r"'([^']+)'::", d) if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_ ./+-]*", x)]   # allowed values only, not regex or punctuation literals
            if len(m) >= 2 and "ARRAY" in d: vals = m
        if col in AUDIT_TEXT: text, rule = AUDIT_TEXT[col], "audit"
        elif (keyrel, col) in pk and col == "id": text, rule = "Surrogate primary key (64-bit identity). Never reused, never shown to users.", "pk"
        elif (keyrel, col) in fk:
            ref = fk[(keyrel, col)]
            role = col[:-3] if col.endswith("_id") else col
            text, rule = f"Reference to {ref} ({humanise(role)}). {'Required.' if notnull else 'NULL when there is none.'}", "fk"
        elif vals:
            text, rule = f"One of: {', '.join(vals)}.", "enum"
        elif col == "currency_code" or col.endswith("_currency_code"): text, rule = "ISO 4217 currency of the amount(s) in this row, three capital letters.", "currency"
        elif col.endswith("_percentage") or col.endswith("_percent") or col.startswith("percentile"): text, rule = "Percentage from 0 to 100.", "percent"
        elif col.endswith("_hours"): text, rule = "Duration in hours.", "unit"
        elif col.endswith("_days"): text, rule = "Number of days.", "unit"
        elif col.endswith("_years") or col == "experience_years": text, rule = "Number of years (decimals allowed).", "unit"
        elif col.endswith("_bytes"): text, rule = "Size in bytes.", "unit"
        elif col.endswith("_sha256") or col.endswith("_hash"): text, rule = "Hexadecimal hash (SHA-256 unless the column says otherwise); never the original value.", "hash"
        elif col.endswith("_url"): text, rule = "Absolute URL.", "url"
        elif col.endswith("_json"): text, rule = "JSON document (jsonb).", "json"
        elif col.endswith("_e164") or col == "phone_e164": text, rule = "Phone number in E.164 format with country code, for example +919812345678.", "phone"
        elif col.endswith("_at") and typ.startswith("timestamp with time zone"):
            text, rule = f"Instant (UTC) at which this row's {humanise(col[:-3])} happened.", "timestamp"
        elif col.endswith("_date") and typ == "date": text, rule = f"Calendar date of {humanise(col[:-5])}.", "date"
        elif typ == "boolean" and (col.startswith("is_") or col.startswith("has_") or col.startswith("can_") or col.startswith("allow_") or col.startswith("show_")):
            text, rule = f"True when {humanise(col.split('_', 1)[1])}{'' if col.startswith('is_') else ''}. Default {default}.", "boolean"
        elif col.endswith("_count"): text, rule = "Number of " + humanise(col[:-6]) + ".", "count"
        elif col in ("sort_order",): text, rule = "Position when listed; lower comes first.", "sort"
        elif col in ("code",): text, rule = "Stable machine-readable code (lower case), unique within the table.", "code"
        elif col == "normalized_name": text, rule = "Lower-case, trimmed form of name used for matching and uniqueness.", "norm"
        out.append((rel, col, typ, "NOT NULL" if notnull else "NULL", rule, text or ""))
    only_fb = "--fallback" in sys.argv
    for row in out:
        if only_fb and row[4] != "fallback": continue
        print("\t".join(row))
    from collections import Counter
    print("# rules:", dict(Counter(r[4] for r in out)), file=sys.stderr)


if __name__ == "__main__":
    main()
