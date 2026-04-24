#!/bin/bash
#
# Per-node ChampSim job (array task). Each array task is ONE Slurm job
# that claims 1 Grace node with 48 CPUs and runs up to TASKS_PER_NODE
# (bin, trace) combinations simultaneously, 1 CPU per combo. Memory is
# requested per CPU (--mem-per-cpu) rather than as a node-wide pool, so
# we only consume what ChampSim actually needs (~300 MB per task).
#
# Submitted via: ./submit_per_node_jobs.sh
# (that helper builds combinations.txt and sizes the array to cover all
#  14 bins x ~132 traces = ~1848 combinations)
#
# The helper passes two env vars per chunk:
#   MANIFEST = absolute path to the combinations manifest file
#   OFFSET   = absolute manifest-index offset for SLURM_ARRAY_TASK_ID=0
# Absolute combo window for this array task:
#   start = OFFSET + SLURM_ARRAY_TASK_ID * TASKS_PER_NODE
#   end   = min(start + TASKS_PER_NODE, N_total) - 1

##NECESSARY JOB SPECIFICATIONS
#SBATCH --job-name=champsim-node
#SBATCH --time=02:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=48
#SBATCH --ntasks-per-node=48
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=512M
#SBATCH --output=logs/node_%A_%a.out
#SBATCH --mail-type=ALL
#SBATCH --mail-user=shantanu_w@tamu.edu


set -euo pipefail

# Load the same GCC toolchain used at build time so that the newer
# libstdc++ (GLIBCXX_3.4.26+) is available at runtime on compute nodes.
module load GCCcore/13.3.0
module load binutils/2.42

PROJECT_DIR="${SLURM_SUBMIT_DIR:-$PWD}"
cd "$PROJECT_DIR"

MANIFEST="${MANIFEST:-$PROJECT_DIR/combinations.txt}"
OFFSET="${OFFSET:-0}"
TASKS_PER_NODE="${TASKS_PER_NODE:-48}"
WARMUP="${WARMUP:-200000000}"
SIM="${SIM:-500000000}"
TRACE_ROOT="${TRACE_ROOT:-$(dirname "$PROJECT_DIR")/traces}"

if [[ ! -f "$MANIFEST" ]]; then
  echo "ERROR: Manifest not found: $MANIFEST" >&2
  exit 1
fi
if [[ -z "${SLURM_ARRAY_TASK_ID:-}" ]]; then
  echo "ERROR: SLURM_ARRAY_TASK_ID not set. Submit via submit_per_node_jobs.sh." >&2
  exit 1
fi

N_TOTAL=$(wc -l < "$MANIFEST")
START=$(( OFFSET + SLURM_ARRAY_TASK_ID * TASKS_PER_NODE ))
END=$(( START + TASKS_PER_NODE - 1 ))
(( END >= N_TOTAL )) && END=$(( N_TOTAL - 1 ))

if (( START >= N_TOTAL )); then
  echo "ERROR: START=$START exceeds manifest length $N_TOTAL; nothing to run." >&2
  exit 1
fi

SLICE_SIZE=$(( END - START + 1 ))
RESULT_ROOT="${RESULT_ROOT:-$PROJECT_DIR/results/champsim_per_node_${SLURM_ARRAY_JOB_ID:-$SLURM_JOB_ID}}"
mkdir -p "$RESULT_ROOT"

echo "============================================================"
echo "Array job ID   : ${SLURM_ARRAY_JOB_ID:-n/a}"
echo "Array task ID  : ${SLURM_ARRAY_TASK_ID}"
echo "Task job ID    : ${SLURM_JOB_ID}"
echo "OFFSET         : ${OFFSET}"
echo "TASKS_PER_NODE : ${TASKS_PER_NODE}"
echo "Manifest lines : ${N_TOTAL}"
echo "Abs window     : [${START}, ${END}] (${SLICE_SIZE} combos)"
echo "Host           : $(hostname)"
echo "Nodelist       : ${SLURM_JOB_NODELIST:-n/a}"
echo "Result root    : $RESULT_ROOT"
echo "Warmup / Sim   : $WARMUP / $SIM"
echo "Start time     : $(date -Is)"
echo "============================================================"

# Extract this task's slice of the manifest (1-based: START+1..END+1).
mapfile -t SLICE < <(sed -n "$((START + 1)),$((END + 1))p" "$MANIFEST")

if (( ${#SLICE[@]} == 0 )); then
  echo "ERROR: Empty manifest slice for window [$START, $END]" >&2
  exit 1
fi

launched=0
for line in "${SLICE[@]}"; do
  BIN="${line%%$'\t'*}"
  TRACE="${line#*$'\t'}"

  if [[ ! -x "$BIN" ]]; then
    echo "SKIP: binary not executable: $BIN" >&2
    continue
  fi
  if [[ ! -f "$TRACE" ]]; then
    echo "SKIP: trace not found: $TRACE" >&2
    continue
  fi

  BIN_NAME="$(basename "$BIN")"
  REL_TRACE="${TRACE#"$TRACE_ROOT"/}"
  SAFE_TRACE="${REL_TRACE//\//__}"
  SAFE_TRACE="${SAFE_TRACE// /_}"

  OUT_DIR="$RESULT_ROOT/$BIN_NAME"
  mkdir -p "$OUT_DIR"
  OUT_FILE="$OUT_DIR/${SAFE_TRACE}.out"

  srun --exclusive -N1 -n1 -c1 --cpu-bind=cores \
    "$BIN" \
      --warmup-instructions "$WARMUP" \
      --simulation-instructions "$SIM" \
      "$TRACE" \
    > "$OUT_FILE" 2>&1 &

  launched=$(( launched + 1 ))
done

echo "Launched $launched parallel srun steps; waiting for completion..."
wait
echo "End time       : $(date -Is)"
echo "All $launched srun steps finished for window [$START, $END]."
