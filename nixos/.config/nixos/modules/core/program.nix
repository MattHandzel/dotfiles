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
    xorg.libX11
    xorg.libxcb
    xorg.libXcomposite
    xorg.libXcursor
    xorg.libXdamage
    xorg.libXext
    xorg.libXfixes
    xorg.libXi
    xorg.libXrandr
    xorg.libXrender
    xorg.libXScrnSaver
    xorg.libXtst
    xorg.libxshmfence
    xorg.libxkbfile
    xorg.libXxf86vm
    xorg.libXinerama
    xorg.libXv
    xorg.libXxf86vm
    xorg.xcbutil
    xorg.xcbutilwm
    xorg.xcbutilimage
    xorg.xcbutilkeysyms
    xorg.xcbutilrenderutil
    xorg.xcbutilcursor
    xorg.xcbutil
    xorg.libXrandr
    xorg.libXScrnSaver
    xorg.libXcursor
    xorg.libXdamage
    xorg.libXcomposite
    xorg.libXext
    xorg.libXfixes
    xorg.libXi
    xorg.libXrender
    xorg.libX11
    xorg.libxcb
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
