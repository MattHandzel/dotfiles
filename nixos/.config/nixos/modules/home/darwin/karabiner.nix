# Karabiner-Elements does exactly FIVE things here. kanata
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
#   3. Inside kitty ONLY, the LEFT Command key becomes Control, so the nvim and
#      tmux chords that are Ctrl-something on Linux stay under the same thumb
#      here. See cmdIsCtrlInKitty below for the full trade-off.
#
#   4. Command+Delete deletes the previous WORD instead of the whole line,
#      everywhere except kitty. See cmdDeleteIsWordDelete below.
#
#   5. Print Screen is folded onto F13, so AeroSpace can bind screenshots to it
#      (f13 = kbshot, alt-f13 = kbshot --ocr). See simple_modifications below.
#
# Karabiner-Elements is a cask (modules/darwin/homebrew.nix) because it ships a
# DriverKit system extension that has to be Apple-notarized.
#
# NOTE: complex modifications run BEFORE simple modifications in Karabiner, so
# the Alt+Caps rule sees a real caps_lock and wins over the esc swap below.
_: let
  kittyBundleId = "^net\\.kovidgoyal\\.kitty$";

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

  # Command+Delete on macOS deletes to the START OF THE LINE. On Linux the
  # equivalent thumb-and-backspace reflex (Ctrl+Backspace) deletes one word, so
  # the Mac behaviour quietly ate whole lines. Option+Delete is macOS's own
  # delete-previous-word, so this rewrites the chord rather than reimplementing
  # the deletion.
  #
  # Excluded inside kitty for two reasons: the terminal already has Ctrl+W for
  # word-delete, and rule 3 below turns left Command into Control there, so a
  # "command" modifier would not be what actually reaches this rule.
  cmdDeleteIsWordDelete = {
    description = "Command+Delete deletes the previous word (not the whole line)";
    manipulators = [
      {
        type = "basic";
        from = {
          key_code = "delete_or_backspace";
          modifiers = {
            mandatory = ["command"];
            optional = ["caps_lock"];
          };
        };
        to = [
          {
            key_code = "delete_or_backspace";
            modifiers = ["option"];
          }
        ];
        conditions = [
          {
            type = "frontmost_application_unless";
            bundle_identifiers = [kittyBundleId];
          }
        ];
      }
    ];
  };

  # THE TRADE-OFF, stated plainly: while kitty is frontmost, LEFT Command is
  # Control. Ctrl-w / Ctrl-d / Ctrl-r / Ctrl-o in nvim, and the tmux prefix, all
  # come back under the thumb they lived under on Linux.
  #
  # The cost is that left Command stops being Command in that one app:
  #   - left Cmd+C sends SIGINT, it does not copy. Use RIGHT Command to copy.
  #   - left Cmd+Tab does not switch apps while kitty is focused. Right Command
  #     does.
  # RIGHT Command is deliberately left untouched to be that escape hatch. Only
  # `left_command` is remapped; do not "tidy" this into both.
  #
  # This is a key-level remap rather than one manipulator per chord, so every
  # Ctrl-something binding works without enumerating them.
  cmdIsCtrlInKitty = {
    description = "kitty: left Command acts as Control (Linux nvim/tmux chords)";
    manipulators = [
      {
        type = "basic";
        from = {
          key_code = "left_command";
          modifiers.optional = ["any"];
        };
        to = [{key_code = "left_control";}];
        conditions = [
          {
            type = "frontmost_application_if";
            bundle_identifiers = [kittyBundleId];
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
        # Order matters: Karabiner walks this list top to bottom. The input
        # source toggle must see a real caps_lock, and the delete rule must be
        # evaluated before the key-level Command remap rewrites the modifier.
        complex_modifications.rules = [
          toggleInputSource
          cmdDeleteIsWordDelete
          cmdIsCtrlInKitty
        ];
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
          # Print Screen -> F13. macOS has no Print Screen concept: a PC
          # keyboard's key already arrives as F13, but a keyboard that sends a
          # literal print_screen usage would otherwise land nowhere. Folding
          # both onto F13 means aerospace.nix needs exactly one binding
          # (f13 = kbshot, alt-f13 = kbshot --ocr) instead of two spellings.
          {
            from.key_code = "print_screen";
            to = [{key_code = "f13";}];
          }
        ];
        # DELIBERATELY EMPTY — Karabiner must NOT grab the Totem (Matt, 2026-09-12).
        #
        # Karabiner only rewrites keys on devices it grabs, and it has never
        # grabbed the Totem: /var/log/karabiner/core_service.log shows the
        # internal keyboard grabbed 16 times and every Totem line a termination.
        # Adding a `devices` entry for ZMK Project (vendor 7504, product 24926)
        # would switch that on — and was explicitly rejected, because it would
        # also apply the escape<->caps_lock swap to a board whose firmware
        # already handles that, costing Matt his Escape key.
        #
        # CONSEQUENCE, so nobody re-adds it looking for a fix: every rule in this
        # file is INTERNAL-KEYBOARD-ONLY. On the Totem, Command-as-Control and
        # print_screen->F13 do nothing. The Totem already sends F13 natively,
        # and the kitty Ctrl chords are handled in kitty.nix instead, which
        # works on any keyboard.
        #
        # Command+Delete word-delete is the exception: Matt hit the whole-line
        # delete in Google Docs from the Totem (2026-09-12), so that rewrite
        # now ALSO lives in ~/.hammerspoon/init.lua as an event tap, which sits
        # after every keyboard driver and so covers both boards. The Karabiner
        # copy above stays; on the internal keyboard it fires first and the
        # Hammerspoon tap then sees Option+Delete and leaves it alone.
        devices = [];
        fn_function_keys = [];
      }
    ];
  };
in {
  home.file.".config/karabiner/karabiner.json".text = builtins.toJSON karabinerConfig;
}
