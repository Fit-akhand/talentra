#!/usr/bin/env python3
"""
Talentra Benchmark Runner & Execution Plan Profiler (Milestone 21: B67–B70)
Engine: PostgreSQL 17
Executes the 12 fixed benchmark queries in db/queries/, measures p50/p95/p99 latencies,
extracts EXPLAIN (ANALYZE, BUFFERS) execution plans, profiles buffer cache hits,
measures index impact (with vs without index), and exports reports to benchmarks/results/.
"""

import glob
import json
import os
import re
import statistics
import sys
import time
import psycopg2

DB_HOST = os.getenv("POSTGRES_HOST", "127.0.0.1")
DB_PORT = int(os.getenv("POSTGRES_PORT", "5432"))
DB_NAME = os.getenv("POSTGRES_DB", "talentra")
DB_USER = os.getenv("POSTGRES_USER", "talentra_admin")
DB_PASS = os.getenv("POSTGRES_PASSWORD", "354vctrho9t769874t8B*^&$%&**tf2eej2rh")

QUERIES_DIR = os.path.join(os.path.dirname(__file__), "..", "db", "queries")
RESULTS_DIR = os.path.join(os.path.dirname(__file__), "..", "benchmarks", "results")

def get_connection():
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

def run_benchmarks(iterations=10, warmup=2):
    os.makedirs(RESULTS_DIR, exist_ok=True)
    query_files = sorted(glob.glob(os.path.join(QUERIES_DIR, "*.sql")))

    print("================================================================")
    print(" Talentra Fixed Benchmark Suite (PostgreSQL 17)")
    print(f" Queries: {len(query_files)} | Iterations: {iterations} | Warmup: {warmup}")
    print("================================================================\n")

    conn = get_connection()
    conn.autocommit = True
    cur = conn.cursor()

    benchmark_records = []

    for qfile in query_files:
        qname = os.path.basename(qfile)
        with open(qfile, "r", encoding="utf-8") as f:
            raw_sql = f.read()

        # Extract title comment
        title = qname
        for line in raw_sql.splitlines():
            if line.startswith("-- Purpose:"):
                title = line.replace("-- Purpose:", "").strip()
                break
            elif line.startswith("-- Query"):
                title = line.replace("--", "").strip()

        print(f"[*] Benchmarking {qname}: {title[:55]}...")

        # 1. Warmup
        for _ in range(warmup):
            try:
                cur.execute(raw_sql)
                cur.fetchall()
            except Exception as e:
                # Some queries might not return rows
                pass

        # 2. Timed Iterations
        timings = []
        for _ in range(iterations):
            t_start = time.perf_counter()
            cur.execute(raw_sql)
            try:
                cur.fetchall()
            except psycopg2.ProgrammingError:
                pass
            elapsed_ms = (time.perf_counter() - t_start) * 1000.0
            timings.append(elapsed_ms)

        timings.sort()
        p50 = percentile(timings, 50)
        p95 = percentile(timings, 95)
        p99 = percentile(timings, 99)
        mean_lat = round(statistics.mean(timings), 3)
        min_lat = round(min(timings), 3)
        max_lat = round(max(timings), 3)

        # 3. EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
        explain_sql = f"EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) {raw_sql}"
        shared_hit = 0
        shared_read = 0
        exec_time = 0.0
        plan_time = 0.0

        try:
            cur.execute(explain_sql)
            plan_json = cur.fetchone()[0]
            plan_root = plan_json[0]
            exec_time = plan_root.get("Execution Time", 0.0)
            plan_time = plan_root.get("Planning Time", 0.0)
            
            plan_node = plan_root.get("Plan", {})
            shared_hit = plan_node.get("Shared Hit Blocks", 0)
            shared_read = plan_node.get("Shared Read Blocks", 0)
        except Exception as e:
            plan_json = {"error": str(e)}

        total_blocks = shared_hit + shared_read
        hit_ratio = round((shared_hit / total_blocks * 100.0), 2) if total_blocks > 0 else 100.0

        record = {
            "query_file": qname,
            "title": title,
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
            "raw_plan": plan_json
        }
        benchmark_records.append(record)
        print(f"    -> p50: {p50:.2f}ms | p95: {p95:.2f}ms | p99: {p99:.2f}ms | Cache Hit: {hit_ratio:.1f}%")

    # 4. Measure Index Impact (Targeted Index Justification)
    print("\n[*] Measuring Index Optimization Impact (Before vs After Index Simulation)...")
    index_tests = [
        ("01_candidate_multicriteria_search.sql", "Candidate Skill & Location Index"),
        ("03_recruiter_pipeline_funnel.sql", "Candidate Application Job Status Index"),
        ("07_non_overlapping_gig_worker_search.sql", "Gig Availability & Non-Overlap GiST Index")
    ]
    index_impact_results = []

    for qname, idx_name in index_tests:
        qfile = os.path.join(QUERIES_DIR, qname)
        with open(qfile, "r", encoding="utf-8") as f:
            sql = f.read()

        # Indexed latency
        cur.execute("SET enable_seqscan = on; SET enable_indexscan = on; SET enable_bitmapscan = on;")
        t0 = time.perf_counter()
        for _ in range(5):
            cur.execute(sql)
            cur.fetchall()
        t_indexed = (time.perf_counter() - t0) / 5.0 * 1000.0

        # Unindexed simulation (force sequential table scan)
        cur.execute("SET enable_indexscan = off; SET enable_bitmapscan = off; SET enable_indexonlyscan = off;")
        t0 = time.perf_counter()
        for _ in range(5):
            cur.execute(sql)
            cur.fetchall()
        t_unindexed = (time.perf_counter() - t0) / 5.0 * 1000.0

        # Reset
        cur.execute("RESET enable_indexscan; RESET enable_bitmapscan; RESET enable_indexonlyscan;")

        speedup = round(t_unindexed / t_indexed, 2) if t_indexed > 0 else 1.0
        index_impact_results.append({
            "query": qname,
            "index_target": idx_name,
            "with_index_ms": round(t_indexed, 2),
            "without_index_ms": round(t_unindexed, 2),
            "speedup_factor": speedup
        })
        print(f"    -> {qname} ({idx_name}): {t_indexed:.2f}ms with index vs {t_unindexed:.2f}ms seq-scan ({speedup}x speedup)")

    conn.close()

    # 5. Export JSON Results
    results_payload = {
        "benchmark_timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "engine": "PostgreSQL 17",
        "iterations": iterations,
        "queries": benchmark_records,
        "index_impact": index_impact_results
    }
    json_path = os.path.join(RESULTS_DIR, "benchmark_results.json")
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(results_payload, f, indent=2)
    print(f"\n[+] Saved raw benchmark JSON to {json_path}")

    # 6. Export Formatted Markdown Summary
    md_path = os.path.join(RESULTS_DIR, "benchmark_summary.md")
    with open(md_path, "w", encoding="utf-8") as f:
        f.write("# Talentra Database Performance & Benchmark Suite\n\n")
        f.write(f"**Database Engine**: PostgreSQL 17  \n")
        f.write(f"**Execution Timestamp**: {results_payload['benchmark_timestamp']}  \n")
        f.write(f"**Sample Count**: {iterations} timed iterations per query (+ {warmup} warmup runs)  \n\n")
        f.write("## 1. Fixed Query Latency Profile\n\n")
        f.write("| Query | Purpose / Workload | p50 (ms) | p95 (ms) | p99 (ms) | Mean (ms) | Buffer Hit Ratio |\n")
        f.write("| :--- | :--- | :---: | :---: | :---: | :---: | :---: |\n")
        for r in benchmark_records:
            f.write(f"| `{r['query_file']}` | {r['title']} | **{r['p50_ms']}** | **{r['p95_ms']}** | {r['p99_ms']} | {r['mean_ms']} | {r['buffer_hit_ratio_pct']}% |\n")
        
        f.write("\n## 2. Targeted Index Optimization Impact\n\n")
        f.write("| Query | Target Index Structure | With Index (ms) | Without Index / SeqScan (ms) | Speedup Factor |\n")
        f.write("| :--- | :--- | :---: | :---: | :---: |\n")
        for idx in index_impact_results:
            f.write(f"| `{idx['query']}` | {idx['index_target']} | **{idx['with_index_ms']} ms** | {idx['without_index_ms']} ms | **{idx['speedup_factor']}x** |\n")

    print(f"[+] Saved formatted Markdown benchmark report to {md_path}")
    print("\n================================================================")
    print(" Benchmark Execution Completed Successfully!")
    print("================================================================")

if __name__ == "__main__":
    run_benchmarks()
