# Mixed-workload load test

PostgreSQL 17.11 (Debian 17.11-1.pgdg13+2), max_connections 100, 10 CPUs, 2026-10-27T21:46:11Z. `scripts/run_load_test.py`. medium seed (10,000 candidates, 1,000 jobs, 50,000 applications). Mix: search 25%, feed 25%, funnel 10%, apply 15%, wallet_debit 10%, login 15%.

Client: Python threads on the same machine as the server, default server configuration. Absolute numbers include client overhead.

| Clients | ops/s | errors | search p95 | feed p95 | funnel p95 | apply p95 | wallet_debit p95 | login p95 |
|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| 1 | 1805.5 | 0 | 0.79 ms | 0.77 ms | 0.38 ms | 0.43 ms | 0.47 ms | 0.48 ms |
| 8 | 8428.6 | 0 | 1.82 ms | 1.48 ms | 0.92 ms | 1.27 ms | 1.39 ms | 1.41 ms |
| 32 | 10770.6 | 0 | 5.88 ms | 5.32 ms | 4.0 ms | 6.16 ms | 6.88 ms | 6.97 ms |
| 64 | 10517.0 | 0 | 13.59 ms | 11.83 ms | 8.54 ms | 14.44 ms | 17.41 ms | 18.5 ms |

After the run: largest difference between a wallet balance and its ledger sum = **0.0**; 31683 sessions written; users over the device limit: **0**.
Latency (p95 more than 3x the single-client figure) first rises at **32** clients.
