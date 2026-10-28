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
   - git access to github.com/clevyr/jeb with an SSH key that is in the macOS keychain, so background fetches never prompt. Check with `ssh -T git@github.com` (a greeting message means it works). If it fails, the user needs to add a key to GitHub and run `ssh-add --apple-use-keychain <key>`.
2. If the clone is not there yet, clone `git@github.com:clevyr/jeb.git` into `~/jeb`, or where the user says. If it already exists, use it.
3. Explain briefly what `./install` changes, then run it from the clone with no flags (`--dev` is only for the repo owner):
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
