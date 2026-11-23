<p align="center">
  <img src="docs/logo.svg" alt="Jeb" width="400">
</p>

<p align="center">
  <sub>Made by</sub><br>
  <a href="https://clevyr.com">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="docs/made-by-clevyr-dark.svg">
      <img src="docs/made-by-clevyr.svg" alt="Clevyr" width="149">
    </picture>
  </a>
</p>

Jeb is a little farm on your Mac's desktop that shows what your Claude Code sessions are up to. A Claude Code plugin watches your sessions, and a desktop app draws the farm.

**Latest release:** [github.com/clevyr/jeb/releases/latest](https://github.com/clevyr/jeb/releases/latest). There's nothing to download by hand: the install below fetches it, and Jeb keeps itself up to date.

![farm-day](docs/screenshots/farm-day.png)

## Getting Jeb

You need a Mac and Claude Code. Claude does the rest in about five minutes, with no Homebrew, Xcode, git, admin password or Terminal setup.

**1. Ask Claude to set it up.** Open Claude Code in any folder and paste this in:

    Set up or update Jeb for me from github.com/clevyr/jeb. Do every step yourself, without asking me
    to run anything. Never ask me for an administrator password or sudo, to edit my shell profile or
    PATH, to install Homebrew, or to accept the Xcode license, and never compile anything. Run:
    mkdir -p ~/.jeb/bin && curl -fsSL https://github.com/clevyr/jeb/releases/latest/download/jebctl-macos -o ~/.jeb/bin/jebctl.new && chmod +x ~/.jeb/bin/jebctl.new && mv -f ~/.jeb/bin/jebctl.new ~/.jeb/bin/jebctl && ~/.jeb/bin/jebctl install
    It installs Jeb or updates it. Read what it prints and fix any FIX line it reports, following
    https://raw.githubusercontent.com/clevyr/jeb/main/.claude/skills/jeb-install/SKILL.md.

Claude runs the install and tells you when everything's healthy. The release's signature is checked before anything runs, so a tampered download is refused. Paste the same prompt again any time to update or repair Jeb. After that, everything is a `jebctl` command (`update`, `doctor`, `status`, `uninstall`); if `jebctl` isn't found, `~/.jeb/bin/jebctl` always works.

**2. Start a new Claude Code session.** Jeb only joins sessions started after the install. The farm looks pretty empty at first and fills in as you work.

![farm-built](docs/screenshots/farm-built.png)

## Using Jeb

There's nothing to run. Jeb starts when you log in, comes back on its own if it stops, and updates itself in the background.

It adds an item to the menu bar with:

- A status line showing whether it's running and at what frame rate, or why it's paused.
- **Pause / Resume** to stop and start drawing.
- **Frame rate**: Adaptive (the default, which slows down when nothing's moving), 60 fps or 30 fps.
- **Check for Updates** to update now instead of waiting. The menu shows the installed version, when Jeb last checked, the progress of a running update and its result.
- **Notifications** to turn update banners, holiday greetings and sound on or off, or show sample banners. When an update finishes, Jeb shows his own banner at the top right of the screen; click or swipe to dismiss it. These aren't macOS notifications, so any old Jeb entries in System Settings or Notification Center can be cleared.
- **Reload art** to pick up new plugin art without restarting.
- **Save Screenshot**, which saves a picture per screen to `~/Pictures/Jeb/` and shows it in Finder. It only saves what Jeb draws, never your other windows.
- **Restart** to start a fresh copy.
- **Quit Jeb Desktop**, which stops it until you next log in.

![jeb-banjo](docs/screenshots/jeb-banjo.png)

## Updating

Jeb updates itself at login and every 6 hours. To update now, click **Check for Updates** or run `jebctl update`. To have Claude do it and report back, paste this into Claude Code:

    Update Jeb: follow ~/.jeb/current/.claude/skills/jeb-update/SKILL.md.

Installed before v1.3.0 (from a git clone)? Run `jebctl install` once to convert it.

## If something looks wrong

Run `jebctl doctor`; every `FIX` line it prints says what to do. Easier still, paste this into Claude Code and it finds and fixes the problem itself:

    Check my Jeb install: follow ~/.jeb/current/.claude/skills/jeb-doctor/SKILL.md and fix what it finds.

Common problems:

- **Nothing on the desktop and no menu bar item.** Jeb was quit or isn't running. Log out and back in, or ask Claude to check your Jeb install.
- **The menu bar says "Waiting for art".** Jeb can't find its files, usually because the `~/.jeb` folder was moved or deleted. Ask Claude to install Jeb again.
- **The desktop is empty.** Start a new Claude Code session; Jeb only joins sessions started after the install.
- **Check for Updates says it couldn't start, or is taking too long.** The app reloads an update agent that launchd has dropped when you click, and at start; if the menu still says it couldn't start, run `jebctl doctor` or `jebctl status`.

## Removing Jeb

In Terminal:

    ~/.local/bin/jebctl uninstall --remove-files

That removes the app, takes Jeb out of Claude Code and deletes the `~/.jeb` folder. Your farm is kept in case you come back; add `--purge --purge-farm` to remove everything. Installs from before the bundle layout keep a git clone in `~/.jeb/repo` (or `~/jeb`); `--remove-files` removes it too when it has no local changes, otherwise it tells you to drag it to the Trash.

![jeb-idle](docs/art/jeb-idle.gif) ![jeb-hoe](docs/art/jeb-hoe.gif) ![jeb-sip](docs/art/jeb-sip.gif) ![jeb-banjo](docs/art/jeb-banjo.gif) ![blue-run](docs/art/blue-run.gif) ![cow](docs/art/cow.gif) ![hen](docs/art/hen.gif) ![owl](docs/art/owl.gif) ![fire](docs/art/fire.gif)

## Cost and privacy

The plugin calls Haiku at most 9 times a day, on your own Claude account.

No work names, paths or text ever leave a session. The plugin keeps an area key (a keyed SipHash-2-4 hash, truncated, under a secret unique to your install) and a handful of coarse values. Ticket keys, repo names, prompts and tool output are reduced to those before anything is written, and the tests check that the raw strings never show up in the stored state.

![rain](docs/screenshots/rain.png) ![farm-night](docs/screenshots/farm-night.png) ![ridges-home](docs/screenshots/ridges-home.png)

## More

- [Installing and updates](docs/install-and-updates.md): what's in the repo, requirements, installing by hand, how updates work and signed releases.
- [Reference](docs/reference.md): `jebctl` commands, troubleshooting and where things live, including environment variables.
- [Releasing](docs/releasing.md): how the owner cuts and publishes a release.
- [Contributing](CONTRIBUTING.md): setting up, building, art and commit messages.
- [Security](SECURITY.md): reporting a vulnerability.

## License

This project is licensed under the [PolyForm Internal Use License 1.0.0](LICENSE). It applies to every release from v1.0.0 onward.
