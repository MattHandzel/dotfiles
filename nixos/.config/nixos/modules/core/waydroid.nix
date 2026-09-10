{...}: {
  # Waydroid runs a full Android container on top of the Wayland session so we
  # can run Android-only apps (e.g. Granola, which ships no Linux desktop
  # build). The NixOS module pulls in the LXC stack and loads the binder
  # kernel module; the actual Android image + APKs are provisioned imperatively
  # after a rebuild:
  #   sudo waydroid init            # one-time, downloads the system image
  #   systemctl start waydroid-container
  #   waydroid session start        # from the graphical session
  #   waydroid app install <granola.apk>   # sideload the Granola APK
  virtualisation.waydroid.enable = true;
}
