#!/usr/bin/env bash
# =============================================================================
# Talentra backup, restore and recovery-time check (docket B80; NFR-010, NFR-011)
#
#   1. pg_dump the source database (custom format)
#   2. pg_restore it into a fresh database, stopping at the first error
#   3. compare the EXACT row count of every base table, and the number of functions, triggers,
#      row-level-security policies and indexes, between source and restored copy
#   4. report the restore time against the recovery time objective
#
# Recovery time = time to restore. The dump is taken before the incident, so its duration is not part
# of recovery and is reported separately.
#
# Usage:
#   scripts/backup_restore.sh                 uses local pg_dump/pg_restore/psql and PGHOST, PGPORT, PGUSER, PGPASSWORD
#   scripts/backup_restore.sh --docker [NAME] runs the tools inside container NAME (default talentra-postgres)
#   Environment: SOURCE_DB (default talentra), MAX_RTO_SECONDS (default 900), LOG_FILE (optional)
# =============================================================================
set -euo pipefail

SOURCE_DB="${SOURCE_DB:-talentra}"
RECOVERY_DB="${SOURCE_DB}_recovery_$$"
MAX_RTO_SECONDS="${MAX_RTO_SECONDS:-900}"
DB_USER="${PGUSER:-talentra_admin}"
DOCKER=""
if [ "${1:-}" = "--docker" ]; then DOCKER="${2:-talentra-postgres}"; fi

run() { if [ -n "$DOCKER" ]; then docker exec -i "$DOCKER" "$@"; else "$@"; fi; }
sql() { run psql -U "$DB_USER" -X -q -t -A "$@"; }
BACKUP_FILE="${TMPDIR:-/tmp}/talentra_backup_$$.dump"
[ -n "$DOCKER" ] && BACKUP_FILE="/tmp/talentra_backup_$$.dump"

cleanup() {
  sql -d postgres -c "DROP DATABASE IF EXISTS \"$RECOVERY_DB\";" >/dev/null 2>&1 || true
  if [ -n "$DOCKER" ]; then docker exec "$DOCKER" rm -f "$BACKUP_FILE" >/dev/null 2>&1 || true; else rm -f "$BACKUP_FILE"; fi
}
trap cleanup EXIT

say() { echo "$@" | { if [ -n "${LOG_FILE:-}" ]; then tee -a "$LOG_FILE"; else cat; fi; }; }

say "== Talentra backup / restore check: $(date -u +%FT%TZ) =="
say "source=$SOURCE_DB  engine=$(sql -d "$SOURCE_DB" -c 'SHOW server_version;')  rto_target=${MAX_RTO_SECONDS}s"

t0=$(date +%s)
run pg_dump -U "$DB_USER" -Fc -d "$SOURCE_DB" -f "$BACKUP_FILE"
backup_s=$(( $(date +%s) - t0 ))
say "[1/4] backup: ${backup_s}s (informational: not part of recovery time)"

sql -d postgres -c "CREATE DATABASE \"$RECOVERY_DB\" OWNER \"$DB_USER\";" >/dev/null
t1=$(date +%s)
run pg_restore -U "$DB_USER" -d "$RECOVERY_DB" --no-owner --exit-on-error "$BACKUP_FILE"
restore_s=$(( $(date +%s) - t1 ))
say "[2/4] restore: ${restore_s}s"

# row counts of every base table, from the data itself (pg_class.reltuples is an estimate, not a count)
tables=$(sql -d "$SOURCE_DB" -c "SELECT quote_ident(table_schema)||'.'||quote_ident(table_name) FROM information_schema.tables WHERE table_type='BASE TABLE' AND table_schema NOT IN ('pg_catalog','information_schema','public') ORDER BY 1;")
mismatch=0; checked=0
for t in $tables; do
  a=$(sql -d "$SOURCE_DB" -c "SELECT count(*) FROM $t;"); b=$(sql -d "$RECOVERY_DB" -c "SELECT count(*) FROM $t;")
  checked=$((checked + 1))
  if [ "$a" != "$b" ]; then say "  [MISMATCH] $t source=$a restored=$b"; mismatch=$((mismatch + 1)); fi
done
say "[3/4] row counts: $checked tables compared, $mismatch mismatches"

objects="SELECT (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname NOT IN ('pg_catalog','information_schema','public'))
 ||','|| (SELECT count(*) FROM pg_trigger WHERE NOT tgisinternal)
 ||','|| (SELECT count(*) FROM pg_policy)
 ||','|| (SELECT count(*) FROM pg_indexes WHERE schemaname NOT IN ('pg_catalog','information_schema'))
 ||','|| (SELECT count(*) FROM pg_constraint c JOIN pg_namespace n ON n.oid=c.connamespace WHERE n.nspname NOT IN ('pg_catalog','information_schema','public'));"
so=$(sql -d "$SOURCE_DB" -c "$objects"); ro=$(sql -d "$RECOVERY_DB" -c "$objects")
if [ "$so" = "$ro" ]; then say "[4/4] schema objects (functions,triggers,policies,indexes,constraints) match: $so"; else say "[4/4] SCHEMA OBJECTS DIFFER source=$so restored=$ro"; mismatch=$((mismatch + 1)); fi

if [ "$mismatch" -ne 0 ]; then say "RESULT: FAIL (restored copy differs from the source)"; exit 2; fi
if [ "$restore_s" -gt "$MAX_RTO_SECONDS" ]; then say "RESULT: FAIL (restore ${restore_s}s exceeds RTO ${MAX_RTO_SECONDS}s)"; exit 1; fi
say "RESULT: PASS  restore=${restore_s}s (RTO ${MAX_RTO_SECONDS}s)  backup=${backup_s}s"

# record the verified backup, so audit.ops_job_freshness can show how long ago the last one was proved restorable (NFR-011, NFR-026)
sql -d "$SOURCE_DB" -c "INSERT INTO audit.maintenance_run (job_name, run_status, started_at, rows_affected, detail_json) VALUES ('backup_restore_check', 'succeeded', now() - make_interval(secs => $((backup_s + restore_s))), $checked, jsonb_build_object('backup_seconds', $backup_s, 'restore_seconds', $restore_s, 'rto_seconds', $MAX_RTO_SECONDS));" >/dev/null 2>&1 \
  || say "(could not record the run in audit.maintenance_run: is migration 031 applied?)"
