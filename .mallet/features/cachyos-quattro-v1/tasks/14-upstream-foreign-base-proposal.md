# Task: upstream-foreign-base-proposal
Status: deferred (phase 2 roadmap, 2026-10-21)
Deps: 13

## Goal
Draft a proposal for an Omarchy "foreign base" opt-out and open it upstream once the user approves the text.

## Steps
1. Write `docs/upstream-proposal.md`: problem statement with the concrete conflicts from `docs/conflicts.md` (file paths and package lines); the precedents already in upstream (the Apple Silicon branch in `omarchy-settings` `.INSTALL` that keeps distro identity; the T2 skip and machine-wide marker in migration `1789325478`); a minimal proposal — one flag (e.g. `/etc/omarchy/foreign-base`) that makes `.INSTALL` skip the identity `cp -f` lines, ships the mkinitcpio and limine-entry-tool drop-ins inert, and lets migrations that change boot or pacman config return early; and a link to this project as a working reference.
2. Check `gh issue list -R basecamp/omarchy --search "CachyOS OR foreign base OR derivative" --state all` and `gh api repos/basecamp/omarchy/discussions` (if enabled) for prior discussion; cite or join it instead of duplicating.
3. Show the draft to the user; after explicit approval, open it as an issue or discussion on basecamp/omarchy with `gh issue create -R basecamp/omarchy --title "<title>" --body-file docs/upstream-proposal.md`.
4. Link the upstream URL from `README.md` and `state.md`.

## Notes
Opening the upstream issue is outward-facing and needs explicit user approval of the final text.
