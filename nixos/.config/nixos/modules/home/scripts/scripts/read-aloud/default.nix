# read-aloud: hotkey -> hear the article you're looking at. See read-aloud.py.
#
# trafilatura does the boilerplate-stripping (nav, ads, comments) that makes a web
# page listenable; the rest of the runtime deps are called by name, so they are
# baked into the wrapper's PATH rather than assumed to be on the user's.
{pkgs}: let
  python = pkgs.python3.withPackages (ps: [ps.trafilatura]);
in
  pkgs.writeShellApplication {
    name = "read-aloud";
    runtimeInputs = with pkgs; [
      python
      mpv # playback + the IPC socket the pause/seek binds talk to
      ffmpeg # stitches TTS chunks into one file for --output
      wl-clipboard # primary selection and clipboard
      hyprland # focused-window lookup, for the browser-tab fallback
      fuzzel # the --menu control panel
      libnotify
    ];
    text = ''
      exec ${python}/bin/python3 ${./read-aloud.py} "$@"
    '';
  }
