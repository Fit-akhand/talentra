#!/usr/bin/env python3
"""Render docs/lifecycle/step-map.md from docs/lifecycle/steps.json and check that
every artifact the step map cites exists. Exit status 1 if any cited path is missing.

The JSON is the single source of truth; the markdown is generated so the two cannot drift.
Usage: python3 scripts/lifecycle/gen_lifecycle_report.py
"""
import json, os, sys, collections

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
SRC = os.path.join(ROOT, "docs", "lifecycle", "steps.json")
OUT = os.path.join(ROOT, "docs", "lifecycle", "step-map.md")
PHASES = {1: "Discover", 2: "Model", 3: "Prove", 4: "Platform", 5: "Insight", 6: "Specify", 7: "Design", 8: "Release"}
ICON = {"done": "done", "partial": "partial", "missing": "MISSING", "deferred": "deferred"}

def link(a):
    return f"[`{a[5:]}`](../{a[5:]})" if a.startswith("docs/") else f"[`{a}`](../../{a})"

def main():
    d = json.load(open(SRC))
    steps, gates, meta = d["steps"], d["gates"], d["meta"]
    missing_paths = [(s["n"], a) for s in steps for a in s["artifacts"] if not os.path.exists(os.path.join(ROOT, a))]
    assert [s["n"] for s in steps] == list(range(1, 47)), "steps must be 1..46 in order"

    tally = collections.Counter(s["status"] for s in steps)
    L = ["# Talentra: Lifecycle Step Map\n",
         "Generated from [`steps.json`](steps.json) by `scripts/lifecycle/gen_lifecycle_report.py`. **Edit the JSON, not this file.**\n",
         f"**Structure:** the 8 phases and 46 steps of the Talencia Global Data-Driven Development Lifecycle. **Verified:** {meta['verified_on']}.\n",
         f"> {meta['verification_basis']}\n",
         "## Totals\n", "| Status | Steps | Meaning |", "|:--|--:|:--|"]
    for k in ("done", "partial", "missing", "deferred"):
        L.append(f"| {ICON[k]} | {tally[k]} | {meta['status_values'][k]} |")
    L.append(f"| **all** | **{len(steps)}** | |\n")
    in_scope = [s for s in steps if s["status"] != "deferred"]
    L.append(f"In-scope steps: **{len(in_scope)}**, of which **{tally['done']}** are done ({round(100*tally['done']/len(in_scope))}%).\n")

    L += ["## Gates\n", "| Gate | Phase | Name | Verdict | Basis |", "|:--|--:|:--|:--|:--|"]
    for g in gates:
        L.append(f"| {g['id']} | {g['phase']} | {g['name']} | **{g['verdict']}** | {g['basis']} |")
    L += ["", "A phase is complete only when its gate passes. A gate is checked by a reviewer who did not produce the work.\n"]

    for p in range(1, 9):
        ps = [s for s in steps if s["phase"] == p]
        done = sum(1 for s in ps if s["status"] == "done")
        L += [f"## Phase {p}: {PHASES[p]}  (steps {ps[0]['n']}-{ps[-1]['n']}, {done}/{len(ps)} done)\n",
              "| Step | Name | Status | Artifacts | Docket | Note |", "|--:|:--|:--|:--|:--|:--|"]
        for s in ps:
            arts = "<br>".join(link(a) for a in s["artifacts"]) or "-"
            L.append(f"| {s['n']:02d} | {s['name']} | **{ICON[s['status']]}** | {arts} | {', '.join(s['docket']) or '-'} | {s['note']} |")
        L.append("")

    rev = collections.defaultdict(list)
    for s in steps:
        for b in s["docket"]: rev[b].append(s["n"])
    L += ["## Docket crosswalk (B1-B82 to lifecycle steps)\n",
          "The docket's five delivery phases are a different cut of the same work. Each backlog item maps to the lifecycle step that produces its deliverable.\n",
          "| Backlog | Step(s) | Backlog | Step(s) | Backlog | Step(s) |", "|:--|:--|:--|:--|:--|:--|"]
    cells = [(f"B{i}", ", ".join(f"{n:02d}" for n in rev.get(f"B{i}", [])) or "**unmapped**") for i in range(1, 83)]
    for i in range(0, 82, 3):
        row = cells[i:i + 3]
        while len(row) < 3: row.append(("", ""))
        L.append("| " + " | ".join(f"{a} | {b}" for a, b in row) + " |")
    unm = [c[0] for c in cells if c[1] == "**unmapped**"]
    L.append(f"\n**{82 - len(unm)} of 82 backlog items are mapped to a step.** Unmapped: {', '.join(unm) if unm else 'none'}.\n")
    if missing_paths:
        L += ["## Broken artifact references\n"] + [f"- step {n}: `{a}`" for n, a in missing_paths]
    open(OUT, "w").write("\n".join(L) + "\n")
    print(f"wrote {os.path.relpath(OUT, ROOT)}: {dict(tally)}; unmapped docket items: {len(unm)}; broken paths: {len(missing_paths)}")
    for n, a in missing_paths: print("  MISSING step", n, a)
    sys.exit(1 if missing_paths else 0)

if __name__ == "__main__":
    main()
