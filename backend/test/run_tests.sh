#!/usr/bin/env bash
# ============================================================================
# Atendify backend regression suite.
#
# Spins up a scratch Postgres database, loads the test stub (a minimal
# stand-in for the pieces of Supabase's auth/storage schemas the app's own
# schema touches), applies supabase_schema.sql, then runs every numbered
# test file in this directory in order. Each test file asserts real
# behavior — an RLS policy allowing or rejecting a specific caller, a
# trigger assigning the right role, a function returning the right answer —
# using test_assert()/test_assert_raises() (defined in pg_stub.sql), which
# raise a real Postgres error on failure. With `ON_ERROR_STOP=1`, that
# makes psql exit non-zero, which is what turns a failed assertion into a
# failed CI run.
#
# Finally, re-applies phase1b_migration.sql on top of the fresh install
# (twice) as an idempotency check — it should be a safe no-op re-affirming
# a schema that already has every fix, exactly as it would be if someone
# re-ran it against an already-migrated live database.
#
# Usage:
#   ./run_tests.sh                 # local dev, via `sudo -u postgres psql`
#   PGHOST=localhost PGUSER=postgres PGPASSWORD=postgres ./run_tests.sh
#                                   # CI, connecting directly (see the
#                                   # GitHub Actions workflow in this repo)
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$(dirname "$SCRIPT_DIR")"
DB_NAME="${ATD_TEST_DB:-atendify_test}"

if [ -n "${PGHOST:-}" ]; then
  PSQL=(psql -v ON_ERROR_STOP=1 -q)
else
  PSQL=(sudo -u postgres psql -v ON_ERROR_STOP=1 -q)
fi

pass_count=0
fail_count=0

run_step() {
  local label="$1"; shift
  echo "==> ${label}"
  if "${PSQL[@]}" "$@"; then
    pass_count=$((pass_count + 1))
  else
    echo "    ✗ FAILED: ${label}"
    fail_count=$((fail_count + 1))
  fi
}

echo "==> Resetting test database: ${DB_NAME}"
"${PSQL[@]}" -c "drop database if exists ${DB_NAME};"
"${PSQL[@]}" -c "create database ${DB_NAME};"

run_step "Loading test fixture (pg_stub.sql)" -d "${DB_NAME}" -f "${SCRIPT_DIR}/pg_stub.sql"
run_step "Loading supabase_schema.sql (fresh install)" -d "${DB_NAME}" -f "${BACKEND_DIR}/supabase_schema.sql"

for test_file in "${SCRIPT_DIR}"/[0-9][0-9][0-9]_*.sql; do
  run_step "$(basename "${test_file}")" -d "${DB_NAME}" -f "${test_file}"
done

# ---- Migration idempotency check ------------------------------------------
# phase1b_migration.sql is meant to be safe to re-run against a database
# that already has every fix (a fresh install already does, and so does a
# live database someone already migrated once). Applying it twice here
# checks exactly that, against the current schema, every time this suite
# runs — not just once, by hand, at the moment each fix shipped.
run_step "Applying phase1b_migration.sql (1st pass, idempotency check)" -d "${DB_NAME}" -f "${BACKEND_DIR}/phase1b_migration.sql"
run_step "Applying phase1b_migration.sql (2nd pass, idempotency check)" -d "${DB_NAME}" -f "${BACKEND_DIR}/phase1b_migration.sql"

echo "==> Cleaning up (${DB_NAME})"
"${PSQL[@]}" -c "drop database if exists ${DB_NAME};" >/dev/null

echo ""
echo "============================================================"
echo " ${pass_count} step(s) passed, ${fail_count} step(s) failed"
echo "============================================================"

if [ "${fail_count}" -ne 0 ]; then
  exit 1
fi
