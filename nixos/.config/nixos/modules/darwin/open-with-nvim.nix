# "Open in Neovim" as a real macOS default-application.
#
# LaunchServices will only ever hand a document to an APP BUNDLE. `nvim` is a
# plain binary, so it can never be a default handler on its own, and neither can
# kitty (kitty opens a terminal, not the file you double-clicked). This module
# generates a one-purpose bundle that adapts between the two: it receives the
# `odoc` AppleEvent and runs `nvim <file>` inside a kitty window.
#
# Why generated at activation instead of built in Nix: the only tool that can
# compile an AppleScript droplet is /usr/bin/osacompile, which lives outside the
# store and cannot be used inside a sandboxed derivation. The SOURCE is
# declarative (below); the compile step is idempotent and re-runs on every
# switch, so the bundle always matches this file.
#
# postActivation, not a custom `neovimDroplet` name: nix-darwin silently ignores
# activationScripts entries it does not know, so from the day this module was
# written until 2026-09-20 it never ran even once and the bundle on disk was the
# hand-made 2026-09-10 one. Same trap as dia-policy.nix and system-defaults.nix.
#
# The default-app BINDING is set with `duti` below rather than through Finder's
# "Do you want all documents with the extension .md to open with Neovim?" sheet,
# which cannot be answered from a config file.
#
# obsidian:// links (2026-11-02, Matt: "I DONT WANT IT TO OPEN UP .md files in
# obsidian. only in neovim."): the bundle also owns the obsidian:// URL scheme,
# so every link the vault's tools print (Work Test, bug board, recall, triage,
# morning-focus, built-for-you) opens the note in nvim. obsidian-url-nvim
# resolves vault/file/path to a file and, when an nvim already has that file
# open, brings kitty forward instead of opening a second copy. Obsidian claims
# the scheme back each time it launches (Electron setAsDefaultProtocolClient),
# so the obsidian-url-guard agent watches the LaunchServices prefs and sets it
# back to Neovim whenever it changes. duti writes the same
# com.apple.LaunchServices/com.apple.launchservices.secure LSHandlers entry the
# sheet would, so the binding survives a reboot and is re-asserted every switch.
{
  pkgs,
  username,
  ...
}: let
  nvimBin = "/etc/profiles/per-user/${username}/bin/nvim";

  # obsidian://open?vault=V&file=F | ?path=/abs | obsidian://vault/V/F -> nvim
  urlHandler = pkgs.writeScript "obsidian-url-nvim" ''
    #!${pkgs.python3}/bin/python3
    import json, os, subprocess, sys, time
    from urllib.parse import urlparse, parse_qs, unquote

    HOME = os.path.expanduser("~")
    LOG = os.path.join(HOME, "Library/Logs/obsidian-url-nvim.log")
    NVIM = "${nvimBin}"

    def log(msg):
        with open(LOG, "a") as f:
            f.write(time.strftime("%Y-%m-%dT%H:%M:%S ") + msg + "\n")

    def vaults():
        try:
            cfg = json.load(open(os.path.join(HOME, "Library/Application Support/obsidian/obsidian.json")))
            return {os.path.basename(v["path"]): v["path"] for v in cfg.get("vaults", {}).values()}
        except Exception:
            return {}

    def resolve(url):
        u = urlparse(url)
        q = {k: v[0] for k, v in parse_qs(u.query).items()}
        vs = vaults()
        default_root = vs.get("Main") or os.path.join(HOME, "Obsidian/Main")
        if u.netloc == "vault":  # obsidian://vault/<vault>/<file>
            parts = unquote(u.path).lstrip("/").split("/", 1)
            q.setdefault("vault", parts[0])
            if len(parts) > 1:
                q.setdefault("file", parts[1])
        if q.get("path"):
            return q["path"].split("#")[0]
        name = q.get("vault")
        root = vs.get(name) or (os.path.join(HOME, "Obsidian", name) if name else default_root)
        f = q.get("file")
        if not f:
            return root
        f = f.split("#")[0].split("^")[0]
        for cand in (os.path.join(root, f), os.path.join(root, f + ".md")):
            if os.path.exists(cand):
                return cand
        # Bare note name: Obsidian resolves it anywhere in the vault.
        base = os.path.basename(f) + ("" if f.endswith(".md") else ".md")
        r = subprocess.run(["${pkgs.fd}/bin/fd", "--type", "f", "--fixed-strings", base, root],
                           capture_output=True, text=True)
        hits = [p for p in r.stdout.splitlines() if os.path.basename(p) == base]
        hits.sort(key=lambda p: ("/archive/" in p, len(p)))
        if hits:
            return hits[0]
        return os.path.join(root, f if f.endswith(".md") else f + ".md")

    def already_open(target):
        ps = subprocess.run(["/bin/ps", "-axo", "command="], capture_output=True, text=True).stdout
        return any("nvim" in line.split(" ", 1)[0] and target in line for line in ps.splitlines())

    url = sys.argv[1] if len(sys.argv) > 1 else ""
    target = resolve(url)
    if already_open(target):
        subprocess.run(["/usr/bin/open", "-a", "/Applications/kitty.app"])
        log(f"{url} -> {target} (already open, focused kitty)")
        sys.exit(0)
    d = target if os.path.isdir(target) else os.path.dirname(target)
    subprocess.run(["/usr/bin/open", "-na", "/Applications/kitty.app", "--args", "--single-instance",
                    "--instance-group=nvim", "--directory", d, "-e", NVIM, target])
    log(f"{url} -> {target}")
  '';

  # Keeps obsidian:// on Neovim. Only writes when the handler changed, so its
  # own write to the watched prefs file doesn't loop.
  urlGuard = pkgs.writeShellScript "obsidian-url-guard" ''
    DUTI=/opt/homebrew/bin/duti
    [ -x "$DUTI" ] || exit 0
    cur="$("$DUTI" -d obsidian 2>/dev/null || true)"
    if [ "$cur" != "com.matth.neovim" ]; then
      "$DUTI" -s com.matth.neovim obsidian
      echo "$(date '+%FT%T') obsidian:// was ''${cur:-unset}, set back to com.matth.neovim"
    fi
  '';

  droplet = pkgs.writeText "neovim-droplet.applescript" ''
    on open theFiles
        repeat with f in theFiles
            set p to POSIX path of (f as text)
            do shell script "/usr/bin/open -na /Applications/kitty.app --args --single-instance --instance-group=nvim --directory " & quoted form of (do shell script "dirname " & quoted form of p) & " -e ${nvimBin} " & quoted form of p
        end repeat
    end open

    on open location theURL
        do shell script "${urlHandler} " & quoted form of theURL & " >/dev/null 2>&1 &"
    end open location

    on run
        do shell script "/usr/bin/open -na /Applications/kitty.app --args --single-instance --instance-group=nvim -e ${nvimBin}"
    end run
  '';
in {
  system.activationScripts.postActivation.text = ''
    APP=/Applications/Neovim.app
    PB=/usr/libexec/PlistBuddy
    LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
    DUTI=/opt/homebrew/bin/duti

    # Compile to a staging path and swap in. A bare `rm -rf "$APP"` followed by a
    # failing osacompile would leave the machine with no Neovim handler at all.
    STAGE=$(/usr/bin/mktemp -d /tmp/neovim-droplet.XXXXXX)
    if /usr/bin/osacompile -o "$STAGE/Neovim.app" ${droplet}; then
      P="$STAGE/Neovim.app/Contents/Info.plist"
      "$PB" -c "Set :CFBundleIdentifier com.matth.neovim" "$P" 2>/dev/null \
        || "$PB" -c "Add :CFBundleIdentifier string com.matth.neovim" "$P"
      "$PB" -c "Set :CFBundleName Neovim" "$P" 2>/dev/null \
        || "$PB" -c "Add :CFBundleName string Neovim" "$P"
      "$PB" -c "Add :CFBundleDisplayName string Neovim" "$P" 2>/dev/null || true

      # Named types only, on purpose. Widening this to public.plain-text would
      # make Neovim the handler for every .txt/.log/.json on the machine.
      "$PB" -c "Delete :CFBundleDocumentTypes" "$P" 2>/dev/null || true
      "$PB" -c "Add :CFBundleDocumentTypes array" "$P"

      "$PB" -c "Add :CFBundleDocumentTypes:0 dict" "$P"
      "$PB" -c "Add :CFBundleDocumentTypes:0:CFBundleTypeName string Markdown document" "$P"
      "$PB" -c "Add :CFBundleDocumentTypes:0:CFBundleTypeRole string Editor" "$P"
      "$PB" -c "Add :CFBundleDocumentTypes:0:LSHandlerRank string Owner" "$P"
      "$PB" -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes array" "$P"
      "$PB" -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes:0 string net.daringfireball.markdown" "$P"
      "$PB" -c "Add :CFBundleDocumentTypes:0:CFBundleTypeExtensions array" "$P"
      "$PB" -c "Add :CFBundleDocumentTypes:0:CFBundleTypeExtensions:0 string md" "$P"
      "$PB" -c "Add :CFBundleDocumentTypes:0:CFBundleTypeExtensions:1 string markdown" "$P"
      "$PB" -c "Add :CFBundleDocumentTypes:0:CFBundleTypeExtensions:2 string mdx" "$P"

      # 2026-09-20: .csv was bound to Claude.app, and Finder's "Open With >
      # Other…" panel greys out any app that does not DECLARE the type, so there
      # was no way to reach nvim from Finder at all.
      "$PB" -c "Add :CFBundleDocumentTypes:1 dict" "$P"
      "$PB" -c "Add :CFBundleDocumentTypes:1:CFBundleTypeName string Comma-separated values" "$P"
      "$PB" -c "Add :CFBundleDocumentTypes:1:CFBundleTypeRole string Editor" "$P"
      "$PB" -c "Add :CFBundleDocumentTypes:1:LSHandlerRank string Alternate" "$P"
      "$PB" -c "Add :CFBundleDocumentTypes:1:LSItemContentTypes array" "$P"
      "$PB" -c "Add :CFBundleDocumentTypes:1:LSItemContentTypes:0 string public.comma-separated-values-text" "$P"
      "$PB" -c "Add :CFBundleDocumentTypes:1:CFBundleTypeExtensions array" "$P"
      "$PB" -c "Add :CFBundleDocumentTypes:1:CFBundleTypeExtensions:0 string csv" "$P"

      # obsidian:// links (see the header).
      "$PB" -c "Delete :CFBundleURLTypes" "$P" 2>/dev/null || true
      "$PB" -c "Add :CFBundleURLTypes array" "$P"
      "$PB" -c "Add :CFBundleURLTypes:0 dict" "$P"
      "$PB" -c "Add :CFBundleURLTypes:0:CFBundleURLName string Obsidian link" "$P"
      "$PB" -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" "$P"
      "$PB" -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string obsidian" "$P"

      # Ad-hoc signature: unsigned bundles get a fresh identity on every rebuild,
      # which would drop any TCC grant the bundle picks up later.
      /usr/bin/codesign --force --deep -s - "$STAGE/Neovim.app" >/dev/null 2>&1 || true

      rm -rf "$APP"
      /bin/mv "$STAGE/Neovim.app" "$APP"
      /usr/sbin/chown -R ${username} "$APP" || true
      "$LSREG" -f "$APP" || true
    else
      echo "open-with-nvim: osacompile failed, keeping the existing $APP" >&2
    fi
    rm -rf "$STAGE"

    # As ${username}: LSHandlers live in the USER's LaunchServices prefs, and
    # activation runs as root.
    # `sudo -u` alone talks to root's cfprefsd; `launchctl asuser` puts the call
    # in ${username}'s GUI session so it reaches the same prefs Finder reads.
    UID_M=$(/usr/bin/id -u ${username})
    if [ -x "$DUTI" ] && [ -n "$UID_M" ]; then
      /bin/launchctl asuser "$UID_M" /usr/bin/sudo -u ${username} \
        "$DUTI" -s com.matth.neovim public.comma-separated-values-text all || true
      /bin/launchctl asuser "$UID_M" /usr/bin/sudo -u ${username} \
        "$DUTI" -s com.matth.neovim net.daringfireball.markdown all || true
      /bin/launchctl asuser "$UID_M" /usr/bin/sudo -u ${username} \
        "$DUTI" -s com.matth.neovim obsidian || true
    fi
  '';

  launchd.user.agents.obsidian-url-guard.serviceConfig = {
    ProgramArguments = ["${urlGuard}"];
    RunAtLoad = true;
    WatchPaths = ["/Users/${username}/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist"];
    StartInterval = 900;
    StandardOutPath = "/Users/${username}/Library/Logs/obsidian-url-guard.log";
    StandardErrorPath = "/Users/${username}/Library/Logs/obsidian-url-guard.log";
  };
}
