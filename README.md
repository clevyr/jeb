# Jeb

Internal to Clevyr. This repository is private and has no public licence; do not redistribute it.

Jeb is a Claude Code plugin plus a macOS desktop app that draws what the plugin observes.

- `mod/` is a Claude Code plugin. Its hooks observe Claude Code sessions and write anonymized state to the plugin store.
- `desktop/` is a macOS app (Swift) with Python control scripts. It reads that state and draws it.
- `creative/` is a scheduled builder that extends the plugin. It is off and is not installed by `./install`; nothing here starts it. `brief.md` is its instruction file and `tools/` holds its gate and sandbox test harnesses.

## Quick install with Claude Code

Paste this into Claude Code (any folder):

    Install Jeb for me. Clone git@github.com:clevyr/jeb.git into ~/jeb (or use it if it is already there),
    then follow the jeb-install skill in that clone's .claude/skills/jeb-install/SKILL.md: check the
    requirements, run ./install with no flags, run desktop/jebctl doctor, and explain anything that fails.

Claude checks the requirements, tells you how to fix anything missing, runs the install and a health check, and explains any problem in plain words. When it finishes, start a new Claude Code session so the plugin loads.

If something looks wrong later, open Claude Code in the clone and ask it to run the `jeb-doctor` skill.

## Requirements

- macOS with a desktop session.
- Xcode Command Line Tools (`xcode-select --install`). The desktop app is built from source on each machine, so no signing or notarization is involved.
- `/usr/bin/python3` (installed with the Command Line Tools) and `git`.
- Claude Code (`claude` on PATH), signed in with your own account.
- Access to this repository over your own git credentials (SSH key or HTTPS credential helper). The release agent fetches in the background, so the credentials must work without a prompt: an SSH key in the macOS keychain (`ssh-add --apple-use-keychain`) or the HTTPS keychain helper. `ssh -T git@github.com` should greet you without asking for a passphrase.

## Install

    git clone git@github.com:clevyr/jeb.git ~/jeb
    cd ~/jeb
    ./install

The clone can live anywhere; the install records its location. `./install --dry-run` prints every step and changes nothing.

`./install` does the following:

1. Checks the requirements above and stops with a message if one is missing.
2. Release mode (the default) needs a clean git clone. `desktop/jebctl install` pins the release signers from the cloned checkout (see Signed releases), fetches tags and moves the clone to the newest tag that passes the checks (signed by a pinned signer, commit on the default branch). With no pinned signer or no verified tag it stays on the cloned commit, detached from the branch, so it can move to the first verified release later.
3. Builds the desktop app and runs the first-install checks (compile, smoke test, headless start), then installs the LaunchAgents and starts the app. The longer checks (parity and a scripted day) run on every update and release, not on the first install. If a check fails, it stops here, the clone goes back to the commit you cloned, and nothing is installed or changed.
4. Adds the clone's `mod/` folder to `CLAUDE_CODE_PLUGIN_DIRS` in `~/.claude/settings.json`. The file is backed up first to `~/.claude/backups/jeb/settings.<timestamp>.json`, existing entries are kept, and a second run changes nothing.

Then run the health check and start a new Claude Code session so it loads the plugin:

    desktop/jebctl doctor

The desktop stays mostly empty until a session has run with the plugin.

## Using it

The desktop runs on its own: it starts at login, a watchdog restarts it if it stops, and only one copy runs at a time.

### Menu bar item

Jeb Desktop adds an item to the macOS menu bar. Its menu has:

- A status line: running and its frame rate, or paused and why.
- **Pause / Resume**: stops and resumes drawing.
- **Frame rate**: Adaptive (the default; slower when nothing is moving), 60 fps or 30 fps.
- **Reload art**: re-reads the plugin's art without restarting.
- **Restart**: starts a fresh copy, which takes over from the running one.
- **Quit Jeb Desktop**: stops the app and tells the watchdog to leave it stopped. It stays quit until your next login or `desktop/jebctl start`.

### Commands

Run these from the clone:

    desktop/jebctl status            # app, heartbeat, mode, last update, LaunchAgents
    desktop/jebctl doctor            # health check: one ok/FIX line per check, with the fix
    desktop/jebctl start             # start it again after Quit
    desktop/jebctl quit              # stop it (same as Quit in the menu)
    desktop/jebctl pause-updates     # stop following releases
    desktop/jebctl resume-updates
    desktop/jebctl rollback          # put the previous version back

## Troubleshooting

Start with `desktop/jebctl doctor`. Every `FIX` line names its fix. Common cases:

- **Nothing on the desktop, no menu bar item.** It was quit from the menu, or it is not running: `desktop/jebctl start`. If the LaunchAgents are missing, run `./install` again.
- **A menu bar item titled "Jeb" saying "Waiting for art".** The app cannot find the plugin's art file (`mod/hooks/pixel-art.ts`), usually because the clone was moved or deleted. It checks again every 30 seconds and starts drawing once the file is back. If the clone moved, run `./install` again from its new location.
- **The desktop is empty.** Start a new Claude Code session; the plugin loads only in sessions started after the install. `doctor` shows whether the plugin is registered and whether its state file exists.
- **Updates stopped.** `desktop/jebctl status` shows the last release check and any failed tags. Updates skip a clone with local changes or one checked out on a branch; commit or stash the changes, or run `./install` again. Paused updates show in `doctor`.
- **An update failed.** The previous version keeps running and the failed release is not retried. `~/.claude/jeb-desktop/update.log` and `release.log` say why.

Logs are in `~/.claude/jeb-desktop/`: `update.log` (builds and checks), `release.log` (release checks), `watchdog.log` (restarts).

## Updates

In release mode the clone follows release tags (`vYYYY.MM.DD`, with `.N` for a second release on the same day). A LaunchAgent (`com.jeb.desktop.release`) runs at login and every 6 hours:

1. `git fetch --tags origin` with your own git credentials.
2. Each newer tag, newest first, must be signed by a pinned signer and point at a commit on the default branch. A tag that fails either check is recorded as failed (the reason is logged) and the next older one is tried, so a bogus tag cannot block real releases.
3. The first tag that passes is resolved to its commit SHA once and exported (`git archive <sha>`) into `~/.claude/jeb-desktop/staging/<tag>/`; the export is refused if it holds anything but regular files and directories, or a name that is absolute, contains `..` or lands outside the folder. The new desktop build goes through the full automated checks (compile, smoke, parity, scripted day, headless start) against the staged files.
4. Only if every check passes does the clone switch to that SHA (the plugin reloads in open sessions) and the new app replace the old one. If the new app crashes or stops reporting in the following minutes, the previous SHA and app are restored and the failed tag is not retried.

The update does nothing if the clone has local changes or is checked out on a branch. A clone that is detached with no release tag (a first install before any verified release) takes the newest verified tag. `jebctl status` shows the install mode, the release the clone is on, the last release check and its result, and any failed tags. `jebctl follow --dry-run` shows what a check would do.

## Signed releases

Releases are signed tags, and `jebctl follow` trusts only the signers pinned on the machine, so a pushed tag from anyone else is ignored.

- `desktop/release-signers` in the repo lists the allowed signers (`ssh-keygen` allowed_signers format, namespace `git`). The owner creates it with `./release setup` before the first release.
- `jebctl install` (release mode) copies it to `~/.claude/jeb-desktop/release-signers` (mode 0600) if that file does not exist yet. A later tag, or a later pull, cannot replace the pinned copy: trust is set at first install.
- Key rotation: update `desktop/release-signers` in a release, then on each machine run `./install --repin` (or `jebctl install --repin`) to replace the pinned copy.
- Until a signer is pinned, installs do not update: `follow` logs that no signers are pinned and does nothing. `jebctl status` and `jebctl doctor` show whether signers are pinned.
- Recommended on the GitHub repository: protect the `v*` tags (a tag protection rule or a ruleset) so only the owner can create, move or delete release tags, and protect the default branch.

## Uninstall

    cd ~/jeb
    ./uninstall

This stops and removes the LaunchAgents (including the release agent) and the app, and removes this clone's `mod/` entry from `CLAUDE_CODE_PLUGIN_DIRS` (settings backed up first). Desktop versions and logs in `~/.claude/jeb-desktop` are kept; `--purge` removes that folder and everything in it. The plugin's state file in `~/.claude/plugins/store/` is kept unless you pass `--purge-farm`, which backs it up and then removes it. The clone itself is not deleted. `--dry-run` shows the steps.

## Owner mode and releases

The owner runs from the working tree instead of release tags:

    ./install --dev

In dev mode the update agent watches `desktop/src` and ships local edits through the full automated checks; there is no release agent.

Releases are cut locally; there is no CI. One-time setup, with an SSH signing key configured in git (`git config gpg.format ssh`, `git config user.signingkey ~/.ssh/<key>.pub`):

    ./release setup        # writes desktop/release-signers from your git email and signing key

Commit and push `desktop/release-signers` before the first release. Then, from a clean checkout of the default branch:

    ./release [--dry-run]

It runs `desktop/jebctl release --parity`: checks the tree is clean and on the default branch, runs `claude plugin validate mod`, `claude plugin test mod`, a dev build (`JEB_OUT=JebDesktop.dev ./build.sh` in `desktop/src`) and the parity gate, then creates a local signed tag (`git tag -s`). It then asks before pushing the branch and the tag to origin, and pushes only on `y`. Other installs pick the release up on their next check.

## Cost

The mod calls Haiku at most 9 times a day, on your own Claude account.

## Privacy model

No work names, paths or text leave a session. The mod keeps only an area key, a keyed hash (SipHash-2-4, truncated) under a per-install secret, and coarse enums. Ticket keys, repository names, prompts and tool output are reduced to those values before anything is written, and the tests check that the raw strings never appear in the stored state.

## Runtime state

Code runs from the clone. State stays outside it.

- `~/.claude/jeb-desktop`: desktop logs, installed versions, heartbeat, telemetry, updater and release state, staging.
- `~/.claude/jeb-creative`: the builder's changelog, run log, lock and run output (unused while the builder is off).
- The Claude Code plugin store (`~/.claude/plugins/store/`): the mod's state file, which the desktop reads.

The installed app finds the plugin's folder from the `JebMod` key in its `Info.plist`, written at build time. A `JEB_MOD` environment variable overrides it, and a development build falls back to the `mod/` folder beside `desktop/`.

Environment variables (mostly for tests; the install sets the paths itself):

- `JEB_HOME`: desktop state root (default `~/.claude/jeb-desktop`).
- `JEB_SRC`: desktop app source for `jebctl` and `updater.py` (default `desktop/src` in the clone).
- `JEB_MOD`: the mod folder, used to find `hooks/pixel-art.ts`. Tools default to the `mod/` beside `desktop/`.
- `JEB_BUNDLE_MOD`: the folder written into the bundle's `JebMod` key (default `JEB_MOD`). Release updates set it to the clone's `mod/`, since the staged copy is removed after the update.
- `JEB_APP_DIR`: where `JebDesktop.app` is installed (default `~/Applications`).
- `JEB_LAUNCHAGENTS`: where the LaunchAgent plists are installed (default `~/Library/LaunchAgents`).
- `JEB_SETTINGS`, `JEB_BACKUPS`, `JEB_STORE_DIR`: the settings file, its backups and the store folder, for `./install`, `./uninstall` and `jebctl doctor`.

## Checks

    claude plugin validate mod
    claude plugin test mod
    cd desktop/src && JEB_OUT=JebDesktop.dev ./build.sh

Bench and measurement scripts live in `desktop/src/dev/` and are not part of the install.
