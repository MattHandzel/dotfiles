# kanata for the laptop keyboard. DEFAULT layer is plain QWERTY — kanata runs
# only so that "both Alt keys together" can be detected as a real chord for
# speech-to-text (hyprland can't: it treats both Alts as the same ALT modifier,
# so a single Alt press wrongly fired the old `ALT, Alt_L` bind).
#
# Matt's custom Corne layout (+ home-row mods, nav/num layers, letter chords) is
# kept but DORMANT — reach it any time with Left-Alt + Esc, and Left-Alt + Esc
# again returns to QWERTY. Source of truth: github.com/MattHandzel/Corne.
#
# ── ACTIVE IN QWERTY (the default) ──────────────────────────────────────────
#   Left-Alt + Right-Alt  -> emits F14 -> hyprland speech-to-text bind (needs
#                            BOTH physical alts; a single alt does nothing).
#   Left-Alt + Esc        -> toggle to the custom Corne layout (and back).
#   Everything else is plain QWERTY (no home-row mods, no letter chords).
#
# ── CUSTOM "base" layout (via Alt+Esc) ──────────────────────────────────────
#     ;  ,  .  P  Y  | F  G  C  R  L        home-row mods: ring O/N=Super,
#     A  O  E  I  U  | D  H  T  N  S        middle E/T=Alt, index I/H=Ctrl.
#     '  Q  J  K  X  | B  M  W  V  Z        hold Space=NAV, hold Tab=NUM.
#   chords: A+Q=Esc  F+G=Tab  J+K=Bksp  K+L=Ctrl+Bksp(del word)
#
# ── REVERSIBLE ───────────────────────────────────────────────────────────────
#   Nuclear off (no kanata at all, but then both-Alt STT stops too):
#     sudo systemctl stop kanata-homerow
#   Permanent: comment the import in hosts/laptop/default.nix, or roll back gen.
#
# Logs: journalctl -u kanata-homerow -f
{...}: {
  services.kanata = {
    enable = true;
    keyboards.homerow = {
      extraDefCfg = "process-unmapped-keys no\nconcurrent-tap-hold yes";
      config = ''
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
          (a q)       esc     40  all-released (base)
          (f g)       tab     40  all-released (base)
          (j k)       bspc    40  all-released (base)
          (k l)       C-bspc  40  all-released (base)
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
    };
  };
}
