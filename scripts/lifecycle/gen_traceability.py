#!/usr/bin/env python3
"""Generate docs/phase-6-specify/34-traceability-matrix.md from the requirement register (step 34).

Playbook rule: generate the matrix from artifact IDs, never by hand. Parses the tables in
docs/phase-1-discover/01-requirements.md, cross-checks every cited ID, test file and
migration file, and reports requirements with no test and tests with no requirement.
"""
import json, os, re, sys, glob, datetime, collections

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
REG = os.path.join(ROOT, "docs", "phase-1-discover", "01-requirements.md")
OUT = os.path.join(ROOT, "docs", "phase-6-specify", "34-traceability-matrix.md")
ID = re.compile(r"\b(?:REQ|BR|SEC|DATA|OPS|NFR)-\d{3}\b")

def rows():
    hdr = None
    for line in open(REG, encoding="utf-8"):
        if not line.startswith("|"): hdr = None; continue
        cells = [c.strip() for c in re.split(r"(?<!\\)\|", line.strip().strip("|"))]
        if cells and cells[0] == "ID": hdr = cells; continue
        if hdr and re.fullmatch(r"(?:REQ|BR|SEC|DATA|OPS|NFR)-\d{3}", cells[0]) and len(cells) == len(hdr):
            yield dict(zip(hdr, cells))

def tags():
    """test file -> IDs named in its 'Covers:' header."""
    out = {}
    for path in glob.glob(os.path.join(ROOT, "tests", "test_*")):
        head = "\n".join(open(path, encoding="utf-8").read().splitlines()[:25])
        m = re.search(r"^(?:--|#)\s*Covers:\s*(.*)$", head, re.M)
        out[os.path.relpath(path, ROOT)] = set(re.findall(r"\b(?:REQ|BR|SEC|DATA|OPS|NFR|FEAT)-\d{3}\b", m.group(1))) if m else set()
    return out


def main():
    R = {r["ID"]: r for r in rows()}
    ext = json.load(open(os.path.join(ROOT, "docs", "phase-3-prove", "18-rule-extensions.json"), encoding="utf-8"))
    known = set(R) | {e["id"] for e in ext["extensions"]}
    tg = tags()
    tests_on_disk = {os.path.relpath(p, ROOT) for p in glob.glob(os.path.join(ROOT, "tests", "*"))}
    mig_on_disk = {os.path.basename(p) for p in glob.glob(os.path.join(ROOT, "db", "migrations", "*.sql"))}
    by_type = collections.Counter(i.split("-")[0] for i in R)
    dangling, no_test, bad_tests, bad_mig = [], [], [], []
    used_tests = collections.defaultdict(list)
    out_rows = []
    for i, r in R.items():
        refs = set(ID.findall(" ".join(v for k, v in r.items() if k in ("BR", "NFR", "REQ", "REQ / BR / SEC", "REQ / BR", "Actor(s)"))))
        for x in refs:
            if x not in R: dangling.append((i, x))
        ver = r.get("Verification", "")
        tests = sorted(set(re.findall(r"tests/[\w\-.]+", ver)))
        arte = sorted(set(re.findall(r"(?:scripts/[\w\-.]+\.(?:py|sh)|docker-compose\.yml|\.github/workflows/[\w.\-]+)", ver)))
        tagged = sorted(t for t, ids in tg.items() if i in ids)
        tests = sorted(set(tests) | set(tagged))
        for t in tests:
            (used_tests[t].append(i) if t in tests_on_disk else bad_tests.append((i, t)))
        src = r.get("Source", "")
        migs = sorted(set(re.findall(r"(\d{3}_[a-z_]+\.sql)", src)) | {m for m in mig_on_disk if re.search(r"db/migrations/%s\b" % m[:3], src)})
        for m in re.findall(r"(\d{3}_[a-z_]+\.sql)", src):
            if m not in mig_on_disk: bad_mig.append((i, m))
        typ = i.split("-")[0]
        if typ in ("REQ", "SEC", "DATA", "OPS") and not tests and not arte: no_test.append(i)
        out_rows.append((i, r, tests, migs))

    L = ["# Talentra: Requirements Traceability Matrix (Step 34)\n",
         "**Phase:** 6 Specify | **Step:** 34 Traceability Matrix",
         f"**Generated** by `scripts/lifecycle/gen_traceability.py` from [`01-requirements.md`](../phase-1-discover/01-requirements.md). Do not hand-edit.\n",
         "Links each requirement to its actors, linked rules, features, workflows, migration source and named tests. Code and KPI columns follow in steps 42 and 46 of the lifecycle; for a database project the code is the migration.\n",
         "## Integrity checks\n", "| Check | Result |", "|:--|:--|",
         f"| Requirements parsed | **{len(R)}** ({', '.join(f'{k} {v}' for k, v in sorted(by_type.items()))}) |",
         f"| Cross-references to an ID that does not exist | **{len(dangling)}**{(' ' + str(dangling[:5])) if dangling else ''} |",
         f"| Named test files that do not exist | **{len(bad_tests)}**{(' ' + str(bad_tests[:5])) if bad_tests else ''} |",
         f"| Cited migration files that do not exist | **{len(bad_mig)}**{(' ' + str(bad_mig[:5])) if bad_mig else ''} |",
         f"| Functional, security, data and operational requirements with no named file under `tests/` | **{len(no_test)}**{(': ' + ', '.join(no_test)) if no_test else ''} |"]
    bad_tags = sorted((t, x) for t, ids in tg.items() for x in ids if x not in known and not x.startswith("FEAT"))
    untagged = sorted(t for t, ids in tg.items() if not ids)
    orphan = sorted(t for t in tests_on_disk if t not in used_tests and t.endswith((".sql", ".py")) and not tg.get(t))
    L += [f"| Test files with no `Covers:` header | **{len(untagged)}**{(': ' + ', '.join(f'`{t}`' for t in untagged)) if untagged else ''} |",
          f"| `Covers:` tags naming an ID that exists in no register | **{len(bad_tags)}**{(' ' + str(bad_tags[:5])) if bad_tags else ''} |"]
    L += [f"| Test files that no requirement names and that carry no tag | **{len(orphan)}**{(': ' + ', '.join(f'`{t}`' for t in orphan)) if orphan else ''} |", ""]
    L += ["## Matrix\n", "| ID | Requirement | Actors | Linked | Priority | Migration | Tests | Status |", "|:--|:--|:--|:--|:--|:--|:--|:--|"]
    for i, r, tests, migs in out_rows:
        txt = (r.get("Requirement") or r.get("Rule") or "").replace("|", "/")
        txt = txt if len(txt) <= 110 else txt[:107] + "..."
        linked = ", ".join(sorted(set(ID.findall(" ".join(r.get(k, "") for k in ("BR", "NFR", "REQ", "REQ / BR / SEC", "REQ / BR")))) | set(re.findall(r"FEAT-\d+|WF-\d+", " ".join(r.values())))))
        st = re.sub(r"\*\*", "", r.get("Status", ""))[:40]
        L.append(f"| {i} | {txt} | {r.get('Actor(s)','')[:40]} | {linked or '-'} | {r.get('Priority','-')} | {', '.join(m[:3] for m in migs) or '-'} | {', '.join(t[6:] for t in tests) or '-'} | {st} |")
    L += ["", "## Tests by requirement count\n", "| Test file | Requirements covered |", "|:--|--:|"]
    for t, ids in sorted(used_tests.items(), key=lambda kv: -len(kv[1])):
        L.append(f"| `{t}` | {len(set(ids))} |")
    open(OUT, "w", encoding="utf-8").write("\n".join(L) + "\n")
    print(f"{len(R)} requirements; dangling={len(dangling)} bad_tests={len(bad_tests)} bad_mig={len(bad_mig)} no_test={len(no_test)} orphan_tests={len(orphan)} untagged={len(untagged)} bad_tags={len(bad_tags)}")
    if untagged or bad_tags: sys.exit(1)

if __name__ == "__main__":
    main()
