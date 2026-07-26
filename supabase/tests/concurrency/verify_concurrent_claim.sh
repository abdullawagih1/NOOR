#!/usr/bin/env bash
# ============================================================================
# Genuine dual-process concurrent-claim proof for
# claim_next_document_processing_job() (migration 0007).
#
# A single psql session (as used by 006_processing_orchestration.sql) can
# only prove sequential exclusivity — it cannot demonstrate that two
# *simultaneous* callers never claim the same row. This script launches two
# real, independent OS processes (each its own `docker exec ... psql`
# connection, i.e. its own Postgres backend/transaction) that race to drain
# a shared pool of queued jobs, then verifies:
#   1. every job was claimed by exactly one worker (no duplicate ids across
#      the two workers' claim logs, no job claimed twice by the same worker)
#   2. the two workers' claimed-id sets are disjoint
#   3. total claims across both workers == total jobs seeded
#
# Usage: bash verify_concurrent_claim.sh [container] [db] [job_count]
# Requires: the given container already has all migrations + seed applied
# (run the standard local-verification sequence first).
# ============================================================================
set -euo pipefail

CONTAINER="${1:-noor_test_pg}"
DB="${2:-noor_test}"
JOBS="${3:-100}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "=== Seeding $JOBS queued jobs for the concurrency race ==="
docker exec -i "$CONTAINER" psql -U postgres -d "$DB" -v ON_ERROR_STOP=1 -v jobs="$JOBS" \
  < "$SCRIPT_DIR/setup_concurrent_claim_fixture.sql"

# The database may carry other already-queued document_parsing jobs left
# behind by unrelated test suites run earlier in the same session (this
# harness does not require or assume a pristine database) — so the
# pass/fail check below is against the actual claimable total measured
# right now, not blindly against $JOBS.
EXPECTED=$(docker exec "$CONTAINER" psql -U postgres -d "$DB" -tAc \
  "select count(*) from document_processing_jobs where job_type = 'document_parsing' and (status = 'queued' or (status = 'retry_scheduled' and next_attempt_at <= now()));")
EXPECTED=$(echo "$EXPECTED" | tr -d '[:space:]')
echo "actual claimable jobs at race start: $EXPECTED (seeded $JOBS; the rest, if any, are pre-existing)"

claim_loop() {
  local worker_name="$1"
  local out_file="$2"
  : > "$out_file"
  while true; do
    job_id=$(docker exec "$CONTAINER" psql -U postgres -d "$DB" -tAc \
      "select out_job_id from claim_next_document_processing_job('$worker_name', array['document_parsing'], 90, gen_random_uuid());")
    job_id=$(echo "$job_id" | tr -d '[:space:]')
    if [ -z "$job_id" ]; then
      break
    fi
    echo "$job_id" >> "$out_file"
  done
}

echo "=== Racing two independent worker processes against the shared queue ==="
claim_loop "concur-worker-X" "$WORKDIR/claims_x.txt" &
PID_X=$!
claim_loop "concur-worker-Y" "$WORKDIR/claims_y.txt" &
PID_Y=$!

wait "$PID_X"
wait "$PID_Y"

COUNT_X=$(wc -l < "$WORKDIR/claims_x.txt" | tr -d '[:space:]')
COUNT_Y=$(wc -l < "$WORKDIR/claims_y.txt" | tr -d '[:space:]')
TOTAL=$((COUNT_X + COUNT_Y))
UNIQUE_TOTAL=$(cat "$WORKDIR/claims_x.txt" "$WORKDIR/claims_y.txt" | sort -u | wc -l | tr -d '[:space:]')
OVERLAP=$(comm -12 <(sort "$WORKDIR/claims_x.txt") <(sort "$WORKDIR/claims_y.txt") | wc -l | tr -d '[:space:]')

echo "worker X claimed: $COUNT_X"
echo "worker Y claimed: $COUNT_Y"
echo "total claimed:    $TOTAL (expected $EXPECTED)"
echo "unique job ids:   $UNIQUE_TOTAL (expected $EXPECTED)"
echo "overlap between workers: $OVERLAP (expected 0)"

FAIL=0
if [ "$TOTAL" -ne "$EXPECTED" ]; then
  echo "FAIL: total claims ($TOTAL) != actual claimable total ($EXPECTED) — a job was lost"
  FAIL=1
fi
if [ "$UNIQUE_TOTAL" -ne "$EXPECTED" ]; then
  echo "FAIL: duplicate job ids were claimed (unique=$UNIQUE_TOTAL, expected=$EXPECTED)"
  FAIL=1
fi
if [ "$OVERLAP" -ne 0 ]; then
  echo "FAIL: $OVERLAP job id(s) were claimed by both workers"
  FAIL=1
fi

if [ "$FAIL" -ne 0 ]; then
  echo "CONCURRENCY PROOF FAILED"
  exit 1
fi

echo "CONCURRENCY PROOF PASSED: $EXPECTED claimable jobs, two real concurrent worker processes, zero double-claims, zero lost jobs"
