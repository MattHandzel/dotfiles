# filesystem-server.nix — NixOS module (MAT-565). Read-only, tailnet-only web file server.
#
# Goal: open a file referenced in a Linear issue straight from the laptop. Linear issues carry
# `file:///home/matth/...` links; this maps them 1:1 to a URL you can paste in a browser:
#
#     file:///home/matth/Obsidian/Main/x.md  →  http://filesystem.matthandzel.com/home/matth/Obsidian/Main/x.md
#
# i.e. strip `file://` and prepend `http://filesystem.matthandzel.com`. The URL path IS the
# absolute filesystem path, so no mental translation is needed.
#
# ── SECURITY MODEL (this exposes filesystem paths, so it is deliberately conservative) ───────────
# Mirrors the proven, in-production pattern of `dashboard.server.matthandzel.com`
# (modules/core/exocortex-dashboard.nix §2b): a PRIVATE service reachable ONLY from Matt's tailnet,
# never the public internet. Four independent layers:
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
# Plus: READ-ONLY (only GET/HEAD; no upload/delete/write). Transport is WireGuard-encrypted by
# Tailscale, so plain HTTP is fine and needs no cert — exactly like ntfy (:8124) and the dashboard.
#
# HOW IT IS WIRED IN: imported from modules/core/server.nix. This is a NixOS change → Matt reviews
# the diff and runs the staged safe-rebuild (scripts/nixos-safe-rebuild.sh). Tunables at the top.

{ config, lib, pkgs, ... }:

let
  tailnetIP = "100.118.206.104";          # this server's Tailscale IP (blocky / same as the dashboard)
  hosts     = [ "filesystem.matthandzel.com" "filesystem.server.matthandzel.com" ];

  # The ONLY filesystem subtrees served. Add a root here to widen access (keep it narrow).
  # These cover the vault notes + repo files that Linear `file://` links point at.
  roots = [ "/home/matth/Obsidian/" "/home/matth/Projects/" ];

  # nginx `location` prefix blocks for the allowed roots. `root /;` makes the URL path map 1:1 to the
  # real filesystem path (URI /home/matth/Obsidian/x → file /home/matth/Obsidian/x). Plain prefix
  # (NOT `^~`) so the regex blocks below (secret-deny, inline-text) still get a chance to match first.
  rootLocations = lib.concatMapStrings (r: ''
    location ${r} {
      root /;
    }
  '') roots;

  # Extensions rendered inline as readable UTF-8 text (markdown, notes, code, configs, logs…).
  # `types { }` clears nginx's mime table for this location so EVERYTHING here serves as text/plain
  # (otherwise `.md`→text/markdown and `.json`→application/json make browsers download instead of show).
  textExts = "md|markdown|txt|text|org|rst|adoc|log|conf|cfg|ini|toml|nix|sh|bash|zsh|fish|py|rb|pl|lua|vim|el|js|mjs|cjs|jsx|ts|tsx|json|ya?ml|csv|tsv|sql|c|h|cc|cpp|hpp|rs|go|java|kt|php|css|scss|sass|html?|xml|svg|env-sample|gitignore-sample";
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

  # ── 1b. Let nginx TRAVERSE (only) into the home dir ──────────────────────────────────────────────
  # nginx runs as user `nginx`, but /home/matth is mode 0700 — without this nginx cannot even descend
  # into the (already world-readable, 0755/0644) roots, so every request would 403. Grant the nginx
  # daemon execute/traverse ONLY (no `r` → it still cannot LIST ~, just pass through to known paths).
  # This is the minimum capability; content access stays governed by the roots' own perms + the nginx
  # ACL/deny rules. Merges with the tmpfiles rules in focus-dns.nix (NixOS concatenates list options).
  systemd.tmpfiles.rules = [
    "a+ /home/matth - - - - u:nginx:x"
  ];

  # ── 2. nginx vhost: read-only, tailnet-only, scoped, secret-scrubbed ─────────────────────────────
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
      autoindex on;            # browsable directory listings
      autoindex_exact_size off;
      autoindex_localtime on;

      # --- LAYER 4: hard-deny secrets + dotfiles FIRST (nginx: first matching regex wins) ---
      location ~ /\.                                                  { deny all; }   # .env .git .ssh .claude .aws .netrc …
      location ~* (^|/)(id_rsa|id_ed25519|id_ecdsa|known_hosts|authorized_keys|credentials|secrets?)([._/-]|$) { deny all; }
      location ~* \.(pem|key|crt|cer|p12|pfx|ppk|kdbx|jks|keystore|asc|gpg)$  { deny all; }

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
