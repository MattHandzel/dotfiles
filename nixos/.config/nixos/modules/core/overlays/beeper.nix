# Beeper 4.3.73 from the vendored package in pkgs/beeper (see its header comment).
final: prev: {
  beeper = final.callPackage ../../../pkgs/beeper { };
}
