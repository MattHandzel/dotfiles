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
  version = "0.10.0";
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
  #
  # A file's own `gdoc_theme:` frontmatter key overrides the config theme on
  # create and on every push, so generated meeting notes stay `professional`
  # while everything else keeps catppuccin-latte (Oops 2026-10-20). Worktree
  # `~/Projects/gdoc-sync-theme` (branch `oops-gdoc-theme`, uncommitted), on top
  # of the three patches above.
  #
  # `status` parsed the whole state file once per link (is_pull_only reloads
  # it), so `status --json` took over a minute with ~1,100 links and
  # gdoc-sync.nvim's link cache never filled (2026-10-21). Not upstream yet.
  #
  # gdoc (github.com/LucaDeLeo/gdoc, MIT) vendored as gdoc_sync._gdoc: its
  # commands (cat, edit, suggest, comment --quote, revisions, cells, mcp, ...)
  # run with gdoc-sync's login and accept a linked .md in place of a doc ID;
  # {>>comment:<<} markers become anchored comments; `gdoc-sync hook` for
  # Claude Code (2026-10-22). Branch `gdoc-integration` in the worktree
  # `~/Projects/gdoc-sync-gdoc-integration`, committed on top of the five
  # patches above; this patch is `git diff 6379a31 HEAD` there minus the
  # vendored tests (tests/gdoc_upstream, 1963 tests, run in the worktree).
  #
  # `unlink` accepts a path whose file is gone: that is the case `status` and
  # `sync --all` tell you to run it for, and it used to refuse with "file not
  # found" (2026-11-10). Worktree `~/Projects/gdoc-sync-unlink-missing` (branch
  # `oops-unlink-missing`, uncommitted).
  #
  # A Doc edit inside a numbered list no longer conflicts just because the
  # vault numbers it 1. 2. 3. and the Doc renders 1. 1. 1.: merge3 retries with
  # uniform numbers and keeps that only if it is clean (bug
  # err-gdoc-sync-20261111-113950). Worktree `~/Projects/gdoc-sync-list-numbering`
  # (branch `oops-list-numbering-merge`, uncommitted, on top of the patches above).
  #
  # A lost network (DNS gone, network unreachable, read timeout) anywhere in an
  # API command is one line on stderr and exit 75 (EX_TEMPFAIL) instead of a
  # traceback and "ERROR while syncing <file>"; the launchd pass treats 75 as
  # "offline mid-pass" (bug err-gdoc-sync-20261027-181808). Worktree
  # `~/Projects/gdoc-sync-network-skip` (detached, base commit = the patches
  # above, change uncommitted).
  #
  # A dead Google login (RefreshError invalid_grant mid-run) is one line,
  # "the Google login is dead ... Run: gdoc-sync auth --force", and exit 77
  # (EX_NOPERM), instead of "ERROR while syncing <whichever file was first>" and
  # a traceback; it stays loud because only a re-auth fixes it (bug
  # err-gdoc-sync-20261105-214358). Worktree `~/Projects/gdoc-sync-auth-dead`
  # (detached; base commit cd8de0b = all patches above, change staged).
  #
  # A trailing space trimmed in the vault ("1. " -> "1." on an editor save) no
  # longer turns a Doc edit of that list into a conflict: merge3 retries with
  # each side's whitespace-only trims undone (and with uniform list numbers on
  # top), keeping a retry only if it is clean; added hard breaks are kept (bug
  # err-gdoc-sync-20261113-122443). Worktree `~/Projects/gdoc-sync-ws-merge`
  # (detached; base commit ab8d1d0 = all patches above, change uncommitted).
  patches = [./footnote-links.patch ./mirror.patch ./empty-list-items.patch ./frontmatter-theme.patch ./status-one-state-load.patch ./gdoc-integration.patch ./unlink-missing.patch ./list-numbering-merge.patch ./network-loss-exit-75.patch ./dead-login-exit-77.patch ./merge-trailing-whitespace.patch];

  build-system = [python3Packages.setuptools];
  nativeBuildInputs = [makeWrapper];

  propagatedBuildInputs = with python3Packages; [
    google-api-python-client
    google-auth-oauthlib
    google-auth-httplib2
    # httplib2 ignores http(s)_proxy without PySocks; the Claude Code Bash sandbox only lets traffic out
    # through its proxy, so gdoc-sync inside a sandboxed headless job (gdoc-claude) needs this. 2026-11-04.
    pysocks
    pyyaml
    requests
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
