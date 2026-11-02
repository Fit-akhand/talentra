#!/usr/bin/env python3
"""Give every test file a 'Covers:' header naming the requirement, rule and NFR IDs it verifies (playbook step 20).

The IDs come from two places: the Verification column of the requirement register (requirement -> test file) and the rule catalogue
(rule -> test files). A file that already has a hand-written 'Covers:' line is left alone. Run again after adding tests; it is idempotent.
Usage: python3 scripts/lifecycle/tag_tests.py [--check]      (--check exits 1 when a test lacks a tag)
"""
import glob, importlib.util, json, os, re, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
spec = importlib.util.spec_from_file_location("trace", os.path.join(os.path.dirname(os.path.abspath(__file__)), "gen_traceability.py"))
trace = importlib.util.module_from_spec(spec); spec.loader.exec_module(trace)
MARK = "generated from the registers by scripts/lifecycle/tag_tests.py"


def collect():
    by_test = {}
    for r in trace.rows():
        for t in set(re.findall(r"tests/([\w\-.]+)", r.get("Verification", ""))):
            by_test.setdefault(t, set()).add(r["ID"])
    ext = json.load(open(os.path.join(ROOT, "docs", "phase-3-prove", "18-rule-extensions.json"), encoding="utf-8"))
    for e in ext["extensions"]:
        for t in e["tests"]: by_test.setdefault(t, set()).add(e["id"])
    for i, o in ext["overrides"].items():
        for t in o["tests"]: by_test.setdefault(t, set()).add(i)
    # rules tested through the requirement they implement
    reg = {r["ID"]: r for r in trace.rows()}
    for i, r in reg.items():
        if i.startswith("BR-"):
            for q in re.findall(r"REQ-\d{3}", r.get("REQ", "")):
                for t, ids in list(by_test.items()):
                    if q in ids: ids.add(i)
    return by_test


def main():
    check = "--check" in sys.argv
    by_test = collect(); missing = []
    for path in sorted(glob.glob(os.path.join(ROOT, "tests", "test_*"))):
        name = os.path.basename(path)
        if not name.endswith((".sql", ".py")): continue
        src = open(path, encoding="utf-8").read()
        head = "\n".join(src.splitlines()[:25])
        if re.search(r"^(--|#)\s*Covers:", head, re.M) and MARK not in head: continue   # hand-written
        ids = sorted(by_test.get(name, ()), key=lambda x: (x.split("-")[0], x))
        if not ids: missing.append(name); continue
        c = "#" if name.endswith(".py") else "--"
        line = f"{c} Covers: {', '.join(ids)}   ({MARK})"
        lines = src.split("\n")
        existing = next((k for k, l in enumerate(lines[:25]) if MARK in l), None)
        if existing is not None:
            if lines[existing] == line: continue
            if check: missing.append(name + " (stale tag)"); continue
            lines[existing] = line
        else:
            if check: missing.append(name); continue
            pos = 0
            if lines and lines[0].startswith("#!"): pos = 1
            if name.endswith(".py") and len(lines) > pos and lines[pos].startswith(('"""', "'''")):
                end = next((k for k in range(pos, min(len(lines), pos + 40)) if k > pos and ('"""' in lines[k] or "'''" in lines[k])), None)
                if end is None and lines[pos].count('"""') >= 2: end = pos
                pos = (end + 1) if end is not None else pos
            else:
                while pos < len(lines) and lines[pos].startswith(c) and not lines[pos].startswith(c + " Covers"):
                    pos += 1
                    if pos >= 1 and (lines[pos - 1].strip() in ("--", "#") or not lines[pos - 1].strip()): break
                pos = 1 if pos == 0 else min(pos, 2)
            lines.insert(pos, line)
        open(path, "w", encoding="utf-8").write("\n".join(lines))
    if missing:
        print("tests with no IDs to tag (add a hand-written 'Covers:' line):", ", ".join(missing), file=sys.stderr)
        if check or missing: sys.exit(1)


if __name__ == "__main__":
    main()
