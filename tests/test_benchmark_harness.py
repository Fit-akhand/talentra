#!/usr/bin/env python3
"""
Talentra Database Design — Benchmark Harness Methodology Test Suite

Verifies the Phase 2C corrections to scripts/run_benchmarks.py:

1. Normal query plans are labelled as the BASELINE measurement, and the
   planner-method comparison is labelled DIAGNOSTIC.
2. The planner-method metric measures the cost of DISABLING index access
   paths, and no output attributes a speedup to a named index.
3. Result validity is classified: a valid non-empty case is distinguished
   from an empty-result case and from a skipped case.
4. Deterministic fixture substitution replaces hardcoded identifiers using
   values discovered from the database, and refuses to substitute when the
   query file has drifted away from the declared fixture pattern.
5. The historical (methodology v1) benchmark artifacts are never overwritten,
   and newly generated results carry a methodology version and timestamp.

This suite is database-free: it exercises the harness logic against a fake
cursor so it can run in any environment. Live database validation is a
separate concern reported in docs/phase2c-benchmark-correction-report.md.
"""
# Covers: OPS-006   (generated from the registers by scripts/lifecycle/tag_tests.py)

import importlib.util
import io
import json
import os
import re
import sys
import tempfile

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(TESTS_DIR)
HARNESS_PATH = os.path.join(REPO_ROOT, "scripts", "run_benchmarks.py")


def _load_harness():
    """Import scripts/run_benchmarks.py as a module without requiring psycopg2."""
    spec = importlib.util.spec_from_file_location("talentra_benchmark_harness", HARNESS_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


H = _load_harness()


class FakeCursor:
    """Minimal psycopg2-cursor stand-in that records executed SQL.

    `results` maps a SQL fragment to the row the cursor should return. Any
    execute() whose SQL contains a key of `results` returns that row;
    otherwise it returns a single row of (1,).
    """

    def __init__(self, results=None, default_row=(1,)):
        self.results = results or {}
        self.default_row = default_row
        self.executed = []
        self._pending = None
        self._error = None

    def execute(self, sql, params=None):
        self.executed.append(sql)
        self._pending = self.default_row
        self._error = None
        # A matching fragment wins even when its configured row is None: None means
        # "the query returned no row", which must not be replaced by the default row.
        for fragment, row in self.results.items():
            if fragment in sql:
                self._pending = row
                break

    def fetchone(self):
        if self._error:
            raise self._error
        return self._pending

    def fetchall(self):
        if self._error:
            raise self._error
        return [self._pending]


# ---------------------------------------------------------------------------
# 1. Measurement role labels
# ---------------------------------------------------------------------------

def test_baseline_records_are_labelled_baseline():
    print("\n--- Test 1: Baseline records carry measurement_role='baseline' ---")

    plan = [{
        "Plan": {
            "Node Type": "Limit",
            "Actual Rows": 50,
            "Index Name": "idx_candidate_application_job_status",
            "Plans": [{
                "Node Type": "Index Scan",
                "Index Name": "idx_candidate_application_job_status",
                "Actual Rows": 50,
            }],
        },
        "Execution Time": 1.2,
        "Planning Time": 0.3,
    }]

    record = H.build_baseline_record(
        "03_recruiter_pipeline_funnel.sql",
        "Recruiter dashboard aggregation.",
        [1.0, 1.2, 0.9],
        50,
        None,
        plan,
        1.2,
        0.3,
        4,
        0,
        {"required": True, "applied": True, "parameters": {}},
        10,
        H.STATUS_VALID,
        "",
    )

    assert record["measurement_role"] == H.ROLE_BASELINE, (
        f"Expected baseline role, got {record['measurement_role']}"
    )
    assert record["measurement_type"] == "baseline_latency_and_execution_plan", (
        f"Unexpected measurement_type: {record['measurement_type']}"
    )
    assert record["result_status"] == H.STATUS_VALID, (
        f"Expected valid status, got {record['result_status']}"
    )
    assert record["p50_ms"] == 1.0, f"Unexpected p50: {record['p50_ms']}"
    assert record["plan_root_actual_rows"] == 50, (
        f"Expected root actual rows 50, got {record['plan_root_actual_rows']}"
    )
    assert record["plan_indexes_used"] == ["idx_candidate_application_job_status"], (
        f"Unexpected indexes used: {record['plan_indexes_used']}"
    )
    print("PASS: Baseline records are explicitly labelled as the baseline measurement.")


def test_diagnostic_records_are_labelled_diagnostic_and_carry_no_index_claim():
    print("\n--- Test 2: Diagnostic comparison is labelled and makes no index claim ---")

    comparison = {
        "default_plan_ms": 1.21,
        "index_access_paths_disabled_ms": 6.07,
        "disabled_over_default_latency_ratio": 5.02,
        "error": None,
    }
    record = H.build_diagnostic_record(
        "03_recruiter_pipeline_funnel.sql",
        comparison,
        ["idx_candidate_application_job_status"],
    )

    assert record["measurement_role"] == H.ROLE_DIAGNOSTIC, (
        f"Expected diagnostic role, got {record['measurement_role']}"
    )
    assert record["measurement_type"] == H.DIAGNOSTIC_METRIC, (
        f"Unexpected measurement_type: {record['measurement_type']}"
    )
    assert record["attribution"] == "none", (
        f"Diagnostic record must not attribute the ratio, got {record['attribution']}"
    )
    for forbidden in ("index_target", "speedup_factor", "with_index_ms", "without_index_ms"):
        assert forbidden not in record, (
            f"Diagnostic record must not contain the field '{forbidden}'"
        )
    assert "indexes_observed_in_baseline_plan" in record, (
        "Diagnostic record should report the indexes actually observed in the baseline plan"
    )
    assert record["indexes_observed_in_baseline_plan"] == [
        "idx_candidate_application_job_status"
    ], "Observed index list was not recorded"

    print("PASS: Diagnostic comparison is labelled diagnostic and attributes no speedup.")


def test_payload_legend_distinguishes_baseline_from_diagnostic():
    print("\n--- Test 3: Payload legend separates baseline and diagnostic roles ---")

    payload = H.build_payload(
        [H.build_baseline_record(
            "01_candidate_multicriteria_search.sql", "Search.",
            [1.0], 50, None, [], 1.0, 0.1, 1, 0,
            {"required": False, "applied": False, "parameters": {}},
            10, H.STATUS_VALID, "",
        )],
        [H.build_diagnostic_record(
            "01_candidate_multicriteria_search.sql",
            {"default_plan_ms": 1.0, "index_access_paths_disabled_ms": 2.0,
             "disabled_over_default_latency_ratio": 2.0, "error": None},
            [],
        )],
        10,
        2,
    )

    assert payload["methodology_version"] == H.METHODOLOGY_VERSION, (
        "Payload must carry a methodology version"
    )
    assert payload["generated_at_utc"], "Payload must carry a generation timestamp"
    assert H.ROLE_BASELINE in payload["measurement_role_legend"], (
        "Payload legend must define the baseline role"
    )
    assert H.ROLE_DIAGNOSTIC in payload["measurement_role_legend"], (
        "Payload legend must define the diagnostic role"
    )
    assert "index_impact" not in payload, (
        "Payload must not retain the unlabelled 'index_impact' block"
    )
    assert "planner_method_comparison" in payload, (
        "Payload must expose the diagnostic block under an explicit name"
    )
    assert payload["queries"][0]["measurement_role"] == H.ROLE_BASELINE, (
        "Query record must be labelled baseline"
    )
    assert payload["planner_method_comparison"][0]["measurement_role"] == H.ROLE_DIAGNOSTIC, (
        "Diagnostic record must be labelled diagnostic"
    )
    print("PASS: Payload legend and role labels distinguish baseline from diagnostic.")


# ---------------------------------------------------------------------------
# 2. Result validity classification
# ---------------------------------------------------------------------------

def test_result_status_classification():
    print("\n--- Test 4: Harness distinguishes valid, empty and skipped cases ---")

    status, reason = H.classify_result_status(50)
    assert status == H.STATUS_VALID, f"Expected valid status, got {status}"
    assert reason == "", f"Valid case should carry no reason, got {reason!r}"

    status, reason = H.classify_result_status(0)
    assert status == H.STATUS_EMPTY, f"Expected empty status, got {status}"
    assert "zero rows" in reason, f"Empty case must explain itself, got {reason!r}"

    status, reason = H.classify_result_status(12)
    assert status == H.STATUS_VALID, f"Expected valid status, got {status}"

    status, reason = H.classify_result_status(None)
    assert status == H.STATUS_SKIPPED, f"Expected skipped status, got {status}"
    assert reason, "Skipped case must carry an explicit reason"

    status, reason = H.classify_result_status(0, error="relation does not exist")
    assert status == H.STATUS_SKIPPED, (
        f"An execution error must be skipped, not merely empty, got {status}"
    )
    assert "relation does not exist" in reason, (
        f"Skip reason must preserve the underlying error, got {reason!r}"
    )

    # The three statuses must be mutually exclusive.
    assert len({H.STATUS_VALID, H.STATUS_EMPTY, H.STATUS_SKIPPED}) == 3, (
        "Result status vocabulary must contain three distinct values"
    )
    print("PASS: Valid non-empty, empty-result and skipped cases are distinguished.")


def test_empty_result_is_surfaced_in_the_markdown_report():
    print("\n--- Test 5: Empty-result cases are listed in the rendered report ---")

    valid = H.build_baseline_record(
        "01_candidate_multicriteria_search.sql", "Search.",
        [30.0], 50, None, [], 30.0, 1.0, 300, 0,
        {"required": False, "applied": False, "parameters": {}},
        10, H.STATUS_VALID, "",
    )
    empty = H.build_baseline_record(
        "09_high_volume_notification_write.sql", "Notifications.",
        [0.83], 0, None, [], 0.03, 0.05, 100, 0,
        {"required": True, "applied": True, "parameters": {}},
        10, H.STATUS_EMPTY,
        "query returned zero rows; the recorded latencies measure the cost "
        "of an empty result set, not the workload described in the query header",
    )
    payload = H.build_payload([valid, empty], [], 10, 2)
    md = H.render_markdown(payload)

    assert "measurement_role: baseline" in md, "Report must label the baseline section"
    assert "measurement_role: diagnostic" in md, "Report must label the diagnostic section"
    assert "not an index-benefit measurement" in md.lower(), (
        "Report must state that the diagnostic section is not an index-benefit measurement"
    )
    assert "09_high_volume_notification_write.sql" in md, (
        "Empty-result case must appear in the report"
    )
    assert "Invalid or Skipped Benchmark Cases" in md, (
        "Report must contain an explicit invalid/skipped section"
    )
    assert "Speedup Factor" not in md, (
        "Report must not present a 'Speedup Factor' column"
    )
    print("PASS: Empty-result cases are surfaced and no speedup column is emitted.")


# ---------------------------------------------------------------------------
# 3. Deterministic fixture handling
# ---------------------------------------------------------------------------

def test_fixture_substitution_uses_discovered_values():
    print("\n--- Test 6: Fixture substitution replaces hardcoded identifiers ---")

    sql = "SELECT ... FROM recruitment.candidate_application ca\nWHERE ca.job_posting_id = 1\nGROUP BY 1;"
    spec = H.FIXTURE_SPECS["03_recruiter_pipeline_funnel.sql"]
    out = H.apply_fixture(sql, spec, {"job_posting_id": 4242})

    assert "ca.job_posting_id = 4242" in out, (
        f"Substitution did not apply the discovered value:\n{out}"
    )
    assert "job_posting_id = 1" not in out, (
        f"Original hardcoded literal survived substitution:\n{out}"
    )
    print("PASS: Fixture substitution applies the discovered, non-arbitrary value.")


def test_fixture_substitution_refuses_ambiguous_match():
    print("\n--- Test 7: Fixture substitution refuses to alter query semantics ---")

    sql = "WHERE ca.job_posting_id = 1 AND ca.job_posting_id = 1"
    spec = H.FIXTURE_SPECS["03_recruiter_pipeline_funnel.sql"]
    try:
        H.apply_fixture(sql, spec, {"job_posting_id": 7})
    except H.FixtureError as exc:
        assert "matched 2 times" in str(exc), f"Unexpected error text: {exc}"
        print("PASS: Ambiguous fixture pattern is refused instead of silently rewriting the query.")
        return
    raise AssertionError("Expected FixtureError for a pattern that matches more than once")


def test_fixture_discovery_returns_none_when_no_candidate_exists():
    print("\n--- Test 8: Missing fixture data yields an explicit skip reason ---")

    cur = FakeCursor(results={"recruitment.candidate_application": None})
    spec = H.FIXTURE_SPECS["03_recruiter_pipeline_funnel.sql"]
    resolved, reason = H.resolve_fixture(cur, spec)

    assert resolved is None, "Expected no resolved fixture when the table is empty"
    assert reason, "A missing fixture must carry an explicit reason"
    assert "no Job posting that actually has applicants exists" in reason, (
        f"Unexpected skip reason: {reason!r}"
    )
    print("PASS: A missing fixture produces an explicit, reportable skip reason.")


def test_fixture_discovery_uses_the_declared_parameter_value():
    print("\n--- Test 9: Fixture discovery returns the discovered identifier ---")

    cur = FakeCursor(results={"recruitment.candidate_application": (4242,)})
    spec = H.FIXTURE_SPECS["03_recruiter_pipeline_funnel.sql"]
    resolved, reason = H.resolve_fixture(cur, spec)

    assert reason is None, f"Unexpected reason: {reason!r}"
    assert resolved == {"job_posting_id": 4242}, f"Unexpected resolution: {resolved!r}"
    assert "GROUP BY ca.job_posting_id" in cur.executed[0], (
        "Discovery must be deterministic (ORDER BY count, then id)"
    )
    print("PASS: Fixture discovery returns a deterministic, database-sourced value.")


def test_every_fixture_discovery_statement_is_read_only():
    print("\n--- Test 10: All fixture discovery statements are read-only SELECTs ---")

    for qname, spec in H.FIXTURE_SPECS.items():
        for param in spec["parameters"]:
            sql = " ".join(param["discovery_sql"].split()).upper()
            assert sql.startswith("SELECT "), (
                f"{qname}/{param['name']} discovery must be a SELECT, got: {sql[:60]}"
            )
            for forbidden in ("INSERT", "UPDATE", "DELETE", "DROP", "ALTER",
                              "CREATE", "TRUNCATE", "GRANT", "REVOKE"):
                # whole-word match: "REVOKE" must not fire on a column named revoked_at
                assert not re.search(r"\b%s\b" % forbidden, sql), (
                    f"{qname}/{param['name']} discovery contains '{forbidden}'"
                )
    print("PASS: Every fixture discovery statement is a read-only SELECT.")


def test_every_fixture_covers_a_known_empty_benchmark_case():
    print("\n--- Test 11: Fixture coverage matches the confirmed empty-result cases ---")

    # The five benchmark cases whose captured result set was empty in the
    # methodology v1 run, plus Q06 whose block-exclusion subquery matched
    # nothing.
    expected = {
        "03_recruiter_pipeline_funnel.sql",
        "04_concurrent_session_validation.sql",
        "05_wallet_ledger_reconciliation.sql",
        "06_sourcing_outreach_unblocked.sql",
        "08_profile_download_audit_log.sql",
        "09_high_volume_notification_write.sql",
    }
    assert set(H.FIXTURE_SPECS.keys()) == expected, (
        "Fixture coverage changed unexpectedly: "
        f"{sorted(set(H.FIXTURE_SPECS.keys()) ^ expected)}"
    )
    print("PASS: Fixture specs cover exactly the confirmed empty-result cases.")


# ---------------------------------------------------------------------------
# 4. Artifact versioning and preservation
# ---------------------------------------------------------------------------

def test_historical_artifacts_are_never_overwritten():
    print("\n--- Test 12: Historical v1 artifacts are protected from overwrite ---")

    json_path, md_path = H.output_paths()
    assert os.path.basename(json_path) != H.LEGACY_JSON_FILENAME, (
        "Versioned JSON output must not use the historical filename"
    )
    assert os.path.basename(md_path) != H.LEGACY_MD_FILENAME, (
        "Versioned Markdown output must not use the historical filename"
    )
    assert H.METHODOLOGY_TAG in os.path.basename(json_path), (
        "Versioned JSON filename must carry the methodology tag"
    )

    with tempfile.TemporaryDirectory() as tmpdir:
        legacy_json = os.path.join(tmpdir, H.LEGACY_JSON_FILENAME)
        legacy_md = os.path.join(tmpdir, H.LEGACY_MD_FILENAME)
        with open(legacy_json, "w", encoding="utf-8") as f:
            f.write('{"sentinel": "historical v1 artifact"}')
        with open(legacy_md, "w", encoding="utf-8") as f:
            f.write("# historical v1 summary")

        payload = H.build_payload([], [], 10, 2)
        new_json, new_md = H.write_outputs(payload, results_dir=tmpdir)

        assert os.path.exists(legacy_json), "Historical JSON artifact was removed"
        with open(legacy_json, "r", encoding="utf-8") as f:
            assert f.read() == '{"sentinel": "historical v1 artifact"}', (
                "Historical JSON artifact was modified"
            )
        assert os.path.exists(legacy_md), "Historical Markdown artifact was removed"
        with open(legacy_md, "r", encoding="utf-8") as f:
            assert f.read() == "# historical v1 summary", (
                "Historical Markdown artifact was modified"
            )
        assert os.path.basename(new_json) != H.LEGACY_JSON_FILENAME, (
            "New results were written to the historical filename"
        )
    print("PASS: Historical v1 artifacts are preserved unmodified; new results are versioned.")


def test_generated_results_are_distinguishable_from_historical_results():
    print("\n--- Test 13: New results carry a methodology version and timestamp ---")

    payload = H.build_payload([], [], 10, 2)
    assert payload["methodology_version"] == H.METHODOLOGY_VERSION, (
        "Generated payload must carry a methodology version"
    )
    assert payload["generated_at_utc"].endswith("Z"), (
        "Generated payload must carry a UTC generation timestamp"
    )
    assert H.LEGACY_JSON_FILENAME in payload["supersedes"], (
        "Generated payload must reference the superseded historical artifact"
    )

    with tempfile.TemporaryDirectory() as tmpdir:
        new_json, _ = H.write_outputs(payload, results_dir=tmpdir)
        with open(new_json, "r", encoding="utf-8") as f:
            written = json.load(f)
    assert written["methodology_version"] == H.METHODOLOGY_VERSION, (
        "Written JSON lost the methodology version"
    )
    assert written["generated_at_utc"] == payload["generated_at_utc"], (
        "Written JSON lost the generation timestamp"
    )
    print("PASS: Generated results are distinguishable by methodology version and timestamp.")


def test_committed_historical_artifact_is_methodology_v1():
    print("\n--- Test 14: The committed historical artifact is unchanged methodology v1 ---")

    legacy_path = os.path.join(
        REPO_ROOT, "benchmarks", "results", H.LEGACY_JSON_FILENAME
    )
    if not os.path.exists(legacy_path):
        print("SKIP: historical artifact not present in this checkout")
        return

    with open(legacy_path, "r", encoding="utf-8") as f:
        legacy = json.load(f)

    assert "methodology_version" not in legacy, (
        "The historical artifact must not be rewritten to claim a methodology version"
    )
    assert "index_impact" in legacy, (
        "The historical artifact must retain its original v1 'index_impact' block"
    )
    assert legacy["benchmark_timestamp"], "Historical artifact must retain its timestamp"
    print("PASS: The committed historical artifact is still the untouched methodology v1 file.")


if __name__ == "__main__":
    print("======================================================================")
    print("   Talentra Benchmark Harness Methodology Verification Harness")
    print("======================================================================")
    try:
        test_baseline_records_are_labelled_baseline()
        test_diagnostic_records_are_labelled_diagnostic_and_carry_no_index_claim()
        test_payload_legend_distinguishes_baseline_from_diagnostic()
        test_result_status_classification()
        test_empty_result_is_surfaced_in_the_markdown_report()
        test_fixture_substitution_uses_discovered_values()
        test_fixture_substitution_refuses_ambiguous_match()
        test_fixture_discovery_returns_none_when_no_candidate_exists()
        test_fixture_discovery_uses_the_declared_parameter_value()
        test_every_fixture_discovery_statement_is_read_only()
        test_every_fixture_covers_a_known_empty_benchmark_case()
        test_historical_artifacts_are_never_overwritten()
        test_generated_results_are_distinguishable_from_historical_results()
        test_committed_historical_artifact_is_methodology_v1()
        print("\n======================================================================")
        print("   ALL BENCHMARK HARNESS METHODOLOGY TESTS PASSED (100% GREEN)      ")
        print("======================================================================")
        sys.exit(0)
    except AssertionError as ae:
        print(f"\n[FAIL] Assertion Failed: {ae}")
        sys.exit(1)
    except Exception as e:
        print(f"\n[ERROR] Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(2)
