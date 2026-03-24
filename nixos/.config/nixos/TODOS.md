# Memory Leak Investigation TODOs

Date: 2026-03-06
Host: `desktop` (assumed from active session)

## What we know so far

- RAM is not exhausted, but swap usage is high and sticky.
- A Java process tied to `ltex-ls` (Neovim Mason) is consuming significant memory.
- Largest swap holders include `java`, `node`, `beepertexts`, `thunderbird`, and browser processes.
- 5-minute sampling did not show a large monotonic leak, so we need longer/targeted profiling.
- Verified: zram compression is active (`zstd`) and currently effective (about `1.5G` data compressed into about `368M`).
- 60-minute monitor completed (`/tmp/memory-leak-report-20260306-112906`): no monotonic RSS leak >= 5 MiB for all-sample processes.
- 30-minute performance monitor completed (`/tmp/perf-monitor-20260306-113527.log`):
  - Severe stall window during `nix` build and toolchain steps (`xz`, `patchelf`, `cc1plus`, `ld`, `strip`).
  - Counter deltas: `pgmajfault +7,542,895`, `pswpin +12,803,621`, `pswpout +11,962,210`.
  - `vmstat` peaks: `wa=78`, `si=235152`, `so=183812`.

## Priority 0: Immediate containment

- [ ] Restart the `ltex-ls` Java process and measure delta:
  - Before/after: `ps -eo pid,comm,rss,vsz,etimes,args --sort=-rss | head -n 60`
  - Before/after: `for p in /proc/[0-9]*; do awk '/^(Name|VmRSS|VmSwap):/' \"$p/status\" 2>/dev/null | paste -sd ' ' -; done | rg 'java|ltex|VmSwap'`
- [ ] Close unused editors/browsers/Thunderbird windows to force process reclamation and verify swap drops.
- [ ] Run `sudo swapoff -a && sudo swapon -a` once during idle time to confirm how much swap is stale vs actively needed.

## Priority 1: Fix `ltex-ls` Java memory growth

- [x] Identify exact launcher args used by Mason `ltex-ls`:
  - Capture full command: `ps -fp <java_pid>`
  - Confirm jar/classpath in `~/.local/share/nvim/mason/packages/ltex-ls/...`
- [x] Set explicit JVM limits for `ltex-ls`:
  - Target baseline: `-Xms128m -Xmx512m` (or lower if stable).
  - Add `-XX:+UseG1GC` if not already present.
  - Implemented in `~/dotfiles/nvim/.config/nvim/lua/configs/lspconfig.lua` (requires Neovim restart).
- [ ] Disable unneeded LTEX features:
  - Large dictionary checks, heavy language packs, or broad workspace scanning.
  - Restrict to active file/workspace scope only.
- [ ] Ensure no duplicate `ltex-ls` servers per Neovim instance:
  - Validate LSP client attach behavior.
  - Enforce singleton per workspace root.
- [ ] Pin/update `ltex-ls` to a known stable version and retest memory trend.
- [ ] Add a safe auto-restart policy for runaway `ltex-ls`:
  - If RSS > threshold (e.g. 700 MiB) for 10+ minutes, restart LSP server.

## Priority 2: Validate other suspected offenders

- [x] `node` processes: map each PID to project/service and cap memory where possible (`--max-old-space-size`).
  - Mapped major trees:
    - `notetaker` tree (~`690 MiB` RSS, ~`1.3 GiB` swap): `nvim` + `ltex-ls` + Copilot node + codex/gemini descendants.
    - tmux root tree (~`438 MiB` RSS, ~`2.1 GiB` swap): separate `nvim`/`ltex-ls` + codex/gemini workloads.
- [ ] `beepertexts`: verify version and known memory issues; update if newer stable build exists.
- [ ] `thunderbird`: disable heavy extensions and check if memory plateaus after restart.
- [ ] Browser processes (`zen/chromium`): compare memory use with/without extension load.
- [ ] `netdata`: verify collector/plugin footprint; disable collectors not used.

## Priority 3: Add reliable leak detection (longer window)

- [x] Create a 60-minute sampler (1/min) capturing:
  - `free -m`
  - top RSS
  - `/proc/<pid>/status` (`VmRSS`, `VmSwap`) for tracked PIDs
- [x] Compute monotonic and slope-based growth:
  - Flag processes with >5 MiB/10 min sustained growth.
  - Separate “sawtooth GC behavior” from true monotonic leaks.
- [x] Persist report to `/tmp/mem-leak-report-<timestamp>.md`.
- [x] Added monitor script: `memory-leak-monitor` (from `modules/home/scripts/scripts/memory-leak-monitor.sh`).
- [x] Script smoke-tested: `memory-leak-monitor 2 1` generated `/tmp/memory-leak-report-20260306-112026`.
- [x] Fixed monitor reliability issues:
  - Correct sample-count math for arbitrary interval (`samples = minutes * 60 / interval`).
  - Robust process parsing (tab-separated extraction) to avoid malformed rows when command names contain spaces.
- [ ] Compare idle vs active workload sessions (editing, browsing, mail open) with the fixed monitor script.

## Priority 4: NixOS-level tuning

- [x] Confirm current memory tuning in Nix config:
  - `vm.swappiness`
  - zram size/algorithm
  - swapfile priority
- [x] Tune swap behavior if interactive performance degrades:
  - Keep low swappiness, but verify zram/swapfile priority order.
  - Updated `modules/core/system.nix`: `vm.swappiness = 5`, `zramSwap.algorithm = "zstd"`, `zramSwap.priority = 100`.
  - Applied immediately for current boot via `sudo sysctl -w vm.swappiness=5`.
  - Persistent activation still requires next `nixos-rebuild switch` that includes this repo state.
- [x] Repo validation: `nix flake check` passes after changes.
- [ ] Add optional observability tools:
  - `smem`, `btop`, and a small script exporting top `VmSwap` holders.
- [ ] Add a periodic watchdog service (systemd user) to log high-memory PIDs.

## Definition of done

- [ ] `ltex-ls` stays below agreed limit during normal editing sessions.
- [ ] Total swap does not continually increase during 60+ minutes of normal use.
- [ ] No process shows sustained monotonic RSS growth after fixes.
- [ ] Results documented with before/after metrics and exact commands used.
