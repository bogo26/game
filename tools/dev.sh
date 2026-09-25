#!/usr/bin/env bash
# Developer helper.
#   ./tools/dev.sh import            re-import assets / rebuild class cache
#   ./tools/dev.sh test [--filter=x] run the headless test suite
#   ./tools/dev.sh run [scene] [...] run the game (or a specific scene)
#   ./tools/dev.sh editor            open the Godot editor
#   ./tools/dev.sh stress [...]      run the horde stress test
#   ./tools/dev.sh export [mac|win]  export release builds into build/ (needs export templates)
# Set GODOT=/path/to/Godot to override binary discovery.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

find_godot() {
  if [[ -n "${GODOT:-}" ]]; then echo "$GODOT"; return; fi
  local candidates=(
    "/Applications/Godot.app/Contents/MacOS/Godot"
    "$HOME/Applications/Godot.app/Contents/MacOS/Godot"
    "$HOME/Downloads/Godot.app/Contents/MacOS/Godot"
  )
  for c in "${candidates[@]}"; do
    if [[ -x "$c" ]]; then echo "$c"; return; fi
  done
  for c in godot godot4; do
    if command -v "$c" >/dev/null 2>&1; then command -v "$c"; return; fi
  done
  echo "Godot not found. Set GODOT=/path/to/Godot" >&2
  exit 1
}

GODOT_BIN="$(find_godot)"
cmd="${1:-run}"
shift || true

case "$cmd" in
  import)
    "$GODOT_BIN" --headless --path "$ROOT" --import
    ;;
  test)
    "$GODOT_BIN" --headless --path "$ROOT" --import >/dev/null 2>&1 || true
    "$GODOT_BIN" --headless --path "$ROOT" -s res://tests/run_tests.gd -- "$@"
    ;;
  run)
    "$GODOT_BIN" --path "$ROOT" "$@"
    ;;
  editor)
    "$GODOT_BIN" --path "$ROOT" --editor "$@"
    ;;
  stress)
    "$GODOT_BIN" --path "$ROOT" res://tools/stress_test.tscn -- "$@"
    ;;
  export)
    target="${1:-all}"
    "$GODOT_BIN" --headless --path "$ROOT" --import >/dev/null 2>&1 || true
    status=0
    if [[ "$target" == "all" || "$target" == "mac" ]]; then
      mkdir -p "$ROOT/build/macos"
      "$GODOT_BIN" --headless --path "$ROOT" --export-release "macOS" "$ROOT/build/macos/HordeCrawler.zip" || status=1
    fi
    if [[ "$target" == "all" || "$target" == "win" ]]; then
      mkdir -p "$ROOT/build/windows"
      "$GODOT_BIN" --headless --path "$ROOT" --export-release "Windows Desktop" "$ROOT/build/windows/HordeCrawler.exe" || status=1
    fi
    ls -la "$ROOT/build"/*/ 2>/dev/null || true
    exit $status
    ;;
  *)
    sed -n '2,9p' "$0"
    exit 1
    ;;
esac
