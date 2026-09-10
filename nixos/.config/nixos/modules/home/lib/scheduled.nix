# One scheduled-job declaration -> systemd user units on Linux, a launchd agent
# on macOS.
#
# WHY THIS EXISTS
# ---------------
# ~15 Home Manager modules here each hand-write a `systemd.user.service` plus a
# matching `systemd.user.timer` (and sometimes a `.path` watcher). None of that
# exists on macOS, where the equivalent is a single launchd agent plist. Rather
# than fork every module, each one declares WHAT it runs and WHEN, and this
# helper emits the right units for the platform it is being evaluated on.
#
# EQUIVALENCE ON LINUX IS THE HARD REQUIREMENT
# --------------------------------------------
# The Linux output must stay byte-for-byte what the hand-written units produced,
# so every knob those units used is a parameter here (including the escape
# hatches `unitExtra` / `serviceExtra` / `timerExtra`). Nothing is silently
# normalised, and `%h`/`%t` are left verbatim on Linux for systemd to expand —
# they are only expanded by this helper on darwin, where nothing expands them.
#
# THE MAPPING
# -----------
#   Type=oneshot + timer          -> StartInterval / StartCalendarInterval
#   OnCalendar "*:0/15"           -> everySeconds = 900   (given explicitly by
#                                    the caller; OnCalendar is NOT parsed here,
#                                    because a half-right calendar parser in Nix
#                                    is worse than an explicit number)
#   OnBootSec/OnUnitActiveSec     -> StartInterval + RunAtLoad
#   Persistent=true               -> implicit (launchd runs a missed StartCalendarInterval
#                                    job at next load)
#   RandomizedDelaySec            -> no launchd equivalent; the caller's script
#                                    jitters itself if it matters
#   Restart=on-failure            -> KeepAlive.SuccessfulExit = false
#   RestartSec                    -> ThrottleInterval
#   PathChanged=                  -> WatchPaths
#   ConditionPathExists=          -> guard inside the script (callers do this)
#   After=network-online.target   -> nothing; launchd has no ordering, callers retry
#
# A LaunchAgent starts with an essentially EMPTY environment — no PATH at all —
# so `path` (or `linuxPathEntries`/`darwinPathEntries`) is effectively mandatory
# for anything that shells out.
#
# `isDarwin` is passed in EXPLICITLY rather than read off
# `pkgs.stdenv.hostPlatform`. This helper decides the top-level attribute NAMES
# of the config it returns (`systemd.user.*` vs `launchd.agents.*`), and the
# module system has to read those names while it is still working out
# `_module.args` — i.e. before `pkgs` exists. Deriving the platform from `pkgs`
# there is an infinite recursion. Call sites pass `host == "mac"`, and `host` is
# a specialArg, which is available at that stage by construction.
{
  lib,
  pkgs,
  config,
  isDarwin,
}: let
  home = config.home.homeDirectory;

  # systemd expands these itself; launchd does not, so do it here.
  expand = s:
    if isDarwin
    then
      builtins.replaceStrings
      ["%h" "%t"]
      [home "${home}/.cache"]
      s
    else s;

  expandList = map expand;

  # systemd's ExecStart parser understands shell-style quoting, so quoting only
  # the arguments that need it keeps the generated unit readable while
  # preserving argv semantics exactly (a message with spaces stays ONE argv).
  safeArg = a: builtins.match "[a-zA-Z0-9_.,:/=@%+-]+" a != null;
  quoteArg = a:
    if safeArg a
    then a
    else lib.escapeShellArg a;
  execStartOf = command: lib.concatMapStringsSep " " quoteArg (expandList command);

  mkPath = entries: pkgs': lib.concatStringsSep ":" ((map (p: "${p}/bin") pkgs') ++ entries);
in {
  scheduled = {
    name,
    description,
    # argv list; element 0 must be an absolute path (a store path in practice).
    command,
    # ── schedule (Linux) ──────────────────────────────────────────────────
    onCalendar ? null,
    onBootSec ? null,
    onUnitActiveSec ? null,
    persistent ? null,
    randomizedDelaySec ? null,
    # Some existing timers name their unit explicitly and some rely on the
    # implicit <name>.service; both are reproduced faithfully.
    timerUnit ? null,
    timerDescription ? null,
    # ── schedule (darwin) ─────────────────────────────────────────────────
    everySeconds ? null,
    startCalendarInterval ? null,
    # ── shape ─────────────────────────────────────────────────────────────
    watchPaths ? [],
    # Some existing .path units are named differently from the service they
    # trigger; keep those names so no unit is silently renamed.
    pathsName ? null,
    pathsDescription ? null,
    pathsExtra ? {},
    keepAlive ? false,
    restart ? null,
    restartSec ? null,
    runAtLoad ? null,
    oneshot ? true,
    workingDirectory ? null,
    # PATH and logging are declared PER PLATFORM on purpose. A LaunchAgent has
    # no PATH and no journal, so `path`/`logFile` (the darwin side) are close to
    # mandatory there — but adding either to a systemd user unit that does not
    # have one today would CHANGE that unit, and Linux equivalence is the gate
    # this whole refactor has to pass. So the Linux side is opt-in and spelled
    # out separately, and only the modules that really do set Environment= or
    # StandardOutput=append: today pass it.
    path ? [], # darwin PATH (packages)
    darwinPathEntries ? ["/usr/bin" "/bin" "/usr/sbin" "/sbin"],
    logFile ? null, # darwin StandardOutPath/StandardErrorPath
    linuxPathPackages ? [],
    linuxPathEntries ? [],
    linuxLogFile ? null,
    environment ? {},
    after ? [],
    wants ? [],
    partOf ? [],
    install ? null,
    unitExtra ? {},
    serviceExtra ? {},
    timerExtra ? {},
    launchdExtra ? {},
  }: let
    linuxPath = mkPath linuxPathEntries linuxPathPackages;
    darwinPath = mkPath darwinPathEntries path;

    hasSchedule =
      onCalendar
      != null
      || onBootSec != null
      || onUnitActiveSec != null;

    # ── Linux ────────────────────────────────────────────────────────────
    linuxService =
      {
        Unit =
          {Description = description;}
          // lib.optionalAttrs (after != []) {After = after;}
          // lib.optionalAttrs (wants != []) {Wants = wants;}
          // lib.optionalAttrs (partOf != []) {PartOf = partOf;}
          // unitExtra;
        Service =
          lib.optionalAttrs oneshot {Type = "oneshot";}
          // {ExecStart = execStartOf command;}
          // lib.optionalAttrs (workingDirectory != null) {WorkingDirectory = workingDirectory;}
          // lib.optionalAttrs (linuxPathPackages != [] || linuxPathEntries != [] || environment != {}) {
            Environment =
              lib.optional (linuxPathPackages != [] || linuxPathEntries != []) "PATH=${linuxPath}"
              ++ lib.mapAttrsToList (k: v: "${k}=${v}") environment;
          }
          // lib.optionalAttrs (linuxLogFile != null) {
            StandardOutput = "append:${linuxLogFile}";
            StandardError = "append:${linuxLogFile}";
          }
          // lib.optionalAttrs (restart != null) {Restart = restart;}
          // lib.optionalAttrs (restartSec != null) {RestartSec = restartSec;}
          // serviceExtra;
      }
      // lib.optionalAttrs (install != null) {Install = install;};

    linuxTimer = {
      Unit.Description =
        if timerDescription != null
        then timerDescription
        else "Timer for ${name}";
      Timer =
        lib.optionalAttrs (onCalendar != null) {OnCalendar = onCalendar;}
        // lib.optionalAttrs (onBootSec != null) {OnBootSec = onBootSec;}
        // lib.optionalAttrs (onUnitActiveSec != null) {OnUnitActiveSec = onUnitActiveSec;}
        // lib.optionalAttrs (persistent != null) {Persistent = persistent;}
        // lib.optionalAttrs (randomizedDelaySec != null) {RandomizedDelaySec = randomizedDelaySec;}
        // lib.optionalAttrs (timerUnit != null) {Unit = timerUnit;}
        // timerExtra;
      Install.WantedBy = ["timers.target"];
    };

    linuxWatcher = {
      Unit.Description =
        if pathsDescription != null
        then pathsDescription
        else "Watch paths for ${name}";
      Path =
        {
          PathChanged = watchPaths;
          Unit = "${name}.service";
        }
        // pathsExtra;
      Install.WantedBy = ["paths.target"];
    };

    # ── darwin ───────────────────────────────────────────────────────────
    darwinAgent =
      {
        Label = "org.nix-community.home.${name}";
        ProgramArguments = expandList command;
        ProcessType = "Background";
        EnvironmentVariables = {PATH = darwinPath;} // environment;
        RunAtLoad =
          if runAtLoad != null
          then runAtLoad
          # A long-running agent must start at load; a timer-driven oneshot with
          # an interval should also fire once so a fresh boot is not a dead slot.
          else (!oneshot || onBootSec != null);
      }
      // lib.optionalAttrs (everySeconds != null) {StartInterval = everySeconds;}
      // lib.optionalAttrs (startCalendarInterval != null) {StartCalendarInterval = startCalendarInterval;}
      // lib.optionalAttrs (watchPaths != []) {WatchPaths = expandList watchPaths;}
      // lib.optionalAttrs (keepAlive || restart != null) {
        KeepAlive =
          if restart == "always"
          then true
          else {SuccessfulExit = false;};
      }
      // lib.optionalAttrs (restartSec != null) {ThrottleInterval = restartSec;}
      // lib.optionalAttrs (workingDirectory != null) {WorkingDirectory = expand workingDirectory;}
      // lib.optionalAttrs (logFile != null) {
        StandardOutPath = expand logFile;
        StandardErrorPath = expand logFile;
      }
      // launchdExtra;
  in
    if isDarwin
    then {
      launchd.agents.${name} = {
        enable = true;
        config = darwinAgent;
      };
    }
    else {
      # `//` merges SHALLOWLY, so these must be combined one level down — at
      # services/timers/paths, which are distinct keys. Written as three
      # separate `systemd.user.*` attrsets joined with `//`, each one replaces
      # the whole `systemd` attribute of the one before it and the service
      # silently disappears wherever a timer or a path watcher is also declared.
      systemd.user =
        {
          services.${name} = linuxService;
        }
        // lib.optionalAttrs hasSchedule {
          timers.${name} = linuxTimer;
        }
        // lib.optionalAttrs (watchPaths != []) {
          paths.${
            if pathsName != null
            then pathsName
            else name
          } =
            linuxWatcher;
        };
    };
}
