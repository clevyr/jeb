---
name: jeb-install
description: Set up Jeb (the Claude Code mod plus the macOS desktop app) from github.com/clevyr/jeb on a teammate's Mac: install, update, repair or remove it. Use when the user asks to install, update, repair or remove Jeb, or pastes the README's prompt.
---

# Set up Jeb

Set up Jeb from the clevyr/jeb release (install, update, repair or remove), doing every step yourself. Most users are not developers: never ask them to run a command. The only thing they do is sign in to GitHub in the browser. A teammate's Mac needs no Xcode, Command Line Tools, git or Homebrew. Keep progress updates to one short line per step, and explain a failure in simple words.

## What to do

Decide from the Mac and the request, after steps 1 to 3 below (you need gh to read this skill in the first place, so they have run):

- No `~/.jeb/current`, no `~/.jeb/repo` and no `~/jeb`: Jeb is not installed; run Steps 4 and 5.
- `~/.jeb/current` resolves, or an old clone exists at `~/.jeb/repo` or `~/jeb`: Jeb is already installed, so do not reinstall unless the user asked for that. Follow the jeb-update skill (`~/.jeb/current/.claude/skills/jeb-update/SKILL.md`), then the doctor skill (`~/.jeb/current/.claude/skills/jeb-doctor/SKILL.md`). `~/.jeb/bin/jebctl install` does both for you and converts an old clone.
- The user asked to repair: follow the doctor skill and apply its fixes.
- The user asked to remove Jeb: run `~/.jeb/bin/jebctl uninstall --remove-files`. If the installed release is older than the one that added that flag, run `~/.jeb/current/python/bin/python3 -I ~/.jeb/current/uninstall --remove-files` instead.

## Steps

jebctl is the only tool a teammate needs: it fetches the newest signed release, verifies its signature and hashes against the pinned signer, unpacks it and runs the bundle's own install.

1. Architecture: `sysctl -n hw.optional.arm64` prints 1 for `arm64`, otherwise use `x86_64`.
2. The GitHub CLI: use `~/.jeb/bin/gh`, else `/opt/homebrew/bin/gh` or `/usr/local/bin/gh`. If there is none, download the pinned copy (v2.102.0 from github.com/cli/cli/releases: `gh_2.102.0_macOS_arm64.zip` or `gh_2.102.0_macOS_amd64.zip`) with curl, check it with `shasum -a 256` (arm64 `da922c20d1792e5b2cbf375593d7a658acf034c12c84e007e71c76ef959c337e`, amd64 `b245f24eb2bf5f75b426b4c26da3651a107f8d5b6f4fddfbfccc5679041378b3`), stop if it differs, unpack with `ditto -x -k`, and copy `bin/gh` to `~/.jeb/bin/gh`. Call gh by its full path from then on.
3. Signed in: `gh auth status`. Fix: run `gh auth login --hostname github.com --git-protocol https --web` in the background, show the user the one-time code it prints (it opens the browser), and wait for it to finish. Do not run `gh auth setup-git`.
4. Get jebctl: `mkdir -p ~/.jeb/bin`, then `gh release download -R clevyr/jeb -p jebctl-macos --clobber -O ~/.jeb/bin/jebctl` and `chmod +x ~/.jeb/bin/jebctl`. If it fails, the user's GitHub account needs access to the repo (tell them and stop), or the newest release predates jebctl-macos (see "Older releases without jebctl-macos").
5. Run `~/.jeb/bin/jebctl install` (no flags; `--dev` is only for people working on Jeb itself). It takes a minute or two and prints one short line per step. It:
   - finds the newest release, downloads its manifest, signature and this Mac's zip, and refuses anything whose signature or SHA-256 does not check out;
   - unpacks it into `~/.jeb/versions/<tag>` and runs the bundle's own install, which installs the desktop app in `~/Applications` (prebuilt; nothing is compiled), adds LaunchAgents in `~/Library/LaunchAgents` that keep it running and following releases, points `~/.jeb/current` at this version, adds `~/.jeb/current/mod` to `CLAUDE_CODE_PLUGIN_DIRS` in `~/.claude/settings.json` after saving a backup, and links `jebctl` into `~/.local/bin`;
   - runs the health check at the end.
   Tell the user in one line what it set up once it finishes.
6. If it fails, read the error and fix it yourself where these steps cover it, then run it again; otherwise explain the problem in plain words. Never edit the release's code to make it pass. "GitHub sign-in did not finish" means step 3 again; "your GitHub account needs access" means the user must ask for access to clevyr/jeb. An older install (a git clone in `~/.jeb/repo` or `~/jeb`) converts itself when `jebctl install` runs; do not move it by hand.
7. Read the install's final lines: it runs the doctor itself and tells the user to start a new Claude Code session. Fix any `FIX` line the doctor skill (`~/.jeb/current/.claude/skills/jeb-doctor/SKILL.md`) covers, apart from the mod store line, which fills in once a session has run. Then tell the user in one line to start a NEW Claude Code session so the plugin loads.

## Older releases without jebctl-macos

Until the newest release carries `jebctl-macos`, step 4 fails with "no assets match". Do what jebctl does by hand, with the same checks, replacing steps 4 and 5:

a. The newest release: `gh release list -R clevyr/jeb --exclude-drafts --exclude-pre-releases --limit 1 --json tagName --jq '.[0].tagName'`. If it fails, the user's GitHub account needs access to the repo; tell them and stop.
b. In a fresh folder from `mktemp -d`, run `gh release download <tag> -R clevyr/jeb` with `-p Jeb-<tag>-manifest.json -p Jeb-<tag>-manifest.json.sig -p Jeb-<tag>-macos-<arch>.zip`.
c. Verify the manifest against the pinned signer. Write this pinned signer line, exactly, to a file in that folder: `anthony@clevyr.com namespaces="jeb-release" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGrfSJyAm3dy3vkC1jKbk2YIxJk9BvoThi605ul1gMZC`. Then `ssh-keygen -Y verify -f <that file> -I anthony@clevyr.com -n jeb-release -s Jeb-<tag>-manifest.json.sig < Jeb-<tag>-manifest.json`. It must say "Good". Stop if not.
d. `plutil -extract bundles.<arch>.sha256 raw -o - Jeb-<tag>-manifest.json` must equal `shasum -a 256 Jeb-<tag>-macos-<arch>.zip`. Stop if not.
e. `mkdir -p ~/.jeb/versions/<tag>` and `ditto -x -k <zip> ~/.jeb/versions/<tag>`. If `~/.jeb/versions/<tag>` is already there and complete, use it.
f. Run `~/.jeb/versions/<tag>/python/bin/python3 -I ~/.jeb/versions/<tag>/install` (no flags). Then continue with step 6.

## Rules

- Never ask for an administrator password or use `sudo`, never run `xcodebuild -license`, never install Homebrew or anything with it, never edit the shell profile or PATH, and never use `./install --add-path`.
- Never compile anything or use `--build-from-source`; if the install says it needs a build, report that instead.
- Always call `jebctl` as `~/.local/bin/jebctl` (or `~/.jeb/bin/jebctl`) and gh by its full path, since this shell's PATH may not have them.
- Do not take screenshots of the desktop or describe what it draws; the user should see it themselves.
- Do not change settings beyond what the install does.
- To remove Jeb: `~/.jeb/bin/jebctl uninstall --remove-files` (older releases: `~/.jeb/current/python/bin/python3 -I ~/.jeb/current/uninstall --remove-files`).
