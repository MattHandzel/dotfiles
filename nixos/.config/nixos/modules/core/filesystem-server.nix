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
# WHAT YOU GET (MAT-565 + the two follow-up asks "open in nvim" / "explore folders"):
#   • FILES open in a styled viewer: markdown renders to HTML (incl. inline IMAGES — MAT-1091: both
#     Obsidian `![[img.png]]` embeds and standard `![](path.png)` resolve to served URLs and display);
#     any other text/code shows in a readable code block. Every viewer has an "✎ Edit in nvim" button
#     and a "raw" link. Append `?raw=1` to get the unstyled bytes (what the viewer fetches under the hood).
#   • DIRECTORIES open in a styled browser: click folders to descend, click files to view, and
#     every file row has its own "✎ nvim" link. Append `?json=1` for the raw JSON listing.
#   • "✎ Edit in nvim" emits a `nvim://matts-server/<abs-path>` link. The laptop handler
#     (modules/home/nvim-url-handler.nix) opens it in nvim — the local syncthing copy if present,
#     else over SSH to this server. That handler is the ONE piece that needs the laptop rebuilt.
#   • images/PDF render inline; other binaries download.
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
# NOTE: the markdown/directory rendering is 100% CLIENT-SIDE (a static, vendored HTML+JS shell that
# fetches `?raw=1`/`?json=1`); the server stays static-file-only (no app code, no exec), so the
# secret-deny + scoped-root rules still gate every single byte the browser can fetch.
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
  nvimHost  = "matts-server";              # host embedded in nvim:// links (the laptop handler ssh's here)

  # The ONLY filesystem subtrees served. Add a dir here to widen access (keep it narrow). These cover
  # the vault notes + repo files that Linear `file://` links point at. `rootDirs` (no trailing slash)
  # is what gets bind-mounted into nginx's namespace; `roots` (trailing slash) builds nginx prefixes.
  rootDirs = [ "/home/matth/Obsidian" "/home/matth/Projects" ];
  roots    = map (d: d + "/") rootDirs;

  # nginx `location` prefix blocks for the allowed roots. `root /;` makes the URL path map 1:1 to the
  # real filesystem path (URI /home/matth/Obsidian/x → file /home/matth/Obsidian/x). Plain prefix
  # (NOT `^~`) so the regex blocks below (secret-deny, viewer, browser) still get a chance to match
  # first. A directory hit here (no trailing slash) 301-redirects to add the slash, which then matches
  # the directory-browser regex below.
  rootLocations = lib.concatMapStrings (r: ''
    location ${r} {
      root /;
    }
  '') roots;

  # Extensions treated as text and shown in the viewer's code block (notes, code, configs, logs…).
  # Markdown (.md/.markdown) is handled separately (rendered to HTML by the viewer); this is for
  # everything else that should display, not download. Served as text/plain when fetched with `?raw=1`.
  textExts = "txt|text|org|rst|adoc|log|conf|cfg|ini|toml|nix|sh|bash|zsh|fish|py|rb|pl|lua|vim|el|js|mjs|cjs|jsx|ts|tsx|json|ya?ml|csv|tsv|sql|c|h|cc|cpp|hpp|rs|go|java|kt|php|css|scss|sass|html?|xml|svg|env-sample|gitignore-sample";

  # ── Unified viewer/browser ─────────────────────────────────────────────────────────────────────
  # ONE self-contained HTML+JS shell that handles BOTH a file and a directory, decided client-side
  # from the URL (a directory URL ends in `/`). nginx serves this shell for:
  #   • a directory request without `?json` (the shell then fetches `?json=1` → JSON autoindex), and
  #   • a markdown/text file request without `?raw` (the shell then fetches `?raw=1` → the bytes).
  # Rendering is client-side with a VENDORED marked.js (no external network at view time → works
  # offline on the tailnet, zero CDN trust). The server itself only ever serves static bytes / the
  # JSON listing, so the secret-deny + scoped-root rules gate everything the shell can request.
  #
  # "✎ Edit in nvim" links are `nvim://matts-server/<abs-path>`; the laptop's nvim:// handler opens
  # them (local copy if synced, else SSH). encodeURI keeps the path slashes but escapes spaces.
  fsview = pkgs.writeText "fsview.html" ''
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
      header { position: sticky; top: 0; z-index: 5; padding: 8px 16px; font: 12px/1.4 ui-monospace, SFMono-Regular, Menlo, monospace; background: rgba(127,127,127,.10); border-bottom: 1px solid rgba(127,127,127,.25); backdrop-filter: blur(6px); display: flex; gap: 12px; align-items: center; justify-content: space-between; }
      header .crumbs { overflow-wrap: anywhere; }
      header a { color: inherit; opacity: .75; text-decoration: none; }
      header a:hover { opacity: 1; text-decoration: underline; }
      header .actions { display: flex; gap: 12px; white-space: nowrap; }
      header .nvim { opacity: 1; font-weight: 600; color: #1a7f37; }
      @media (prefers-color-scheme: dark) { header .nvim { color: #3fb950; } }
      main { max-width: 980px; margin: 0 auto; padding: 20px 16px 96px; }
      /* directory listing */
      .listing { list-style: none; margin: 0; padding: 0; font: 14px/1.9 ui-monospace, SFMono-Regular, Menlo, monospace; }
      .listing li { display: flex; align-items: center; gap: 10px; padding: 2px 6px; border-radius: 6px; }
      .listing li:hover { background: rgba(127,127,127,.10); }
      .listing .name { flex: 1; overflow-wrap: anywhere; }
      .listing .name a { color: #0969da; text-decoration: none; }
      @media (prefers-color-scheme: dark) { .listing .name a { color: #4493f8; } }
      .listing .name a:hover { text-decoration: underline; }
      .listing .dir a { font-weight: 600; }
      .listing .meta { opacity: .55; font-size: 12px; white-space: nowrap; }
      .listing .nv { font-size: 12px; opacity: .6; color: #1a7f37; text-decoration: none; white-space: nowrap; }
      @media (prefers-color-scheme: dark) { .listing .nv { color: #3fb950; } }
      .listing li:hover .nv { opacity: 1; }
      .listing .nv:hover { text-decoration: underline; }
      /* rendered markdown */
      .md h1, .md h2 { border-bottom: 1px solid rgba(127,127,127,.25); padding-bottom: .3em; }
      .md h1, .md h2, .md h3, .md h4 { margin-top: 1.4em; line-height: 1.25; }
      .md a { color: #0969da; } @media (prefers-color-scheme: dark) { .md a { color: #4493f8; } }
      .md code { background: rgba(127,127,127,.18); padding: .2em .4em; border-radius: 6px; font: .88em ui-monospace, SFMono-Regular, Menlo, monospace; }
      .md pre { background: rgba(127,127,127,.12); padding: 14px 16px; border-radius: 8px; overflow: auto; }
      .md pre code { background: none; padding: 0; }
      .md blockquote { margin: 0; padding: 0 1em; border-left: .25em solid rgba(127,127,127,.35); opacity: .85; }
      .md table { border-collapse: collapse; } .md th, .md td { border: 1px solid rgba(127,127,127,.35); padding: 6px 13px; }
      .md img { max-width: 100%; } .md hr { border: none; border-top: 1px solid rgba(127,127,127,.25); }
      /* raw code block (non-markdown text files) */
      pre.code { background: rgba(127,127,127,.10); padding: 16px; border-radius: 8px; overflow: auto; font: 13px/1.55 ui-monospace, SFMono-Regular, Menlo, monospace; }
      .err { color: #cf222e; } @media (prefers-color-scheme: dark) { .err { color: #ff7b72; } }
    </style>
    <script>${builtins.readFile ./marked.min.js}</script>
    </head>
    <body>
    <header>
      <span class="crumbs" id="crumbs"></span>
      <span class="actions" id="actions"></span>
    </header>
    <main><div id="c">Loading…</div></main>
    <script>
      (function () {
        var HOST = "${nvimHost}";
        var pathRaw = location.pathname;                 // %-encoded, exactly as the server sees it
        var path = decodeURIComponent(pathRaw);          // human-readable
        var isDir = pathRaw.charAt(pathRaw.length - 1) === "/";
        var c = document.getElementById("c");

        function esc(s) { return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }
        function nvimHref(absPath) { return "nvim://" + HOST + encodeURI(absPath); }

        // breadcrumb: each path segment links to its directory
        (function () {
          var segs = path.replace(/\/+$/, "").split("/");          // ["", "home", "matth", ...]
          var acc = "", html = "";
          for (var i = 0; i < segs.length; i++) {
            if (segs[i] === "") continue;
            acc += "/" + segs[i];
            var isLast = i === segs.length - 1;
            var href = encodeURI(acc) + (isLast && !isDir ? "" : "/");
            html += ' / <a href="' + href + '">' + esc(segs[i]) + "</a>";
          }
          document.getElementById("crumbs").innerHTML = html || " /";
        })();

        document.title = path.replace(/\/+$/, "").split("/").pop() || "filesystem";

        var actions = document.getElementById("actions");
        if (isDir) {
          actions.innerHTML = '<a href="?json=1">json</a>';
          fetch(pathRaw + "?json=1")
            .then(function (r) { if (!r.ok) throw new Error(r.status + " " + r.statusText); return r.json(); })
            .then(renderDir)
            .catch(function (e) { c.innerHTML = '<p class="err">Failed to list directory: ' + esc(e.message) + "</p>"; });
        } else {
          actions.innerHTML =
            '<a class="nvim" href="' + nvimHref(path) + '">✎ Edit in nvim</a>' +
            '<a href="?raw=1">raw</a>';
          fetch(pathRaw + "?raw=1")
            .then(function (r) { if (!r.ok) throw new Error(r.status + " " + r.statusText); return r.text(); })
            .then(renderFile)
            .catch(function (e) { c.innerHTML = '<p class="err">Failed to load source: ' + esc(e.message) + "</p>"; });
        }

        // Image extensions we resolve to served URLs (MAT-1091).
        var IMG_RE = /\.(png|jpe?g|gif|svg|webp|bmp|avif|ico)$/i;
        // Vault root for the served file (the dir holding `.obsidian/`): /home/matth/Obsidian/<Vault>.
        // Obsidian's "shortest path" link format resolves a bare `![[name.png]]` vault-wide, and the
        // default attachment folder is `assets/`, so we probe the vault root's `assets/` as a fallback.
        function vaultRootOf(absDir) {
          var m = absDir.match(/^(\/home\/matth\/Obsidian\/[^/]+)(\/|$)/);
          return m ? m[1] : null;
        }

        // Turn Obsidian embeds `![[target|size]]` into standard markdown `![](target)` BEFORE marked
        // runs, so marked emits a normal <img>. `|size`/`|alt` hints are dropped (sizing is best-effort
        // via CSS max-width). Non-image wikilink embeds (`![[Some Note]]`) are left as plain text — out
        // of scope. Spaces in the target are %-encoded so marked treats the whole thing as one URL.
        function preprocessEmbeds(md) {
          return md.replace(/!\[\[([^\]]+?)\]\]/g, function (whole, inner) {
            var target = inner.split("|")[0].trim();   // drop |width / |alt
            if (!IMG_RE.test(target)) return whole;     // not an image embed → leave untouched
            return "![](" + target.replace(/ /g, "%20") + ")";
          });
        }

        // Resolve one image reference (the raw `src` marked produced) to a served absolute URL, given
        // the served file's directory `absDir` and a basename→absPath index built from autoindex JSON.
        // Returns null if it cannot be resolved (caller leaves the original src so it visibly 404s).
        function resolveImg(src, absDir, index) {
          var raw = src;
          try { raw = decodeURIComponent(src); } catch (e) {}
          if (/^(https?:)?\/\//i.test(raw) || /^data:/i.test(raw)) return src;   // external URL / data → pass through
          if (raw.charAt(0) === "/") {                                            // absolute filesystem path
            if (/^\/home\/matth\/(Obsidian|Projects)\//.test(raw)) return encodeURI(raw);
            return null;                                                          // outside served roots
          }
          raw = raw.replace(/^\.\//, "");
          if (raw.indexOf("/") !== -1) {                                          // has a path → resolve vs file dir
            return encodeURI(absDir + "/" + raw);
          }
          var hit = index[raw.toLowerCase()];                                     // bare basename → index lookup
          return hit ? encodeURI(hit) : null;
        }

        // Build a basename→absPath index by listing (via the existing `?json=1` autoindex) the served
        // file's own directory, its immediate subdirectories (one level), and the vault `assets/` dir.
        // This covers: same-folder attachments, project subfolders (e.g. `mockups/`), and the default
        // vault attachment folder — every place a bare-basename embed realistically resolves to. Reuses
        // the server's existing endpoint, so it stays 100% client-side and within the scoped roots.
        function buildImageIndex(absDir, cb) {
          var index = {};
          function add(dirAbs, entries) {
            entries.forEach(function (e) {
              if (e.type !== "directory" && IMG_RE.test(e.name)) {
                var key = e.name.toLowerCase();
                if (!(key in index)) index[key] = dirAbs + "/" + e.name;   // first wins (closest dir)
              }
            });
          }
          function listJson(dirAbs) {
            return fetch(encodeURI(dirAbs) + "/?json=1")
              .then(function (r) { return r.ok ? r.json() : []; })
              .catch(function () { return []; });
          }
          listJson(absDir).then(function (entries) {
            add(absDir, entries);
            var subdirs = entries.filter(function (e) { return e.type === "directory"; })
                                 .map(function (e) { return absDir + "/" + e.name; });
            var vaultRoot = vaultRootOf(absDir);
            var assetsDir = vaultRoot ? vaultRoot + "/assets" : null;
            if (assetsDir && subdirs.indexOf(assetsDir) === -1 && assetsDir !== absDir) subdirs.push(assetsDir);
            Promise.all(subdirs.map(function (d) {
              return listJson(d).then(function (es) { add(d, es); });
            })).then(function () { cb(index); });
          });
        }

        function renderFile(text) {
          if (/\.(md|markdown)$/i.test(path)) {
            c.className = "md";
            c.innerHTML = marked.parse(preprocessEmbeds(text));
            var imgs = c.querySelectorAll("img");
            if (!imgs.length) return;
            var absDir = path.replace(/\/+$/, "").replace(/\/[^/]*$/, "");   // dir holding the served file
            buildImageIndex(absDir, function (index) {
              for (var i = 0; i < imgs.length; i++) {
                var orig = imgs[i].getAttribute("src") || "";
                var resolved = resolveImg(orig, absDir, index);
                if (resolved) imgs[i].setAttribute("src", resolved);
                imgs[i].setAttribute("loading", "lazy");
              }
            });
          } else {
            c.className = "";
            c.innerHTML = '<pre class="code">' + esc(text) + "</pre>";
          }
        }

        function renderDir(entries) {
          // nginx autoindex JSON: [{name,type:"directory"|"file",mtime,size}, ...]; dirs first, by name
          entries.sort(function (a, b) {
            var ad = a.type === "directory", bd = b.type === "directory";
            if (ad !== bd) return ad ? -1 : 1;
            return a.name.toLowerCase() < b.name.toLowerCase() ? -1 : 1;
          });
          var ul = document.createElement("ul");
          ul.className = "listing";
          // up-link (unless already at a served root top)
          if (!/^\/home\/matth\/(Obsidian|Projects)\/?$/.test(path.replace(/\/+$/, "") + "/")) {
            var up = document.createElement("li");
            up.innerHTML = '<span class="name dir"><a href="../">../</a></span>';
            ul.appendChild(up);
          }
          entries.forEach(function (e) {
            var li = document.createElement("li");
            var isd = e.type === "directory";
            var enc = encodeURIComponent(e.name) + (isd ? "/" : "");
            var size = (!isd && typeof e.size === "number") ? human(e.size) : "";
            var nv = isd ? "" : '<a class="nv" href="' + nvimHref(path + e.name) + '">✎ nvim</a>';
            li.innerHTML =
              '<span class="name ' + (isd ? "dir" : "file") + '"><a href="' + enc + '">' + esc(e.name) + (isd ? "/" : "") + "</a></span>" +
              '<span class="meta">' + size + "</span>" + nv;
            ul.appendChild(li);
          });
          c.className = "";
          c.innerHTML = "";
          c.appendChild(ul);
        }

        function human(n) {
          if (n < 1024) return n + " B";
          var u = ["KB", "MB", "GB", "TB"], i = -1;
          do { n /= 1024; i++; } while (n >= 1024 && i < u.length - 1);
          return n.toFixed(1) + " " + u[i];
        }
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

  # ── 2. nginx vhost: read-only, tailnet-only, scoped, secret-scrubbed, rendered ────────────────────
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
      autoindex on;            # directory listings (JSON form is consumed by the browser shell)
      autoindex_format json;
      autoindex_exact_size off;
      autoindex_localtime on;

      # --- Unified viewer/browser shell (internal; reached via the rewrites below). Self-contained. ---
      location = /__fsview {
        internal;
        alias ${fsview};
        default_type text/html;
        charset utf-8;
        add_header X-Content-Type-Options nosniff;
      }

      # --- LAYER 4: hard-deny secrets + dotfiles FIRST (nginx: first matching regex wins) ---
      location ~ /\.                                                  { deny all; }   # .env .git .ssh .claude .aws .netrc …
      location ~* (^|/)(id_rsa|id_ed25519|id_ecdsa|known_hosts|authorized_keys|credentials|secrets?)([._/-]|$) { deny all; }
      location ~* \.(pem|key|crt|cer|p12|pfx|ppk|kdbx|jks|keystore|asc|gpg)$  { deny all; }

      # --- DIRECTORIES (URL ends in `/`): bare → styled browser shell; `?json=1` → JSON autoindex. ---
      location ~* ^/home/matth/(Obsidian|Projects)(/.*)?/$ {
        root /;
        charset utf-8;
        default_type application/json;
        if ($arg_json = "") { rewrite ^ /__fsview last; }
      }

      # --- MARKDOWN + TEXT/CODE FILES: bare → styled viewer; `?raw=1` → the raw bytes (text/plain).
      #     `if`-with-rewrite is the documented-safe subset of `if`. ---
      location ~* ^/home/matth/(Obsidian|Projects)/.*\.(md|markdown|${textExts})$ {
        root /;
        charset utf-8;
        types { }                       # clear the mime map → serve raw fetches as plain text
        default_type text/plain;
        add_header Content-Disposition inline;
        add_header X-Content-Type-Options nosniff;
        if ($arg_raw = "") { rewrite ^ /__fsview last; }
      }

      # --- LAYER 3: the only served roots (images/PDF render, binaries download; a slash-less
      #     directory 301-redirects to add the trailing slash → matches the browser regex above) ---
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
