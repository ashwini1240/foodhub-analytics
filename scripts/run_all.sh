#!/usr/bin/env bash
# ============================================================================
# FoodHub Analytics — one-shot pipeline runner (bash / Git Bash)
#
# Usage (from project root):
#   PGPASSWORD=yourpassword ./scripts/run_all.sh
#
# Creates the DB (if needed), builds schema, loads+cleans data, adds indexes,
# creates Power BI views, and prints key findings.
# ============================================================================
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CSVDIR="$ROOT/data/csv"
U=postgres; H=localhost

echo "==> Creating database 'foodhub' (ignored if it exists)"
createdb -U "$U" -h "$H" foodhub 2>/dev/null || echo "   (foodhub already exists — continuing)"

echo "==> 01 schema";       psql -U "$U" -h "$H" -d foodhub -v ON_ERROR_STOP=1 -f "$ROOT/sql/01_schema.sql"
echo "==> 02 load + clean"; psql -U "$U" -h "$H" -d foodhub -v ON_ERROR_STOP=1 -v "csvdir=$CSVDIR" -f "$ROOT/sql/02_load_data.sql"
echo "==> 03 indexes";      psql -U "$U" -h "$H" -d foodhub -v ON_ERROR_STOP=1 -f "$ROOT/sql/03_indexes.sql"
echo "==> 04 views";        psql -U "$U" -h "$H" -d foodhub -v ON_ERROR_STOP=1 -f "$ROOT/sql/04_powerbi_views.sql"
echo "==> 05 key findings"; psql -U "$U" -h "$H" -d foodhub -f "$ROOT/sql/05_key_findings.sql"

echo ""
echo "DONE. Database 'foodhub' is loaded and ready for Power BI."
