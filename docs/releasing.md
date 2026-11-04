# Releasing

How the owner cuts, signs and publishes a Jeb release.

Releases are cut locally by the owner; there's no CI. Releases are signed, so once, from the clone:

    ./release setup

If this clone has no signing key yet, it makes one at `~/.ssh/jeb_signing` (it asks you for a passphrase) and points this clone's git at it. Then it writes `desktop/release-signers` from your git email and that key, with the namespaces `git,jeb-release`. Commit and push that file before the first release, and put the same line in the manual install steps in [docs/install-and-updates.md](install-and-updates.md#installing-by-hand). Back the key up somewhere safe, like a password manager: if it's lost, every install has to run `install --repin` to trust a new one. Git asks for the passphrase once each time you release, and `ssh-keygen` once more to sign the manifest.

To get a "Verified" badge on the tags on GitHub, also add `~/.ssh/jeb_signing.pub` to your account as a *Signing Key* (Settings, then SSH and GPG keys). Installs don't need it.

From a clean checkout of `main`, one command cuts a release and puts it on GitHub:

    ./release

It works out the version the way release-please does, from the [commit messages](../CONTRIBUTING.md#commit-messages-and-versions) since the last release: any breaking change makes it a major release, otherwise any `feat` makes it minor, otherwise any `fix`, `perf` or `revert` makes it a patch. If there's nothing releasable it says so and stops. The release notes are built from the same commits. The very first release is 1.0.0. The version always comes from the release tags and the commits, never from a number you set; the release writes it into `mod/.claude-plugin/plugin.json` for the record.

Add `--dry-run` to see the version and notes it would use without changing anything. To force a level, pass it: `./release patch`, `./release minor` or `./release major`.

It validates and tests the plugin, does a universal release build (arm64 and x86_64) and runs the parity checks on that binary. Only if all of that passes does it write the new version to `plugin.json`, commit it as `chore(release): v<version>` and make a signed `v<version>` tag. A failed check leaves nothing behind. It then builds one bundle per architecture: the tag's tree (`git archive`), the prebuilt app and helper tools, and a pinned relocatable Python from [python-build-standalone](https://github.com/astral-sh/python-build-standalone) (release `20261013`, Python 3.12.15, `install_only_stripped`, SHA-256 checked against the pins in `release`, pruned, every Mach-O signature checked, and its standard-library imports smoke-tested). To change the Python, edit the pins at the top of `release` (`PBS_TAG`, `PBS_PY` and the two hashes, taken from that release's `SHA256SUMS`). The zips and a manifest listing their hashes are signed with your signing key, and the manifest is verified against `desktop/release-signers` before anything is published. If building a bundle fails, the local tag stays, nothing is pushed, and it says how to continue.

It then asks once, and on `y` pushes the branch and tag and publishes the GitHub release with the notes, the manifest, its signature, both zips and `jebctl-macos` (the universal native jebctl, built from `desktop/cli` with the version baked in next to the app zip, and copied into every bundle as `desktop/bin/jebctl`). The old `JebDesktop-<tag>-macos.zip` and the tag message's `app-sha256` are still published while older installs that update from a git clone convert to the bundle layout; they can be dropped later. That last step needs `gh` signed in. Without a terminal it prints the commands instead. `./release bundle --tag <tag> --app <dir> --key <key> --out <dir>` builds the bundles on their own (`--from-tree` uses the working tree instead of a tag).

It doesn't use release-please itself because that tool creates tags on GitHub's side, unsigned, and installs only trust releases signed by a pinned key.

To check a published release the way a new user gets it, run `./release smoke` (or `./release smoke v1.2.0` for another tag; `--dry-run` prints the plan). It works in a sandbox under `.git/jeb-smoke/<tag>/` with a fake home folder, so your own install is never touched: it downloads the release's manifest, signature and `jebctl-macos` over HTTPS (`JEB_RELEASE_BASE` overrides where releases are read), verifies them against `desktop/release-signers`, checks that `jebctl-macos` matches the manifest and reports the tag from `--version`, then runs that `jebctl-macos install --no-agents`, which downloads this Mac's zip, unpacks it into the sandbox's `.jeb/versions/<tag>` and runs the bundle's own install (no LaunchAgent, `launchctl` or PATH change). Releases older than v1.5.0 are refused: their `jebctl-macos` installs with gh. It checks that the prebuilt app is signed and points at the bundle's mod, that `current` and the plugin setting are right, and that exactly one version is on disk. It then runs `jebctl follow --dry-run` (the Python HTTPS path) and `jebctl doctor` read-only. An earlier sandbox is moved aside to `old-<time>`, not deleted. A pre-release tag (`v1.5.0-rc.1`) is smoked only when it is the newest tag or named explicitly.

Existing installs pick the release up on their next check either way. On GitHub, it's worth protecting `v*` tags and `main` so only the owner can create or move them.
