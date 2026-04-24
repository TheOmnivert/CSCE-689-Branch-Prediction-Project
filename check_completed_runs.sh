#!/bin/bash
#
# check_completed_runs.sh
#
# Scans .out files in the results directory to determine which
# (binary, trace) combinations completed successfully. A run is
# considered successful when its .out file contains the string
# "Channel 0 REFRESHES ISSUED:" (written only at the very end of
# a ChampSim simulation).
#
# Usage:
#   ./check_completed_runs.sh [options]
#
# Options (all override environment variables of the same name):
#   --manifest   PATH   Combinations file (default: ./combinations.txt)
#   --result-root PATH  Results root dir  (default: newest results/champsim_per_node_* dir)
#   --trace-root  PATH  Trace root used when building .out names
#                       (default: auto-detected from manifest)
#   --success    PATH   Output file for successful combos (default: ./successful_combinations.txt)
#   --fail       PATH   Output file for failed combos     (default: ./unsuccessful_combinations.txt)
#
# The two output files share the same tab-separated format as
# combinations.txt (BIN<TAB>TRACE), so unsuccessful_combinations.txt
# can be passed directly as MANIFEST= when re-submitting jobs.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Defaults ──────────────────────────────────────────────────────────────────
MANIFEST="${MANIFEST:-$PROJECT_DIR/combinations.txt}"
SUCCESS_OUT="${SUCCESS_OUT:-$PROJECT_DIR/successful_combinations.txt}"
FAIL_OUT="${FAIL_OUT:-$PROJECT_DIR/unsuccessful_combinations.txt}"
RESULT_ROOT="${RESULT_ROOT:-}"   # auto-detect below if empty
TRACE_ROOT="${TRACE_ROOT:-}"     # auto-detect below if empty

# ── Argument parsing ───────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest)   MANIFEST="$2";    shift 2 ;;
    --result-root) RESULT_ROOT="$2"; shift 2 ;;
    --trace-root)  TRACE_ROOT="$2";  shift 2 ;;
    --success)    SUCCESS_OUT="$2"; shift 2 ;;
    --fail)       FAIL_OUT="$2";    shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# ── Validate manifest ──────────────────────────────────────────────────────────
if [[ ! -f "$MANIFEST" ]]; then
  echo "ERROR: Manifest not found: $MANIFEST" >&2
  exit 1
fi

# ── Auto-detect RESULT_ROOT ───────────────────────────────────────────────────
if [[ -z "$RESULT_ROOT" ]]; then
  # Pick the most-recently modified champsim_per_node_* directory.
  RESULT_ROOT="$(ls -1dt "$PROJECT_DIR"/results/champsim_per_node_* 2>/dev/null | head -1 || true)"
  if [[ -z "$RESULT_ROOT" ]]; then
    echo "ERROR: No results/champsim_per_node_* directory found. Pass --result-root." >&2
    exit 1
  fi
  echo "Auto-detected RESULT_ROOT: $RESULT_ROOT"
fi

if [[ ! -d "$RESULT_ROOT" ]]; then
  echo "ERROR: Result root not found: $RESULT_ROOT" >&2
  exit 1
fi

# ── Auto-detect TRACE_ROOT ────────────────────────────────────────────────────
if [[ -z "$TRACE_ROOT" ]]; then
  # Read the first trace path from the manifest and strip everything after
  # the top-level "traces" directory component.
  first_trace="$(awk -F'\t' 'NR==1{print $2}' "$MANIFEST")"
  # Match up to and including ".../traces" in the path.
  TRACE_ROOT="$(echo "$first_trace" | grep -oP '^.+?/traces')"
  if [[ -z "$TRACE_ROOT" ]]; then
    echo "ERROR: Cannot auto-detect TRACE_ROOT from manifest. Pass --trace-root." >&2
    exit 1
  fi
  echo "Auto-detected TRACE_ROOT: $TRACE_ROOT"
fi

echo "Manifest    : $MANIFEST"
echo "Result root : $RESULT_ROOT"
echo "Trace root  : $TRACE_ROOT"
echo "Success out : $SUCCESS_OUT"
echo "Fail out    : $FAIL_OUT"
echo ""

# ── Main loop ─────────────────────────────────────────────────────────────────
COMPLETE_STRING="Channel 0 REFRESHES ISSUED:"

total=0
success=0
fail=0
missing=0

: > "$SUCCESS_OUT"
: > "$FAIL_OUT"

while IFS=$'\t' read -r BIN TRACE; do
  [[ -z "$BIN" || -z "$TRACE" ]] && continue
  total=$(( total + 1 ))

  BIN_NAME="$(basename "$BIN")"
  REL_TRACE="${TRACE#"$TRACE_ROOT"/}"
  SAFE_TRACE="${REL_TRACE//\//__}"
  SAFE_TRACE="${SAFE_TRACE// /_}"
  OUT_FILE="$RESULT_ROOT/$BIN_NAME/${SAFE_TRACE}.out"

  if [[ ! -f "$OUT_FILE" ]]; then
    # .out file doesn't exist at all — definitely failed / never ran
    missing=$(( missing + 1 ))
    fail=$(( fail + 1 ))
    printf '%s\t%s\n' "$BIN" "$TRACE" >> "$FAIL_OUT"
    continue
  fi

  if grep -qF "$COMPLETE_STRING" "$OUT_FILE"; then
    success=$(( success + 1 ))
    printf '%s\t%s\n' "$BIN" "$TRACE" >> "$SUCCESS_OUT"
  else
    fail=$(( fail + 1 ))
    printf '%s\t%s\n' "$BIN" "$TRACE" >> "$FAIL_OUT"
  fi
done < "$MANIFEST"

echo "============================================================"
echo "Total combinations  : $total"
echo "Successful (complete): $success"
echo "Failed / incomplete : $fail  (of which $missing had no .out file)"
echo "============================================================"
echo ""
echo "Successful combos -> $SUCCESS_OUT"
echo "Failed combos     -> $FAIL_OUT"
echo ""
echo "To re-run only the failed combinations:"
echo "  MANIFEST=\"$FAIL_OUT\" ./submit_per_node_jobs.sh"
