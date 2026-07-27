#!/usr/bin/env bash
# ============================================================================
# Genuine dual-process concurrent extraction-identity proof (mission §35).
#
# Two independent OS processes (separate `docker exec ... psql`
# connections — genuinely separate Postgres backends) each hold their own
# real claimed-and-started processing job, pointing at two DIFFERENT
# source documents that happen to share identical byte content (same
# sha256/size — a real, plausible scenario). Both race to
# create/extract/finalize an extraction run at the exact SAME
# deterministic identity (same source_sha256 + pipeline/config/extractor
# versions) concurrently.
#
# Proves: only one extraction run ever reaches `succeeded` at that
# identity (the database's own partial unique index is the ultimate
# guarantee — supabase/migrations/0008_deterministic_pdf_extraction.sql),
# and the "loser" is handled gracefully (invalidated + the winner's result
# returned) rather than surfacing a raw constraint-violation error to the
# Worker — see finalize_document_extraction_run's unique_violation handler.
#
# Usage: bash verify_concurrent_extraction_identity.sh [container] [db]
# Requires: the given container already has all migrations + seed applied.
# ============================================================================
set -euo pipefail

CONTAINER="${1:-noor_test_pg}"
DB="${2:-noor_test}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# A fresh, run-specific configuration_version guarantees this run's
# extraction identity has never been seen before in this database — this
# harness does not require or assume a pristine database (the same
# tolerance every other test file in this repo has for cumulative shared
# state), and it means a re-run after a prior failed/partial run can never
# collide with leftover data from that earlier attempt.
RUN_SUFFIX="concur-$(date +%s)-$$"
CONFIGURATION_VERSION="1-${RUN_SUFFIX}"

echo "=== Seeding two jobs sharing one extraction identity ==="
docker exec -i "$CONTAINER" psql -U postgres -d "$DB" -v ON_ERROR_STOP=1 < "$SCRIPT_DIR/setup_concurrent_extraction_fixture.sql" > "$WORKDIR/setup.log" 2>&1 || {
  echo "SETUP FAILED"; cat "$WORKDIR/setup.log"; exit 1;
}
cat "$WORKDIR/setup.log"

JOB1=$(grep -oP '(?<=job1=)[a-f0-9-]+' "$WORKDIR/setup.log")
JOB2=$(grep -oP '(?<=job2=)[a-f0-9-]+' "$WORKDIR/setup.log")
SHA256=$(grep -oP '(?<=shared_sha256=)[a-f0-9]+' "$WORKDIR/setup.log")
TOKEN1=$(grep -oP '(?<=token1=)[a-f0-9]+' "$WORKDIR/setup.log")
TOKEN2=$(grep -oP '(?<=token2=)[a-f0-9]+' "$WORKDIR/setup.log")

echo "job1=$JOB1 job2=$JOB2 sha256=$SHA256"

race_worker() {
  local job_id="$1"
  local worker_name="$2"
  local token="$3"
  local out_file="$4"

  # Deliberately NOT ON_ERROR_STOP: a fourth, equally legitimate race
  # outcome exists beyond the three already documented below — this
  # worker's own run gets superseded by the other job's attempt (a
  # different attempt at the same identity) *after* this worker already
  # committed its claim/create call but *before* it reaches finalize (the
  # claim -> create -> insert-pages -> finalize sequence is several
  # separate auto-committed statements, not one spanning transaction).
  # finalize_document_extraction_run() then correctly raises a retryable
  # error ("was superseded... before this attempt could finalize") when
  # no winner exists yet to adopt — exactly what a real Worker would
  # receive as an OrchestrationError and classify as a retryable job
  # failure. ON_ERROR_STOP would turn this expected, correct outcome into
  # a hard script abort; the result is instead inspected below.
  docker exec -i "$CONTAINER" psql -U postgres -d "$DB" \
    -v job_id="$job_id" -v worker_name="$worker_name" -v lease_token="$token" -v sha256="$SHA256" -v config_version="$CONFIGURATION_VERSION" <<'SQL' > "$out_file" 2>&1
select out_extraction_run_id, out_status, out_reused
  from create_document_extraction_run(:'job_id', :'worker_name', :'lease_token', :'sha256', 1000, 'pdf-text-v1', :'config_version', 'pypdf', '6.14.2');
\gset run_
-- A genuinely concurrent race can legitimately resolve BEFORE this
-- worker even reaches this point (the other worker's entire
-- create->insert->finalize sequence already committed) — in that case
-- out_reused is true and this worker must not attempt to insert a
-- duplicate page or finalize an already-succeeded run at all; it simply
-- adopts the winning run's result, exactly like the real Python
-- processor does (app/pdf_extraction/processor.py).
\if :run_out_reused
\echo REUSED existing succeeded run — skipping page insert and finalize
\else
insert into document_extraction_pages (
  organization_id, extraction_run_id, source_document_id, page_number,
  width_points, height_points, rotation_degrees, raw_text, normalized_text,
  character_count, word_count, is_blank, suspected_scanned, extraction_status, page_checksum
)
select organization_id, :'run_out_extraction_run_id'::uuid, source_document_id, 1, 595.0, 842.0, 0, 'race text', 'race text', 9, 2, false, false, 'text_extracted', encode(digest(:'worker_name', 'sha256'), 'hex')
from document_processing_jobs where id = :'job_id';
select out_extraction_run_id, out_status, out_completed_at
  from finalize_document_extraction_run(:'run_out_extraction_run_id'::uuid, :'job_id', :'worker_name', :'lease_token', 1, 'guideline-processed', 'concur-extract/race.json', encode(digest(:'worker_name' || '-artifact', 'sha256'), 'hex'), 100, 'application/json');
\endif
SQL
}

echo "=== Racing two independent worker processes at the same extraction identity ==="
race_worker "$JOB1" "concur-worker-1" "$TOKEN1" "$WORKDIR/worker1.log" &
PID1=$!
race_worker "$JOB2" "concur-worker-2" "$TOKEN2" "$WORKDIR/worker2.log" &
PID2=$!

wait "$PID1"
wait "$PID2"

echo "--- worker1 output ---"
cat "$WORKDIR/worker1.log"
echo "--- worker2 output ---"
cat "$WORKDIR/worker2.log"

echo "=== Verifying exactly one succeeded run at the shared identity ==="
SUCCEEDED_COUNT=$(docker exec "$CONTAINER" psql -U postgres -d "$DB" -tAc \
  "select count(*) from document_extraction_runs where source_sha256 = '$SHA256' and pipeline_version = 'pdf-text-v1' and configuration_version = '$CONFIGURATION_VERSION' and extractor_name = 'pypdf' and extractor_version = '6.14.2' and status = 'succeeded';")
TOTAL_RUNS=$(docker exec "$CONTAINER" psql -U postgres -d "$DB" -tAc \
  "select count(*) from document_extraction_runs where source_sha256 = '$SHA256' and pipeline_version = 'pdf-text-v1' and configuration_version = '$CONFIGURATION_VERSION' and extractor_name = 'pypdf' and extractor_version = '6.14.2';")
INVALIDATED_COUNT=$(docker exec "$CONTAINER" psql -U postgres -d "$DB" -tAc \
  "select count(*) from document_extraction_runs where source_sha256 = '$SHA256' and pipeline_version = 'pdf-text-v1' and configuration_version = '$CONFIGURATION_VERSION' and extractor_name = 'pypdf' and extractor_version = '6.14.2' and status = 'invalidated';")

echo "succeeded runs at this identity: $SUCCEEDED_COUNT (expected exactly 1)"
echo "total runs at this identity:     $TOTAL_RUNS (1 or 2 are both valid outcomes — see below)"
echo "invalidated runs:                $INVALIDATED_COUNT"
echo
echo "Four race outcomes are all correct, depending on timing (this is not"
echo "asserted to be a specific one — only that exactly one run ever"
echo "succeeds, and every error either worker sees is one of the two named,"
echo "classifiable, expected messages below — never a raw/unclassified one):"
echo "  1. TOTAL_RUNS=1: one worker's create call already found the"
echo "     other's fully-succeeded run and cleanly reused it."
echo "  2. TOTAL_RUNS=2, one invalidated: a genuinely simultaneous insert"
echo "     race, resolved by finalize's unique_violation handler."
echo "  3. TOTAL_RUNS=2, one failed (superseded_by_retry, then reused a"
echo "     winner at finalize time): one worker's create call found the"
echo "     other's still-running (different-attempt) row and superseded it,"
echo "     but the superseding attempt had already succeeded by the time"
echo "     the superseded worker reached finalize."
echo "  4. TOTAL_RUNS=2, one failed (superseded_by_retry, and the"
echo "     superseded worker's OWN finalize call raises a retryable"
echo "     'superseded... before this attempt could finalize' error,"
echo "     because no winner exists yet) — exactly what a real Worker"
echo "     receives as an OrchestrationError and reports as a retryable"
echo "     job failure; a later retry cleanly reuses whichever attempt"
echo "     eventually succeeds."

# Only these two exact, named, classifiable messages are acceptable
# outcomes in a worker's log — anything else is a genuine, unexpected
# failure.
ACCEPTABLE_ERROR_PATTERN='already succeeded with a different artifact checksum|was superseded by a later attempt at the same identity'

FAIL=0
for log in "$WORKDIR/worker1.log" "$WORKDIR/worker2.log"; do
  if grep -qi "ERROR" "$log"; then
    if grep -qiE "$ACCEPTABLE_ERROR_PATTERN" "$log"; then
      echo "INFO: $(basename "$log") hit an expected, classifiable race-loss error (not a failure)"
    else
      echo "FAIL: $(basename "$log") hit an unexpected/unclassified error:"
      grep -i "ERROR" "$log"
      FAIL=1
    fi
  fi
done
if [ "$SUCCEEDED_COUNT" -ne 1 ]; then
  echo "FAIL: expected exactly 1 succeeded run regardless of race timing"
  FAIL=1
fi

if [ "$FAIL" -ne 0 ]; then
  echo "CONCURRENT EXTRACTION IDENTITY PROOF FAILED"
  exit 1
fi

echo "CONCURRENT EXTRACTION IDENTITY PROOF PASSED: two real concurrent worker processes raced the same extraction identity — exactly one succeeded; any error the other saw was one of the two named, classifiable, expected race-loss messages, never a raw/unclassified error"
