{
  lib,
  python3Packages,
  buildNpmPackage,
  makeWrapper,
  vhs,
  gifsicle,
  marp-cli,
  tesseract,
  ffmpeg,
  chromium,
  grim,
  wtype,
  nodejs,
  hyprland,
  kitty,
  src,
}: let

  # Bundle the Node-side Playwright dependency (used for .playwright.js
  # workflow scripts). We build node_modules from the committed lockfile and
  # disable Playwright's browser download — we point at the system `chromium`
  # at runtime instead.
  nodeDeps = buildNpmPackage {
    pname = "project-asset-generator-node-deps";
    version = "1.0.0";
    src = builtins.path {
      path = src;
      name = "project-asset-generator-node-src";
      filter = path: type: let
        base = baseNameOf path;
      in
        base == "package.json" || base == "package-lock.json";
    };

    npmDepsHash = "sha256-HbcInltZTypDNfwdFGh8HgNkZccqXYOKCPHwHD40XhI=";

    dontNpmBuild = true;
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r node_modules $out/
      runHook postInstall
    '';
  };
in
  python3Packages.buildPythonApplication {
    pname = "project-asset-generator";
    version = "1.0.0";
    format = "pyproject";

    inherit src;

    nativeBuildInputs = with python3Packages;
      [
        setuptools
        wheel
      ]
      ++ [makeWrapper];

    propagatedBuildInputs = with python3Packages; [
      pyyaml
      pillow
      pytesseract
      playwright # Python bindings (BrowserApp class)
    ];

    doCheck = false;

    # Ship the test fixtures alongside the package so `generate-assets
    # --self-test` works from the installed binary.
    postInstall = ''
      mkdir -p $out/share/project-asset-generator
      cp -r tests/fixtures $out/share/project-asset-generator/fixtures
    '';

    # Make runtime tools available on PATH, point Playwright at system
    # chromium, expose the bundled node_modules via NODE_PATH, and point the
    # --self-test command at the installed fixtures directory.
    postFixup = ''
      wrapProgram $out/bin/generate-assets \
        --prefix PATH : ${lib.makeBinPath [
        vhs
        gifsicle
        marp-cli
        tesseract
        ffmpeg
        chromium
        grim
        wtype
        nodejs
        hyprland
        kitty
      ]} \
        --set PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH ${chromium}/bin/chromium \
        --prefix NODE_PATH : ${nodeDeps}/node_modules \
        --set-default ASSET_GENERATOR_FIXTURES_DIR $out/share/project-asset-generator/fixtures
    '';

    meta = with lib; {
      description = "Generate demo assets (GIFs, screenshots, slides, videos) for software projects";
      homepage = "https://github.com/MattHandzel/project-asset-generator";
      license = licenses.mit;
      mainProgram = "generate-assets";
      platforms = platforms.linux;
    };
  }
