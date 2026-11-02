#!/usr/bin/env python3
"""
Talentra Benchmark Runner & Execution Plan Profiler — Methodology v2 (Phase 2C)
Engine: PostgreSQL 17

Executes the 12 fixed benchmark queries in db/queries/, measures p50/p95/p99
latencies, captures EXPLAIN (ANALYZE, BUFFERS) plans, profiles buffer cache
hits, and exports reports to benchmarks/results/.

Methodology v2 corrects the defects recorded in
`docs/phase2b-query-performance-validation.md` and
`docs/phase2c-benchmark-correction-report.md`:

  1. The per-query latency/plan measurements are explicitly labelled
     `measurement_role: "baseline"`. They are the reference measurement, not
     the product of any index change.

  2. The former "index impact" block is replaced by a clearly labelled
     DIAGNOSTIC planner-method comparison. It measures the cost of DENYING
     the planner every index access path (`enable_indexscan`,
     `enable_bitmapscan`, `enable_indexonlyscan` set to `off`). It is NOT the
     measured benefit of adding an index, and no output attributes the ratio
     to a named index.

  3. Every query is classified by result validity
     (`valid_non_empty` / `invalid_empty_result` / `skipped`) with an explicit
     reason, so a latency figure measured over an empty result set can never
     be read as a workload measurement.

  4. Parameterized benchmark queries are executed with deterministic fixtures
     discovered from the database instead of arbitrary hardcoded ids. The
     `.sql` files on disk are executed verbatim apart from a recorded,
     deterministic parameter substitution. When no valid fixture exists the
     case is marked skipped with an explicit reason.

  5. Output is written to versioned filenames. The historical v1 artifact
     (`benchmark_results.json`) is never silently overwritten, and every
     artifact carries `methodology_version` plus a generation timestamp so
     historical and newly generated results are distinguishable.

The runner opens a read-only session: it executes SELECT/EXPLAIN/SET only and
cannot write to the database.
"""

import glob
import json
import os
import platform
import re
import statistics
import sys
import time

try:
    import psycopg2
except ImportError:  # pragma: no cover - psycopg2 is required only for live runs
    psycopg2 = None

# ---------------------------------------------------------------------------
# Methodology identity
# ---------------------------------------------------------------------------

METHODOLOGY_VERSION = "2.0"
METHODOLOGY_TAG = "v2"

#: Filenames used by the historical (methodology v1) run. These are never
#: written to by this harness; they are preserved as immutable evidence.
LEGACY_JSON_FILENAME = "benchmark_results.json"
LEGACY_MD_FILENAME = "benchmark_summary.md"

#: Result-validity vocabulary. `valid_non_empty` = the query exercised the
#: workload its header comment describes. `invalid_empty_result` = the query
#: returned zero rows, so the timings measure the cost of finding nothing.
#: `skipped` = the case could not be executed or no valid fixture exists.
STATUS_VALID = "valid_non_empty"
STATUS_EMPTY = "invalid_empty_result"
STATUS_SKIPPED = "skipped"

#: Role vocabulary for every measurement block in the payload.
ROLE_BASELINE = "baseline"
ROLE_DIAGNOSTIC = "diagnostic"

DB_HOST = os.getenv("POSTGRES_HOST") or os.getenv("PGHOST", "127.0.0.1")
DB_PORT = int(os.getenv("POSTGRES_PORT") or os.getenv("PGPORT", "5432"))
DB_NAME = os.getenv("POSTGRES_DB") or os.getenv("PGDATABASE", "talentra")
DB_USER = os.getenv("POSTGRES_USER") or os.getenv("PGUSER", "talentra_admin")
DB_PASS = os.getenv("POSTGRES_PASSWORD") or os.getenv("PGPASSWORD")

QUERIES_DIR = os.path.join(os.path.dirname(__file__), "..", "db", "queries")
RESULTS_DIR = os.path.join(os.path.dirname(__file__), "..", "benchmarks", "results")

#: The diagnostic comparison: the real planner's plan versus a plan where the
#: planner has been denied every index access path. Recorded for transparency
#: only — it is not an index-benefit measurement.
DIAGNOSTIC_METRIC = "cost_of_disabling_index_access_paths"
DIAGNOSTIC_QUERIES = [
    "01_candidate_multicriteria_search.sql",
    "03_recruiter_pipeline_funnel.sql",
    "07_non_overlapping_gig_worker_search.sql",
]


class FixtureError(Exception):
    """Raised when a fixture parameter cannot be substituted safely."""


# ---------------------------------------------------------------------------
# Deterministic fixture discovery
# ---------------------------------------------------------------------------
#
# The benchmark suite hardcodes identifier literals (`= 1`, `= 2`) that do not
# necessarily exist in the loaded dataset, which made several captured plans
# vacuous. Rather than hardcoding a different arbitrary id, each parameterized
# query below declares a read-only discovery statement that selects a
# deterministic, representative value straight from the loaded data.
#
# Every discovery statement is a SELECT; none of them mutate data, and the
# harness runs inside a read-only transaction.

FIXTURE_SPECS = {
    "03_recruiter_pipeline_funnel.sql": {
        "description": "Job posting that actually has applicants",
        "parameters": [
            {
                "name": "job_posting_id",
                "pattern": r"(ca\.job_posting_id\s*=\s*)(\d+)",
                "discovery_sql": (
                    "SELECT ca.job_posting_id AS v "
                    "FROM recruitment.candidate_application ca "
                    "GROUP BY ca.job_posting_id "
                    "ORDER BY COUNT(*) DESC, ca.job_posting_id ASC "
                    "LIMIT 1;"
                ),
            }
        ],
    },
    "04_concurrent_session_validation.sql": {
        "description": "User account holding active device sessions",
        "parameters": [
            {
                "name": "user_account_id",
                "pattern": r"(u\.id\s*=\s*)(\d+)",
                "discovery_sql": (
                    "SELECT s.user_account_id AS v "
                    "FROM core.user_session s "
                    "WHERE s.ended_at IS NULL AND s.revoked_at IS NULL "
                    "GROUP BY s.user_account_id "
                    "ORDER BY COUNT(*) DESC, s.user_account_id ASC "
                    "LIMIT 1;"
                ),
            }
        ],
    },
    "05_wallet_ledger_reconciliation.sql": {
        "description": "Organization holding a wallet with ledger entries",
        "parameters": [
            {
                "name": "organization_id",
                "pattern": r"(w\.organization_id\s*=\s*)(\d+)",
                "discovery_sql": (
                    "SELECT w.organization_id AS v "
                    "FROM commercial.wallet w "
                    "JOIN commercial.wallet_ledger wl ON wl.wallet_id = w.id "
                    "GROUP BY w.organization_id "
                    "ORDER BY COUNT(*) DESC, w.organization_id ASC "
                    "LIMIT 1;"
                ),
            }
        ],
    },
    "06_sourcing_outreach_unblocked.sql": {
        "description": "Recruiter user and organization that are actual block targets",
        "parameters": [
            {
                "name": "blocked_user_account_id",
                "pattern": r"(ub\.blocked_user_account_id\s*=\s*)(\d+)",
                "discovery_sql": (
                    "SELECT ub.blocked_user_account_id AS v "
                    "FROM core.user_block ub "
                    "WHERE ub.blocked_user_account_id IS NOT NULL "
                    "GROUP BY ub.blocked_user_account_id "
                    "ORDER BY COUNT(*) DESC, ub.blocked_user_account_id ASC "
                    "LIMIT 1;"
                ),
            },
            {
                "name": "blocked_organization_id",
                "pattern": r"(ub\.blocked_organization_id\s*=\s*)(\d+)",
                "discovery_sql": (
                    "SELECT ub.blocked_organization_id AS v "
                    "FROM core.user_block ub "
                    "WHERE ub.blocked_organization_id IS NOT NULL "
                    "GROUP BY ub.blocked_organization_id "
                    "ORDER BY COUNT(*) DESC, ub.blocked_organization_id ASC "
                    "LIMIT 1;"
                ),
            },
        ],
    },
    "08_profile_download_audit_log.sql": {
        "description": "Organization holding candidate profile download history",
        "parameters": [
            {
                "name": "organization_id",
                "pattern": r"(dh\.organization_id\s*=\s*)(\d+)",
                "discovery_sql": (
                    "SELECT dh.organization_id AS v "
                    "FROM commercial.candidate_profile_download_history dh "
                    "GROUP BY dh.organization_id "
                    "ORDER BY COUNT(*) DESC, dh.organization_id ASC "
                    "LIMIT 1;"
                ),
            }
        ],
    },
    "09_high_volume_notification_write.sql": {
        "description": "User account holding delivered notifications",
        "parameters": [
            {
                "name": "recipient_user_account_id",
                "pattern": r"(nd\.recipient_user_account_id\s*=\s*)(\d+)",
                "discovery_sql": (
                    "SELECT nd.recipient_user_account_id AS v "
                    "FROM messaging.notification_delivery nd "
                    "GROUP BY nd.recipient_user_account_id "
                    "ORDER BY COUNT(*) DESC, nd.recipient_user_account_id ASC "
                    "LIMIT 1;"
                ),
            }
        ],
    },
}


def resolve_fixture(cur, spec):
    """Resolve every fixture parameter of `spec` against the live database.

    Returns `(resolved, reason)`. `resolved` is a dict of parameter name to
    discovered value, or None when a fixture could not be established. `reason`
    is a human readable explanation of why a fixture is unavailable.
    """
    resolved = {}
    for param in spec["parameters"]:
        try:
            cur.execute(param["discovery_sql"])
            row = cur.fetchone()
        except Exception as exc:  # pragma: no cover - depends on live schema
            return None, (
                f"fixture discovery for '{param['name']}' failed: {exc}"
            )
        if row is None or row[0] is None:
            return None, (
                f"fixture discovery for '{param['name']}' returned no row; "
                f"no {spec['description']} exists in the loaded dataset"
            )
        resolved[param["name"]] = row[0]
    return resolved, None


def apply_fixture(sql, spec, resolved):
    """Substitute resolved fixture values into `sql`.

    Raises FixtureError if a declared pattern does not match exactly once,
    which means the query file drifted away from the declared fixture and the
    substitution could silently change the query's meaning.
    """
    substituted = sql
    for param in spec["parameters"]:
        value = resolved.get(param["name"])
        if value is None:
            raise FixtureError(
                f"no resolved value for fixture parameter '{param['name']}'"
            )
        pattern = re.compile(param["pattern"])
        matches = pattern.findall(substituted)
        if len(matches) != 1:
            raise FixtureError(
                f"fixture pattern for '{param['name']}' matched {len(matches)} "
                f"times in the query file; expected exactly 1"
            )
        substituted = pattern.sub(lambda _m, v=value: f"{_m.group(1)}{v}", substituted)
    return substituted


# ---------------------------------------------------------------------------
# Result classification and plan facts
# ---------------------------------------------------------------------------

def classify_result_status(row_count, error=None):
    """Classify a benchmark case by the validity of its result set.

    Returns `(status, reason)`.
    """
    if error:
        return STATUS_SKIPPED, f"execution failed: {error}"
    if row_count is None:
        return STATUS_SKIPPED, "driver returned no result set for this statement"
    if row_count == 0:
        return (
            STATUS_EMPTY,
            "query returned zero rows; the recorded latencies measure the "
            "cost of an empty result set, not the workload described in the "
            "query header",
        )
    return STATUS_VALID, ""


def extract_plan_facts(plan_json):
    """Collect verifiable facts from an EXPLAIN (FORMAT JSON) plan.

    Returns a dict with the root node's actual row count, the index names the
    planner actually used, and the node types that appeared in the plan.
    """
    facts = {
        "root_actual_rows": None,
        "indexes_used": [],
        "node_types": [],
    }
    if not isinstance(plan_json, list) or not plan_json:
        return facts
    root = plan_json[0]
    if not isinstance(root, dict):
        return facts
    plan = root.get("Plan", {})
    facts["root_actual_rows"] = plan.get("Actual Rows")
    indexes = set()
    node_types = set()

    def walk(node):
        if not isinstance(node, dict):
            return
        if node.get("Index Name"):
            indexes.add(node["Index Name"])
        if node.get("Node Type"):
            node_types.add(node["Node Type"])
        for child in node.get("Plans", []) or []:
            walk(child)

    walk(plan)
    facts["indexes_used"] = sorted(indexes)
    facts["node_types"] = sorted(node_types)
    return facts


def _is_no_result_error(exc):
    prog_err = getattr(psycopg2, "ProgrammingError", None) if psycopg2 else None
    return prog_err is not None and isinstance(exc, prog_err)


# ---------------------------------------------------------------------------
# Measurement
# ---------------------------------------------------------------------------

def get_connection():
    if psycopg2 is None:
        raise RuntimeError(
            "psycopg2 is not installed; install it to run live benchmarks"
        )
    return psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASS
    )


def percentile(data, p):
    """Compute percentile from sorted list"""
    if not data:
        return 0.0
    k = (len(data) - 1) * (p / 100.0)
    f = int(k)
    c = min(f + 1, len(data) - 1)
    d0 = data[f] * (c - k)
    d1 = data[c] * (k - f)
    return round(d0 + d1, 3)


def measure_latency(cur, sql, iterations):
    """Execute `sql` `iterations` times, returning `(timings, row_count, error)`."""
    timings = []
    row_count = None
    error = None
    for _ in range(iterations):
        t_start = time.perf_counter()
        try:
            cur.execute(sql)
            try:
                rows = cur.fetchall()
                row_count = len(rows)
            except Exception as exc:
                if _is_no_result_error(exc):
                    row_count = None
                else:
                    raise
        except Exception as exc:
            error = str(exc)
            break
        timings.append((time.perf_counter() - t_start) * 1000.0)
    return timings, row_count, error


def measure_planner_method_comparison(cur, sql, iterations=5):
    """Measure the cost of denying the planner every index access path.

    This is a DIAGNOSTIC comparison of two planner configurations, not a
    measurement of the benefit of adding an index. The "disabled" leg is a
    deliberately crippled plan produced by turning `enable_indexscan`,
    `enable_bitmapscan` and `enable_indexonlyscan` off; it is not a
    representation of "the schema without the index".
    """
    # Default planner configuration: every access path available.
    cur.execute(
        "SET enable_seqscan = on; SET enable_indexscan = on; "
        "SET enable_bitmapscan = on; SET enable_indexonlyscan = on;"
    )
    default_timings, _, default_error = measure_latency(cur, sql, iterations)

    # Denied planner configuration: no index access path may be chosen.
    cur.execute(
        "SET enable_indexscan = off; SET enable_bitmapscan = off; "
        "SET enable_indexonlyscan = off;"
    )
    disabled_timings, _, disabled_error = measure_latency(cur, sql, iterations)

    cur.execute(
        "RESET enable_seqscan; RESET enable_indexscan; "
        "RESET enable_bitmapscan; RESET enable_indexonlyscan;"
    )

    default_ms = (
        round(statistics.mean(default_timings), 3) if default_timings else None
    )
    disabled_ms = (
        round(statistics.mean(disabled_timings), 3) if disabled_timings else None
    )
    ratio = None
    if default_ms and default_ms > 0 and disabled_ms is not None:
        ratio = round(disabled_ms / default_ms, 2)
    return {
        "default_plan_ms": default_ms,
        "index_access_paths_disabled_ms": disabled_ms,
        "disabled_over_default_latency_ratio": ratio,
        "error": default_error or disabled_error,
    }


# ---------------------------------------------------------------------------
# Record construction
# ---------------------------------------------------------------------------

def build_baseline_record(qname, title, timings, row_count, error, plan_json,
                           exec_time, plan_time, shared_hit, shared_read,
                           fixture_info, iterations, status, status_reason):
    """Assemble a baseline measurement record for one query."""
    sorted_timings = sorted(timings)
    p50 = percentile(sorted_timings, 50)
    p95 = percentile(sorted_timings, 95)
    p99 = percentile(sorted_timings, 99)
    mean_lat = round(statistics.mean(sorted_timings), 3) if sorted_timings else 0.0
    min_lat = round(min(sorted_timings), 3) if sorted_timings else 0.0
    max_lat = round(max(sorted_timings), 3) if sorted_timings else 0.0
    total_blocks = shared_hit + shared_read
    hit_ratio = round((shared_hit / total_blocks * 100.0), 2) if total_blocks > 0 else 100.0

    facts = extract_plan_facts(plan_json)

    return {
        "query_file": qname,
        "title": title,
        "measurement_role": ROLE_BASELINE,
        "measurement_type": "baseline_latency_and_execution_plan",
        "iterations": iterations,
        "p50_ms": p50,
        "p95_ms": p95,
        "p99_ms": p99,
        "mean_ms": mean_lat,
        "min_ms": min_lat,
        "max_ms": max_lat,
        "explain_execution_time_ms": exec_time,
        "explain_planning_time_ms": plan_time,
        "shared_hit_blocks": shared_hit,
        "shared_read_blocks": shared_read,
        "buffer_hit_ratio_pct": hit_ratio,
        "result_status": status,
        "result_status_reason": status_reason,
        "result_row_count": row_count,
        "plan_root_actual_rows": facts["root_actual_rows"],
        "plan_indexes_used": facts["indexes_used"],
        "plan_node_types": facts["node_types"],
        "fixture": fixture_info,
        "raw_plan": plan_json,
    }


def build_diagnostic_record(qname, comparison, baseline_indexes_used):
    """Assemble a diagnostic planner-method comparison record.

    The record deliberately carries no `index_target` field and no `speedup`
    field: nothing in this comparison supports a claim that a named index
    produced a speedup.
    """
    return {
        "query": qname,
        "measurement_role": ROLE_DIAGNOSTIC,
        "measurement_type": DIAGNOSTIC_METRIC,
        "metric_definition": (
            "Latency of the same query under the default planner "
            "configuration versus the same query with enable_indexscan, "
            "enable_bitmapscan and enable_indexonlyscan forced off. The "
            "resulting ratio measures the cost of denying the planner all "
            "index access paths; it is NOT the benefit of adding an index."
        ),
        "indexes_observed_in_baseline_plan": list(baseline_indexes_used or []),
        "default_plan_ms": comparison.get("default_plan_ms"),
        "index_access_paths_disabled_ms": comparison.get("index_access_paths_disabled_ms"),
        "disabled_over_default_latency_ratio": comparison.get(
            "disabled_over_default_latency_ratio"
        ),
        "attribution": "none",
        "error": comparison.get("error"),
    }


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

def build_payload(benchmark_records, diagnostic_records, iterations, warmup, environment=None):
    """Build the versioned results payload.

    `environment` records what the numbers were measured on (engine version, dataset size, host).
    Without it a latency has no context and cannot be compared with another run.
    """
    environment = environment or {}
    return {
        "methodology_version": METHODOLOGY_VERSION,
        "methodology_tag": METHODOLOGY_TAG,
        "generated_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "engine": environment.get("engine", "PostgreSQL (version not recorded)"),
        "environment": environment,
        "iterations": iterations,
        "warmup_iterations": warmup,
        "supersedes": (
            f"benchmarks/results/{LEGACY_JSON_FILENAME} (methodology v1, "
            "unlabelled 'index_impact' metric); the v1 artifact is retained "
            "unmodified as historical evidence"
        ),
        "measurement_role_legend": {
            ROLE_BASELINE: (
                "Reference measurement of the query as it runs against the "
                "current schema with the default planner configuration. No "
                "index change is implied by these numbers."
            ),
            ROLE_DIAGNOSTIC: (
                "Diagnostic comparison of planner configurations. Reported for "
                "transparency; it does not measure the benefit of any index."
            ),
        },
        "result_status_legend": {
            STATUS_VALID: "The query returned a non-empty result set.",
            STATUS_EMPTY: (
                "The query returned zero rows. The recorded latencies measure "
                "the cost of an empty result set and must not be used as a "
                "workload measurement."
            ),
            STATUS_SKIPPED: (
                "The case could not be executed, or no valid fixture could be "
                "established. The reason is recorded with the case."
            ),
        },
        "queries": benchmark_records,
        "planner_method_comparison": diagnostic_records,
    }


def render_markdown(payload):
    """Render the human-readable benchmark summary."""
    records = payload["queries"]
    diagnostics = payload["planner_method_comparison"]

    out = []
    out.append("# Talentra Database Performance & Benchmark Suite\n\n")
    out.append(f"**Database Engine**: {payload['engine']}  \n")
    env = payload.get("environment") or {}
    if env.get("dataset"):
        out.append(f"**Dataset**: {env['dataset']}  \n")
    if env.get("host"):
        out.append(f"**Host**: {env['host']}  \n")
    out.append(
        f"**Methodology Version**: {payload['methodology_version']} "
        f"(`{payload['methodology_tag']}`)  \n"
    )
    out.append(f"**Generated At (UTC)**: {payload['generated_at_utc']}  \n")
    out.append(
        f"**Sample Count**: {payload['iterations']} timed iterations per query "
        f"(+ {payload['warmup_iterations']} warmup runs)  \n"
    )
    out.append(f"**Supersedes**: `{payload['supersedes']}`  \n\n")

    out.append("> **How to read this report**\n>\n")
    out.append(
        "> * Section 1 is the **baseline** measurement "
        "(`measurement_role: baseline`): the query running against the "
        "current schema under the default planner configuration. These "
        "numbers are the reference point, not the result of an index "
        "change.\n"
    )
    out.append(
        "> * Section 2 is a **diagnostic** planner-method comparison "
        "(`measurement_role: diagnostic`). It compares the default plan "
        "with a plan where the planner has been denied every index access "
        "path. It measures the cost of that denial, and it does **not** "
        "attribute any speedup to a named index.\n"
    )
    out.append(
        "> * Section 3 lists the benchmark cases whose result set was empty "
        "or which were skipped. Their latencies are **not** workload "
        "measurements.\n\n"
    )

    out.append("## 1. Baseline Latency Profile (measurement_role: baseline)\n\n")
    out.append(
        "| Query | Purpose / Workload | Result Validity | Rows | p50 (ms) | "
        "p95 (ms) | p99 (ms) | Mean (ms) | Buffer Hit Ratio |\n"
    )
    out.append(
        "| :--- | :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: |\n"
    )
    for r in records:
        out.append(
            f"| `{r['query_file']}` | {r['title']} | {r['result_status']} | "
            f"{r['result_row_count'] if r['result_row_count'] is not None else 'n/a'} | "
            f"**{r['p50_ms']}** | **{r['p95_ms']}** | {r['p99_ms']} | "
            f"{r['mean_ms']} | {r['buffer_hit_ratio_pct']}% |\n"
        )

    out.append(
        "\n## 2. Diagnostic: Cost of Disabling Index Access Paths "
        "(measurement_role: diagnostic)\n\n"
    )
    out.append(
        "This section is not an index-benefit measurement. Each row "
        "compares the default planner configuration with the same query run "
        "under `enable_indexscan = off; enable_bitmapscan = off; "
        "enable_indexonlyscan = off;`. The second configuration is a "
        "deliberately crippled plan; it is not equivalent to \"the schema "
        "without the index\", and it credits no index with a speedup. The "
        "ratio is *disabled latency divided by default latency*: values "
        "above 1.0 mean the crippled plan was slower.\n\n"
    )
    out.append(
        "| Query | Indexes Observed in Baseline Plan | Default Plan (ms) | "
        "Index Access Paths Disabled (ms) | Disabled / Default Ratio |\n"
    )
    out.append("| :--- | :--- | :---: | :---: | :---: |\n")
    for d in diagnostics:
        observed = ", ".join(f"`{i}`" for i in d["indexes_observed_in_baseline_plan"]) or "none observed"
        ratio = d["disabled_over_default_latency_ratio"]
        out.append(
            f"| `{d['query']}` | {observed} | "
            f"{d['default_plan_ms'] if d['default_plan_ms'] is not None else 'n/a'} ms | "
            f"{d['index_access_paths_disabled_ms'] if d['index_access_paths_disabled_ms'] is not None else 'n/a'} ms | "
            f"{ratio if ratio is not None else 'n/a'} |\n"
        )

    out.append("\n## 3. Invalid or Skipped Benchmark Cases\n\n")
    flagged = [r for r in records if r["result_status"] != STATUS_VALID]
    if not flagged:
        out.append(
            "No query returned an empty result set and no case was skipped "
            "in this run.\n\n"
        )
    else:
        out.append(
            "The following cases did not produce a usable workload "
            "measurement. Their latency figures must not be cited as "
            "evidence of query performance.\n\n"
        )
        out.append("| Query | Status | Rows | Reason |\n")
        out.append("| :--- | :--- | :---: | :--- |\n")
        for r in flagged:
            reason = (r["result_status_reason"] or "").replace("|", "\\|")
            rows = r["result_row_count"] if r["result_row_count"] is not None else "n/a"
            out.append(
                f"| `{r['query_file']}` | {r['result_status']} | {rows} | {reason} |\n"
            )
        out.append("\n")

    return "".join(out)


def output_paths(results_dir=None):
    """Return the versioned output paths. The legacy v1 artifacts are never
    returned, so the historical evidence cannot be silently overwritten."""
    base = results_dir or RESULTS_DIR
    # BENCHMARK_LABEL=laptop writes benchmark_results_v2_laptop.json, so runs on different datasets sit side by side
    label = os.getenv("BENCHMARK_LABEL", "").strip()
    suffix = f"_{label}" if label else ""
    return (
        os.path.join(base, f"benchmark_results_{METHODOLOGY_TAG}{suffix}.json"),
        os.path.join(base, f"benchmark_summary_{METHODOLOGY_TAG}{suffix}.md"),
    )


def write_outputs(payload, results_dir=None):
    """Write the versioned JSON and Markdown artifacts."""
    json_path, md_path = output_paths(results_dir)
    os.makedirs(os.path.dirname(json_path), exist_ok=True)

    if os.path.basename(json_path) == LEGACY_JSON_FILENAME:
        raise RuntimeError(
            "refusing to overwrite the historical benchmark artifact"
        )
    if os.path.basename(md_path) == LEGACY_MD_FILENAME:
        raise RuntimeError(
            "refusing to overwrite the historical benchmark summary"
        )

    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2)
    with open(md_path, "w", encoding="utf-8") as f:
        f.write(render_markdown(payload))
    return json_path, md_path


# ---------------------------------------------------------------------------
# Orchestration
# ---------------------------------------------------------------------------

def extract_title(raw_sql, qname):
    """Extract the title comment from a benchmark query file."""
    title = qname
    for line in raw_sql.splitlines():
        if line.startswith("-- Purpose:"):
            title = line.replace("-- Purpose:", "").strip()
            break
        elif line.startswith("-- Query"):
            title = line.replace("--", "").strip()
    return title


def run_benchmarks(iterations=10, warmup=2):
    os.makedirs(RESULTS_DIR, exist_ok=True)
    query_files = sorted(glob.glob(os.path.join(QUERIES_DIR, "*.sql")))

    print("================================================================")
    print(" Talentra Fixed Benchmark Suite")
    print(f" Methodology: v{METHODOLOGY_VERSION} ({METHODOLOGY_TAG})")
    print(f" Queries: {len(query_files)} | Iterations: {iterations} | Warmup: {warmup}")
    print("================================================================\n")

    conn = get_connection()
    # Read-only session: the harness executes SELECT/EXPLAIN/SET only.
    conn.set_session(readonly=True, autocommit=True)
    cur = conn.cursor()

    cur.execute("SHOW server_version;")
    server_version = cur.fetchone()[0]
    cur.execute("SELECT (SELECT COUNT(*) FROM profile.candidate_profile), (SELECT COUNT(*) FROM recruitment.job_posting), "
                "(SELECT COUNT(*) FROM recruitment.candidate_application);")
    n_cand, n_jobs, n_apps = cur.fetchone()
    environment = {
        "engine": f"PostgreSQL {server_version}",
        "dataset": f"{n_cand:,} candidate profiles, {n_jobs:,} job postings, {n_apps:,} applications",
        "host": f"{platform.platform()}, {os.cpu_count()} CPUs",
    }

    benchmark_records = []
    baseline_plans = {}

    for qfile in query_files:
        qname = os.path.basename(qfile)
        with open(qfile, "r", encoding="utf-8") as f:
            raw_sql = f.read()

        title = extract_title(raw_sql, qname)
        print(f"[*] Benchmarking {qname}: {title[:55]}...")

        # 1. Resolve a deterministic fixture for parameterized queries.
        spec = FIXTURE_SPECS.get(qname)
        sql = raw_sql
        fixture_info = {"required": False, "applied": False, "parameters": {}}
        status = STATUS_VALID
        status_reason = ""

        if spec:
            fixture_info = {
                "required": True,
                "applied": False,
                "description": spec["description"],
                "parameters": {},
            }
            resolved, reason = resolve_fixture(cur, spec)
            if resolved is None:
                status = STATUS_SKIPPED
                status_reason = reason
                fixture_info["skipped_reason"] = reason
            else:
                try:
                    sql = apply_fixture(raw_sql, spec, resolved)
                except FixtureError as exc:
                    status = STATUS_SKIPPED
                    status_reason = f"fixture substitution failed: {exc}"
                    fixture_info["skipped_reason"] = status_reason
                else:
                    fixture_info["applied"] = True
                    fixture_info["parameters"] = {
                        name: {
                            "value": value,
                            "source": "db_discovery",
                            "description": spec["description"],
                        }
                        for name, value in resolved.items()
                    }

        if status == STATUS_SKIPPED:
            benchmark_records.append(
                build_baseline_record(
                    qname, title, [], None, None, [], 0.0, 0.0, 0, 0,
                    fixture_info, iterations, status, status_reason,
                )
            )
            print(f"    -> SKIPPED: {status_reason}")
            continue

        # 2. Warmup
        for _ in range(warmup):
            try:
                cur.execute(sql)
                cur.fetchall()
            except Exception:
                pass

        # 3. Timed iterations
        timings, row_count, error = measure_latency(cur, sql, iterations)
        if error:
            status = STATUS_SKIPPED
            status_reason = f"execution failed: {error}"
        else:
            status, status_reason = classify_result_status(row_count)

        # 4. EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
        explain_sql = f"EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) {sql}"
        shared_hit = 0
        shared_read = 0
        exec_time = 0.0
        plan_time = 0.0
        plan_json = []

        try:
            cur.execute(explain_sql)
            plan_json = cur.fetchone()[0]
            plan_root = plan_json[0]
            exec_time = plan_root.get("Execution Time", 0.0)
            plan_time = plan_root.get("Planning Time", 0.0)

            plan_node = plan_root.get("Plan", {})
            shared_hit = plan_node.get("Shared Hit Blocks", 0)
            shared_read = plan_node.get("Shared Read Blocks", 0)
        except Exception as exc:
            plan_json = {"error": str(exc)}
            if status != STATUS_SKIPPED:
                status = STATUS_SKIPPED
                status_reason = f"EXPLAIN (ANALYZE) failed: {exc}"

        record = build_baseline_record(
            qname, title, timings, row_count, error, plan_json, exec_time,
            plan_time, shared_hit, shared_read, fixture_info, iterations,
            status, status_reason,
        )
        benchmark_records.append(record)
        baseline_plans[qname] = record

        print(
            f"    -> p50: {record['p50_ms']:.2f}ms | p95: {record['p95_ms']:.2f}ms | "
            f"p99: {record['p99_ms']:.2f}ms | Cache Hit: {record['buffer_hit_ratio_pct']:.1f}% | "
            f"Status: {status} | Rows: {row_count}"
        )

    # 5. Diagnostic planner-method comparison
    print(
        "\n[*] Diagnostic: cost of disabling index access paths "
        "(NOT an index-benefit measurement)..."
    )
    diagnostic_records = []
    for qname in DIAGNOSTIC_QUERIES:
        qfile = os.path.join(QUERIES_DIR, qname)
        with open(qfile, "r", encoding="utf-8") as f:
            raw_sql = f.read()

        baseline = baseline_plans.get(qname)
        sql = raw_sql
        if baseline and baseline["fixture"]["applied"]:
            spec = FIXTURE_SPECS.get(qname)
            resolved = {
                name: meta["value"]
                for name, meta in baseline["fixture"]["parameters"].items()
            }
            try:
                sql = apply_fixture(raw_sql, spec, resolved)
            except FixtureError:
                sql = raw_sql

        comparison = measure_planner_method_comparison(cur, sql)
        record = build_diagnostic_record(
            qname,
            comparison,
            baseline["plan_indexes_used"] if baseline else [],
        )
        diagnostic_records.append(record)
        print(
            f"    -> {qname}: default {record['default_plan_ms']}ms vs "
            f"index-paths-disabled {record['index_access_paths_disabled_ms']}ms "
            f"(diagnostic ratio {record['disabled_over_default_latency_ratio']})"
        )

    conn.close()

    payload = build_payload(
        benchmark_records, diagnostic_records, iterations, warmup, environment
    )
    json_path, md_path = write_outputs(payload)
    print(f"\n[+] Saved raw benchmark JSON to {json_path}")
    print(f"[+] Saved formatted Markdown benchmark report to {md_path}")
    print(
        f"[+] Historical artifact retained unmodified: "
        f"{os.path.join(RESULTS_DIR, LEGACY_JSON_FILENAME)}"
    )
    print("\n================================================================")
    print(" Benchmark Execution Completed Successfully!")
    print("================================================================")


if __name__ == "__main__":
    run_benchmarks()
