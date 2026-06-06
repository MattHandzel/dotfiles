# filesystem-server.nix — NixOS module (MAT-565). Read-only, tailnet-only web file server.
#
# Goal: open a file referenced in a Linear issue straight from the laptop. Linear issues carry
# `file:///home/matth/...` links; this maps them 1:1 to a URL you can paste in a browser:
#
#     file:///home/matth/Obsidian/Main/x.md  →  http://filesystem.matthandzel.com/home/matth/Obsidian/Main/x.md
#
# i.e. strip `file://` and prepend `http://filesystem.matthandzel.com`. The URL path IS the
# absolute filesystem path, so no mental translation is needed. Markdown renders as HTML;
# directories are browsable; everything else shows inline or downloads.
#
# ── SECURITY MODEL (this exposes filesystem paths, so it is deliberately conservative) ───────────
# Mirrors the proven, in-production pattern of `dashboard.server.matthandzel.com`
# (modules/core/exocortex-dashboard.nix §2b): a PRIVATE service reachable ONLY from Matt's tailnet,
# never the public internet. FIVE independent layers:
#   1. TAILNET-ONLY DNS — `filesystem.matthandzel.com` resolves to the server's tailnet IP
#      100.118.206.104 (a CGNAT 100.64/10 address, unroutable from the public internet). Provided
#      here declaratively via blocky customDNS (every tailnet device already uses blocky as its
#      resolver), so NO registrar change is required. A public A record is an optional add-on.
#   2. nginx ACL — `allow 100.64.0.0/10` (the whole Tailscale range) + loopback, `deny all` else.
#      So even a direct hit on the box's public IP with a spoofed Host header is refused.
#   3. SCOPED ROOTS — only the vault (/home/matth/Obsidian) and Projects (/home/matth/Projects) are
#      served. Everything else 404s. NOT all of $HOME (that would expose ~/.ssh, ~/.aws, tokens…).
#   4. SECRET + DOTFILE DENY — `.env`, `.git`, `.ssh`, `.claude`, private keys, credential files are
#      hard-denied even inside the allowed roots (repo dirs contain `.env.local`, `.git`, etc).
#   5. KERNEL NAMESPACE ISOLATION (the real fix for the v1 404s — see below) — the nginx systemd unit
#      runs with `ProtectHome=tmpfs`, so inside nginx's mount namespace ALL of /home is an empty
#      tmpfs; only the two roots are bind-mounted back in read-only. nginx physically CANNOT open any
#      path in /home other than Obsidian/ and Projects/, regardless of what the config or ACLs say.
# Plus: READ-ONLY (only GET/HEAD; no upload/delete/write). Transport is WireGuard-encrypted by
# Tailscale, so plain HTTP is fine and needs no cert — exactly like ntfy (:8124) and the dashboard.
#
# ── WHY v1 404'd (every link), and the fix ───────────────────────────────────────────────────────
# NixOS hardens `services.nginx` with `ProtectHome=yes` by default. That replaces /home with an
# EMPTY, mode-000 mount *inside nginx's namespace*, so the worker's open() of any vault/Projects file
# returned EACCES (logged as "Permission denied" → HTTP 403/404) even though the file's own perms +
# the traverse ACL were correct. A tmpfiles ACL alone could never fix it — the block was the mount
# namespace, not the inode perms. Fix: `ProtectHome=tmpfs` (traversable empty /home) + bind the two
# roots back read-only. This is strictly TIGHTER than the old ACL approach, so it doubles as layer 5.
#
# HOW IT IS WIRED IN: imported from modules/core/server.nix. This is a NixOS change → Matt reviews
# the diff and runs the staged safe-rebuild (scripts/nixos-safe-rebuild.sh). Tunables at the top.

{ config, lib, pkgs, ... }:

let
  tailnetIP = "100.118.206.104";          # this server's Tailscale IP (blocky / same as the dashboard)
  hosts     = [ "filesystem.matthandzel.com" "filesystem.server.matthandzel.com" ];

  # The ONLY filesystem subtrees served. Add a dir here to widen access (keep it narrow). These cover
  # the vault notes + repo files that Linear `file://` links point at. `rootDirs` (no trailing slash)
  # is what gets bind-mounted into nginx's namespace; `roots` (trailing slash) builds nginx prefixes.
  rootDirs = [ "/home/matth/Obsidian" "/home/matth/Projects" ];
  roots    = map (d: d + "/") rootDirs;

  # nginx `location` prefix blocks for the allowed roots. `root /;` makes the URL path map 1:1 to the
  # real filesystem path (URI /home/matth/Obsidian/x → file /home/matth/Obsidian/x). Plain prefix
  # (NOT `^~`) so the regex blocks below (secret-deny, inline-text) still get a chance to match first.
  rootLocations = lib.concatMapStrings (r: ''
    location ${r} {
      root /;
    }
  '') roots;

  # Extensions rendered inline as readable UTF-8 text (notes, code, configs, logs…). Markdown is
  # handled separately (rendered to HTML); this is for everything else that should show, not download.
  # `types { }` clears nginx's mime table for this location so EVERYTHING here serves as text/plain
  # (otherwise `.json`→application/json etc. make the browser download instead of show).
  textExts = "txt|text|org|rst|adoc|log|conf|cfg|ini|toml|nix|sh|bash|zsh|fish|py|rb|pl|lua|vim|el|js|mjs|cjs|jsx|ts|tsx|json|ya?ml|csv|tsv|sql|c|h|cc|cpp|hpp|rs|go|java|kt|php|css|scss|sass|html?|xml|svg|env-sample|gitignore-sample";

  # ── Markdown viewer ──────────────────────────────────────────────────────────────────────────────
  # A self-contained HTML shell that fetches the raw markdown (same URL + `?raw=1`) and renders it
  # client-side with a VENDORED marked.js (no external network at view time → works offline on the
  # tailnet, zero CDN trust). nginx serves this for `*.md` requests that lack `?raw`; the shell then
  # asks for `?raw=1` to get the source. Rendering is client-side so the server stays static-file-only
  # (no app code, minimal attack surface) and the secret-deny rules still gate every byte fetched.
  mdViewer = pkgs.writeText "fsview.html" ''
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>filesystem.matthandzel.com</title>
    <style>
      :root { color-scheme: light dark; }
      body { margin: 0; background: #fff; color: #1f2328; font: 16px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif; }
      @media (prefers-color-scheme: dark) { body { background: #0d1117; color: #e6edf3; } }
      header { position: sticky; top: 0; padding: 8px 16px; font: 12px/1.4 ui-monospace, SFMono-Regular, Menlo, monospace; background: rgba(127,127,127,.10); border-bottom: 1px solid rgba(127,127,127,.25); backdrop-filter: blur(6px); display: flex; gap: 12px; justify-content: space-between; }
      header a { color: inherit; opacity: .7; text-decoration: none; }
      header a:hover { opacity: 1; text-decoration: underline; }
      main { max-width: 860px; margin: 0 auto; padding: 24px 16px 96px; }
      .md h1, .md h2 { border-bottom: 1px solid rgba(127,127,127,.25); padding-bottom: .3em; }
      .md h1, .md h2, .md h3, .md h4 { margin-top: 1.4em; line-height: 1.25; }
      .md a { color: #0969da; } @media (prefers-color-scheme: dark) { .md a { color: #4493f8; } }
      .md code { background: rgba(127,127,127,.18); padding: .2em .4em; border-radius: 6px; font: .88em ui-monospace, SFMono-Regular, Menlo, monospace; }
      .md pre { background: rgba(127,127,127,.12); padding: 14px 16px; border-radius: 8px; overflow: auto; }
      .md pre code { background: none; padding: 0; }
      .md blockquote { margin: 0; padding: 0 1em; border-left: .25em solid rgba(127,127,127,.35); opacity: .85; }
      .md table { border-collapse: collapse; } .md th, .md td { border: 1px solid rgba(127,127,127,.35); padding: 6px 13px; }
      .md img { max-width: 100%; } .md hr { border: none; border-top: 1px solid rgba(127,127,127,.25); }
    </style>
    <script>${builtins.readFile ./marked.min.js}</script>
    </head>
    <body>
    <header><span id="path"></span><a id="rawlink" href="?raw=1">raw</a></header>
    <main><div id="c" class="md">Loading…</div></main>
    <script>
      (function () {
        var p = location.pathname;
        var name = decodeURIComponent(p.split("/").pop());
        document.getElementById("path").textContent = decodeURIComponent(p);
        document.title = name;
        fetch(p + "?raw=1")
          .then(function (r) { if (!r.ok) throw new Error(r.status + " " + r.statusText); return r.text(); })
          .then(function (t) { document.getElementById("c").innerHTML = marked.parse(t); })
          .catch(function (e) { document.getElementById("c").textContent = "Failed to load source: " + e.message; });
      })();
    </script>
    </body>
    </html>
  '';
in
{
  # ── 1. DNS: resolve the hostnames to the tailnet IP for every tailnet device (no registrar step) ──
  # Merges into the blocky settings declared in focus-dns.nix (NixOS deep-merges attrsets; customDNS
  # is set nowhere else, so there is no conflict). If blocky is ever down, devices fall back to public
  # DNS — add a public A record (filesystem.matthandzel.com → 100.118.206.104) if you want that path.
  services.blocky.settings.customDNS = {
    customTTL = "1h";
    mapping = lib.genAttrs hosts (_: tailnetIP);
  };

  # ── 1b. KERNEL NAMESPACE ISOLATION — the real fix for the v1 404s, and security layer 5 ───────────
  # NixOS sets `ProtectHome=yes` on nginx by default → /home is an empty, mode-000 mount inside
  # nginx's namespace, so the worker's open() of any served file returns EACCES (the v1 404/403s).
  # Switch to `ProtectHome=tmpfs` (an empty but *traversable* tmpfs over /home, /root, /run/user) and
  # bind the two roots back in READ-ONLY. Net effect: nginx's view of /home contains ONLY Obsidian/ and
  # Projects/ — nothing else exists for it to open, no matter what the config/ACL allow. Verified:
  # ProtectHome=tmpfs+bind → vault/Projects files readable, dirs listable, ~/.ssh & ~/.aws absent.
  systemd.services.nginx.serviceConfig = {
    ProtectHome = lib.mkForce "tmpfs";
    BindReadOnlyPaths = rootDirs;
  };

  # ── 2. nginx vhost: read-only, tailnet-only, scoped, secret-scrubbed, markdown-rendered ───────────
  # Bind 0.0.0.0:80 (robust to tailscaled boot-order) and let the ACL below enforce tailnet-only,
  # identical to the exocortex dashboard. Routed by Host header, so it coexists with the other :80
  # vhosts. Plain HTTP: transport is already WireGuard-encrypted over the tailnet.
  services.nginx.virtualHosts.${builtins.head hosts} = {
    serverAliases = builtins.tail hosts;
    listen = [ { addr = "0.0.0.0"; port = 80; } ];

    # Server-level directives (inherited by every location): the tailnet ACL is the security boundary.
    extraConfig = ''
      # --- LAYER 2: tailnet-only access control (defends the public :80 against a spoofed Host) ---
      allow 100.64.0.0/10;   # Tailscale CGNAT range — every tailnet device
      allow 127.0.0.1;       # the server itself
      deny all;              # nobody else

      # --- READ-ONLY: refuse anything that could mutate the filesystem (server-level method guard) ---
      if ($request_method !~ ^(GET|HEAD)$) { return 405; }

      charset utf-8;
      autoindex on;            # browsable directory listings (folder exploration)
      autoindex_exact_size off;
      autoindex_localtime on;

      # --- Markdown viewer shell (internal; reached via rewrite below). Self-contained HTML. ---
      location = /__fsview {
        internal;
        alias ${mdViewer};
        default_type text/html;
        charset utf-8;
        add_header X-Content-Type-Options nosniff;
      }

      # --- LAYER 4: hard-deny secrets + dotfiles FIRST (nginx: first matching regex wins) ---
      location ~ /\.                                                  { deny all; }   # .env .git .ssh .claude .aws .netrc …
      location ~* (^|/)(id_rsa|id_ed25519|id_ecdsa|known_hosts|authorized_keys|credentials|secrets?)([._/-]|$) { deny all; }
      location ~* \.(pem|key|crt|cer|p12|pfx|ppk|kdbx|jks|keystore|asc|gpg)$  { deny all; }

      # --- Markdown → rendered HTML. Bare URL renders; `?raw=1` returns the source (fetched by the
      #     viewer). `if`-with-rewrite is the documented-safe subset of `if`. ---
      location ~* ^/home/matth/(Obsidian|Projects)/.*\.(md|markdown)$ {
        root /;
        charset utf-8;
        types { }                       # raw markdown source served as plain text
        default_type text/plain;
        add_header Content-Disposition inline;
        add_header X-Content-Type-Options nosniff;
        if ($arg_raw = "") { rewrite ^ /__fsview last; }
      }

      # --- text/code → inline UTF-8 plain text (scoped to the allowed roots) ---
      location ~* ^/home/matth/(Obsidian|Projects)/.*\.(${textExts})$ {
        root /;
        types { }                       # clear mime map → serve everything here as text/plain
        default_type text/plain;
        charset utf-8;
        add_header Content-Disposition inline;
        add_header X-Content-Type-Options nosniff;
      }

      # --- LAYER 3: the only served roots (images/PDF render, binaries download, dirs list) ---
      ${rootLocations}

      # Apex: a one-line hint. Anything outside the allowed roots 404s (fail-closed).
      location = / {
        default_type text/plain;
        return 200 "filesystem.matthandzel.com (read-only, tailnet-only) — browse /home/matth/Obsidian/ or /home/matth/Projects/";
      }
      location / { return 404; }
    '';
  };
}
