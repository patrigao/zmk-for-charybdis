#!/usr/bin/env bash
# Keymap simulator tests. Each tests/<name>/native_posix_64.keymap runs on ZMK's
# mock board (native_posix_64) in the same container image as build.sh.
# A line `#include "real/<label>.dtsi"` pulls that node verbatim from
# config/charybdis.keymap, so the tests exercise the real behaviors and combos.
# The output is filtered by events.patterns and diffed against
# keycode_events.snapshot.
#
#   ./test.sh               run every test
#   ./test.sh <name>        run one test
#   ACCEPT=1 ./test.sh      overwrite the snapshots with the current output
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
ROOT=$PWD
IMAGE=${ZMK_IMAGE:-zmkfirmware/zmk-build-arm:stable}

# Print the node with this label (`label: name {` or `&label {`) from the keymap.
node() {
  awk -v l="$1" '!p && ($1 == l":" || ($1 == l && $2 == "{")) {p = 1}
    p {print; d += gsub(/[{]/, "&") - gsub(/[}]/, "&"); if (d == 0) exit}' config/charybdis.keymap
}

names=("$@")
[ ${#names[@]} -gt 0 ] || mapfile -t names < <(ls tests)
fail=0
for t in "${names[@]}"; do
  src=tests/$t out=build/tests/$t
  rm -rf "$out/case" && mkdir -p "$out/case/real"
  cp "$src/native_posix_64.keymap" "$out/case/"
  for l in $(sed -n 's/^[[:space:]]*#include "real\/\(.*\)\.dtsi".*/\1/p' "$src/native_posix_64.keymap"); do
    node "$l" > "$out/case/real/$l.dtsi"
    [ -s "$out/case/real/$l.dtsi" ] || { echo "$t: no node '$l' in config/charybdis.keymap" >&2; exit 2; }
  done

  if ! docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$ROOT:$ROOT" -w "$ROOT" "$IMAGE" \
    bash -euc "west build -p -s zmk/app -d $out/zephyr -b native_posix_64 -- -DCONFIG_ASSERT=y \
      -DZMK_CONFIG=$ROOT/$out/case -DZephyr_DIR=$ROOT/zephyr/share/zephyr-package/cmake \
      > $out/build.log 2>&1 && $out/zephyr/zephyr/zmk.exe > $out/full.log 2>&1"; then
    echo "FAILED: $t did not build or run (see $out/build.log)"; fail=1; continue
  fi

  sed -e 's/.*> //' "$out/full.log" | sed -n -f "$src/events.patterns" > "$out/events.log"
  if [ "${ACCEPT:-0}" = 1 ]; then
    cp "$out/events.log" "$src/keycode_events.snapshot"; echo "ACCEPTED: $t"
  elif diff -u "$src/keycode_events.snapshot" "$out/events.log"; then
    echo "PASS: $t"
  else
    echo "FAILED: $t"; fail=1
  fi
done
exit $fail
