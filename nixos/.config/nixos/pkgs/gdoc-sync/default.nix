{
  lib,
  python3Packages,
  makeWrapper,
  pandoc,
  src,
}:
python3Packages.buildPythonApplication {
  pname = "gdoc-sync";
  # Must track src/gdoc_sync/__init__.py's __version__. gdoc-sync.nvim's
  # health check requires >= 0.6 and its :Gdoc watch calls `watch --json`,
  # which only exists from 0.6.0 (MAT-1780 follow-up).
  version = "0.9.0";
  pyproject = true;

  inherit src;

  build-system = [python3Packages.setuptools];
  nativeBuildInputs = [makeWrapper];

  propagatedBuildInputs = with python3Packages; [
    google-api-python-client
    google-auth-oauthlib
    google-auth-httplib2
    pyyaml
  ];

  # pandoc does the markdown → docx conversion at runtime.
  postFixup = ''
    wrapProgram $out/bin/gdoc-sync \
      --prefix PATH : ${lib.makeBinPath [pandoc]}
  '';

  nativeCheckInputs = [python3Packages.pytestCheckHook];

  meta = with lib; {
    description = "Sync Markdown files with Google Docs from the CLI";
    homepage = "https://github.com/MattHandzel/gdoc-sync";
    license = licenses.mit;
    mainProgram = "gdoc-sync";
  };
}
