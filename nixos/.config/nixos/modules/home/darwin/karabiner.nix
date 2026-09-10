# Karabiner-Elements does exactly TWO things here. kanata
# (modules/darwin/kanata.nix) owns the home-row mods, the layers and the chords;
# duplicating any of that here would produce two remappers fighting over the
# same keypress.
#
#   1. Caps ⇄ Esc — a real SWAP, not just caps→esc.
#      `system.keyboard.remapCapsLockToEscape` (modules/darwin/system-defaults.nix)
#      already gives caps→esc at the firmware level, which is what makes Esc
#      work before kanata has loaded at boot. The other half of the swap
#      (esc→caps) has no nix-darwin option, so it lives here.
#
#   2. Alt+Caps → toggle the input source between US and Polish.
#      This replaces the xkb `us,pl` group toggle from the Hyprland config.
#      Karabiner's `select_input_source` cannot toggle on its own, so a variable
#      tracks which side is active and two rules flip between them.
#      Polish must be added once in System Settings → Keyboard → Input Sources.
#
# Karabiner-Elements is a cask (modules/darwin/homebrew.nix) because it ships a
# DriverKit system extension that has to be Apple-notarized.
#
# NOTE: complex modifications run BEFORE simple modifications in Karabiner, so
# the Alt+Caps rule sees a real caps_lock and wins over the esc swap below.
_: let
  toggleInputSource = {
    description = "Alt+Caps Lock toggles US ⇄ Polish input source";
    manipulators = [
      {
        type = "basic";
        from = {
          key_code = "caps_lock";
          modifiers = {
            mandatory = ["option"];
            optional = ["any"];
          };
        };
        conditions = [
          {
            type = "variable_if";
            name = "input_source_polish";
            value = 0;
          }
        ];
        to = [
          {select_input_source = {language = "^pl$";};}
          {
            set_variable = {
              name = "input_source_polish";
              value = 1;
            };
          }
        ];
      }
      {
        type = "basic";
        from = {
          key_code = "caps_lock";
          modifiers = {
            mandatory = ["option"];
            optional = ["any"];
          };
        };
        conditions = [
          {
            type = "variable_if";
            name = "input_source_polish";
            value = 1;
          }
        ];
        to = [
          {select_input_source = {language = "^en$";};}
          {
            set_variable = {
              name = "input_source_polish";
              value = 0;
            };
          }
        ];
      }
    ];
  };

  karabinerConfig = {
    global = {
      check_for_updates_on_startup = false;
      show_in_menu_bar = false;
      show_profile_name_in_menu_bar = false;
    };
    profiles = [
      {
        name = "nix-managed";
        selected = true;
        virtual_hid_keyboard.keyboard_type_v2 = "ansi";
        complex_modifications.rules = [toggleInputSource];
        simple_modifications = [
          # The half of the caps/esc swap nix-darwin cannot express.
          {
            from.key_code = "escape";
            to = [{key_code = "caps_lock";}];
          }
          {
            from.key_code = "caps_lock";
            to = [{key_code = "escape";}];
          }
        ];
        devices = [];
        fn_function_keys = [];
      }
    ];
  };
in {
  home.file.".config/karabiner/karabiner.json".text = builtins.toJSON karabinerConfig;
}
