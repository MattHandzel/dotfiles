# Learn This browser extension, packaged as an unsigned XPI for declarative
# force-install into Zen (MAT-826). The source is vendored under ./src (the
# upstream ~/Projects/zen-learn-extension is not git-tracked, so a dangling
# absolute path would not be reproducible — we copy it into the flake instead).
#
# The XPI is just a zip of the extension dir; Firefox/Zen matches it to the
# ExtensionSettings policy key by the gecko id in manifest.json
# (learn-this@matthandzel.com). Because it is unsigned, the consuming
# wrapFirefox must also disable signature enforcement (see packages.nix).
{
  lib,
  stdenvNoCC,
  zip,
}:
stdenvNoCC.mkDerivation {
  pname = "zen-learn-extension";
  version = "2.0.0";

  src = ./src;

  # The XPI filename must be the gecko id so the wrapper/policy can find it.
  geckoId = "learn-this@matthandzel.com";

  nativeBuildInputs = [ zip ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    # zip the extension contents (not the parent dir) into an XPI.
    cd "$src"
    zip -r -X "$TMPDIR/$geckoId.xpi" . -x '*.git*'
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm444 "$TMPDIR/$geckoId.xpi" "$out/$geckoId.xpi"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Learn This — browser-native learning extension (capture, flashcards) packaged as an unsigned XPI";
    platforms = platforms.all;
  };
}
