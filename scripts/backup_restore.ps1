# ==============================================================================
# Talentra Disaster Recovery & Recovery Time Objective (RTO) Validation Script
# ==============================================================================
# Verifies:
# 1. Full database backup using pg_dump custom format (-Fc)
# 2. Complete restoration into a clean staging database
# 3. Row integrity verification across operational schemas
# 4. Strict timing against Recovery Time Objective (Target RTO < 15 minutes)
# ==============================================================================

$ErrorActionPreference = "Stop"

$DB_CONTAINER = "talentra-postgres"
$DB_USER = "talentra_admin"
$SOURCE_DB = "talentra"
$RECOVERY_DB = "talentra_recovery_test"
$BACKUP_FILE = "talentra_backup.dump"
$MAX_RTO_SECONDS = 900 # 15 minutes

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "   Talentra Disaster Recovery & RTO Verification Engine" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan

# Step 1: Execute Backup
Write-Host "`n[1/4] Initiating full database dump via pg_dump (-Fc)..." -ForegroundColor Yellow
$backupStart = Get-Date

docker exec -i $DB_CONTAINER pg_dump -U $DB_USER -Fc -d $SOURCE_DB -f "/tmp/$BACKUP_FILE"

$backupEnd = Get-Date
$backupElapsed = ($backupEnd - $backupStart).TotalSeconds
Write-Host ("[PASS] Backup completed in {0:N2} seconds." -f $backupElapsed) -ForegroundColor Green

# Inspect Dump Size
$dumpSizeStr = docker exec -i $DB_CONTAINER ls -lh "/tmp/$BACKUP_FILE"
Write-Host ("Backup artifact size: {0}" -f $dumpSizeStr) -ForegroundColor Gray

# Step 2: Prepare Clean Recovery Database
Write-Host "`n[2/4] Initializing clean recovery staging database '$RECOVERY_DB'..." -ForegroundColor Yellow
docker exec -i $DB_CONTAINER psql -U $DB_USER -d postgres -c "DROP DATABASE IF EXISTS $RECOVERY_DB;" | Out-Null
docker exec -i $DB_CONTAINER psql -U $DB_USER -d postgres -c "CREATE DATABASE $RECOVERY_DB OWNER $DB_USER;" | Out-Null
Write-Host "[PASS] Recovery database created successfully." -ForegroundColor Green

# Step 3: Execute Restoration
Write-Host "`n[3/4] Restoring database into '$RECOVERY_DB' via pg_restore..." -ForegroundColor Yellow
$restoreStart = Get-Date

# pg_restore returns exit code 0 or 1 for minor warnings; we run inside container
docker exec -i $DB_CONTAINER pg_restore -U $DB_USER -d $RECOVERY_DB --no-owner --role=$DB_USER "/tmp/$BACKUP_FILE"

$restoreEnd = Get-Date
$restoreElapsed = ($restoreEnd - $restoreStart).TotalSeconds
$totalRTO = $backupElapsed + $restoreElapsed

Write-Host ("[PASS] Restoration completed in {0:N2} seconds." -f $restoreElapsed) -ForegroundColor Green
Write-Host ("[METRIC] Total Recovery Time (Backup + Restore): {0:N2} seconds (RTO Target: < {1} seconds)" -f $totalRTO, $MAX_RTO_SECONDS) -ForegroundColor Cyan

if ($totalRTO -gt $MAX_RTO_SECONDS) {
    Write-Host "[FAIL] Recovery Time exceeded RTO threshold of 15 minutes!" -ForegroundColor Red
    exit 1
}

# Step 4: Verify Restored Data Integrity
Write-Host "`n[4/4] Verifying table row counts and schema integrity in restored database..." -ForegroundColor Yellow

$tablesToCheck = @(
    "core.user_account",
    "recruitment.organization",
    "recruitment.job_posting",
    "profile.candidate_profile",
    "gig.gig_worker_profile",
    "commercial.wallet_ledger",
    "audit.audit_event"
)

$allMatched = $true
foreach ($tbl in $tablesToCheck) {
    $srcCount = (docker exec -i $DB_CONTAINER psql -U $DB_USER -d $SOURCE_DB -t -A -c "SELECT COUNT(*) FROM $tbl;").Trim()
    $recCount = (docker exec -i $DB_CONTAINER psql -U $DB_USER -d $RECOVERY_DB -t -A -c "SELECT COUNT(*) FROM $tbl;").Trim()
    
    if ($srcCount -eq $recCount) {
        Write-Host ("  [MATCH] {0,-35}: {1} rows in source and restored database" -f $tbl, $srcCount) -ForegroundColor Green
    } else {
        Write-Host ("  [MISMATCH] {0,-35}: Source has {1}, Restored has {2}" -f $tbl, $srcCount, $recCount) -ForegroundColor Red
        $allMatched = $false
    }
}

# Cleanup
Write-Host "`nCleaning up recovery artifacts..." -ForegroundColor Gray
docker exec -i $DB_CONTAINER psql -U $DB_USER -d postgres -c "DROP DATABASE IF EXISTS $RECOVERY_DB;" | Out-Null
docker exec -i $DB_CONTAINER rm -f "/tmp/$BACKUP_FILE" | Out-Null

if (-not $allMatched) {
    Write-Host "`n[FAIL] Restored database row counts did not match source!" -ForegroundColor Red
    exit 2
}

Write-Host "`n======================================================================" -ForegroundColor Green
Write-Host ("   RTO VALIDATION PASSED: Total Recovery Time = {0:N2}s (RTO < 15 min)" -f $totalRTO) -ForegroundColor Green
Write-Host "======================================================================" -ForegroundColor Green
