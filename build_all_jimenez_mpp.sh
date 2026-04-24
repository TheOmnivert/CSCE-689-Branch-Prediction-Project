#!/usr/bin/env bash
# Builds ChampSim binaries for jimenez_mpp size variants.
# Uses isolated build directories so multiple instances of this script can run in parallel.
#
# Usage:
#   ./build_all_jimenez_mpp.sh [-j jobs] [-v variant] [-o output_dir] [-p build_root]
# Examples:
#   ./build_all_jimenez_mpp.sh
#   ./build_all_jimenez_mpp.sh -v 192kb -j 8

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

JOBS=4
OUTPUT_DIR="bin"
BUILD_ROOT=".parallel_builds"
SINGLE_VARIANT=""
ALL_VARIANTS=(24kb 48kb 96kb 192kb 384kb 768kb 1536kb)

usage() {
  echo "Usage: $0 [-j jobs] [-v variant] [-o output_dir] [-p build_root]" >&2
  echo "  -j jobs       Number of make jobs per build (default: 4)" >&2
  echo "  -v variant    Build only one variant (e.g., 24kb)" >&2
  echo "  -o output_dir Output directory for final binaries (default: bin)" >&2
  echo "  -p build_root Root directory for per-variant build artifacts (default: .parallel_builds)" >&2
}

while getopts ":j:v:o:p:h" opt; do
  case "$opt" in
    j) JOBS="$OPTARG" ;;
    v) SINGLE_VARIANT="$OPTARG" ;;
    o) OUTPUT_DIR="$OPTARG" ;;
    p) BUILD_ROOT="$OPTARG" ;;
    h) usage; exit 0 ;;
    :) echo "ERROR: Option -$OPTARG requires an argument." >&2; usage; exit 1 ;;
    \?) echo "ERROR: Invalid option -$OPTARG" >&2; usage; exit 1 ;;
  esac
done

if [[ -n "$SINGLE_VARIANT" ]]; then
  VARIANTS=("$SINGLE_VARIANT")
else
  VARIANTS=("${ALL_VARIANTS[@]}")
fi

if [[ "$OUTPUT_DIR" = /* ]]; then
  ABS_OUTPUT_DIR="$OUTPUT_DIR"
else
  ABS_OUTPUT_DIR="$SCRIPT_DIR/$OUTPUT_DIR"
fi

if [[ "$BUILD_ROOT" = /* ]]; then
  ABS_BUILD_ROOT="$BUILD_ROOT"
else
  ABS_BUILD_ROOT="$SCRIPT_DIR/$BUILD_ROOT"
fi

mkdir -p "$ABS_OUTPUT_DIR" "$ABS_BUILD_ROOT"

for VARIANT in "${VARIANTS[@]}"; do
  CONFIG="champsim_config_jimenez_mpp_${VARIANT}.json"
  FINAL_BINARY="${ABS_OUTPUT_DIR}/champsim_jimenez_mpp_${VARIANT}"
  VARIANT_ROOT="${ABS_BUILD_ROOT}/jimenez_mpp_${VARIANT}"
  VARIANT_BINDIR="${VARIANT_ROOT}/bin"
  VARIANT_OBJDIR="${VARIANT_ROOT}/.csconfig"
  VARIANT_MAKEDIR="${VARIANT_ROOT}/mk"

  if [[ ! -f "$CONFIG" ]]; then
    echo "ERROR: Config file '$CONFIG' not found, skipping." >&2
    continue
  fi

  rm -rf "$VARIANT_ROOT"
  mkdir -p "$VARIANT_BINDIR" "$VARIANT_MAKEDIR"

  echo "============================================================"
  echo "  Building variant: jimenez_mpp_${VARIANT}"
  echo "  Config:     $CONFIG"
  echo "  Build root: $VARIANT_ROOT"
  echo "  Output:     $FINAL_BINARY"
  echo "============================================================"

  ./config.sh --no-compile-all-modules --prefix "$VARIANT_ROOT" --bindir "$VARIANT_BINDIR" --makedir "$VARIANT_MAKEDIR" "$CONFIG"
  make -j"$JOBS" NO_BASE_MODULES=1 CONFIG_MK="$VARIANT_MAKEDIR/_configuration.mk" OBJ_ROOT="$VARIANT_OBJDIR" DEP_ROOT="$VARIANT_OBJDIR" BIN_ROOT="$VARIANT_BINDIR"

  cp "${VARIANT_BINDIR}/champsim" "$FINAL_BINARY"
  echo "  -> Saved binary to $FINAL_BINARY"
  echo
done

echo "Build(s) complete. Binaries in $ABS_OUTPUT_DIR:"
ls -lh "${ABS_OUTPUT_DIR}"/champsim_jimenez_mpp_* 2>/dev/null || echo "  (none found)"
