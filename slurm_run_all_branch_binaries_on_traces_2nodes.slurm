#!/bin/bash
#
# Run all generated TAGE-SC and jimenez_mpp binaries across all traces
# using TWO nodes and many single-core parallel runs.
#
# Submit with:
#   sbatch slurm_run_all_branch_binaries_on_traces_2nodes.slurm
#
# Optional overrides at submit time:
#   sbatch --export=ALL,WARMUP=200000000,SIM=500000000,MAX_PARALLEL=96,TRACE_ROOT=/path/to/traces slurm_run_all_branch_binaries_on_traces_2nodes.slurm

#SBATCH --job-name=champsim-all-traces-2n
#SBATCH --time=7-00:00:00
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=48
#SBATCH --cpus-per-task=1
#SBATCH --mem=32G
#SBATCH --output=slurm_champsim_runs_2nodes_%j.out
#SBATCH --mail-type=ALL
#SBATCH --mail-user=shantanu_w@tamu.edu

set -euo pipefail

# Optional: uncomment and set your project allocation if required.
##SBATCH --account=YOUR_ALLOCATION

# Optional: pick a partition explicitly.
##SBATCH --partition=long

PROJECT_DIR="${SLURM_SUBMIT_DIR:-$PWD}"
cd "$PROJECT_DIR"

TRACE_ROOT="${TRACE_ROOT:-$PROJECT_DIR/traces}"
WARMUP="${WARMUP:-200000000}"
SIM="${SIM:-500000000}"
MAX_PARALLEL="${MAX_PARALLEL:-${SLURM_NTASKS:-96}}"

if [[ ! -d "$TRACE_ROOT" ]]; then
  echo "ERROR: TRACE_ROOT directory not found: $TRACE_ROOT" >&2
  exit 1
fi

VCPKG_HEADER="$PROJECT_DIR/vcpkg_installed/x64-linux/include/fmt/core.h"
if [[ ! -f "$VCPKG_HEADER" ]]; then
  echo "vcpkg dependencies missing; preparing toolchain..."
  LOCKFILE="$PROJECT_DIR/.vcpkg-install.lock"
  exec 9>"$LOCKFILE"
  flock 9
  if [[ ! -f "$VCPKG_HEADER" ]]; then
    if [[ ! -x "$PROJECT_DIR/vcpkg/vcpkg" ]]; then
      "$PROJECT_DIR/vcpkg/bootstrap-vcpkg.sh"
    fi
    "$PROJECT_DIR/vcpkg/vcpkg" install --x-install-root="$PROJECT_DIR/vcpkg_installed"
  fi
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
  find "$TRACE_ROOT" -type f \( -name "*.gz" -o -name "*.xz" \) \
    ! -name "*.sha256sum.txt" | sort
)

if [[ ${#TRACES[@]} -eq 0 ]]; then
  echo "ERROR: No traces found under $TRACE_ROOT" >&2
  exit 1
fi

RESULT_ROOT="$PROJECT_DIR/results/champsim_runs_2nodes_${SLURM_JOB_ID}"
mkdir -p "$RESULT_ROOT"

echo "============================================================"
echo "Job ID         : $SLURM_JOB_ID"
echo "Project dir    : $PROJECT_DIR"
echo "Nodes          : ${SLURM_NNODES:-2}"
echo "Allocated tasks: ${SLURM_NTASKS:-unknown}"
echo "Trace root     : $TRACE_ROOT"
echo "Binaries       : ${#BINARIES[@]}"
echo "Traces         : ${#TRACES[@]}"
echo "Total runs     : $((${#BINARIES[@]} * ${#TRACES[@]}))"
echo "Warmup instr   : $WARMUP"
echo "Sim instr      : $SIM"
echo "Parallel runs  : $MAX_PARALLEL"
echo "Result root    : $RESULT_ROOT"
echo "============================================================"

running=0
total=0

for bin in "${BINARIES[@]}"; do
  bin_name="$(basename "$bin")"
  mkdir -p "$RESULT_ROOT/$bin_name"

  for trace in "${TRACES[@]}"; do
    rel_trace="${trace#"$TRACE_ROOT"/}"
    safe_trace="${rel_trace//\//__}"
    safe_trace="${safe_trace// /_}"
    out_file="$RESULT_ROOT/$bin_name/${safe_trace}.out"

    while (( running >= MAX_PARALLEL )); do
      wait -n
      ((running--))
    done

    srun --exclusive -N1 -n1 -c1 --cpu-bind=cores \
      "$bin" \
      --warmup-instructions "$WARMUP" \
      --simulation-instructions "$SIM" \
      "$trace" \
      >"$out_file" 2>&1 &

    ((running++))
    ((total++))
    if (( total % 50 == 0 )); then
      echo "Launched $total runs so far..."
    fi
  done
done

wait

echo "All runs completed."
echo "Results available under: $RESULT_ROOT"
