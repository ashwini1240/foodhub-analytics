# ============================================================================
# FoodHub Analytics — one-shot pipeline runner (PowerShell)
#
# Usage (from project root), providing your postgres password once:
#   $env:PGPASSWORD = 'yourpassword'; .\scripts\run_all.ps1
#
# Or run it via Claude Code's session with the ! prefix so output is captured:
#   ! $env:PGPASSWORD='yourpassword'; powershell -File scripts\run_all.ps1
#
# Creates the DB (if needed), builds schema, loads+cleans data, adds indexes,
# creates Power BI views, and prints key findings.
# ============================================================================
$ErrorActionPreference = 'Stop'
$root   = Split-Path -Parent $PSScriptRoot
$csvdir = (Join-Path $root 'data\csv') -replace '\\','/'
$U = 'postgres'; $H = 'localhost'

Write-Host "==> Creating database 'foodhub' (ignored if it exists)"
& createdb -U $U -h $H foodhub 2>$null
if ($LASTEXITCODE -ne 0) { Write-Host "   (foodhub already exists — continuing)" }

Write-Host "==> 01 schema";       & psql -U $U -h $H -d foodhub -v ON_ERROR_STOP=1 -f "$root\sql\01_schema.sql"
Write-Host "==> 02 load + clean"; & psql -U $U -h $H -d foodhub -v ON_ERROR_STOP=1 -v "csvdir=$csvdir" -f "$root\sql\02_load_data.sql"
Write-Host "==> 03 indexes";      & psql -U $U -h $H -d foodhub -v ON_ERROR_STOP=1 -f "$root\sql\03_indexes.sql"
Write-Host "==> 04 views";        & psql -U $U -h $H -d foodhub -v ON_ERROR_STOP=1 -f "$root\sql\04_powerbi_views.sql"
Write-Host "==> 05 key findings"; & psql -U $U -h $H -d foodhub -f "$root\sql\05_key_findings.sql"

Write-Host "`nDONE. Database 'foodhub' is loaded and ready for Power BI."
