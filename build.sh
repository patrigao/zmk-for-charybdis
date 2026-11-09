#!/usr/bin/env bash
# Local firmware build. Mirrors .github/workflows/build.yml (ZMK v0.3 reusable
# workflow) by running west in the same container image CI uses.
#
#   ./build.sh                 build left, right and reset
#   ./build.sh right           build one target
#   UPDATE=1 ./build.sh        re-run `west update` first (after editing config/west.yml)
#
# UF2 files land in ./firmware/. The west workspace (.west, zmk, zephyr, modules,
# zmk-pmw3610-driver) and ./build live in the repo root, as in CI.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
ROOT=$PWD
IMAGE=${ZMK_IMAGE:-zmkfirmware/zmk-build-arm:stable}

run() {
  docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
    -v "$ROOT:$ROOT" -w "$ROOT" "$IMAGE" bash -euc "$1"
}

# ponytail: targets copied from build.yaml by hand; keep the two in sync.
declare -A WEST_ARGS=(
  [left]="-b nice_nano_v2 -- -DSHIELD=charybdis_left"
  [right]="-b nice_nano_v2 -S studio-rpc-usb-uart -- -DSHIELD=charybdis_right -DCONFIG_ZMK_STUDIO=y"
  [reset]="-b nice_nano_v2 -- -DSHIELD=settings_reset"
)
declare -A UF2_NAME=(
  [left]=charybdis_left-nice_nano_v2-zmk
  [right]=charybdis_right-nice_nano_v2-zmk
  [reset]=settings_reset-nice_nano_v2-zmk
)

targets=("$@")
[ ${#targets[@]} -gt 0 ] || targets=(left right reset)
for t in "${targets[@]}"; do
  [ -n "${WEST_ARGS[$t]:-}" ] || { echo "unknown target: $t (use left, right or reset)" >&2; exit 2; }
done

[ -d .west ] || run "west init -l config"
if [ ! -d zmk ] || [ "${UPDATE:-0}" = 1 ]; then
  run "west update --fetch-opt=--filter=tree:0"
fi

mkdir -p firmware
for t in "${targets[@]}"; do
  echo "=== building $t"
  # Zephyr_DIR replaces CI's `west zephyr-export`, whose registry would vanish with the container.
  run "west build -p auto -s zmk/app -d build/$t ${WEST_ARGS[$t]} -DZMK_CONFIG=$ROOT/config \
    -DZephyr_DIR=$ROOT/zephyr/share/zephyr-package/cmake"
  cp "build/$t/zephyr/zmk.uf2" "firmware/${UF2_NAME[$t]}.uf2"
done
ls -l firmware
