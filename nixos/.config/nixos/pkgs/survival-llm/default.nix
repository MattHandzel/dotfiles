# Survival LLM: offline AI assistant + emergency reference library (Matt, 2026-11-21, delegate dlg-9f85ee).
# Upstream: https://github.com/anonnerdfrenzy/survival-llm  (site: https://www.brangus.io/survival-llm)
# The release is an ad-hoc-signed .app with bundled Python + Ollama. Its local server binds 127.0.0.1 only;
# models and the library download at first run into ~/Library/Application Support/Survival LLM (not the store).
# Its in-app "update the app" button cannot replace a read-only store copy: bump version + hash here instead.
{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:
stdenvNoCC.mkDerivation rec {
  pname = "survival-llm";
  version = "0.4.1";

  src = fetchurl {
    url = "https://github.com/anonnerdfrenzy/survival-llm/releases/download/v${version}/Survival-LLM-mac.zip";
    # = the GitHub release asset digest sha256:b1a602f3e46fd15d26122a7d5608d24fc34081c385ab901d0e01a3f5306098bc
    hash = "sha256-saYC8+Rv0V0mEip9VgjST8NAgcOFq5AdDgGj9TBgmLw=";
  };

  nativeBuildInputs = [unzip];
  sourceRoot = ".";
  dontFixup = true; # keep the upstream ad-hoc signature intact

  installPhase = ''
    runHook preInstall
    mkdir -p $out/Applications
    cp -R "Survival LLM.app" $out/Applications/
    runHook postInstall
  '';

  meta = {
    description = "Offline AI assistant and emergency library that runs on your own computer";
    homepage = "https://www.brangus.io/survival-llm";
    platforms = ["aarch64-darwin"];
    sourceProvenance = [lib.sourceTypes.binaryNativeCode];
  };
}
