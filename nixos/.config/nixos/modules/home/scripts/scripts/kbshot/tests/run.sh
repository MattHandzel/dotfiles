#!/usr/bin/env bash
# Every check kbshot has, in one command. Builds its own dependencies from the
# flake's pinned nixpkgs, so it needs nothing installed but nix.
#
#   run.sh            unit + contrast + image eval
#   run.sh --e2e      also the two that need a compositor and the patched picker
#   run.sh --scenes   regenerate the synthetic corpus first (it is gitignored)
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
NIXPKGS="https://github.com/NixOS/nixpkgs/archive/724cf38d99ba81fbb4a347081db93e2e3a9bc2ae.tar.gz"

want_e2e=0
want_scenes=0
for a in "$@"; do
  case "$a" in
    --e2e) want_e2e=1 ;;
    --scenes) want_scenes=1 ;;
    *) echo "run.sh: unknown flag $a"; exit 2 ;;
  esac
done

echo "building the python environment..."
PY="$(nix build --no-link --print-out-paths --impure --expr \
  "with import (builtins.fetchTarball {url=\"$NIXPKGS\";}) {system=builtins.currentSystem;}; \
   python3.withPackages (ps: with ps; [numpy scipy pillow])")/bin/python3"
[ -x "$PY" ] || { echo "run.sh: could not build python"; exit 2; }

rc=0
run() { echo; echo "=== $1 ==="; shift; "$@" || rc=1; }

[ "$want_scenes" = 1 ] && run "generating scenes" "$PY" "$HERE/gen_scenes.py"
[ -d "$HERE/scenes" ] || { echo "no scenes/ yet -- run with --scenes once"; exit 2; }

run "hierarchy unit tests" "$PY" "$HERE/test_hierarchy.py"
run "overlay contrast" "$PY" "$HERE/test_contrast.py"
run "detection + labelling eval" "$PY" "$HERE/harness.py" --scenes "$HERE/scenes" \
  --determinism -o "$HERE/out/scorecard.json"

if [ "$want_e2e" = 1 ]; then
  echo
  echo "building the patched picker and a nested compositor..."
  KB="$(nix build --no-link --print-out-paths --impure --expr \
    "let p = import (builtins.fetchTarball {url=\"$NIXPKGS\";}) {system=builtins.currentSystem;}; \
     in p.wl-kbptr.overrideAttrs (o: { patches = (o.patches or []) ++ [ $HERE/../wl-kbptr-label-anchor.patch ]; })")"
  TOOLS="$(nix build --no-link --print-out-paths --impure --expr \
    "let p = import (builtins.fetchTarball {url=\"$NIXPKGS\";}) {system=builtins.currentSystem;}; \
     in p.buildEnv { name=\"kbshot-e2e\"; paths=[p.sway p.wtype]; }")"
  export KBSHOT_E2E_TOOLS="$TOOLS"
  run "picker keys (real binary)" "$HERE/e2e_picker.sh" "$KB/bin"
  run "drill-down (real binary)" "$HERE/e2e_drilldown.sh" "$PY" "$KB/bin"
fi

echo
[ "$rc" = 0 ] && echo "ALL GREEN" || echo "SOMETHING FAILED"
exit "$rc"
