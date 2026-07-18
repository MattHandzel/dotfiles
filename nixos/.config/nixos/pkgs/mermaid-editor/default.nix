{
  lib,
  buildGoModule,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs,
}: let
  pname = "mermaid-editor";
  version = "0-unstable-2026-05-18";

  src = fetchFromGitHub {
    owner = "mozi-app";
    repo = "mermAId";
    rev = "e27a83a8d94759acb825396c0c85cdb464f635d9";
    hash = "sha256-dODegtiyxEGE4lG1chEzPkZB03VCZw4V4KK67HFMygg=";
  };

  # JS bundle (static/bundle.js) — produced by esbuild against the locked
  # npm deps. Output also includes a copy of style.css so the Go build can
  # consume both with one cp.
  frontend = buildNpmPackage {
    pname = "${pname}-frontend";
    inherit version src;

    npmDepsHash = "sha256-kk1EcbE7EUOK90PoygDGrKzNtkLvva/qINzkZJH6vIQ=";

    # The package has no `build` script — drive esbuild directly.
    dontNpmBuild = true;

    buildPhase = ''
      runHook preBuild
      npx --offline esbuild frontend/app.js \
        --bundle \
        --format=iife \
        --minify \
        --sourcemap \
        --outfile=bundle.js
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp bundle.js $out/bundle.js
      cp bundle.js.map $out/bundle.js.map
      cp frontend/style.css $out/style.css
      runHook postInstall
    '';
  };
in
  buildGoModule {
    inherit pname version src;

    vendorHash = "sha256-uvNl0adt0mVVa7+QMTvtl/N86jmkHFzfh0rFsi6KHcs=";

    # Static assets are embedded into the Go binary via //go:embed. Drop the
    # frontend artifacts into static/ before the Go build runs.
    preBuild = ''
      cp ${frontend}/bundle.js static/bundle.js
      cp ${frontend}/bundle.js.map static/bundle.js.map
      cp ${frontend}/style.css static/style.css
    '';

    ldflags = ["-X main.version=${version}"];

    # On Linux, no CGO or system libraries are required (per upstream README).
    # The macOS-only Cocoa/WebKit path lives behind GOOS=darwin build tags.
    env.CGO_ENABLED = "0";

    # Skip tests at package level — the upstream test suite covers behavior
    # that depends on local state dirs and is not relevant to packaging.
    doCheck = false;

    meta = with lib; {
      description = "Local Mermaid diagram editor with MCP server for AI agents";
      homepage = "https://github.com/mozi-app/mermAId";
      license = licenses.mit;
      mainProgram = "mermaid-editor";
      platforms = platforms.linux;
    };
  }
