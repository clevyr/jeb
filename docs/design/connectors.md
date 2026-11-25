# Connectors: design proposal (Slack first)

Status: proposal. Nothing here is built yet.

Date: 2026-11-25

This document proposes how Jeb could talk to outside services, starting with Slack. External facts are marked **[verified]** when they come from the live documentation read on 2026-11-25, and **[assumption]** when they still need checking. Assumptions A1 to A10 in section 4.0 are checked in chunk 0 of the plan.

## 1. Where Jeb is today

Jeb already sees when Claude Code uses an MCP server or a claude.ai connector. The hooks read the server name from `mcp__<server>__<tool>` and map it through a fixed table in `mod/hooks/mcp.ts`. Only a glyph and a fixed line come out. An unknown server is never named. This needs no token, so "Claude used Slack" is already visible.

Jeb's other outside contacts are GitHub update checks and Haiku calls through Claude Code. The docs promise that no work names, paths or text leave a session, and that hooks only observe: no network, no processes, no file writes.

Constraints that shape the design:

- The plugin store belongs to the mod. The mod is the only writer. The desktop only reads it.
- Live records are strict `v:1`. Anything else is dropped, so they cannot be extended.
- Hooks may not do network, process or file-write work, and a quiet tick makes no `$` calls. The mod may only read a small file at decision points.
- No new LaunchAgent. Anything long-lived must be a child of `com.jeb.desktop`.
- The app is ad-hoc signed and not sandboxed. It can spawn processes, but plugins run with the user's full rights, and the Keychain behaves differently for ad-hoc code (section 3.7).
- Plugins ship prebuilt inside the signed release. Install compiles nothing.
- With no connectors enabled, `jebctl doctor` output must be byte-identical to today.
- No Python, and no third-party Swift packages. Foundation and system frameworks only.
- Nothing edits `~/.claude/settings.json`.

## 2. Options and recommendation

### 2.1 Three options

**A. Observe, do not connect.** Keep reading Claude Code's own MCP and connector traffic. It costs nothing and holds no secrets. It is blind when Claude Code is not running, and it cannot be told that someone pinged you.

**B. Native connectors for everything.** The desktop app hosts out-of-process plugins, each with its own credentials. This gives always-on awareness and the ability to act. It needs a plugin host, a protocol, a Sanitize layer, secret handling, `jebctl` commands and doctor lines, repeated per service.

**C. Hybrid.** A stays the default for every service. B is built once, as a small generic host, and used only where A cannot help: inbound awareness while Claude Code is closed, and acting for the user.

### 2.2 Recommendation

**Option C.** Observe by default. Build a native connector only for Slack, for the three things A cannot do: status, letters to @Jeb, and later approved posts.

- Jira and Atlassian stay on A. Ticket cows already work and need no token.
- Calendar stays on A. Slack status usually reflects meetings anyway.
- A user who adds no connector sees no change: no file, agent or prompt is created until `jebctl connector add`.
- Message bodies reach only the Slack plugin process, and are discarded there.

### 2.3 Should a Jeb plugin be an MCP server?

No. Borrow MCP's framing, do not be MCP.

MCP facts **[verified]**: JSON-RPC 2.0, newline-delimited, over stdio. The lifecycle is `initialize`, then `notifications/initialized`. Shutdown is close stdin, then SIGTERM, then SIGKILL. Claude Code hands secrets to MCP servers by putting them in the child's environment.

Why not:

1. MCP is built around the client calling the server. Jeb's rule is the reverse: the plugin pushes events, and Jeb never asks.
2. Sampling, elicitation, roots, tools and prompts would all need negotiating down to nothing. Each is a way for a plugin to ask Jeb for something.
3. The MCP path puts tokens in environment variables, which is the trap this design avoids.
4. Claude Code would start its own copy per session, so two Slack connections would share one token.
5. An MCP server exists to hand content to the model. A Jeb connector exists to keep content out of Jeb.

What Jeb borrows: NDJSON JSON-RPC 2.0 on stdio, logs on stderr, the initialize handshake shape, the shutdown ladder and per-request timeouts. The protocol identifier is not an MCP date version, so an MCP server pointed at Jeb fails cleanly at `initialize`. An author may ship one binary that speaks both, but Jeb never relies on it.

## 3. Architecture

### 3.1 Process picture

```
Slack (TLS) <-> jeb-slack (child process; reads its own Keychain items)
                   | stdin/stdout: NDJSON JSON-RPC, events only
                   v
JebDesktop  [ConnectorHost on a private serial queue] -> Sanitize -> ConnectorSnapshot (enums and counts)
                   |                                                    |-> desktop scene and menu (main thread, at most 1 Hz)
                   |                                                    \-> JEB_HOME/connectors.json (0600, at most 1 KiB)
                   v                                                              |
JEB_HOME/connectors/<id>/status.json  <- jebctl doctor                            v
                                                    mod reads at decision points only -> band lines and visits
```

The store is untouched. Claude Code's settings are untouched. No new LaunchAgent is added.

### 3.2 Plugin host

**Owner.** The desktop app, in a new `desktop/src/ConnectorHost.swift`. It is the only long-lived process, kept alive by `com.jeb.desktop` and healed by the watchdog. The mod cannot host, and `jebctl` is short-lived.

**Start.** The host does not start when `JEB_BENCH` is set, or while a hand-over child is still waiting (it starts after `takeOver`), or when no `JEB_HOME/connectors/*/enabled` marker exists. With no markers the host does nothing: no directory, no file, no thread.

**Discovery.** Manifests are read only from `~/.jeb/current/connectors/*/connector.json`, inside the signed release. The executable must resolve under its own manifest directory. No sideloading in v1.

**Enable state.** Marker files, as with `updates-paused` and `quit`:

- `JEB_HOME/connectors/<id>/enabled` (empty).
- `JEB_HOME/connectors/<id>/grants.json`, written by `jebctl` when the user approves.

Data directories are keyed by plugin id, never by path. `jebctl` posts the Darwin notification `com.jeb.desktop.connectors-changed` after a change, as it does for `update-finished`. The app's existing 60 s timer rescans markers as a fallback.

**Spawn.** Foundation `Process`, with argv from the manifest (never secrets), three pipes, and a minimal environment: `PATH=/usr/bin:/bin`, `HOME`, `LANG`, `JEB_CONNECTOR_ID`, and `JEB_CONNECTOR_DATA=<JEB_HOME>/connectors/<id>/data` (mode 0700).

**I/O.**

- All reads and writes run on a private serial queue, never on main.
- stdout is split on `\n` with a 16 KiB cap per line. Longer lines are discarded and counted. Three oversize lines restart the plugin.
- stdin is non-blocking. Persistent `EAGAIN` for 5 s means the plugin is not reading, and it is restarted.
- stderr goes to `JEB_HOME/connectors/<id>/plugin.log` (0600, 256 KiB, one rotation), with `xox[a-z]-...` and `xapp-...` replaced by `[token]`. It is never forwarded to `run.log`.

**Main thread.** The host publishes an immutable `ConnectorSnapshot` to main at most once per second. The scene and menu read it. The menu is rebuilt on open, as today.

**Limits.**

| Item | Limit |
|---|---|
| `initialize` | 5 s |
| `ping` | every 60 s, 5 s timeout |
| Inbound events | token bucket, 30 per minute, burst 10; excess dropped and counted |
| `shutdown` | 2 s, then close stdin and wait 2 s, then SIGTERM and wait 2 s, then SIGKILL |

**Restart.** Backoff of 2, 4, 8 s and so on up to 900 s. Five abnormal exits within 15 minutes park the plugin until a menu "Retry", `jebctl connector restart <id>`, or the next app start. An exit after `revoked` never restarts.

**Status file.** `JEB_HOME/connectors/<id>/status.json`, written on change. It holds `v`, `state`, `restarts`, `parkedAt`, `dropped`, `lastError`, `protocol` and `version`. Doctor reads it.

**Stop.** On quit, on SIGTERM or SIGINT, on the old instance receiving SIGUSR1 during hand-over, and on disable, the shutdown ladder runs for every child. Plugins must also exit on stdin EOF. Launchd tearing down the process group is a backstop **[assumption: `man launchd.plist`, `AbandonProcessGroup`]**.

**Rollback.** A release older than the host ignores the markers. Tokens stay in the Keychain. Rolling forward resumes.

### 3.3 Manifest

The file is `connectors/slack/connector.json` in the repo and the bundle.

```json
{
  "manifestVersion": 1,
  "id": "com.jeb.slack",
  "publisher": "jeb",
  "name": "Slack",
  "version": "1.0.0",
  "engines": { "jeb": ">=1.10.0" },
  "protocol": { "min": 1, "max": 1 },
  "exec": {
    "path": "./jeb-slack",
    "serve": ["serve"],
    "setup": ["setup"],
    "forget": ["forget"]
  },
  "emits": ["connector.status@1", "slack.presence@1", "slack.inbox@1", "slack.post.result@1"],
  "accepts": ["jeb.ack@1", "jeb.post@1"],
  "reaches": ["desktop", "band", "menu"],
  "secrets": { "keychainService": "com.jeb.connector.slack", "accounts": ["bot", "app"] },
  "network": { "hosts": ["slack.com", "*.slack.com"] },
  "limits": { "eventsPerMinute": 30, "maxLineBytes": 16384 },
  "integrity": null
}
```

Rules:

- `manifestVersion` must be 1 for the manifest to load.
- `id` is reverse-DNS, ASCII `[a-z0-9.-]`, at most 64 characters. It names data directories, the Keychain service, markers and status. It is never a path.
- `name` is ASCII, at most 32 characters, shown only in the menu and doctor.
- `exec.path` must stay inside the manifest's directory.
- `network` and `secrets` are declarations. In v1 `jebctl` shows them to the user, and the OS does not enforce them.
- `integrity` is reserved for a future publisher signature. It is `null` for first-party plugins, which the signed release already covers.

### 3.4 Wire protocol

Newline-delimited JSON-RPC 2.0 over stdio: UTF-8, one object per line, stdout for protocol only. Requests are for lifecycle only (`initialize`, `ping`, `shutdown`). All domain traffic is the `event` notification, in both directions. A plugin may not send requests, and any it sends get `-32601`.

Handshake, host to plugin:

```json
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocol":1,"host":{"name":"jeb-desktop","version":"1.10.0"},"connector":{"id":"com.jeb.slack"},"grants":{"emits":["connector.status@1","slack.presence@1","slack.inbox@1"],"accepts":["jeb.ack@1"]},"limits":{"maxLineBytes":16384,"eventsPerMinute":30,"pingEveryS":60}}}
```

Plugin reply, then the notification that completes it:

```json
{"jsonrpc":"2.0","id":1,"result":{"protocol":1,"connector":{"id":"com.jeb.slack","version":"1.0.0"},"capabilities":{"emits":["connector.status@1","slack.presence@1","slack.inbox@1","slack.post.result@1"],"accepts":["jeb.ack@1","jeb.post@1"]}}}
{"jsonrpc":"2.0","method":"initialized","params":{}}
```

The effective set is the declared capabilities, intersected with the manifest, intersected with the user's grants. Here `jeb.post` is declared but not granted, so it is never sent.

Inbound events, plugin to host:

```json
{"jsonrpc":"2.0","method":"event","params":{"type":"slack.inbox","v":1,"seq":42,"data":{"letters":2,"mentions":1}}}
{"jsonrpc":"2.0","method":"event","params":{"type":"slack.presence","v":1,"seq":43,"data":{"kind":"meeting","untilMin":45}}}
{"jsonrpc":"2.0","method":"event","params":{"type":"connector.status","v":1,"seq":44,"data":{"state":"connected","retryAfterS":0}}}
```

Outbound events, host to plugin:

```json
{"jsonrpc":"2.0","method":"event","params":{"type":"jeb.ack","v":1,"seq":7,"data":{"what":"inbox"}}}
{"jsonrpc":"2.0","method":"event","params":{"type":"jeb.post","v":1,"seq":8,"data":{"ref":"a1b2c3d4","template":"farm_report","text":"Jeb's farm today: 3 cows home, 2 harvests in."}}}
```

Errors:

```json
{"jsonrpc":"2.0","id":1,"error":{"code":-32010,"message":"unsupported protocol","data":{"supported":[1],"requested":2}}}
{"jsonrpc":"2.0","method":"rejected","params":{"seq":45,"reason":"field_not_allowed"}}
```

The first is a plugin refusing an unsupported version. The host marks it `incompatible`, parks it, and doctor shows a FIX. The second tells a plugin that event 45 was dropped. `reason` is one of `oversize`, `bad_json`, `unknown_type`, `not_granted`, `field_not_allowed`, `out_of_range`, `seq_regressed`, `rate_limited`, `token_shape`.

Ping and shutdown:

```json
{"jsonrpc":"2.0","id":9,"method":"ping"}
{"jsonrpc":"2.0","id":9,"result":{}}
{"jsonrpc":"2.0","id":12,"method":"shutdown","params":{"reason":"app_quit"}}
{"jsonrpc":"2.0","id":12,"result":{}}
```

Shutdown `reason` is one of `app_quit`, `disabled`, `handover`, `update`, `parked`. The host then closes stdin and the 2 s, SIGTERM, 2 s, SIGKILL ladder follows.

### 3.5 Event catalogue (v1)

Every field is an enum, a bool or a bounded integer. The inbound catalogue has no free-text field.

| Event | Direction | Fields | Can it carry a name, channel, body or token? |
|---|---|---|---|
| `connector.status@1` | in | `state` in {starting, connected, offline, rate_limited, needs_auth, revoked, error}; `retryAfterS` 0..3600 | No |
| `slack.presence@1` | in | `kind` in {none, meeting, lunch, focus, away, vacation, sick, commuting, other}; `untilMin` 0..1440 in 15-minute steps, 0 for no expiry | No. Status text is never read. The emoji is mapped in the plugin from a fixed allowlist, and anything else becomes `other`. |
| `slack.inbox@1` | in | `letters` 0..99 (DMs to @Jeb since the last ack); `mentions` 0..99 | No. Sender, channel, ts and text are never sent. |
| `slack.post.result@1` | in | `ref` (8 lowercase hex, must echo a ref the host issued); `outcome` in {posted, rate_limited, not_in_channel, revoked, failed} | No |
| `jeb.ack@1` | out | `what` in {inbox} | No |
| `jeb.post@1` | out (chunk 6) | `ref`; `template` in {farm_report, harvest_done, back_from_break}; `text` up to 280 characters | The text is host-generated from a fixed template plus integers. It contains no plugin input. The destination channel lives only in the plugin's data directory. |

`seq` is a monotonic `uint32` per direction. The host stamps arrival time and never trusts plugin clocks.

### 3.6 Permissions

1. **Install-time grant.** `jebctl connector add <id>` prints the manifest's `emits`, `accepts`, `reaches`, `network` and `secrets` in plain English. On a yes it writes `grants.json` (0600) with the accepted subset. `jeb.post` is a separate grant, off by default.
2. **Runtime.** Events outside the effective set are rejected. `reaches` decides whether a value may reach the desktop scene, the band file or the menu.
3. **Acting.** Every outbound `jeb.post` needs a user click on a dialog showing the exact text. There is no standing approval. The band, the mod and Claude Code have no path to request a post.
4. **OS level.** Not enforced in v1. Trust comes from the plugin shipping in the signed release. A later sandbox could enforce the same `network` and `secrets` fields.

### 3.7 Secret storage

- Tokens live only in the login Keychain, as generic-password items with service `com.jeb.connector.<id-suffix>` and the accounts the manifest declares (`bot`, `app`).
- Only the plugin process reads them, through Security.framework `SecItemCopyMatching`. The host never reads, holds or forwards a token. `jebctl` never sees one. The `/usr/bin/security` CLI is not used, because `add-generic-password -w <secret>` would put the secret in argv.
- `jebctl connector add slack` runs `jeb-slack setup` attached to the terminal. The plugin reads each token from `/dev/tty` with echo off, validates it against Slack (`auth.test` **[assumption: docs.slack.dev/reference/methods/auth.test]**), then writes the item itself, so the item's ACL trusts the plugin binary.
- A token never travels in argv, the environment, the store, `connectors.json`, `status.json`, `grants.json`, JSON-RPC or `run.log`. In `plugin.log` the host redacts it as defence in depth.
- On the wire to Slack, the token goes only in the `Authorization` header, never in a URL **[verified]**.
- The app has no keychain-access-groups entitlement, so only the legacy file-based keychain is available **[assumption: Apple TN3137]**. Its ACL is bound to the designated requirement, which for ad-hoc code is the cdhash. That changes every release, so expect an "allow access" prompt after each update **[assumption: Apple TN3127]**. See the open question on this.
- `forget` deletes the items. `jebctl uninstall` runs `forget` for every enabled connector before purging `JEB_HOME`, so no Keychain items are left behind.

### 3.8 Sanitize layer

One pure function in `desktop/src/Sanitize.swift`, modelled on the strict parse in `desktop/src/Live.swift`:

```
Sanitize.accept(line: Data, grants: Grants, last: SeqState) -> Result<ConnectorEvent, Reject>
```

Checks, in order:

1. The line is at most 16 KiB, valid UTF-8, with no NUL.
2. It is a JSON object with `jsonrpc == "2.0"`. Duplicate keys are rejected.
3. A request from the plugin is refused with -32601. A response must carry an `id` the host issued.
4. `method == "event"`.
5. `type@v` is in the effective emits.
6. `data` has exactly the schema's keys. Extra or missing keys are rejected.
7. Integers are clamped to range. A non-integer is rejected.
8. Enums match exactly. An unknown value is rejected.
9. A string anywhere other than an enum slot is rejected.
10. `seq` is greater than the last value.
11. The rate bucket has room.
12. Token-shape screen. If the raw line matches `xox[a-z]-` or `xapp-`, it is rejected, the plugin is parked, and doctor shows a FIX.

The output is a typed `ConnectorEvent`, folded into a `ConnectorSnapshot`. Only the snapshot feeds the desktop, the menu and `connectors.json`. In-app sources, such as Apple Health later, would build the same typed events and use the same entry.

**`connectors.json`.** The app writes `JEB_HOME/connectors.json` with a private-file write, at most 1 KiB:

```json
{"v":1,"at":1795000000,"ttl":600,"slack":{"state":"connected","presence":"meeting","untilMin":45,"letters":2,"mentions":1}}
```

It is a sibling of `flags.json` and not part of it. Flags are durable user preferences with a 4 KiB cap, read fail-open. Connector state changes every few minutes and goes away when the host stops. If they shared a file, a connector could push it over the cap and the user's "drops off" choice would be ignored.

The reader code is the same, though: the flags path function becomes a general app-file path function. The mod parses the file strictly in a new `mod/hooks/outside.ts`: `v == 1`, enums and ranges as above, ignored when `now - at > ttl`, and anything else means "no connectors". The mod reads it only at decision points (`session.start` and the visit draw), at most once per 60 s, never on a quiet tick.

### 3.9 Versioning

- The manifest has `manifestVersion`. The host loads only versions it knows.
- The protocol is an integer, negotiated within the manifest's `min..max` and the host's supported set. A mismatch gives the -32010 error and the plugin is parked as `incompatible`.
- Events are versioned by `type@v`. A new field means a new `v`. The host may accept several versions and map them to one typed event.
- `connectors.json` is `v:1` and strict, like live records. A future mod that sees an unknown `v` ignores the file.
- For a later connector marketplace, the id is reverse-DNS, `publisher` and `integrity` are reserved, and nothing is keyed by path. A registry could supply manifests and signatures without a format change.

### 3.10 `jebctl` commands

New file `desktop/cli/Connectors.swift`, dispatched from `desktop/cli/main.swift`.

| Command | What it does |
|---|---|
| `jebctl connector list` | Lists connectors in this install and their state, read from `status.json`. With none it prints "No connectors are on." |
| `jebctl connector add <name>` | Finds the manifest in `~/.jeb/current/connectors/<name>/`, shows the grants and asks y/n (refuses without a TTY), runs `<exe> setup` attached to the TTY, writes `grants.json` and `enabled`, then posts `connectors-changed`. Running it again repairs the sign-in. |
| `jebctl connector remove <name>` | Removes the marker, posts the notification, waits up to 10 s for the host to stop the plugin, runs `<exe> forget`, then deletes `JEB_HOME/connectors/<id>/`. |
| `jebctl connector restart <name>` | Clears the parked state and posts the notification. |
| Update | Nothing new. Connectors ride the release: `follow` swaps `current`, the app reloads, and the host restarts plugins from the new `current`. |
| Rollback | Below the host's version, connectors are simply off. |
| `jebctl uninstall` | Runs `forget` for each enabled connector first. |

### 3.11 `jebctl doctor`

A new "Connectors" section is printed only when at least one `enabled` marker exists, so the no-connector output stays identical.

| Condition | Line | Step |
|---|---|---|
| Running and connected | `ok    Slack connector is on (connected)` | None |
| `offline` | `note  Slack connector is offline (no network); Jeb works without it` | None |
| `needs_auth` or `revoked` | `FIX   Slack connector needs signing in again` | New `FixID.connectorSignIn`, a sentence: "Run jebctl connector add slack" |
| Parked (crash loop or token shape) | `FIX   Slack connector was stopped after repeated failures` | New `FixID.connectorRestart`, runnable: `jebctl connector restart slack` |
| Marker present, manifest or binary missing | `FIX   Slack connector is on but this Jeb version doesn't include it` | Existing `.update` |
| `incompatible` | `FIX   Slack connector doesn't match this Jeb version` | `.update` |

Doctor never touches the Keychain, so it never causes a prompt. It trusts the state in `status.json`.

## 4. First connector: Slack

### 4.0 External facts and assumptions

Verified on 2026-11-25:

- **Socket Mode** (docs.slack.dev/apis/events-api/using-socket-mode): uses an app-level `xapp-` token. The WebSocket URL comes from `apps.connections.open`, with the token in the `Authorization` header. Up to 10 connections. Each envelope has an `envelope_id` that must be acknowledged. Connections refresh "once every few hours", with `warning` and `refresh_requested` disconnects. Socket Mode apps are "not currently allowed in the public Slack Marketplace".
- **Rate limits** (docs.slack.dev/apis/web-api/rate-limits): Tier 1 is 1+ per minute, Tier 2 20+, Tier 3 50+, Tier 4 100+. A 429 carries `Retry-After`. Posting is "no more than one message per second per channel".
- **Changelog 2025-05-29** (docs.slack.dev/changelog/2025/05/29/rate-limit-changes-for-non-marketplace-apps): `conversations.history` and `conversations.replies` drop to 1 request per minute for commercially distributed non-Marketplace apps. "Internal customer-built applications are not impacted."
- **`app_mention`** needs `app_mentions:read`. No event is sent when the app is not in the conversation. DMs do not trigger it, so `message.im` is used for those.
- **`message.im`** needs `im:history` and has `channel_type: "im"`.
- **`users.profile.get`**: bot or user token with `users.profile:read`. Tier 4. `status_text` up to 100 characters, `status_emoji`, and `status_expiration` as a Unix timestamp where 0 means no expiry.
- **`user_status_changed`** needs `users:read`, and its payload carries `name`, `real_name` and `display_name`.
- **`tokens_revoked`** and **`app_uninstalled`** need no scope. The first lists user IDs, not tokens. The second may arrive before or after the first, and the app is uninstalled "until its final user and bot tokens are revoked".
- **`chat.postMessage`** needs `chat:write`. The app must be in the channel unless it has `chat:write.public`. A user ID as `channel` opens a DM with the app. About 1 message per second per channel.
- **OAuth v2**: `redirect_uri` "must use HTTPS". The exchange in `oauth.v2.access` needs the client secret. "OAuth tokens do not expire" unless token rotation is on.

Assumptions to check in chunk 0:

- **A1.** App-level token scope `connections:write` for `apps.connections.open`. Check docs.slack.dev/reference/methods/apps.connections.open.
- **A2.** Envelope ack time limit and the retry window. Check the Socket Mode page and docs.slack.dev/apis/events-api.
- **A3.** App manifest format (`settings.socket_mode_enabled`, `oauth_config.scopes.bot`, `settings.event_subscriptions.bot_events`). Check docs.slack.dev/app-manifests.
- **A4.** Error strings `invalid_auth`, `token_revoked`, `account_inactive`. Check the "Errors" section of the auth.test and users.profile.get pages.
- **A5.** `auth.revoke` with a bot token. Check docs.slack.dev/reference/methods/auth.revoke.
- **A6.** `message.im` also delivers the bot's own messages (with `bot_id` or a subtype), which must be filtered. Check the message event subtypes page.
- **A7.** Adding a scope later (`chat:write`) requires reinstalling the app. Check docs.slack.dev/authentication/installing-with-oauth.
- **A8.** Calendar integrations set a calendar emoji for "In a meeting". Check the help pages of the Google Calendar and Outlook Calendar apps for Slack.
- **A9.** `apps.connections.open` rate tier. Check its reference page.
- **A10.** Workspace admin approval may be required to install a custom app. Check Slack's help center, "Manage app approval".

### 4.1 Transport

| Approach | Verdict |
|---|---|
| Events API (HTTP) | Needs a public HTTPS endpoint. A laptop has none, so it waits for a Jeb server. |
| Polling `conversations.history` | Needs `*:history` scopes over whole conversations, sees far more than needed, and is 1 request per minute for distributed non-Marketplace apps. |
| **Socket Mode (chosen)** | An outbound WebSocket. No public URL, works behind NAT, and is Foundation `URLSessionWebSocketTask` with no third-party package. Its only limit is no Marketplace listing, which does not matter for an internal app. |

Status is the exception. It is polled with `users.profile.get` for the one paired user every 120 s, which is 0.5 requests per minute against a 100+ tier. The alternative, `user_status_changed`, would stream every colleague's name and status into the plugin.

### 4.2 Tokens and the app

A bot token (`xoxb-`) plus an app-level token (`xapp-`). No user token in v1.

- A bot sees only what people deliberately send to @Jeb, so senders have chosen to address Jeb.
- It can read the owner's status with `users.profile:read`.
- A user token with `im:history` would expose every private conversation the user is in. That is too much for a farm game.

Jeb ships `connectors/slack/slack-app-manifest.json`. The user, or the org's admin, creates the app with "Create from manifest", installs it to the workspace, and pastes the two tokens into `jeb-slack setup`. This makes it an internal customer-built app, exempt from the 2025 limits and fine for Socket Mode. A distributed OAuth app would need an HTTPS redirect, so it waits for a Jeb server.

### 4.3 Minimum scopes

| Scope | Token | For | Chunk |
|---|---|---|---|
| `app_mentions:read` | bot | Counting @Jeb mentions | 5 |
| `im:history` | bot | Counting DMs to @Jeb, and pairing | 5 |
| `users.profile:read` | bot | The owner's status emoji and expiry | 5 |
| `connections:write` | app-level | Socket Mode (A1) | 5 |
| none | bot | `tokens_revoked`, `app_uninstalled` | 5 |
| `chat:write` | bot | Approved posts | 6 only; needs a reinstall (A7) |

Not requested: `users:read`, `channels:history`, `chat:write.public`, `dnd:read`, or any user scope.

### 4.4 Pairing

- `setup` prints a 6-digit code and asks the user to DM @Jeb with it.
- The plugin takes the sender ID of the `message.im` whose text equals the code.
- The owner's user ID is stored in `JEB_CONNECTOR_DATA/config.json` (0600). It is an identifier, not a secret, and it never leaves the plugin.
- During pairing, DM text is compared in memory and then dropped.

### 4.5 What Jeb does with each input

| Slack input | In the plugin | Event to the host | Desktop | Band (mod) |
|---|---|---|---|---|
| DM to @Jeb (`message.im`, not from the bot itself, A6) | Ack the envelope, `letters += 1` (cap 99), drop text, user, channel and ts at once. A ts set is kept for dedupe only, in memory, capped at 500 and expiring after 24 h. | `slack.inbox`, coalesced to at most one per 10 s | The flag goes up on the mailbox prop with a count shown as 1-9 or "9+". | At the next visit decision, a mail visit may come outside the usual 10:00-14:00 window, with a fixed line and a count only. |
| @Jeb in a channel (`app_mention`) | Same, `mentions += 1` | Same | Same flag | A fixed line such as "Somebody's hollerin' for Jeb in town." |
| Owner's status change (poll) | Map `status_emoji` through a fixed allowlist (calendar to `meeting`, plate to `lunch`, palm tree to `vacation`, and so on) and everything else to `other`. `status_text` is never read. Expiry is rounded to 15 minutes. | `slack.presence` on change only | A pose or sign, such as a "Gone fishin'" sign for vacation. Nothing for `none` or `other`. | `meeting` or `focus` makes the band no louder than `ambient`. The user's own `talk` setting is never raised, and `silent` stays silent. |
| User opens the mailbox (prop click or menu item) | Reset the counts | `jeb.ack {what:"inbox"}` from the host | The flag goes down | None |

Jeb never shows or says a sender, a channel, a body or a status text.

### 4.6 Posting

- **v1 (chunk 5): nothing.** The connector is read-only.
- **Chunk 6, opt-in.** A menu item "Post farm report to Slack..." opens a dialog showing the exact host-rendered text, with Post and Cancel. Each post needs its own click. There is at most one post per template per day and six per day in total. The destination is the owner's DM with @Jeb, or one channel ID chosen in `setup`, stored only in the plugin's data directory. Neither Claude Code nor the mod can trigger a post.

### 4.7 Rate limits

| Call | Our rate | Slack's limit |
|---|---|---|
| `users.profile.get` | Every 120 s | Tier 4 |
| `apps.connections.open` | Only on (re)connect, backoff 1 s up to 5 min with jitter, at most 1 per minute when steady (A9) | |
| `chat.postMessage` | At most 6 per day | About 1 per second per channel |

On a 429 the plugin honours `Retry-After`, emits `connector.status {state:"rate_limited", retryAfterS}`, and the menu shows "Slack: waiting". The plugin keeps a single Socket Mode connection.

### 4.8 Offline behaviour

- With no network at start, or after sleep, the plugin reports `offline` and reconnects with backoff. The desktop hides the flag after 10 minutes stale, and the band ignores `connectors.json` once `now - at > ttl`. Otherwise Jeb works as today.
- Events missed while offline are missed (A2). Counts are ambience, not a ledger.
- Counts live in plugin memory, so a restart resets them.
- On Slack's routine refresh (`refresh_requested`, `warning`), the plugin opens the new connection before closing the old one. Refreshes are **[verified]**. The overlap technique is an assumption (A2).

### 4.9 Revocation

The plugin treats these as revocation: a `tokens_revoked` or `app_uninstalled` event, a Web API error of `invalid_auth`, `token_revoked` or `account_inactive` (A4), or an auth failure from `apps.connections.open`. It then sends `connector.status {state:"revoked"}`, deletes its Keychain items and exits 0.

The host records `revoked` and does not restart it. The menu shows "Slack: signed out (run `jebctl connector add slack`)". Doctor shows a FIX. The farm is unaffected.

`jebctl connector remove slack` runs `forget`, which calls `auth.revoke` (A5), deletes the Keychain items and the data directory. Jeb then tells the user they can also delete the Slack app from the workspace.

## 5. Phased plan

Nothing ships before chunk 1, so each chunk ships alone. New mod tests go in new files.

**Chunk 0: spike (not shipped).** On a throwaway workspace and a scratch macOS user, check A1 to A10, measure the Keychain prompt after re-signing ad-hoc versus with a self-signed identity, and measure `URLSessionWebSocketTask` reconnect behaviour. Output: a short decision record. Risk: none to users.

**Chunk 1: wire codec and Sanitize (pure, unused).**
Files: `desktop/src/ConnectorWire.swift`, `desktop/src/Sanitize.swift`, `desktop/src/build.sh`, `desktop/tests/sanitize-test.swift`.
Tests: the seam is `Sanitize.accept(line:grants:last:)`, observed by return value across a golden table of 40+ lines (valid events, oversize, NUL, bad UTF-8, duplicate key, extra field, wrong types, unknown enum, out-of-range, seq regression, not granted, plugin request, unknown response id, token shape, nested object). A second seam is the pure snapshot fold, observed by the resulting value. Risk: low.

**Chunk 2: host lifecycle, behind markers.**
Files: `desktop/src/ConnectorHost.swift`, `desktop/src/main.swift` (start after `takeOver`, never under `JEB_BENCH`, stop on SIGTERM, SIGINT and SIGUSR1), `desktop/src/build.sh`, sh fixture connectors under `desktop/tests/fixtures/connectors/`, `desktop/tests/connector-host-test.swift`.
Tests: the seam is `ConnectorHost(root:home:clock:)` built with a fixture root. The root is an init parameter, not an environment variable, so no production override exists. Fixtures cover a good plugin (observe the wire transcript and `status.json`), one that ignores shutdown (gone within 6.5 s), a crash loop (restart times on a fake clock, parked after 5), a flood (dropped counts, snapshot publishes at most 1 Hz), a 1 MiB line, a token leak (parked), and an old protocol (`incompatible`). With no markers, no process is spawned and no `connectors/` directory is created. Risk: medium. Nothing runs without a marker, and only `jebctl` in chunk 4 can create one.

**Chunk 3: band file and desktop surface.**
Files: `desktop/src/ConnectorHost.swift` (writes and removes `connectors.json`), `desktop/src/Homestead.swift` (flag and poses), a mailbox-flag sprite, `mod/hooks/outside.ts`, `mod/hooks/flags.ts`, `mod/hooks/register.tsx`, `mod/hooks/visits.ts`, `mod/tests/outside.test.tsx`, `desktop/tests/connectors-file-test.swift`.
Tests: `outsideOf` return values for valid, wrong version, stale, oversize, extra key, bad counts and missing file. A register-level test with the `claude-code/testing` mock observes the call log: a quiet tick makes zero `$` calls and a visit decision makes one read. A visit test observes that mail can be drawn outside 10:00-14:00 when letters exist. Swift tests observe the `connectors.json` bytes against a golden (mode 0600) and a golden PNG from a screenshot fixture. Risk: low to medium. Behaviour changes only when the file exists, and only the app writes it.

**Chunk 4: `jebctl connector`, doctor and uninstall.**
Files: `desktop/cli/Connectors.swift`, `desktop/cli/main.swift`, `desktop/cli/Commands.swift`, `desktop/cli/Doctor.swift`, `desktop/cli/Install.swift`, `docs/reference.md`, `desktop/cli/tests/ConnectorTests.swift`, new cases in `desktop/cli/tests/DoctorTests.swift`.
Tests: the existing CLI harness sandbox with a fixture bundle whose setup and forget scripts log their argv. Observes files written (`enabled`, `grants.json` at 0600, nothing without a TTY), golden stdout for `connector list`, doctor goldens (existing output unchanged with no markers, new ones for each state), and that `forget` ran before `JEB_HOME` was purged. Until Slack ships, `add slack` prints "This Jeb version has no Slack connector". Risk: low to medium. It ships without Slack, and doctor stays silent without markers.

**Chunk 5: Slack connector, read-only and opt-in.**
Files: `connectors/slack/connector.json`, `connectors/slack/slack-app-manifest.json`, `connectors/slack/src/` (main, Keychain, SocketMode, WebAPI, SlackCore, StatusMap, Setup), `connectors/slack/build.sh`, the `dev/release` build step and `dev/release/Bundles.swift` (tree and required lists), `desktop/cli/Follow.swift` (architecture check), the network statement in `README.md`, a Slack setup doc.
Tests: the seam is the pure `SlackCore.handle(envelope:)`, observed by return value for recorded-shape envelopes (mention, DM from a user, DM from the bot, duplicate ts, other subtypes, revocation events, hello, warning, refresh). A property check asserts no user, channel, ts or text string appears in any output. `StatusMap` is checked by return value. `WebAPI` runs against the loopback HTTP test server with the base URL as an init parameter, and observes the wire request (bearer header present, token absent from URL and body), 429 handling, and `invalid_auth` leading to a Keychain delete. `SecretStore` is a protocol with an in-memory fake. An end-to-end test runs the chunk 2 host against a loopback WebSocket fake and observes wire messages and `connectors.json` bytes. The bundle dry run fails when the binary is missing or single-architecture. Risk: high. This is the first networked component that holds secrets, against a third-party API that can change. Mitigations: off by default, read-only, parked on any leak signal, visible in doctor.

**Chunk 6: approved posting (optional).**
Files: `connectors/slack/connector.json`, the app manifest (`chat:write`), `desktop/src/ConnectorHost.swift`, `desktop/src/StatusMenu.swift`, `desktop/src/Sanitize.swift`, `connectors/slack/src/SlackCore.swift` and `WebAPI.swift`, the grant prompt in `jebctl connector add`.
Tests: through the menu test hook, a Post click produces exactly one outbound wire message with host-rendered text and Cancel produces none. A result with an unknown ref is rejected (return value). The plugin's daily cap turns a seventh post into `failed` with no HTTP request. A post without the grant is never sent (stdin transcript). Risk: medium. Jeb acts for the user, mitigated by per-post approval and fixed templates.

## 6. Open questions

1. **Setup burden.** Each user creates a Slack app from the shipped manifest and pastes two tokens, and many workspaces require admin approval for custom apps (A10). A one-click "Add to Slack" needs an HTTPS OAuth redirect, which means a Jeb server. *Recommendation:* accept the manual setup for v1, state the admin-approval requirement up front in the setup doc, and revisit a hosted OAuth app only if a server exists for other reasons.
2. **Which Slack feature is the point?** Status-driven quieting of the band, or counting DMs and mentions to @Jeb. The second only matters if people message the bot. *Recommendation:* treat status as the core feature and counts as secondary. Chunk 0 should confirm that status alone justifies the setup cost before chunk 5 is built.
3. **Keychain prompt after every update.** Ad-hoc signing gives a new cdhash each release, and probably an "allow access" prompt each time. *Recommendation:* let chunk 0 measure it. If it prompts, sign release binaries with a stable self-signed code-signing identity kept with the `jeb-release` key. That needs no Apple Developer ID. Otherwise accept one prompt per update for Slack users only.
4. **One Jeb Slack app or one per workspace?** *Recommendation:* a per-workspace internal app from the shipped manifest now. A distributed app needs the HTTPS redirect from question 1.
5. **A user token for "you were mentioned anywhere" or unread counts?** *Recommendation:* no for v1. It would expose all of the user's DMs and channels to the plugin.
6. **Should Jeb post at all?** *Recommendation:* ship chunk 5 read-only, then decide on chunk 6 after use. If it ships, keep per-post approval of the exact text.
7. **May Slack presence quiet the band?** *Recommendation:* yes. `meeting` and `focus` cap talk at `ambient`, never raise it, and leave `silent` alone.
8. **Letters without the mailbox upgrade?** *Recommendation:* the flag appears only on an owned mailbox. Otherwise show a count in the menu only, so the game's economy stays intact.
9. **Setup surface: Terminal or a menu window?** *Recommendation:* Terminal (`jebctl connector add`) for v1, where the plugin reads tokens itself. A window would make the app the Keychain item's creator and the host a token handler.
10. **Apple Health in-app versus ad-hoc signing.** HealthKit needs entitlements and a provisioning profile, which ad-hoc signing cannot carry **[assumption: Apple HealthKit entitlement docs]**. Whether HealthKit is available on macOS at all also needs checking. *Recommendation:* put Health behind the signing decision in question 3, and route it through `Sanitize.accept` when it comes.
11. **Persist inbox counts across restarts?** *Recommendation:* no. Losing them is harmless and nothing is stored.
12. **Sibling `connectors.json` or keys in `flags.json`?** *Recommendation:* a sibling file with the same reader and writer code, so connector churn can never push user preferences past their 4 KiB cap.
13. **Allow sideloaded connectors before a connector marketplace?** *Recommendation:* no. v1 loads only from the signed `~/.jeb/current/connectors`. Developers test with a dev build and a separate `JEB_HOME`.
14. **Count connector activity in telemetry?** *Recommendation:* no, apart from doctor's local `status.json`.
