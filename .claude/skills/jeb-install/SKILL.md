---
name: jeb-install
description: Set up Jeb (the Claude Code mod plus the macOS desktop app) from github.com/clevyr/jeb on a user's Mac: install, update, repair or remove it. Use when the user asks to install, update, repair or remove Jeb, or pastes the README's prompt.
---

# Set up Jeb

Set up Jeb from the clevyr/jeb release (install, update, repair or remove), doing every step yourself. Most users are not developers: never ask them to run a command. A new user's Mac needs no Xcode, Command Line Tools, git or Homebrew. Keep progress updates to one short line per step, and explain a failure in simple words.

## What to do

Decide from the Mac and the request, after steps 1 and 2 below:

- No `~/.jeb/current`, no `~/.jeb/repo` and no `~/jeb`: Jeb is not installed; run Steps 2 and 3.
- `~/.jeb/current` resolves, or an old clone exists at `~/.jeb/repo` or `~/jeb`: Jeb is already installed, so do not reinstall unless the user asked for that. Follow the jeb-update skill (`~/.jeb/current/.claude/skills/jeb-update/SKILL.md`), then the doctor skill (`~/.jeb/current/.claude/skills/jeb-doctor/SKILL.md`). `~/.jeb/bin/jebctl install` does both for you; an old clone is replaced with `~/.jeb/bin/jebctl install --replace-clone`.
- The user asked to repair: follow the doctor skill and apply its fixes.
- The user asked to remove Jeb: run `~/.jeb/bin/jebctl uninstall --remove-files`. If the installed release is older than v1.7.0, run `~/.jeb/current/python/bin/python3 -I ~/.jeb/current/uninstall --remove-files` instead.

## Steps

jebctl is the only tool a new user needs: it fetches the newest signed release, verifies its signature and hashes against the pinned signers (the keys listed in desktop/release-signers; later releases may replace the list, always through a release signed by a key already pinned), unpacks it and runs the bundle's own install.

1. Architecture: `sysctl -n hw.optional.arm64` prints 1 for `arm64`, otherwise use `x86_64`.
2. Get jebctl: `mkdir -p ~/.jeb/bin && curl -fsSL https://github.com/clevyr/jeb/releases/latest/download/jebctl-macos -o ~/.jeb/bin/jebctl.new && chmod +x ~/.jeb/bin/jebctl.new && mv -f ~/.jeb/bin/jebctl.new ~/.jeb/bin/jebctl` (the rename matters: overwriting a signed binary in place can get it killed). If it fails, the Mac has no network to github.com, or the repository is not public yet (tell the user and stop).
3. Run `~/.jeb/bin/jebctl install` (no flags). It takes a minute or two and prints one short line per step. It:
   - finds the newest release, downloads its manifest, signature and this Mac's zip, and refuses anything whose signature or SHA-256 does not check out;
   - unpacks it into `~/.jeb/versions/<tag>` and runs the bundle's own install, which installs the desktop app in `~/Applications` (prebuilt; nothing is compiled), adds LaunchAgents in `~/Library/LaunchAgents` that keep it running and following releases, points `~/.jeb/current` at this version, registers the mod with Claude Code (`claude plugin marketplace add ~/.jeb/current`, then `claude plugin install jeb@jeb`; a leftover Jeb entry in `CLAUDE_CODE_PLUGIN_DIRS` in `~/.claude/settings.json` is removed after saving a backup), and links `jebctl` into `~/.local/bin`;
   - runs the health check at the end.
   Tell the user in one line what it set up once it finishes.
4. If it fails, read the error and fix it yourself where these steps cover it, then run it again; otherwise explain the problem in plain words. Never edit the release's code to make it pass. "could not reach GitHub" means the network, VPN or proxy must allow github.com and release-assets.githubusercontent.com; "HTTP 404" means the release is missing, so tell the user. An older install (a git clone in `~/.jeb/repo` or `~/jeb`) is replaced by `jebctl install --replace-clone`, which moves the clone aside itself; do not move it by hand.
5. Read the install's final lines: it runs the doctor itself and tells the user to start a new Claude Code session. Work through its "To fix them" list with the doctor skill (`~/.jeb/current/.claude/skills/jeb-doctor/SKILL.md`), apart from the "No farm data yet" line, which fills in once a session has run. Then tell the user in one line to start a NEW Claude Code session so the plugin loads.

## Rules

- Never ask for an administrator password or use `sudo`, never run `xcodebuild -license`, never install Homebrew or anything with it, never edit the shell profile or PATH, and never use `./install --add-path`.
- Never compile anything or use `--build-from-source`; if the install says it needs a build, report that instead.
- Always call `jebctl` as `~/.local/bin/jebctl` (or `~/.jeb/bin/jebctl`) since this shell's PATH may not have it.
- Do not take screenshots of the desktop or describe what it draws; the user should see it themselves.
- Do not change settings beyond what the install does.
- To remove Jeb: `~/.jeb/bin/jebctl uninstall --remove-files`.
