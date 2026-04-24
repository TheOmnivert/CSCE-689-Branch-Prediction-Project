#!/bin/bash
#
# Run all generated TAGE-SC and jimenez_mpp binaries on mcf traces only
# using TWO nodes and many single-core parallel runs.
#
# Submit with:
#   sbatch slurm_run_mcf_all_branch_binaries_2nodes.slurm
#
# Optional overrides at submit time:
#   sbatch --export=ALL,WARMUP=200000000,SIM=500000000,MAX_PARALLEL=96,TRACE_ROOT=/path/to/traces,TRACE_GLOB=605.mcf_s-*.champsimtrace.xz slurm_run_mcf_all_branch_binaries_2nodes.slurm

#SBATCH --job-name=champsim-mcf-2n
#SBATCH --time=12:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=48
#SBATCH --ntasks-per-node=48
#SBATCH --cpus-per-task=1
#SBATCH --exclusive
#SBATCH --mem=32G
#SBATCH --output=slurm_champsim_mcf_runs_2nodes_%j.out
#SBATCH --mail-type=ALL
#SBATCH --mail-user=shantanu_w@tamu.edu

set -euo pipefail

# Optional: uncomment and set your project allocation if required.
##SBATCH --account=YOUR_ALLOCATION

# Optional: pick a partition explicitly.
##SBATCH --partition=long

PROJECT_DIR="${SLURM_SUBMIT_DIR:-$PWD}"
cd "$PROJECT_DIR"

TRACE_ROOT="${TRACE_ROOT:-$(dirname "$PROJECT_DIR")/traces}"
TRACE_GLOB="${TRACE_GLOB:-605.mcf_s-*.champsimtrace.xz}"
WARMUP="${WARMUP:-200000000}"
SIM="${SIM:-500000000}"
ALLOCATED_TASKS="${SLURM_NTASKS:-96}"
MAX_PARALLEL="${MAX_PARALLEL:-$ALLOCATED_TASKS}"

if (( MAX_PARALLEL < 1 )); then
  echo "ERROR: MAX_PARALLEL must be >= 1 (got $MAX_PARALLEL)" >&2
  exit 1
fi

if (( MAX_PARALLEL > ALLOCATED_TASKS )); then
  echo "WARNING: MAX_PARALLEL=$MAX_PARALLEL exceeds allocated tasks ($ALLOCATED_TASKS)." >&2
  echo "         Capping MAX_PARALLEL to $ALLOCATED_TASKS." >&2
  MAX_PARALLEL="$ALLOCATED_TASKS"
fi

if [[ ! -d "$TRACE_ROOT" ]]; then
  echo "ERROR: TRACE_ROOT directory not found: $TRACE_ROOT" >&2
  exit 1
fi

readarray -t BINARIES < <(
  for b in "$PROJECT_DIR"/bin/champsim_seznec_tagesc_* "$PROJECT_DIR"/bin/champsim_jimenez_mpp_*; do
    [[ -x "$b" ]] && printf '%s\n' "$b"
  done | sort
)

if [[ ${#BINARIES[@]} -eq 0 ]]; then
  echo "ERROR: No executable binaries found in $PROJECT_DIR/bin" >&2
  echo "Expected names like champsim_seznec_tagesc_* and champsim_jimenez_mpp_*" >&2
  exit 1
fi

readarray -t TRACES < <(
  find "$TRACE_ROOT" -type f -name "$TRACE_GLOB" | sort
)

if [[ ${#TRACES[@]} -eq 0 ]]; then
  echo "ERROR: No traces matched '$TRACE_GLOB' under $TRACE_ROOT" >&2
  exit 1
fi

RESULT_ROOT="$PROJECT_DIR/results/champsim_mcf_runs_2nodes_${SLURM_JOB_ID}"
mkdir -p "$RESULT_ROOT"

echo "============================================================"
echo "Job ID         : $SLURM_JOB_ID"
echo "Project dir    : $PROJECT_DIR"
echo "Nodes          : ${SLURM_NNODES:-2}"
echo "Allocated tasks: ${SLURM_NTASKS:-unknown}"
echo "Trace root     : $TRACE_ROOT"
echo "Trace glob     : $TRACE_GLOB"
echo "Binaries       : ${#BINARIES[@]}"
echo "Traces         : ${#TRACES[@]}"
echo "Total runs     : $((${#BINARIES[@]} * ${#TRACES[@]}))"
echo "Warmup instr   : $WARMUP"
echo "Sim instr      : $SIM"
echo "Parallel runs  : $MAX_PARALLEL (1 CPU per run)"
echo "Result root    : $RESULT_ROOT"
echo "============================================================"

total=0
in_flight=0

for bin in "${BINARIES[@]}"; do
  bin_name="$(basename "$bin")"
  mkdir -p "$RESULT_ROOT/$bin_name"

  for trace in "${TRACES[@]}"; do
    rel_trace="${trace#"$TRACE_ROOT"/}"
    safe_trace="${rel_trace//\//__}"
    safe_trace="${safe_trace// /_}"
    out_file="$RESULT_ROOT/$bin_name/${safe_trace}.out"

    srun --exclusive -N1 -n1 -c1 --cpu-bind=cores \
      "$bin" \
      --warmup-instructions "$WARMUP" \
      --simulation-instructions "$SIM" \
      "$trace" \
      >"$out_file" 2>&1 &

    total=$((total + 1))
    in_flight=$((in_flight + 1))

    if (( in_flight >= MAX_PARALLEL )); then
      wait -n
      in_flight=$((in_flight - 1))
    fi

    if (( total % 25 == 0 )); then
      echo "Launched $total runs so far..."
    fi
  done
done

while (( in_flight > 0 )); do
  wait -n
  in_flight=$((in_flight - 1))
done

echo "All mcf runs completed."
echo "Results available under: $RESULT_ROOT"
