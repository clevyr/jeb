# Installing and updating

What is in the repo, what Jeb needs, how to install it by hand, and how updates and signed releases work.

## What's in the repo

- `mod/` is the Claude Code plugin, listed by `.claude-plugin/marketplace.json` (a marketplace named `jeb`, plugin id `jeb@jeb`). Its hooks watch your sessions and write anonymized state to the plugin store.
- `desktop/` is the macOS app (Swift).
- `desktop/cli/` is the native `jebctl` (Swift, Foundation and CryptoKit only). It installs, updates and looks after Jeb. In a release bundle it is `desktop/bin/jebctl`; as the standalone `~/.jeb/bin/jebctl` it also runs `install` itself. Build it with `JEB_VERSION=dev desktop/cli/build.sh` (`JEB_OUT` names the output, default `desktop/cli/jebctl`; `JEB_UNIVERSAL=1` builds arm64 and x86_64 and joins them with `lipo`). The release builds the universal one itself.
- `desktop/gates/` builds `jebgates` (`sh desktop/gates/build.sh`), the release gates: parity, the scripted day, smoke and headless start. It isn't shipped.
- `dev/release/` is the release tool (Swift); `./release` builds it and runs it. See [Releasing](releasing.md).
- `art/` is `jebart`, the sprite builder (Swift, built by `art/build.sh`). It writes `mod/hooks/pixel-art.ts` and the previews, and isn't shipped.
- `creative/` is a scheduled builder that can extend the plugin (Swift, built by `creative/build.sh` into `creative/jeb-creative-build`). It's switched off, `./install` doesn't touch it, and nothing in here starts it. On a Mac where its LaunchAgent was set up earlier, that plist still runs the old Python builder until it is rewritten to point at `creative/jeb-creative-build`.

## Requirements

- macOS 12 or later, logged in to a desktop session. A release install needs nothing else from the system: no Python, and the release carries the prebuilt app and helper tools, so there's no Xcode, Command Line Tools, git, Homebrew or compiler on your Mac, and nothing is compiled or notarized.
- Claude Code, signed in with your own account.
- Access to github.com and release-assets.githubusercontent.com. Installs and updates download releases over plain HTTPS: no GitHub account, sign-in or `gh`. Downloads trust the certificates in macOS's keychain; behind a TLS-inspecting proxy, install its root certificate there.
- Developers also need the Xcode Command Line Tools (`xcode-select --install`): `swiftc` to build the app, `jebctl`, `jebgates`, `jebart` and the release tool, `lipo` for `./release`, and git for working on the repo.

## Installing by hand

One line installs Jeb, or updates it if it is already installed (from any older version too):

    curl -fsSL https://github.com/clevyr/jeb/releases/latest/download/install.sh | sh

`install.sh` is uploaded with every release. It downloads the newest release's `jebctl-macos` over TLS to `~/.jeb/bin/jebctl` (a new file renamed over the old one) and runs `jebctl install`; everything after that is checked against the pinned signers (see [Signed releases](#signed-releases)). Pass options after `sh -s --`, for example `... | sh -s -- --dry-run`. To read the script first, download it and run `sh install.sh`; to verify the release yourself instead, follow the steps below.

`jebctl install [--dry-run] [--no-agents] [--verbose]` reads the newest release from `releases/latest` (a plain web redirect: no sign-in, no API), downloads its manifest, signature and this Mac's zip, verifies them, unpacks the zip and runs the bundle's own `install`. If Jeb is already installed it runs `jebctl update` (again while that installs a newer release, up to three times, since an install that pins only older signers needs two steps to reach the newest) and the doctor instead, and it converts an old git-clone install. `--dry-run` prints the plan and changes nothing. The curled `jebctl-macos` is trusted through TLS to github.com; from then on everything is checked against the signers pinned in it, including later copies of jebctl, which arrive inside signed bundles. To check that first copy as well, verify the manifest and `.sig` as below and compare `plutil -extract jebctl.sha256 raw -o - Jeb-$tag-manifest.json` with `shasum -a 256 ~/.jeb/bin/jebctl`. These are the steps it performs (the install skill, `.claude/skills/jeb-install/SKILL.md`, lists the same ones). Pick `arm64` or `x86_64` for `<arch>` (`sysctl -n hw.optional.arm64` prints 1 on Apple silicon):

    tag=$(curl -fsSLo /dev/null -w '%{url_effective}' https://github.com/clevyr/jeb/releases/latest); tag=${tag##*/}
    d=$(mktemp -d) && cd "$d"
    for f in Jeb-$tag-manifest.json Jeb-$tag-manifest.json.sig "Jeb-$tag-macos-<arch>.zip"; do curl -fsSLO "https://github.com/clevyr/jeb/releases/download/$tag/$f"; done
    printf '%s\n' \
      'jeb-release namespaces="jeb-release" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAZiJAyq6wAxoupWQTH3aPh366GNiH6jVR5SCWM4dLWt' \
      'jeb-release-backup namespaces="jeb-release" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPRwzakT+4f3XdKWVkZZOQT9E2DVcdOvH4MbeIeiewY7' > signers
    for who in jeb-release jeb-release-backup; do ssh-keygen -Y verify -f signers -I $who -n jeb-release -s Jeb-$tag-manifest.json.sig < Jeb-$tag-manifest.json && break; done     # one Good signature is enough
    plutil -extract bundles.<arch>.sha256 raw -o - Jeb-$tag-manifest.json     # must equal the next line
    shasum -a 256 "Jeb-$tag-macos-<arch>.zip"
    mkdir -p ~/.jeb/versions/"$tag" && ditto -x -k "Jeb-$tag-macos-<arch>.zip" ~/.jeb/versions/"$tag"
    ~/.jeb/versions/"$tag"/install
    ~/.local/bin/jebctl doctor

The release is a zip per architecture holding the app, the Claude Code plugin, Jeb's install script and the native `jebctl`, plus a signed manifest (see [Signed releases](#signed-releases)). It's unpacked into `~/.jeb/versions/<tag>`, and `~/.jeb/current` is a link to the version in use. The bundle's own `./install --dry-run` shows every step without changing anything. It prints one short line per step; add `--verbose` for every command and detail. You never need git: updates download and verify the next zip the same way, then move the `current` link.

The install:

1. Checks it runs on macOS and finds the plugin.
2. Pins the release signer (see [Signed releases](#signed-releases)) and records the install state.
3. Runs a quick set of checks on the release's prebuilt app (smoke test, headless start), then installs the LaunchAgents, which run the bundle's `jebctl`, and starts it. If a check fails, nothing gets installed. An install never compiles anything.
4. Registers the mod through Claude Code's own plugin system: `claude plugin marketplace add ~/.jeb/current` (a local marketplace named `jeb`) and `claude plugin install jeb@jeb`, so it shows up in `/plugin`. Options and the farm from an earlier install carry over, and Jeb's old `CLAUDE_CODE_PLUGIN_DIRS` entry is removed from `~/.claude/settings.json` (backed up to `~/.claude/backups/jeb/` first; your other entries stay). Updates run `claude plugin update jeb@jeb`. Without Claude Code installed this step is skipped with a note. Running it twice is harmless.
5. Links `jebctl` into `~/.local/bin`. If that folder isn't on your PATH, run it by its full path, or `~/.jeb/current/desktop/bin/jebctl` (`./install --add-path` adds it to your shell profile, for developers who want plain `jebctl`).

Installs from before the bundle layout (a git clone in `~/.jeb/repo` or `~/jeb`) are replaced with `jebctl install --replace-clone`: it boots out the old LaunchAgents, moves the clone to `<clone>.old`, takes its entry out of `CLAUDE_CODE_PLUGIN_DIRS` (backing up your settings first) and installs the release. You can delete the `.old` folder afterwards. Without the flag, `jebctl install` stops and says so.

`./uninstall` keeps `~/Library/Application Support/Jeb` unless you pass `--purge`, and keeps the plugin's state file unless you pass `--purge-farm`, which backs it up before removing it. It also runs `claude plugin uninstall jeb@jeb` and `claude plugin marketplace remove jeb`, and takes any Jeb `mod/` folder back out of `CLAUDE_CODE_PLUGIN_DIRS` (backing up your settings first) and removes the `jebctl` link; `--remove-files` deletes `~/.jeb` (`jebctl uninstall --remove-files` and `--purge-farm` do the same with every flag). `--dry-run` shows what it would do, and `--verbose` prints every command and detail.

## Updates

Jeb uses [Semantic Versioning](https://semver.org): releases are tags like `v1.4.2`, and installs follow the highest one. Pre-release tags (`v1.5.0-rc.1`) are never picked up. A LaunchAgent (`com.jeb.desktop.release`) checks at login and every 6 hours:

1. It asks github.com which release is the latest (`/releases/latest`, a plain web request: no sign-in, no API token or rate limit).
2. If the latest is newer than yours, it downloads the manifest, its signature and the zip for your Mac's architecture. The manifest has to be signed by a pinned signer for the `jeb-release` namespace, and the zip's SHA-256 and size have to match it. One that fails is logged and skipped, and the next check takes the newest older release from the releases feed, so a bad release can't block the real ones.
3. The zip is unpacked into `~/.jeb/versions/<tag>`, refusing anything that isn't a plain file or folder or that would land outside it. The release's prebuilt app then goes through the quick checks: smoke test and a headless start. Parity and the scripted day run once, on the owner's Mac, when the release is cut.
4. If everything passes, `~/.jeb/current` moves to the new version (open sessions reload the plugin), the new app replaces the old one and the LaunchAgents are rewritten if they changed. Only one version is kept on disk, so the old folder is deleted. If the new app crashes or stops reporting in the next few minutes, the old one comes back and that tag is never tried again.

Nothing is compiled and no git is involved: a release update only downloads, verifies and unpacks. `jebctl status` shows the install mode, the current release, the last check and any failed tags; `jebctl follow --dry-run` shows what the next check would do, and `jebctl rollback` downloads the previous release again and goes back to it (not further back than v1.7.0, the first release without Python).

### Signed releases

Each release carries a signed manifest, and installs only trust signers pinned on that machine, so a release published by anyone else is ignored. Releasing stays with the owner: the release tool isn't part of any bundle, and without the owner's signing key nothing it produced would be accepted by an install.

- `Jeb-<tag>-manifest.json` lists, per architecture, the zip's name, size and SHA-256, plus a `jebctl` entry (name `jebctl-macos`, size and SHA-256 of the universal native jebctl); `Jeb-<tag>-manifest.json.sig` is its SSH signature in the `jeb-release` namespace.
- `jebctl-macos` is the first thing a new user downloads (with curl; no sign-in). It is the same binary every bundle carries as `desktop/bin/jebctl`, ad-hoc signed, and it pins the `jeb-release` signers in its source (`signerLines` in `desktop/cli/Signers.swift`); `./release` refuses to tag when those lines differ from `desktop/release-signers`. It accepts a release when any one of them verifies the manifest.
- `desktop/release-signers` lists the allowed signers (`ssh-keygen` allowed_signers format, namespaces `git,jeb-release`): the release key `jeb-release` and its offline backup `jeb-release-backup`. The keys in the install steps above are the same ones, so you can check a download before running anything from it.
- A fresh install copies the file to `~/Library/Application Support/Jeb/release-signers` (mode 0600) if there isn't one already (trust on first install; `install --repin` replaces it by hand). After that the pin follows the releases: an installed Jeb adopts the `desktop/release-signers` of a newer release only after it has verified that release against the keys it already trusts (and when it starts up, from the release it runs), and records which release it adopted from. Adoption only moves forward, and a release that is rejected, or a file with no valid `jeb-release` line, changes nothing.
- To rotate keys, add the new key to `desktop/release-signers`, release that signed with a key that is already pinned, and drop the old key in a later release. Installs pick the new list up when they update, with no action on the machine. A release that was rejected only because its signature did not verify is tried again once the pin changes.
- With no signer pinned, installs don't update at all. `status` and `doctor` show whether one is pinned.
