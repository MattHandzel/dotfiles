# good-life: is my life going the way I want, lever by lever? (sleep, exercise, rest without guilt,
# meditation, friends, eating, clean room, outside)
#
# WHY (Matt, 2026-11-16): "I have this consistent failure mode where I forget that things bring me joy
# or happiness... I'd like this dashboard so that when I'm not feeling very good... I know things that I
# can work on." Root note: ~/Obsidian/Main/areas/good-life/good-life.md (levers + evidence), page:
# areas/good-life/dashboard.html (Raycast "Good Life").
#
# Twice a day: extract signals from new or changed daily notes (headless Claude, haiku), then rebuild
# data/status.json, the "Right now" block and the page. Exits non-zero on a failed pass (error collector).
# Expected output row: scripts/bugs/expected-output.tsv (good-life). Doc: areas/second-brain/good-life-dashboard.md
{config, pkgs, ...}: {
  launchd.agents.good-life = {
    enable = true;
    config = {
      ProgramArguments = ["${pkgs.python3}/bin/python3" "-I" "${config.home.homeDirectory}/Obsidian/Main/scripts/good-life/good_life.py" "run"];
      StartCalendarInterval = [
        {
          Hour = 8;
          Minute = 5;
        }
        {
          Hour = 21;
          Minute = 40;
        }
      ];
      ProcessType = "Background";
      Nice = 10;
      # claude (headless extraction) lives in ~/.local/bin or the nix profile.
      EnvironmentVariables.PATH = "${config.home.homeDirectory}/.local/bin:${config.home.homeDirectory}/.nix-profile/bin:/etc/profiles/per-user/${config.home.username}/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin";
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/good-life.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/good-life.log";
    };
  };
}
