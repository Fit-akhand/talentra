#!/usr/bin/env bash
# Regenerate every generated lifecycle document.
# Needs a migrated (and ideally seeded) database: set PGHOST, PGPORT, PGUSER, PGDATABASE, PGPASSWORD.
set -euo pipefail
cd "$(dirname "$0")/../.."
python3 scripts/lifecycle/gen_model_catalogues.py   # steps 06, 07, 08
python3 scripts/lifecycle/gen_volume_sheet.py      # step 13
python3 scripts/lifecycle/gen_integration_doc.py   # step 22
python3 scripts/lifecycle/gen_quality_scorecard.py # step 26
python3 scripts/lifecycle/gen_audit_matrix.py     # step 05
python3 scripts/lifecycle/gen_workflow_coverage.py  # step 16
python3 scripts/lifecycle/gen_rules_catalogue.py    # step 18
python3 scripts/lifecycle/gen_kpi_catalogue.py      # step 29
python3 scripts/lifecycle/tag_tests.py --check       # every test names what it covers
python3 scripts/lifecycle/gen_traceability.py       # step 34 (no database needed)
python3 scripts/lifecycle/gen_lifecycle_report.py   # step map (no database needed; fails on a broken reference)
