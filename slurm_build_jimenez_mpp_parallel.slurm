#!/bin/bash
#
# Submit with:
#   sbatch slurm_build_jimenez_mpp_parallel.slurm
#
# This uses a SLURM job array so each jimenez_mpp size variant builds in parallel.

#SBATCH --job-name=champsim-jimenez-mpp-build
#SBATCH --time=02:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --array=0-6%7
#SBATCH --output=slurm_champsim_jimenez_mpp_build_%A_%a.out
#SBATCH --mail-type=ALL
#SBATCH --mail-user=shantanu_w@tamu.edu

set -euo pipefail

# Optional: uncomment and set your project allocation if required.
##SBATCH --account=YOUR_ALLOCATION

# Optional: set a specific partition if your lab requires one.
##SBATCH --partition=short

PROJECT_DIR="${SLURM_SUBMIT_DIR:-$PWD}"
cd "$PROJECT_DIR"

# One-time serialized setup for all array tasks:
# - ensure vcpkg deps exist
# - regenerate absolute.options (shared response file) to avoid stale/corrupt includes
VCPKG_HEADER="$PROJECT_DIR/vcpkg_installed/x64-linux/include/fmt/core.h"
LOCKFILE="$PROJECT_DIR/.vcpkg-install.lock"
exec 9>"$LOCKFILE"
flock 9

if [[ ! -x "$PROJECT_DIR/vcpkg/vcpkg" ]]; then
  "$PROJECT_DIR/vcpkg/bootstrap-vcpkg.sh"
fi

if [[ ! -f "$VCPKG_HEADER" ]]; then
  echo "vcpkg dependencies missing; installing x64-linux triplet..."
  export VCPKG_MAX_CONCURRENCY="${VCPKG_MAX_CONCURRENCY:-8}"
  "$PROJECT_DIR/vcpkg/vcpkg" install --triplet x64-linux --x-install-root="$PROJECT_DIR/vcpkg_installed" || {
    echo "vcpkg install failed. Check detailed logs under:" >&2
    echo "  $PROJECT_DIR/vcpkg/buildtrees/*/" >&2
    exit 1
  }
fi

rm -f "$PROJECT_DIR/absolute.options"
make -C "$PROJECT_DIR" absolute.options

if [[ ! -f "$VCPKG_HEADER" ]]; then
  echo "ERROR: Missing dependency header after setup: $VCPKG_HEADER" >&2
  exit 1
fi

VARIANTS=(24kb 48kb 96kb 192kb 384kb 768kb 1536kb)
VARIANT="${VARIANTS[$SLURM_ARRAY_TASK_ID]}"

echo "Job ID           : ${SLURM_JOB_ID}"
echo "Array Job/Task   : ${SLURM_ARRAY_JOB_ID}_${SLURM_ARRAY_TASK_ID}"
echo "Variant          : ${VARIANT}"
echo "Submit directory : ${PROJECT_DIR}"
echo "CPUs per task    : ${SLURM_CPUS_PER_TASK:-4}"

TMP_BASE="${TMPDIR:-/tmp}/champsim_jimenez_mpp_build_${SLURM_JOB_ID}_${SLURM_ARRAY_TASK_ID}"
mkdir -p "$TMP_BASE"

FINAL_BIN_DIR="${PROJECT_DIR}/bin"
mkdir -p "$FINAL_BIN_DIR"

./build_all_jimenez_mpp.sh \
  -v "$VARIANT" \
  -j "${SLURM_CPUS_PER_TASK:-4}" \
  -p "$TMP_BASE" \
  -o "$FINAL_BIN_DIR"

echo "Done building ${VARIANT}. Output binary:"
ls -lh "${FINAL_BIN_DIR}/champsim_jimenez_mpp_${VARIANT}"
