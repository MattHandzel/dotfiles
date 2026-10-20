# Rabbithole: the treadmill reader/listener web app, kept running on the Mac.
#
# Serves ~/Projects/rabbithole on 127.0.0.1:8777 (stdlib HTTP server: the app,
# built lessons, link previews, and a one-at-a-time narration queue that runs
# Kokoro TTS locally). The phone reaches it over the tailnet through a
# persistent Tailscale Serve HTTPS proxy, https://matts-mac.tail01a272.ts.net
# (`tailscale serve --bg --https=443 http://127.0.0.1:8777`; the mic and Wake
# Lock need HTTPS). The older plain-HTTP forward http://matts-mac:8778
# (`--tcp 8778`) stays up, and page loads there redirect to the HTTPS address.
# Both serve configs live in tailscaled, not here.
#
# The runtime is the uv venv in ~/Projects/rabbithole/.venv (kokoro-onnx,
# onnxruntime from PyPI wheels), not a nix package -- same arrangement as
# brain-search.nix and kms-ingest.nix. ffmpeg (stitching) and poppler
# (pdftotext, PDF links) come from nixpkgs via runtimeInputs.
# Doc: ~/Obsidian/Main/areas/second-brain/rabbithole.md
{pkgs, ...}: let
  serve = pkgs.writeShellApplication {
    name = "rabbithole-serve";
    runtimeInputs = [pkgs.ffmpeg pkgs.poppler-utils];
    text = ''
      dir="$HOME/Projects/rabbithole"
      if [ ! -x "$dir/.venv/bin/python" ]; then
        echo "$(date -u +%FT%TZ) no venv at $dir/.venv; run 'uv sync' there" >&2
        sleep 300 # KeepAlive would otherwise respawn this every 10 s
        exit 1
      fi
      cd "$dir"
      exec "$dir/.venv/bin/python" -m rabbithole.server
    '';
  };
in {
  launchd.agents.rabbithole = {
    enable = true;
    config = {
      ProgramArguments = ["${serve}/bin/rabbithole-serve"];
      RunAtLoad = true;
      KeepAlive = true;
      EnvironmentVariables.RABBITHOLE_HTTPS_URL = "https://matts-mac.tail01a272.ts.net";
      StandardOutPath = "/Users/matth/Library/Logs/rabbithole.log";
      StandardErrorPath = "/Users/matth/Library/Logs/rabbithole.log";
    };
  };
}
