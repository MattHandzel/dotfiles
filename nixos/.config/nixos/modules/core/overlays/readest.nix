# Readest from a newer nixpkgs than the main pin.
#
# The main pin (nixos-unstable-small, locked Feb 2026) ships readest 0.9.100.
# Readest is chosen over foliate precisely BECAUSE it is actively developed —
# foliate's newest release is 3.3.0 (Apr 2025) — so shipping a six-month-old
# readest would defeat the reason it was picked. Only this one attribute comes
# from the newer tree; everything else still resolves against the main pin.
#
# Cost of this approach: readest links against the other tree's webkitgtk/gtk,
# so it carries its own closure rather than sharing the system's. That is the
# deliberate trade for not bumping the main pin (which would rebuild the world).
inputs: final: prev: {
  readest = inputs.nixpkgs-readest.legacyPackages.${prev.stdenv.hostPlatform.system}.readest;
}
