# The kanata keymap itself, shared verbatim between NixOS and macOS.
#
# The two platforms differ ONLY in how kanata is launched and which device it
# grabs — the layers, chords and home-row mods are one source of truth, because
# muscle memory is the whole point and a drifted copy is a silently broken
# keyboard. NixOS consumes this through `services.kanata` (see
# modules/core/kanata-homerow.nix); macOS writes it to a .kbd file and runs it
# from a launchd daemon (see modules/darwin/kanata.nix).
#
# ── ACTIVE IN QWERTY (the default) ──────────────────────────────────────────
#   Left-Alt + Right-Alt  -> emits F14 -> the speech-to-text bind (needs BOTH
#                            physical alts; a single alt does nothing).
#   Left-Alt + Esc        -> toggle to the custom Corne layout (and back).
#   Everything else is plain QWERTY (no home-row mods, no letter chords).
#
# ── CUSTOM "base" layout (via Alt+Esc) ──────────────────────────────────────
#     ;  ,  .  P  Y  | F  G  C  R  L        home-row mods: ring O/N=Super,
#     A  O  E  I  U  | D  H  T  N  S        middle E/T=Alt, index I/H=Ctrl.
#     '  Q  J  K  X  | B  M  W  V  Z        hold Space=NAV, hold Tab=NUM.
#   chords: A+Q=Esc  F+G=Tab  J+K=Bksp
#
# ON macOS lmet/rmet are Command and lalt/ralt are Option, so the ring-finger
# "Super" of the Corne layout lands on Cmd — which is what you want, since Cmd
# is the load-bearing modifier there. The (lalt ralt) -> F14 chord still works;
# bind F14 inside Wispr Flow.
{
  # The shared layer/chord definitions. Everything below is platform-neutral
  # kanata syntax; nothing here mentions a device or a Linux path.
  body = ''
    (defvar
      ring-l 250  mid-l 250  idx 160  mid-r 200  ring-r 200
      left-keys  (q w e r t a s d f g z x c v b)
      right-keys (y u i o p h j k l ; n m , . /))

    (defalias
      th-o (tap-hold-release-keys $ring-l $ring-l o lmet $left-keys)
      th-e (tap-hold-release-keys $mid-l  $mid-l  e lalt $left-keys)
      th-t (tap-hold-release-keys $mid-r  $mid-r  t ralt $right-keys)
      th-n (tap-hold-release-keys $ring-r $ring-r n rmet $right-keys)
      mo (switch ((key-timing 1 less-than 200)) o break () @th-o break)
      me (switch ((key-timing 1 less-than 200)) e break () @th-e break)
      mt (switch ((key-timing 1 less-than 200)) t break () @th-t break)
      mn (switch ((key-timing 1 less-than 200)) n break () @th-n break)
      mi (tap-hold-release $idx $idx i lctl)
      mh (tap-hold-release $idx $idx h rctl)
      spc (tap-hold-release 200 200 spc (layer-while-held nav))
      tb  (tap-hold-release 200 200 tab (layer-while-held num))
      ;; Alt+Esc toggles between the two persistent layers
      tog (switch ((layer base)) (layer-switch qwerty) break () (layer-switch base) break))

    (defchordsv2
      (a q)       esc     30  all-released (base)
      (g h)       tab     30  all-released (base)
      (j k)       bspc    30  all-released (base)
      (lalt esc)  @tog    200 all-released (base qwerty)
      ;; BOTH alts together -> F14 -> hyprland speech-to-text bind (any layer)
      (lalt ralt) f14     100 all-released (base nav num qwerty))

    (defsrc
      q w e r t y u i o p
      a s d f g h j k l ;
      z x c v b n m , . /
      tab spc esc lalt ralt)

    ;; DEFAULT layer (first) = plain QWERTY passthrough.
    (deflayer qwerty
      q w e r t y u i o p
      a s d f g h j k l ;
      z x c v b n m , . /
      tab spc esc lalt ralt)

    ;; Custom Corne layout — reached via Alt+Esc.
    (deflayer base
      ;   ,   .   p   y   f    g   c    r    l
      a   @mo @me @mi u   d    @mh @mt  @mn  s
      '   q   j   k   x   b    m   w    v    z
      @tb @spc esc lalt ralt)

    (deflayer nav
      esc  home up   end  pgup  _    _    _     _    _
      lmet lalt lctl _    pgdn  left down right del  ret
      _    _    _    _    _     bspc _    _     _    _
      _    _    _    _    _)

    (deflayer num
      _    _    _    S-9  grv   _    S-0  eql  S-eql _
      7    5    3    1    9     8    0    2    4    6
      _    min  S-min lbrc _    bksl rbrc /    S-8  _
      _    _    _    _    _)
  '';

  # defcfg options. NixOS passes these through `services.kanata.*.extraDefCfg`,
  # which writes its own `(defcfg ...)` wrapper; macOS needs the wrapper too and
  # adds the device filter, so both are kept as plain strings rather than a
  # pre-rendered block.
  defcfgOptions = "process-unmapped-keys no\nconcurrent-tap-hold yes";

  # ONLY the built-in keyboard, on both platforms. Without this, kanata grabs
  # every keyboard — including the TOTEM/Corne, which already do home-row mods
  # in firmware — and double-remaps them, breaking every keypress.
  #
  # Do NOT add the TOTEM to make Wispr Flow see it (tried 2026-07-14: it mangles
  # TOTEM keys, e.g. Esc). Wispr's hot-plug blindness is solved by the
  # passthrough relay in modules/home/kbd-relay.nix instead, which forwards the
  # TOTEM verbatim with no remapping.
  #
  # The by-path name is stable for the internal i8042 keyboard across reboots.
  linuxDevices = ["/dev/input/by-path/platform-i8042-serio-0-event-kbd"];
  darwinDeviceNames = ["Apple Internal Keyboard / Trackpad"];
}
