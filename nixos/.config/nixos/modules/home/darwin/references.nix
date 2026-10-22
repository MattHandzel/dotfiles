# references: every 15 minutes, link what reached Matt since the last pass (every Gmail message, every Beeper
# chat's day, pages he read for 45 s+, new meeting notes, new or changed captures and resource notes) to the
# projects, areas and resources it is about: one line each in projects/<p>/_references.md, areas/<a>/_references.md
# or a marked block at the end of a resource note (links and one-line summaries only; the text stays in the
# lifelog). Captures also get related:/project:/tags in their frontmatter. Unsure matches are proposed in the
# "## References" block of today's daily note, which the shutdown ritual reads. A line Matt deletes is learned as
# a rejection on the next pass. Matt, 2026-10-21: "whenever I get an email, the email automatically gets linked to
# any project, person, resource, other type, or data object that I have in my second brain ... the same system
# ... can do the same thing for captures as well".
#
# Reads the lifelog store by id cursor; uses the local brain-search daemon (woken if needed) and one Haiku call per
# unsure item (capped per pass). The script is referenced by its vault path, so edits apply on the next tick.
# Code: ~/Obsidian/Main/scripts/references/. Doc: areas/second-brain/references.md
{
  config,
  pkgs,
  ...
}: let
  home = config.home.homeDirectory;
in {
  launchd.agents.references = {
    enable = true;
    config = {
      ProgramArguments = ["${pkgs.python3}/bin/python3" "-I" "${home}/Obsidian/Main/scripts/references/refs.py" "tick"];
      StartInterval = 900;
      RunAtLoad = true;
      ProcessType = "Background";
      Nice = 10;
      # claude (Haiku adjudication), the brain-search daemon launcher under ~/Projects/SecondBrainSearch/bin
      EnvironmentVariables.PATH = "${home}/.local/bin:/etc/profiles/per-user/${config.home.username}/bin:${home}/.nix-profile/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin";
      StandardOutPath = "${home}/.local/state/references/launchd.log";
      StandardErrorPath = "${home}/.local/state/references/launchd.log";
    };
  };
}
