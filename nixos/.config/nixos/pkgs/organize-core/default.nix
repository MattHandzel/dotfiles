{
  lib,
  python3Packages,
  src,
}:
# organize-core — the engine behind para-organize.nvim (the `rewrite` branch of
# MattHandzel/para-organize). The Neovim plugin is a thin client that spawns
# `organize serve`, so without this binary on PATH the plugin fails with
# `CoreNotFound: organize (ENOENT)`. On the Linux laptop it lived imperatively
# in ~/.local/bin; the Mac gets it through the flake instead.
python3Packages.buildPythonApplication {
  pname = "organize-core";
  # Tracks pyproject.toml's `version`.
  version = "0.1.0";
  pyproject = true;

  inherit src;

  build-system = [python3Packages.setuptools];

  dependencies = with python3Packages; [
    pyyaml
  ];

  # The full pytest suite spawns real `organize serve` processes over unix
  # sockets and takes 10+ minutes; run it from the repo (`make test`), not in
  # the build sandbox. The import + CLI smoke check below still gates the build.
  doCheck = false;
  pythonImportsCheck = ["organize_core"];
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    $out/bin/organize --help > /dev/null
    runHook postInstallCheck
  '';

  meta = with lib; {
    description = "Core engine for the KMS organize stage (para-organize.nvim's `organize serve`)";
    homepage = "https://github.com/MattHandzel/para-organize/tree/rewrite";
    license = licenses.mit;
    mainProgram = "organize";
  };
}
