# Neovim Config Notes

This config is based on NvChad and lazy.nvim.

## Quick Start

1. Open Neovim once.
2. Run `:Lazy sync`.
3. Restart Neovim.

## External Dependencies

- `git`
- `node` (for Copilot/NeoCodeium integrations)
- `python3`
- `ripgrep`
- `fd`
- `wl-paste` (Wayland image paste mapping)

## Key Workflows

- `<leader>e`: Oil file explorer (default and reliable)
- `<leader>E`: Snacks explorer fallback
- `<leader>qs`: restore session for current project
- `<leader>qS`: restore last session
- `<leader>qd`: stop session auto-save for current instance
- `<leader>uD`: toggle diagnostics in current buffer
- `:DiagnosticsToggle`: same as above

## AI / Vibe Coding

- NeoCodeium is enabled for inline suggestions.
- First-time auth: `:NeoCodeium auth`
- Insert mode:
  - `<A-f>` accept suggestion
  - `<A-]>` next suggestion
  - `<A-[>` previous suggestion
- Normal mode:
  - `<leader>ua` toggle NeoCodeium

## Guardrails

- Large file mode auto-enables for:
  - files larger than `1MB`, or
  - buffers larger than `20,000` lines
- In large file mode:
  - Tree-sitter is stopped
  - diagnostics are disabled for that buffer
  - foldmethod is set to `manual`
  - format-on-save is skipped

## Troubleshooting

- If startup/plugin state is odd: `:Lazy sync` then restart Neovim.
- If inline AI is noisy/slow: use `<leader>ua`.
- If diagnostics are distracting while writing notes: `<leader>uD`.
