# Windows entry point for the backup / restore / recovery-time check.
#
# The logic lives in scripts/backup_restore.sh so there is one implementation to keep correct. An earlier
# PowerShell copy had drifted from it (it hid restore errors and counted only a few tables). This wrapper
# runs the shell script through Git Bash or WSL.
#
# Usage:  .\scripts\backup_restore.ps1                      uses psql / pg_dump / pg_restore on PATH and PG* variables
#         .\scripts\backup_restore.ps1 --docker             runs the tools inside the talentra-postgres container
param([Parameter(ValueFromRemainingArguments = $true)] [string[]] $Rest)

$script = Join-Path $PSScriptRoot "backup_restore.sh"
$bash = (Get-Command bash -ErrorAction SilentlyContinue)
if (-not $bash) {
    Write-Error "bash was not found. Install Git for Windows (Git Bash) or WSL, then run this again."
    exit 3
}
& bash $script @Rest
exit $LASTEXITCODE
