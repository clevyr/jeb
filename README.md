<p align="center">
  <img src="docs/logo.svg" alt="Jeb" width="400">
</p>

<p align="center">
  <a href="https://github.com/clevyr/jeb/releases/latest"><img src="https://img.shields.io/github/v/release/clevyr/jeb" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-12%2B-lightgrey" alt="macOS 12 or later">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-PolyForm%20Internal%20Use-blue" alt="License: PolyForm Internal Use 1.0.0"></a>
</p>

Jeb is a cute little farm that lives on your Mac's desktop. It keeps an eye on your Claude Code sessions and turns what they're up to into farm life, and some days it dreams up things all on its own. What turns up, and when, is half the fun.

![Jeb's farm on a sunny day](docs/screenshots/farm-day.png)

## Getting Jeb

You need a Mac running macOS 12 or later (Apple Silicon or Intel) and Claude Code, signed in with your own account. There's no Python, Homebrew, Xcode, git or admin password involved.

**1. Run the installer.** In Terminal:

```sh
curl -fsSL https://github.com/clevyr/jeb/releases/latest/download/install.sh | sh
```

It takes a minute or two and ends with a health check. The release's signature is checked before anything runs, so a tampered download is refused. Run the same command any time to update or repair Jeb.

**2. Start a new Claude Code session.** Jeb only joins sessions started after the install. The farm starts out bare and fills in as you work.

What the install sets up:

- The app in `~/Applications`, its code in `~/.jeb`, and `jebctl` in `~/.local/bin` (`~/.jeb/bin/jebctl` always works).
- Three login items: the app, a watchdog that brings it back if it stops, and an updater that checks GitHub for new releases.
- The Jeb plugin in Claude Code. It can make up to 9 Haiku calls a day on your account; see [Cost and privacy](#cost-and-privacy) to turn them off.

To check the download yourself first, see [Installing by hand](docs/install-and-updates.md#installing-by-hand).

## Let Claude do it

Each of these can be pasted into Claude Code instead of running commands yourself.

Install or update:

```text
Install or update Jeb for me. Run:
curl -fsSL https://github.com/clevyr/jeb/releases/latest/download/install.sh | sh
Then follow ~/.jeb/current/.claude/skills/jeb-install/SKILL.md to finish, and fix anything it
reports yourself. Never ask me for a password or sudo, and never compile anything.
```

Update:

```text
Update Jeb: follow ~/.jeb/current/.claude/skills/jeb-update/SKILL.md.
```

Find and fix a problem:

```text
Check my Jeb install: follow ~/.jeb/current/.claude/skills/jeb-doctor/SKILL.md and fix what it finds.
```

Remove:

```text
Remove Jeb from this Mac: follow ~/.jeb/current/.claude/skills/jeb-install/SKILL.md.
```

## What you'll see

The farm follows your work, but it won't tell you how. Some things to watch for:

- **Your sessions, working.** Each running session shows up. Jeb works while Claude is busy and takes it easy when it isn't, and help turns up when Claude brings some in.
- **Your work, growing.** Crops ripen as Claude works, and what you do shows up in the weather and the chores.
- **Your projects, as places.** Spend a while in a project and the farm gives it a place and a look of its own.
- **Surprises.** On weekdays Jeb comes up with happenings, sayings, decor and almanac lines nobody planned.
- **Real time.** Night falls at 9 pm, seasons turn, and holidays get a banner and a greeting. Some things only show up if you keep coming back.

If you'd rather know exactly what does what, the [spoilers are in the reference](docs/reference.md#what-your-work-turns-into).

<table>
  <tr>
    <td><img src="docs/screenshots/farm-built.png" alt="A built-up homestead with a still"></td>
    <td><img src="docs/screenshots/rain.png" alt="A young farm in the rain, with a tent and torch"></td>
  </tr>
  <tr>
    <td align="center"><sub>A farm a few weeks in</sub></td>
    <td align="center"><sub>Weather moving through</sub></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/farm-night.png" alt="The farm at night, with Jeb and the dog asleep"></td>
    <td><img src="docs/screenshots/ridges-home.png" alt="The farm with a banner and lights over the sign"></td>
  </tr>
  <tr>
    <td align="center"><sub>Night on the farm</sub></td>
    <td align="center"><sub>A holiday banner</sub></td>
  </tr>
</table>

<p align="center">
  <img src="docs/art/jeb-idle.gif" alt="Jeb standing idle"> <img src="docs/art/jeb-hoe.gif" alt="Jeb hoeing"> <img src="docs/art/jeb-sip.gif" alt="Jeb sipping moonshine"> <img src="docs/art/jeb-banjo.gif" alt="Jeb playing the banjo"> <img src="docs/art/blue-run.gif" alt="Blue the dog running"> <img src="docs/art/cow.gif" alt="A cow"> <img src="docs/art/hen.gif" alt="A hen"> <img src="docs/art/owl.gif" alt="An owl"> <img src="docs/art/fire.gif" alt="A small fire"><br>
  <sub>Jeb, Blue and some of the neighbors</sub>
</p>

## Using Jeb

There's nothing to run. Jeb starts when you log in, comes back on its own if it stops, and updates itself at login and every 6 hours.

The menu bar item lets you pause the farm, set the frame rate, check for updates, turn notifications and **Features** (such as Creative Drops) on and off, and save a screenshot to `~/Pictures/Jeb/`. Each feature has a line underneath saying what it does. The full list is in the [reference](docs/reference.md#the-menu-bar).

## FAQ

**Will it slow my Mac down?** It's built not to. The frame rate drops when nothing on the farm is moving, and drawing stops entirely while the screen is asleep or locked, while you're away, or while windows cover the farm. You can also cap it at 30 fps or pause it from the menu bar.

**Does it send my code anywhere?** No. No work names, paths or text ever leave a session; see [Cost and privacy](#cost-and-privacy). Jeb's only network traffic is checking GitHub for updates and, with Creative drops on, the Haiku calls on your own Claude account.

**Do I need an API key?** No. The Haiku calls go through Claude Code on the account you're already signed in with.

**Why isn't my session on the farm?** Jeb only joins sessions started after it was installed. Start a new one.

## If something looks wrong

Run `jebctl doctor --fix`. It runs the safe repairs, checks again and lists the steps for anything left; `jebctl doctor` on its own only checks. Or paste the "Find and fix a problem" prompt from [Let Claude do it](#let-claude-do-it).

- **Nothing on the desktop, or the desktop is empty.** If there's no Jeb in the menu bar, Jeb was quit or isn't running: run `jebctl doctor --fix`, or log out and back in. If the menu bar item is there, start a new Claude Code session.
- **The menu bar says "Waiting for art".** Jeb can't find its files, usually because the `~/.jeb` folder was moved or deleted. Run the installer again.
- **Check for Updates says it couldn't start, or is taking too long.** Jeb restarts a stopped updater when you click it and when it starts. If the menu still says it couldn't start, run `jebctl doctor` or `jebctl status`.

More in [Troubleshooting](docs/reference.md#troubleshooting).

## Removing Jeb

In Terminal:

```sh
~/.jeb/bin/jebctl uninstall --remove-files
```

That removes the app and its login items, takes Jeb out of Claude Code and deletes the `~/.jeb` folder. Your farm is kept in case you come back; add `--purge --purge-farm` to delete it and the rest of Jeb's state too (a backup copy of the farm stays in `~/.claude/backups/jeb`).

## Cost and privacy

With **Creative drops** on (the default), the plugin calls Haiku at most 9 times a day, on your own Claude account: up to 6 for the weekday surprises and up to 3 to make places for your projects. If Haiku isn't available or the day's calls are used up, Jeb writes the surprises himself.

To make no Haiku calls at all, switch Creative drops off, either way:

- In the menu bar: **Features > Creative Drops**. This doesn't change your Claude Code settings.
- In Claude Code: run `/plugin`, open Jeb on the **Installed** tab and choose **Configure options** (it's also a row in `/config`).

That also turns off the weekday surprises and the project places; everything else on the farm keeps working, and whatever is already on the farm stays.

No work names, paths or text ever leave a session. The plugin keeps an area key (a keyed SipHash-2-4 hash, truncated, under a secret unique to your install) and a handful of coarse values. Ticket keys, repo names, prompts and tool output are reduced to those before anything is written, and the tests check that the raw strings never show up in the stored state.

## More

- [Installing and updates](docs/install-and-updates.md): what's in the repo, requirements, installing by hand, how updates work and signed releases.
- [Reference](docs/reference.md): `jebctl` commands, the menu bar, troubleshooting and where things live, including environment variables.
- [Releasing](docs/releasing.md): how the owner cuts and publishes a release.
- [Contributing](CONTRIBUTING.md): setting up, building, art and commit messages.
- [Security](SECURITY.md): reporting a vulnerability.
- Bugs and ideas go to [GitHub Issues](https://github.com/clevyr/jeb/issues).

## License

Jeb is source-available, not open source. It's licensed under the [PolyForm Internal Use License 1.0.0](LICENSE) from v1.0.0 onward: you may use and change it for the internal business operations of you and your company, but you may not distribute or sublicense it. The [LICENSE](LICENSE) is the full and binding text.

<p align="center">
  <sub>Made by</sub><br>
  <a href="https://clevyr.com">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="docs/made-by-clevyr-dark.svg">
      <img src="docs/made-by-clevyr.svg" alt="Clevyr" width="100">
    </picture>
  </a>
</p>
