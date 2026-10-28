---
name: jeb-install
description: Install Jeb (the Claude Code mod plus the macOS desktop app) from github.com/clevyr/jeb on a teammate's Mac. Use when the user asks to install Jeb or pastes the README's install prompt.
---

# Install Jeb

Walk the user through installing Jeb from the clevyr/jeb repo. Be brief and plain; explain any failure in simple words.

## Steps

1. Check the requirements and tell the user how to fix any that is missing:
   - macOS.
   - Xcode Command Line Tools: `xcode-select -p` must succeed. Fix: `xcode-select --install`, then wait for it to finish.
   - `swiftc`: `xcrun --find swiftc` must succeed (comes with the Command Line Tools).
   - `/usr/bin/python3` (comes with the Command Line Tools).
   - Claude Code: `claude` must be on PATH.
   - git: `git --version` must succeed.
   - The GitHub CLI signed in with access to the repo: `gh auth status` must succeed and `gh repo view clevyr/jeb` must work. Fix: `brew install gh`, then `gh auth login`.
   - git must reach the repo without prompting, because updates fetch in the background. Run `gh auth setup-git` (safe to repeat).
2. If the clone is not there yet, clone the latest release into `~/jeb`, or where the user says:
   `tag=$(gh release view --repo clevyr/jeb --json tagName --jq .tagName)` then
   `git clone --branch "$tag" https://github.com/clevyr/jeb.git ~/jeb`.
   A "detached HEAD" note is expected. It must be a git clone, not a downloaded archive, because updates use git. If the clone already exists, use it as it is.
3. Explain briefly what `./install` changes, then run it from the clone with no flags (`--dev` is only for people working on Jeb itself):
   - builds the desktop app from source and installs it in `~/Applications`;
   - adds LaunchAgents in `~/Library/LaunchAgents` that keep it running and following releases;
   - adds the clone's `mod/` folder to `CLAUDE_CODE_PLUGIN_DIRS` in `~/.claude/settings.json`, after saving a backup.
   The install takes a minute or two.
4. If it fails, read the error and explain the fix in plain words. Never edit the repo's code to make it pass.
5. On success run `desktop/jebctl doctor` from the clone and explain any `FIX` line. Then tell the user to start a NEW Claude Code session so the plugin loads, and that the desktop fills in once a session has run.

## Rules

- Do not take screenshots of the desktop or describe what it draws; the user should see it themselves.
- Do not change settings beyond what `./install` does.
- To remove Jeb, the user runs `./uninstall` from the clone.
