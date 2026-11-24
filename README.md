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

[![Latest release](https://img.shields.io/github/v/release/clevyr/jeb)](https://github.com/clevyr/jeb/releases/latest) There's nothing to download by hand: the install below fetches it, and Jeb keeps itself up to date.

![The farm by day](docs/screenshots/farm-day.png)

## Getting Jeb

You need a Mac running macOS 12 or later (Apple Silicon or Intel) and Claude Code, signed in with your own account. Claude does the rest in about five minutes, with no Python, Homebrew, Xcode, git, admin password or Terminal setup.

**1. Ask Claude to set it up.** Open Claude Code in any folder and paste this in:

    Set up or update Jeb for me from github.com/clevyr/jeb. Do every step yourself, without asking me
    to run anything. Never ask me for an administrator password or sudo, to edit my shell profile or
    PATH, to install Homebrew, or to accept the Xcode license, and never compile anything. Run:
    mkdir -p ~/.jeb/bin && curl -fsSL https://github.com/clevyr/jeb/releases/latest/download/jebctl-macos -o ~/.jeb/bin/jebctl.new && chmod +x ~/.jeb/bin/jebctl.new && mv -f ~/.jeb/bin/jebctl.new ~/.jeb/bin/jebctl && ~/.jeb/bin/jebctl install
    It installs Jeb or updates it. Read what it prints and fix any FIX line it reports, following
    https://raw.githubusercontent.com/clevyr/jeb/main/.claude/skills/jeb-install/SKILL.md.

Claude runs the install and tells you when everything's healthy. The release's signature is checked before anything runs, so a tampered download is refused. Paste the same prompt again any time to update or repair Jeb. After that, everything is a `jebctl` command (`update`, `doctor`, `status`, `uninstall`); if `jebctl` isn't found, `~/.jeb/bin/jebctl` always works.

Prefer Terminal to pasting a prompt? See [Installing by hand](docs/install-and-updates.md#installing-by-hand).

**2. Start a new Claude Code session.** Jeb only joins sessions started after the install. The farm looks pretty empty at first and fills in as you work.

![The farm with a built-up homestead and still](docs/screenshots/farm-built.png)

## What you'll see

The farm follows what your sessions do. A few things to look for:

- **Crops grow as you work.** Tobacco, corn and apples each ripen with Claude's work, and the harvest goes in the barn.
- **Each running session shows up.** Jeb works while Claude is busy and idles when it isn't. When Claude hires a subagent, a hired hand turns up in the field.
- **Your workday becomes weather and chores.** Jeb grew up on a Laravel and Docker Compose workflow, so these chores come from those tools:
  - Passing PHP test runs (`artisan test`, Pest, PHPUnit, `composer test`) bring rain; failing ones bring a dry spell.
  - Lint and type-check runs (Pint, PHPStan, ESLint, Prettier, `vue-tsc` and `npm run lint` and the like) are weeding.
  - `docker compose` services named `app`, `hot` and `database` become a barn, a hothouse and a root cellar. Services with other names don't get a building.
  - A ticket key you pass to `/triage` or look up through the Jira connector shows up as a loose cow, as a number only (never the key itself).
- **Each project becomes a place.** Once you've worked in a project for a while, the farm gives it its own place and look. This needs **Creative drops** on (see [Cost and privacy](#cost-and-privacy)).
- **Surprises on weekdays.** At 9:00, 12:00 and 15:00, Monday to Friday, Jeb gets something new: a happening, a saying, a bit of decor or an almanac line. These also need **Creative drops** on.
- **Time and seasons are real.** It's night on the farm from 9 pm to 6 am. Some things turn up on their own over the days; one of them, found on some autumn or winter day, brings falling leaves or snow by day.
- **Holidays.** Jeb gets a banner and a greeting for Christmas, New Year's, Easter, Valentine's Day, St. Patrick's Day, July 4, Halloween and Thanksgiving.

![Jeb standing idle](docs/art/jeb-idle.gif) ![Jeb hoeing](docs/art/jeb-hoe.gif) ![Jeb sipping moonshine](docs/art/jeb-sip.gif) ![Jeb playing the banjo](docs/art/jeb-banjo.gif) ![Blue the dog running](docs/art/blue-run.gif) ![A cow](docs/art/cow.gif) ![A hen](docs/art/hen.gif) ![An owl](docs/art/owl.gif) ![A small fire](docs/art/fire.gif)

![A young farm in the rain, with a tent and torch](docs/screenshots/rain.png) ![The farm at night, with Jeb and the dog asleep](docs/screenshots/farm-night.png) ![The farm with a banner and lights over the sign](docs/screenshots/ridges-home.png)

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

![Jeb playing the banjo](docs/screenshots/jeb-banjo.png)

## Updating

Jeb updates itself at login and every 6 hours. To update now, click **Check for Updates** or run `jebctl update`. To have Claude do it and report back, paste this into Claude Code:

    Update Jeb: follow ~/.jeb/current/.claude/skills/jeb-update/SKILL.md.

Installed before v1.3.0 (from a git clone)? Run `~/.jeb/bin/jebctl install --replace-clone` once to replace it with a release install.

## If something looks wrong

Run `jebctl doctor`; it ends with the steps that fix every `FIX` line, and `jebctl doctor --fix` runs the safe ones for you and then checks again. Easier still, paste this into Claude Code and it finds and fixes the problem itself:

    Check my Jeb install: follow ~/.jeb/current/.claude/skills/jeb-doctor/SKILL.md and fix what it finds.

Common problems:

- **Nothing on the desktop and no menu bar item.** Jeb was quit or isn't running. Log out and back in, or ask Claude to check your Jeb install.
- **The menu bar says "Waiting for art".** Jeb can't find its files, usually because the `~/.jeb` folder was moved or deleted. Ask Claude to install Jeb again.
- **The desktop is empty.** Start a new Claude Code session; Jeb only joins sessions started after the install.
- **Check for Updates says it couldn't start, or is taking too long.** Jeb restarts a stopped update agent when you click it and when it starts. If the menu still says it couldn't start, run `jebctl doctor` or `jebctl status`.

## Removing Jeb

To have Claude do it, paste this into Claude Code:

    Remove Jeb from this Mac: follow ~/.jeb/current/.claude/skills/jeb-install/SKILL.md.

Or in Terminal:

    ~/.jeb/bin/jebctl uninstall --remove-files

That removes the app, takes Jeb out of Claude Code and deletes the `~/.jeb` folder. Your farm is kept in case you come back; add `--purge --purge-farm` to delete it and the rest of Jeb's state too (a backup copy of the farm stays in `~/.claude/backups/jeb`). Installs from before the bundle layout keep a git clone in `~/.jeb/repo` (or `~/jeb`); `--remove-files` removes it too when it has no local changes, otherwise it tells you to drag it to the Trash.

## Cost and privacy

With **Creative drops** on (the default), the plugin calls Haiku at most 9 times a day, on your own Claude account: up to 6 for the weekday surprises and up to 3 to make places for your projects. If Haiku isn't available or the day's calls are used up, Jeb writes the surprises himself.

To make no Haiku calls at all, switch **Creative drops** off: run `/plugin`, open Jeb on the **Installed** tab and choose **Configure options** (it's also a row in `/config`). That also turns off the weekday surprises and the project places; everything else on the farm keeps working.

No work names, paths or text ever leave a session. The plugin keeps an area key (a keyed SipHash-2-4 hash, truncated, under a secret unique to your install) and a handful of coarse values. Ticket keys, repo names, prompts and tool output are reduced to those before anything is written, and the tests check that the raw strings never show up in the stored state.

## More

- [Installing and updates](docs/install-and-updates.md): what's in the repo, requirements, installing by hand, how updates work and signed releases.
- [Reference](docs/reference.md): `jebctl` commands, troubleshooting and where things live, including environment variables.
- [Releasing](docs/releasing.md): how the owner cuts and publishes a release.
- [Contributing](CONTRIBUTING.md): setting up, building, art and commit messages.
- [Security](SECURITY.md): reporting a vulnerability.
- Help and feedback: bugs and ideas go to [GitHub Issues](https://github.com/clevyr/jeb/issues). For a pull request, see [Contributing](CONTRIBUTING.md).

## License

This project is licensed under the [PolyForm Internal Use License 1.0.0](LICENSE). It applies to every release from v1.0.0 onward.

In short: you may use and change Jeb for the internal business operations of you and your company, but you may not distribute or sublicense it. It is source-available, not open source. The [LICENSE](LICENSE) is the full and binding text.
