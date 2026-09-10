# Default-application map. `xdg.mimeApps` is a freedesktop concept — the option
# exists on darwin but writing it there is meaningless (macOS uses Launch
# Services; `duti` is the equivalent, set up in Phase 8), and every value here
# names a .desktop file that only exists on Linux. So it lives in a Linux-only
# module rather than behind a `mkIf`: an option set to a Linux-shaped value on a
# Mac is still wrong, it is just wrong more quietly.
_: {
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "inode/directory" = "yazi.desktop";
      "text/plain" = "nvim.desktop";
      "text/x-python" = "nvim.desktop";
      "text/html" = "zen-beta.desktop";
      "x-scheme-handler/http" = "zen-beta.desktop";
      "x-scheme-handler/https" = "zen-beta.desktop";
      "audio/*" = "mpv.desktop";
      "video/*" = "mpv.desktop";
      "image/*" = "swayimg.desktop";
      "text/css" = "nvim.desktop";
      "text/*" = "nvim.desktop";
      "application/json" = "nvim.desktop";
      "application/x-shellscript" = "nvim.desktop";
      # PDFs stay with zathura — readest claims application/pdf upstream, but
      # its PDF support is experimental and zathura/sioyek are the tools here.
      "application/pdf" = "zathura.desktop";
      # Book formats open in Readest (see modules/home/readest.nix). Previously
      # EPUB went to calibre-ebook-viewer.desktop; calibre stays installed as a
      # library manager, it is just no longer what opens a book on double-click.
      "application/epub+zip" = "readest.desktop";
      "application/x-mobipocket-ebook" = "readest.desktop";
      "application/vnd.amazon.ebook" = "readest.desktop";
      "application/vnd.amazon.mobi8-ebook" = "readest.desktop";
      "application/x-fictionbook+xml" = "readest.desktop";
      "application/vnd.comicbook+zip" = "readest.desktop";
    };
  };
}
