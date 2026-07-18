# Laptop keyboard — Matt's Corne layout (via kanata)

Physical position = where the key is on the laptop (QWERTY body). The letter shown
is what it **produces**. `★` = a key with a hold/special behavior.

## BASE layer (default)
```
 ┌───┬───┬───┬───┬───┐   ┌───┬───┬───┬───┬───┐
 │ ; │ , │ . │ P │ Y │   │ F │ G │ C │ R │ L │
 ├───┼───┼───┼───┼───┤   ├───┼───┼───┼───┼───┤
 │ A │ O★│ E★│ I★│ U │   │ D │ H★│ T★│ N★│ S │   ★ home-row mods:
 ├───┼───┼───┼───┼───┤   ├───┼───┼───┼───┼───┤     O/N=Super  E/T=Alt  I/H=Ctrl
 │ ' │ Q │ J │ K │ X │   │ B │ M │ W │ V │ Z │     (hold = mod, tap = letter)
 └───┴───┴───┴───┴───┘   └───┴───┴───┴───┴───┘
              [Tab ★]  [Space ★]        ★ hold Tab = NUM, hold Space = NAV
```

## NAV layer  —  hold **Space**
```
 ┌────┬────┬────┬────┬────┐   ┌────┬────┬────┬────┬────┐
 │Esc │Home│ ↑  │End │PgUp│   │    │    │    │    │    │
 ├────┼────┼────┼────┼────┤   ├────┼────┼────┼────┼────┤
 │Super│Alt│Ctrl│    │PgDn│   │ ←  │ ↓  │ →  │Del │Enter│
 ├────┼────┼────┼────┼────┤   ├────┼────┼────┼────┼────┤
 │    │    │    │    │    │   │Bksp│    │    │    │    │
 └────┴────┴────┴────┴────┘   └────┴────┴────┴────┴────┘
```

## NUM / symbol layer  —  hold **Tab**
```
 ┌───┬───┬───┬───┬───┐   ┌───┬───┬───┬───┬───┐
 │   │   │   │ ( │ ` │   │   │ ) │ = │ + │   │
 ├───┼───┼───┼───┼───┤   ├───┼───┼───┼───┼───┤
 │ 7 │ 5 │ 3 │ 1 │ 9 │   │ 8 │ 0 │ 2 │ 4 │ 6 │
 ├───┼───┼───┼───┼───┤   ├───┼───┼───┼───┼───┤
 │   │ - │ _ │ [ │   │   │ \ │ ] │ / │ * │   │   ← `/` lives here
 └───┴───┴───┴───┴───┘   └───┴───┴───┴───┴───┘
```

## Chords (press both keys at once)
```
 A + Q  →  Esc            J + K  →  Backspace
 F + G  →  Tab            K + L  →  Ctrl+Backspace (delete word)
```

## QWERTY escape hatch
```
 Left-Alt + Esc   ⇄   toggle between this layout and plain QWERTY (both ways)
 sudo systemctl stop kanata-homerow   →   nuclear option: full plain QWERTY
```

---
### Want a prettier rendered picture?
`keymap-drawer` renders keymaps to SVG. Rough flow:
```
nix shell nixpkgs#python3Packages.keymap-drawer   # or: pipx install keymap-drawer
# then feed it the layer data (I can generate the YAML it wants from this module).
```
Ask me and I'll wire up a one-command `render-keyboard` script that regenerates an
SVG from this module whenever you change the layout.
