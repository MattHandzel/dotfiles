#### Project Information

Project: NixOS Dotfiles (Laptop Focus)
State: Functional monolithic flake. Integrated Home Manager.
Key Issues:
- Secrets are plaintext/imperative.
- Absolute paths hardcoded.
- Repo hygiene (backups/caches in tree).
- Security (Passwordless sudo, permissive firewall).

#### Global Preferences

Preference: Use Gemini API for intelligence.
Preference: Avoid extensive bolding and italics in text output.

#### Roadmap (Prioritized)

Directive: Focus on the following improvements:
1. Adopt sops-nix for secrets.
2. Fix absolute path hardcoding.
3. Clean up repo artifacts (.cache, .git.back).
4. Package Python services (remove runtime pip install).
5. Harden security (sudo, firewall).

#### Development Preferences

Preference: Format code with 'alejandra' (2-space indent).
Preference: Validate with 'nix flake check' and 'nixos-rebuild test'.
Preference: Commit messages should be concise and imperative.