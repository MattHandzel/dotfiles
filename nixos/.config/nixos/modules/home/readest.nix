{...}: {
  # Readest's packaged desktop entry is `Exec=readest` with NO field code, so
  # anything that opens a file by association (xdg-open, yazi, the browser's
  # "open with") launches Readest with no argument — the app appears, the book
  # never does. Since readest.desktop is what mimeapps points at for ebooks,
  # that would look like a working default while silently opening nothing.
  #
  # ~/.local/share/applications wins over the package's share/applications, so
  # this entry shadows the upstream one. Same trick as the Foliate entry in
  # modules/core/user.nix. StartupWMClass is kept verbatim — Hyprland matches
  # the window by it.
  #
  # MimeType deliberately OMITS application/pdf, which upstream claims: PDFs
  # stay with zathura (see the mimeapps block in modules/home/default.nix).
  xdg.desktopEntries.readest = {
    name = "Readest";
    genericName = "E-book Reader";
    comment = "Read and annotate e-books";
    exec = "readest %U";
    icon = "readest";
    terminal = false;
    type = "Application";
    categories = ["Office" "Viewer"];
    mimeType = [
      "application/epub+zip"
      "application/x-mobipocket-ebook"
      "application/vnd.amazon.ebook"
      "application/vnd.amazon.mobi8-ebook"
      "application/x-fictionbook+xml"
      "application/vnd.comicbook+zip"
    ];
    settings.StartupWMClass = "readest";
  };
}
