# newsletter-page: publish the unlisted newsletter page whenever the vault note or its images change.
#
# Matt, 2026-10-11: "yes it should be automatic". launchd watches the issue folder and assets/imgs;
# scripts/newsletter/publish-private-page.sh rebuilds the page data from the note, and commits and pushes
# only when something changed (so a save that changes nothing deploys nothing). Vercel then deploys the
# private website repo's main. Script lives in the vault, so edits apply without a rebuild.
# Doc: areas/second-brain/newsletter-private-page.md
{
  config,
  pkgs,
  ...
}: let
  home = config.home.homeDirectory;
  path = "/etc/profiles/per-user/${config.home.username}/bin:${home}/.nix-profile/bin:/run/current-system/sw/bin:/opt/homebrew/bin:${pkgs.coreutils}/bin:/usr/bin:/bin:/usr/sbin:/sbin";
  log = "${home}/.local/state/newsletter-page.log";
in {
  launchd.agents.newsletter-page = {
    enable = true;
    config = {
      ProgramArguments = ["${pkgs.bash}/bin/bash" "${home}/Obsidian/Main/scripts/newsletter/publish-private-page.sh"];
      WatchPaths = [
        "${home}/Obsidian/Main/areas/personal-brand/personal-newsletter"
        "${home}/Obsidian/Main/assets/imgs"
      ];
      ThrottleInterval = 60;
      ProcessType = "Background";
      EnvironmentVariables.PATH = path;
      StandardOutPath = log;
      StandardErrorPath = log;
    };
  };
}
