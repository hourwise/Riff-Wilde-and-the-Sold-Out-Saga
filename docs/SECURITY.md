# Security Policy

## Repo Security Checklist

- [x] Create private GitHub repo.
- [x] Add `.gitignore` before first commit.
- [x] Add `docs/ASSET_REGISTER.md` before importing any external assets.
- [x] Add `docs/SECURITY.md`.
- [ ] Add `docs/CONTRIBUTING.md` even while solo.
- [x] Do not store secrets in code.
- [x] Do not add online accounts, payments, analytics, or telemetry in prototype.
- [ ] Enable GitHub 2FA.
- [ ] Enable secret scanning/push protection where available.
- [ ] Enable Dependabot alerts where available.
- [ ] Use pull requests for agent-generated work, even if reviewing your own PR.
- [x] Keep all downloaded asset ZIP files outside the repo unless licence permits redistribution.

## Local Machine Security

- Use a password manager.
- Use unique passwords for GitHub, Itch, Steamworks, and AI tools.
- Enable 2FA everywhere.
- Keep commercial assets in a separate local folder outside the repo.
- Do not let coding agents read unrelated personal/business folders.
- Open the project folder only, not your full user directory, when using AI coding tools.

## Secrets Policy

- **Never** commit API keys, tokens, or credentials.
- Firebase API keys and project IDs must be stored in a local config file (`user://firebase.cfg`) or environment variables, **not** in source code.
- Use `docs/firebase_config_template.md` for documenting required config keys without exposing values.
- The `.gitignore` must exclude any local config files containing secrets.
