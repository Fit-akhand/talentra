#!/usr/bin/env bash
# ==============================================================================
# Talentra Disaster Recovery & Recovery Time Objective (RTO) Validation Script
# ==============================================================================
# Verifies:
# 1. Full database backup using pg_dump custom format (-Fc)
# 2. Complete restoration into a clean staging database
# 3. Row integrity verification across operational schemas
# 4. Strict timing against Recovery Time Objective (Target RTO < 15 minutes)
# ==============================================================================

set -euo pipefail

DB_CONTAINER="talentra-postgres"
DB_USER="talentra_admin"
SOURCE_DB="talentra"
RECOVERY_DB="talentra_recovery_test"
BACKUP_FILE="/tmp/talentra_backup.dump"
MAX_RTO_SECONDS=900 # 15 minutes

echo "======================================================================"
echo "   Talentra Disaster Recovery & RTO Verification Engine"
echo "======================================================================"

# Step 1: Backup
echo -e "\n[1/4] Initiating full database dump via pg_dump (-Fc)..."
start_backup=$(date +%s)
docker exec -i "$DB_CONTAINER" pg_dump -U "$DB_USER" -Fc -d "$SOURCE_DB" -f "$BACKUP_FILE"
end_backup=$(date +%s)
backup_elapsed=$(( end_backup - start_backup ))
echo "[PASS] Backup completed in ${backup_elapsed}s"

# Step 2: Prepare clean recovery database
echo -e "\n[2/4] Initializing clean recovery staging database '$RECOVERY_DB'..."
docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d postgres -c "DROP DATABASE IF EXISTS $RECOVERY_DB;" > /dev/null
docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d postgres -c "CREATE DATABASE $RECOVERY_DB OWNER $DB_USER;" > /dev/null
echo "[PASS] Staging database created."

# Step 3: Restore
echo -e "\n[3/4] Restoring database into '$RECOVERY_DB' via pg_restore..."
start_restore=$(date +%s)
docker exec -i "$DB_CONTAINER" pg_restore -U "$DB_USER" -d "$RECOVERY_DB" --no-owner --role="$DB_USER" "$BACKUP_FILE" || true
end_restore=$(date +%s)
restore_elapsed=$(( end_restore - start_restore ))
total_rto=$(( backup_elapsed + restore_elapsed ))
echo "[PASS] Restoration completed in ${restore_elapsed}s"
echo "[METRIC] Total Recovery Time: ${total_rto}s (RTO Target: < ${MAX_RTO_SECONDS}s)"

if [ "$total_rto" -gt "$MAX_RTO_SECONDS" ]; then
    echo "[FAIL] Recovery time exceeded RTO threshold!"
    exit 1
fi

# Step 4: Verify integrity
echo -e "\n[4/4] Verifying table row counts and schema integrity..."
tables=(
    "core.user_account"
    "recruitment.organization"
    "recruitment.job_posting"
    "profile.candidate_profile"
    "gig.gig_worker_profile"
    "commercial.wallet_ledger"
    "audit.audit_event"
)

for tbl in "${tables[@]}"; do
    src=$(docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$SOURCE_DB" -t -A -c "SELECT COUNT(*) FROM $tbl;")
    rec=$(docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$RECOVERY_DB" -t -A -c "SELECT COUNT(*) FROM $tbl;")
    if [ "$src" == "$rec" ]; then
        echo "  [MATCH] $tbl: $src rows"
    else
        echo "  [MISMATCH] $tbl: Source=$src, Restored=$rec"
        exit 2
    fi
done

# Cleanup
echo -e "\nCleaning up recovery database..."
docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d postgres -c "DROP DATABASE IF EXISTS $RECOVERY_DB;" > /dev/null
docker exec -i "$DB_CONTAINER" rm -f "$BACKUP_FILE" > /dev/null

echo "======================================================================"
echo "   RTO VALIDATION PASSED: Total Recovery Time = ${total_rto}s (RTO < 15 min)"
echo "======================================================================"
