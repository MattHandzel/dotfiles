{self, ...}: let
  sharedVariables = import ../../../shared_variables.nix;
in {
  home.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    __GL_GSYNC_ALLOWED = "0";
    __GL_VRR_ALLOWED = "0";
    _JAVA_AWT_WM_NONEREPARENTING = "1";
    SSH_AUTH_SOCK = "/run/user/1000/keyring/ssh";
    DISABLE_QT5_COMPAT = "0";
    GDK_BACKEND = "wayland";
    ANKI_WAYLAND = "1";
    DIRENV_LOG_FORMAT = "";
    # Disabling atomic DRM kills a lot of modern scanout optimizations.
    # Keep this off unless you have a specific kernel/driver bug.
    # WLR_DRM_NO_ATOMIC = "1";
    QT_AUTO_SCREEN_SCALE_FACTOR = "1";
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
    QT_QPA_PLATFORM = "xcb";
    QT_QPA_PLATFORMTHEME = "qt5ct";
    QT_STYLE_OVERRIDE = "kvantum";
    AQ_NO_MODIFIERS = "1";
    # keep the older wlroots knob too in case your Hyprland build still reads it
    # Disabling modifiers can force slower paths on Intel iGPU.
    # WLR_DRM_NO_MODIFIERS = "1";
    MOZ_ENABLE_WAYLAND = "1";
    # Don't force wlroots backend; let Hyprland auto-select a stable path.
    # WLR_BACKEND = "vulkan";
    # Forcing Vulkan/hardware cursor fallbacks here can cause Hyprland to thrash
    # CPU if the graphics stack is unhealthy. Let it auto-detect instead.
    # WLR_RENDERER = "vulkan";
    # WLR_NO_HARDWARE_CURSORS = "1";
    XDG_SESSION_TYPE = "wayland";
    SDL_VIDEODRIVER = "wayland";
    CLUTTER_BACKEND = "wayland";
    GTK_THEME = "catppuccin";
    NIXOS_ROOT_DIR = "${self}";
    SERVER_IP_ADDRESS = sharedVariables.serverIpAddress;
    BROWSER = "zen";
  };
}
