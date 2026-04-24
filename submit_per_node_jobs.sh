#!/bin/bash
#
# Discover all (binary, trace) combinations, write a manifest, and submit
# a Slurm job array where each array task takes one exclusive Grace node
# (48 CPUs) and runs TASKS_PER_NODE (default 48) combinations in parallel,
# one combination per CPU. Each array task is its own job with its own
# 2-hour wall clock, per-CPU memory budget, and mail-ALL events to
# shantanu_w@tamu.edu (set in slurm_per_node_job.slurm).
#
# Usage:
#   ./submit_per_node_jobs.sh
#
# To re-run only failed/incomplete combinations (produced by check_completed_runs.sh):
#   MANIFEST=./unsuccessful_combinations.txt SKIP_MANIFEST_GEN=1 ./submit_per_node_jobs.sh
#
# Optional overrides via environment:
#   TRACE_ROOT         Path to traces root (default: ../traces relative to project)
#   MANIFEST           Path to write the manifest (default: ./combinations.txt)
#   SKIP_MANIFEST_GEN  Set to 1 to skip regenerating the manifest and use the
#                      existing file at MANIFEST as-is (e.g. for re-runs with
#                      unsuccessful_combinations.txt from check_completed_runs.sh)
#   TASKS_PER_NODE     Combos run in parallel per node-job (default: 48)
#   MEM_PER_CPU        Memory budget per CPU/task (default: 512M).
#                      ChampSim typically uses ~300 MB per task, so 512M leaves
#                      ~70% headroom. Bump this (e.g. 1G) if you see OOMs.
#   MAX_ARRAY_SIZE     Max array tasks per sbatch submission (default: 1000).
#                      Used to chunk if the scheduler caps array size.
#   THROTTLE           Max concurrent array tasks per chunk via --array=A-B%T.
#   WARMUP, SIM        ChampSim warmup / simulation instruction counts,
#                      forwarded to the per-task script.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

TRACE_ROOT="${TRACE_ROOT:-$(dirname "$PROJECT_DIR")/traces}"
MANIFEST="${MANIFEST:-$PROJECT_DIR/combinations.txt}"
SKIP_MANIFEST_GEN="${SKIP_MANIFEST_GEN:-0}"
SLURM_SCRIPT="${SLURM_SCRIPT:-$PROJECT_DIR/slurm_per_node_job.slurm}"
TASKS_PER_NODE="${TASKS_PER_NODE:-48}"
MEM_PER_CPU="${MEM_PER_CPU:-512M}"
MAX_ARRAY_SIZE="${MAX_ARRAY_SIZE:-1000}"
THROTTLE="${THROTTLE:-}"
WARMUP="${WARMUP:-200000000}"
SIM="${SIM:-500000000}"

if [[ "$SKIP_MANIFEST_GEN" != "1" ]] && [[ ! -d "$TRACE_ROOT" ]]; then
  echo "ERROR: Trace root directory not found: $TRACE_ROOT" >&2
  exit 1
fi
if [[ ! -f "$SLURM_SCRIPT" ]]; then
  echo "ERROR: Slurm script not found: $SLURM_SCRIPT" >&2
  exit 1
fi
if ! (( TASKS_PER_NODE >= 1 )); then
  echo "ERROR: TASKS_PER_NODE must be >= 1 (got $TASKS_PER_NODE)" >&2
  exit 1
fi
if ! (( MAX_ARRAY_SIZE >= 1 )); then
  echo "ERROR: MAX_ARRAY_SIZE must be >= 1 (got $MAX_ARRAY_SIZE)" >&2
  exit 1
fi

mkdir -p "$PROJECT_DIR/logs"

if [[ "$SKIP_MANIFEST_GEN" == "1" ]]; then
  # Use the existing manifest as-is (e.g. unsuccessful_combinations.txt from
  # check_completed_runs.sh).  Skip binary/trace discovery entirely.
  if [[ ! -f "$MANIFEST" ]]; then
    echo "ERROR: SKIP_MANIFEST_GEN=1 but MANIFEST not found: $MANIFEST" >&2
    exit 1
  fi
  echo "SKIP_MANIFEST_GEN=1 — using existing manifest: $MANIFEST"
else
  readarray -t BINARIES < <(
    for b in "$PROJECT_DIR"/bin/champsim_seznec_tagesc_* "$PROJECT_DIR"/bin/champsim_jimenez_mpp_*; do
      [[ -x "$b" ]] && printf '%s\n' "$b"
    done | sort
  )

  if [[ ${#BINARIES[@]} -eq 0 ]]; then
    echo "ERROR: No executable binaries matching champsim_seznec_tagesc_* or champsim_jimenez_mpp_* in $PROJECT_DIR/bin" >&2
    exit 1
  fi

  readarray -t TRACES < <(
    find "$TRACE_ROOT" -type f \( -name "*.gz" -o -name "*.xz" \) \
      ! -name "*.sha256sum.txt" | sort
  )

  if [[ ${#TRACES[@]} -eq 0 ]]; then
    echo "ERROR: No trace files (*.gz / *.xz) found under $TRACE_ROOT" >&2
    exit 1
  fi

  : > "$MANIFEST"
  for bin in "${BINARIES[@]}"; do
    for trace in "${TRACES[@]}"; do
      printf '%s\t%s\n' "$bin" "$trace" >> "$MANIFEST"
    done
  done
fi

N=$(wc -l < "$MANIFEST")
NUM_ARRAY_TASKS=$(( (N + TASKS_PER_NODE - 1) / TASKS_PER_NODE ))

echo "============================================================"
echo "Project dir       : $PROJECT_DIR"
if [[ "$SKIP_MANIFEST_GEN" != "1" ]]; then
  echo "Trace root        : $TRACE_ROOT"
  echo "Binaries          : ${#BINARIES[@]}"
  echo "Traces            : ${#TRACES[@]}"
fi
echo "Combinations      : $N"
echo "Tasks per node    : $TASKS_PER_NODE"
echo "Node-jobs needed  : $NUM_ARRAY_TASKS"
echo "Manifest          : $MANIFEST"
echo "Slurm script      : $SLURM_SCRIPT"
echo "Per-job cap       : 1 node, ${TASKS_PER_NODE} CPU, 2h, --mem-per-cpu=${MEM_PER_CPU}, mail ALL -> shantanu_w@tamu.edu"
echo "Max array/chunk   : $MAX_ARRAY_SIZE ${THROTTLE:+(throttle=%$THROTTLE)}"
echo "Warmup / Sim      : $WARMUP / $SIM"
echo "============================================================"

chunk=0
task_offset=0
while (( task_offset < NUM_ARRAY_TASKS )); do
  remaining=$(( NUM_ARRAY_TASKS - task_offset ))
  this_size=$(( remaining < MAX_ARRAY_SIZE ? remaining : MAX_ARRAY_SIZE ))
  array_spec="0-$(( this_size - 1 ))"
  [[ -n "$THROTTLE" ]] && array_spec="${array_spec}%${THROTTLE}"

  manifest_offset=$(( task_offset * TASKS_PER_NODE ))

  chunk=$(( chunk + 1 ))
  echo "[chunk $chunk] array_tasks=$this_size --array=$array_spec OFFSET=$manifest_offset"

  sbatch \
    --export=ALL,MANIFEST="$MANIFEST",TRACE_ROOT="$TRACE_ROOT",OFFSET="$manifest_offset",TASKS_PER_NODE="$TASKS_PER_NODE",WARMUP="$WARMUP",SIM="$SIM" \
    --array="$array_spec" \
    --mem-per-cpu="$MEM_PER_CPU" \
    "$SLURM_SCRIPT"

  task_offset=$(( task_offset + this_size ))
done

echo "Submitted $chunk chunk(s) totaling $NUM_ARRAY_TASKS node-jobs covering $N combinations."
