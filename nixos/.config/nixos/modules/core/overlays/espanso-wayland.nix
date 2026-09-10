# espanso 2.3.0 hangs at startup on Hyprland: get_modifiers_state() opens a
# focusable "Espanso Sync Tool" Wayland window and spins in an UNBOUNDED loop
# waiting for a wl_keyboard.modifiers event that wlroots never delivers to a
# focus-less client. The window steals focus while the worker never registers
# keyboards -> "espanso running but not expanding" + browser locked out.
# This patch adds a 500ms timeout to that loop so it returns an unknown (None)
# initial modifier state instead of hanging; evdev picks up modifiers after.
# Only touches source (not Cargo.lock), so the vendored cargoDeps hash is
# unchanged. Root fix for the recurring espanso-broken reports (MAT tally).
self: super: {
  espanso-wayland = super.espanso-wayland.overrideAttrs (old: {
    patches = (old.patches or []) ++ [./espanso-wayland-modifier-timeout.patch];
  });
}
