# Hammerspoon's `hs` command-line tool, rebuilt from the 1.1.1 source with one fix.
#
# The stock CLI (Hammerspoon.app/Contents/Frameworks/hs/hs) ends main() with
#   [core performSelector:@selector(poke:) onThread:core withObject:nil waitUntilDone:YES]
# but its client thread leaves its runloop on its own once a command fails (Lua error or
# timeout). When the thread is already gone the perform raises NSDestinationInvalidException
# (SIGABRT, crash report "hs crashed (EXC_CRASH SIGABRT)") or waits forever. Bug listener item
# err-hs-20261019-200819; repro: ~/Obsidian/Main/scripts/bugs/repros/err-hs-20261019-200819.sh.
# Upstream still has the same code on master (checked 2026-11-12).
#
# Built with nixpkgs' clang + Apple SDK (Foundation/AppKit) and libedit, the same libraries
# the app's own Xcode build links. The ipc protocol matches Hammerspoon 1.1.1; bump `version`
# and the hash together with the app.
{
  lib,
  stdenv,
  fetchurl,
  libedit,
}:
stdenv.mkDerivation rec {
  pname = "hammerspoon-cli";
  version = "1.1.1";

  src = fetchurl {
    url = "https://raw.githubusercontent.com/Hammerspoon/hammerspoon/${version}/extensions/ipc/cli/hs.m";
    hash = "sha256-0qrhuebRLWaZSkzWrXCxhFc6ARKiur0V+Tt8VuyGyHk=";
  };

  dontUnpack = true;
  buildInputs = [libedit];

  buildPhase = ''
    runHook preBuild
    mkdir -p extensions/ipc/cli
    cp $src extensions/ipc/cli/hs.m
    patch -p1 < ${./exited-client-thread.patch}
    $CC -fobjc-arc -fmodules -O2 -w -ledit -o hs extensions/ipc/cli/hs.m
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 hs $out/bin/hs
    runHook postInstall
  '';

  meta = {
    description = "Hammerspoon `hs` CLI with the exited-client-thread abort fixed";
    homepage = "https://github.com/Hammerspoon/hammerspoon";
    license = lib.licenses.mit;
    platforms = lib.platforms.darwin;
    mainProgram = "hs";
  };
}
