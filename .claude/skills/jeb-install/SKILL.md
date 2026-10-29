---
name: jeb-install
description: Install Jeb (the Claude Code mod plus the macOS desktop app) from github.com/clevyr/jeb on a teammate's Mac. Use when the user asks to install Jeb or pastes the README's install prompt.
---

# Install Jeb

Install Jeb from the clevyr/jeb release, doing every step yourself. Most users are not developers: never ask them to run a command. The only thing they do is sign in to GitHub in the browser. A teammate's Mac needs no Xcode, Command Line Tools, git or Homebrew. Keep progress updates to one short line per step, and explain a failure in simple words.

## Steps

1. Architecture: `sysctl -n hw.optional.arm64` prints 1 for `arm64`, otherwise use `x86_64`.
2. The GitHub CLI: use `~/.jeb/bin/gh`, else `/opt/homebrew/bin/gh` or `/usr/local/bin/gh`. If there is none, download the pinned copy (v2.102.0 from github.com/cli/cli/releases: `gh_2.102.0_macOS_arm64.zip` or `gh_2.102.0_macOS_amd64.zip`) with curl, check it with `shasum -a 256` (arm64 `da922c20d1792e5b2cbf375593d7a658acf034c12c84e007e71c76ef959c337e`, amd64 `b245f24eb2bf5f75b426b4c26da3651a107f8d5b6f4fddfbfccc5679041378b3`), stop if it differs, unpack with `ditto -x -k`, and copy `bin/gh` to `~/.jeb/bin/gh`. Call gh by its full path from then on.
3. Signed in: `gh auth status`. Fix: run `gh auth login --hostname github.com --git-protocol https --web` in the background, show the user the one-time code it prints (it opens the browser), and wait for it to finish. Do not run `gh auth setup-git`.
4. The newest release: `gh release list -R clevyr/jeb --exclude-drafts --exclude-pre-releases --limit 1 --json tagName --jq '.[0].tagName'`. If it fails, the user's GitHub account needs access to the repo; tell them and stop.
5. In a fresh folder from `mktemp -d`, run `gh release download <tag> -R clevyr/jeb` with `-p Jeb-<tag>-manifest.json -p Jeb-<tag>-manifest.json.sig -p Jeb-<tag>-macos-<arch>.zip`.
6. Verify the manifest against the signer pinned in the README. Write `anthony@clevyr.com namespaces="jeb-release" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGrfSJyAm3dy3vkC1jKbk2YIxJk9BvoThi605ul1gMZC` to a file in that folder (copy the line from the README's install prompt), then `ssh-keygen -Y verify -f <that file> -I anthony@clevyr.com -n jeb-release -s Jeb-<tag>-manifest.json.sig < Jeb-<tag>-manifest.json`. It must say "Good". Stop if not.
7. `plutil -extract bundles.<arch>.sha256 raw -o - Jeb-<tag>-manifest.json` must equal `shasum -a 256 Jeb-<tag>-macos-<arch>.zip`. Stop if not.
8. `mkdir -p ~/.jeb/versions/<tag>` and `ditto -x -k <zip> ~/.jeb/versions/<tag>`. If `~/.jeb/versions/<tag>` is already there and complete, use it.
9. Run `~/.jeb/versions/<tag>/python/bin/python3 -I ~/.jeb/versions/<tag>/install` (no flags; `--dev` is only for people working on Jeb itself). It:
   - installs the desktop app in `~/Applications`, from the release's prebuilt app; nothing is compiled;
   - adds LaunchAgents in `~/Library/LaunchAgents` that keep it running and following releases;
   - points `~/.jeb/current` at this version and adds `~/.jeb/current/mod` to `CLAUDE_CODE_PLUGIN_DIRS` in `~/.claude/settings.json`, after saving a backup;
   - links `jebctl` into `~/.local/bin`.
   It takes a minute or two. Tell the user in one line what it set up once it finishes.
10. If it fails, read the error and fix it yourself where these steps cover it, then run it again; otherwise explain the problem in plain words. Never edit the release's code to make it pass. "app download failed" or "GitHub sign-in needed" means gh is not signed in (step 3). An older install (a git clone in `~/.jeb/repo` or `~/jeb`) converts itself on its next update; do not move it by hand.
11. On success run `~/.local/bin/jebctl doctor` (or `~/.jeb/current/python/bin/python3 -I ~/.jeb/current/desktop/jebctl doctor`) and fix any `FIX` line the doctor skill (`~/.jeb/current/.claude/skills/jeb-doctor/SKILL.md`) covers. Then tell the user to start a NEW Claude Code session so the plugin loads, and that the desktop fills in once a session has run.

## Rules

- Never ask for an administrator password or use `sudo`, never run `xcodebuild -license`, never install Homebrew or anything with it, never edit the shell profile or PATH, and never use `./install --add-path`.
- Never compile anything or use `--build-from-source`; if the install says it needs a build, report that instead.
- Always call `jebctl` as `~/.local/bin/jebctl` and gh by its full path, since this shell's PATH may not have them.
- Do not take screenshots of the desktop or describe what it draws; the user should see it themselves.
- Do not change settings beyond what the install does.
- To remove Jeb: `~/.jeb/current/python/bin/python3 -I ~/.jeb/current/uninstall --remove-files`.
