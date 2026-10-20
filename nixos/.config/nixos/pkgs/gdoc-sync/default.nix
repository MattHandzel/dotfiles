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

  # Footnote markers in a pushed doc link to their footnotes (Oops
  # 2026-09-24). Not upstream yet: the change is also in the
  # `oops-footnote-links` worktree of ~/Projects/gdoc-sync. Drop this once
  # that lands on main, or the patch will no longer apply.
  #
  # `gdoc-sync mirror DIR` imports every Doc in the account into one folder,
  # pull-only, and keeps them current from one Drive listing; `import` of an
  # already-linked doc returns the existing file; and sync merges the body
  # without the local-only YAML header, which made every edit at the top of an
  # imported doc a conflict (Oops 2026-10-06). Same story:
  # worktree `~/Projects/gdoc-sync-mirror` (branch `oops-mirror`, uncommitted),
  # written against this source with footnote-links.patch applied.
  #
  # An empty list item (`1.` alone under a heading) reaches the doc as an empty
  # numbered paragraph instead of vanishing (Oops 2026-10-08). Worktree
  # `~/Projects/gdoc-sync-empty-list` (branch `oops-empty-list`, uncommitted),
  # written on top of the two patches above.
  patches = [./footnote-links.patch ./mirror.patch ./empty-list-items.patch];

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

  # pandoc is needed at CHECK time too, not just at runtime: the markdown
  # round-trip tests shell out to it and fail with "pandoc not found on PATH"
  # without it. This never surfaced while `src` was a `path:` input, because the
  # store path never changed and the old build stayed cached; repointing the
  # input at the GitHub remote changed the hash and rebuilt it.
  nativeCheckInputs = [python3Packages.pytestCheckHook pandoc];

  meta = with lib; {
    description = "Sync Markdown files with Google Docs from the CLI";
    homepage = "https://github.com/MattHandzel/gdoc-sync";
    license = licenses.mit;
    mainProgram = "gdoc-sync";
  };
}
