{
  pkgs,
  lib,
  ...
}: {
  programs.dconf.enable = true;
  programs.zsh.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
    # pinentryFlavor = "";
  };
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    stdenv.cc.cc.lib
    zlib

    # Core system libraries
    glib
    gtk3
    libgbm # For hardware-accelerated rendering
    libglvnd # Vendor-neutral dispatch layer for GL implementations
    nss
    nspr # Provides libnspr4.so
    at-spi2-core
    at-spi2-atk
    atk
    c-ares
    cairo
    cups
    dbus
    expat
    gdk-pixbuf
    gtk2
    gtk3
    libxkbcommon
    # libxshmfence
    pango
    libx11
    libxcb
    libxcomposite
    libxcursor
    libxdamage
    libxext
    libxfixes
    libxi
    libxrandr
    libxrender
    libxscrnsaver
    libxtst
    libxshmfence
    libxkbfile
    libxxf86vm
    libxinerama
    libxv
    libxcb-util
    libxcb-wm
    libxcb-image
    libxcb-keysyms
    libxcb-render-util
    libxcb-cursor
    libdrm
    mesa
    alsa-lib
    libcap
    libnotify
    libpng
    libtool
    libxkbcommon
    # libxkbfile
    # libxshmfence
    nspr
    nss
    pciutils
    pango
    pciutils
    systemd
    xdg-utils
  ];
}
