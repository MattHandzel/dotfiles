# kbshot: press a hotkey, every screenshot-worthy thing on screen gets a labelled
# box, type the label to capture it. No mouse. See kbshot.py for the design notes.
#
# The picker overlay is wl-kbptr's `floating` mode fed candidate regions on stdin;
# kbshot supplies those regions itself from Hyprland window geometry, tesseract's
# layout analysis, and a scipy edge/connected-component pass. Every runtime binary
# is baked into the wrapper's PATH rather than assumed, because this runs from a
# Hyprland `exec` bind whose PATH is not the login shell's.
{pkgs}: let
  python = pkgs.python3.withPackages (ps: with ps; [numpy scipy pillow]);

  # wl-kbptr draws one rectangle per candidate and centres that candidate's label
  # inside it. That single constraint forces a choice between outlining the real region
  # -- so you can see what you are about to capture -- and putting the label somewhere
  # unambiguous and legible. You cannot have both, because there is only one rect: a
  # label centred in a full-width row lands in blank space belonging to no visible
  # outline in particular, and shrinking the rect to a corner chip is what threw the
  # outline away in the first place.
  #
  # The patch adds an optional second geometry per stdin line,
  # `WxH+X+Y LWxLH+LX+LY`, meaning "outline this, draw the label in that", plus a
  # `label_bg_color` so the label gets its own opaque backing. A line carrying one
  # geometry behaves exactly as before, so it is backward compatible. Scoped to this
  # package rather than applied as a global overlay, so nothing else is affected.
  wl-kbptr-labelled = pkgs.wl-kbptr.overrideAttrs (old: {
    patches = (old.patches or []) ++ [./wl-kbptr-label-anchor.patch];
  });
in
  pkgs.writeShellApplication {
    name = "kbshot";
    runtimeInputs = with pkgs; [
      python
      wl-kbptr-labelled # the labelled keyboard picker overlay
      grim # screen capture
      tesseract # text block/paragraph/line boxes, and --ocr
      wl-clipboard # wl-copy
      libnotify # notify-send
      hyprland # hyprctl: monitor geometry and window rectangles
      procps # pkill -x, to clear a rival or wedged overlay off the screen
    ];
    text = ''
      exec ${python}/bin/python3 ${./kbshot.py} "$@"
    '';
  }
