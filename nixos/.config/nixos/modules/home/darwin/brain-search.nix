# brain-search on the Mac: keeps the local vault index current.
#
# The home server (services.second-brain-search, hosts/server) used to run
# bge-m3 + bge-reranker-v2-m3 on CUDA behind matts-server:47772. Since
# 2026-09-23 the whole pipeline runs here:
#   - this agent: every 10 min, an incremental pass of local_index.py (stat
#     every note, re-embed only notes whose content changed, drop deleted ones).
#     A pass with no changes exits in ~1 s without loading torch.
#   - the query daemon (local_server.py on 127.0.0.1:47772) is NOT an agent:
#     `brain-search` starts it on demand via bin/brain-search-serve and it exits
#     after 5 idle minutes. When it happens to be up, the indexer borrows its
#     loaded model (POST /embed) instead of loading a second copy.
#
# The runtime is the uv venv in ~/Projects/SecondBrainSearch/.venv (torch with
# MPS from PyPI wheels), not a nix package — same arrangement as kms-ingest.nix.
# Index: ~/.local/share/brain-search/index.sqlite. Doc:
# ~/Obsidian/Main/areas/second-brain/second-brain-search.md
{pkgs, ...}: let
  indexRun = pkgs.writeShellApplication {
    name = "brain-search-index-run";
    text = ''
      dir="$HOME/Projects/SecondBrainSearch"
      if [ ! -x "$dir/.venv/bin/python" ]; then
        echo "$(date -u +%FT%TZ) no venv at $dir/.venv; run 'uv sync' there" >&2
        exit 0
      fi
      cd "$dir"
      # Two threads, no tokenizer pool: an incremental pass should never take
      # more than a sliver of one core.
      export BRAIN_SEARCH_THREADS=2
      exec "$dir/.venv/bin/python" "$dir/local_index.py"
    '';
  };
in {
  launchd.agents.brain-search-index = {
    enable = true;
    config = {
      ProgramArguments = ["${indexRun}/bin/brain-search-index-run"];
      RunAtLoad = true;
      StartInterval = 600;
      # Background = E-cores, throttled CPU and I/O; plus nice and low-priority I/O.
      ProcessType = "Background";
      LowPriorityIO = true;
      LowPriorityBackgroundIO = true;
      Nice = 15;
      StandardOutPath = "/Users/matth/Library/Logs/brain-search-index.log";
      StandardErrorPath = "/Users/matth/Library/Logs/brain-search-index.log";
    };
  };
}
