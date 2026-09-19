# `wispr-learn`: teach Wispr Flow the corrections made in Neovim.
#
# Wispr Flow's own "learn from edits" only sees edits inside the Accessibility
# snapshot it takes of the target text field for a short window after it pastes.
# In kitty/Neovim that snapshot is unreliable and anything edited later (or after
# a paste from the clipboard) is never seen, so a fix like "UVM" -> "Neovim" is
# not learned (2026-09-17 Oops). wispr-learn.py aligns recent dictations
# (flow.sqlite History) against the saved buffer and writes each bounded word
# substitution into the Dictionary table exactly as Wispr's learner would
# (source=user_edits, observedSource=<what it heard>); Wispr pushes those rows to
# the server on its next dictionary sync. ~/dotfiles/nvim/.config/nvim/plugin/
# wispr-learn.lua runs it on BufWritePost for prose buffers (:WisprLearn to run
# by hand, :WisprLearnWord to add one phrase).
{pkgs, ...}: let
  wisprLearn = pkgs.writeShellApplication {
    name = "wispr-learn";
    runtimeInputs = [pkgs.python3];
    text = ''
      exec python3 ${./wispr-learn.py} "$@"
    '';
  };
in {
  home.packages = [wisprLearn];
  # The Neovim plugin calls it here, so it works before `rebuild` puts it on PATH.
  home.file.".local/bin/wispr-learn".source = "${wisprLearn}/bin/wispr-learn";
}
