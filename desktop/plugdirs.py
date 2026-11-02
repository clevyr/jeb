"""plugdirs.py: how Jeb's mod is registered with Claude Code, shared by ./install, ./uninstall and jebctl.

A release install goes through Claude Code's own plugin system (`claude plugin ...`): a local marketplace named "jeb" (the bundle's or
clone's .claude-plugin/marketplace.json) and the plugin jeb@jeb. Jeb's code writes ~/.claude/settings.json only to remove its own
legacy CLAUDE_CODE_PLUGIN_DIRS entry (backup first), after the plugin install succeeded. A dev clone still loads through
CLAUDE_CODE_PLUGIN_DIRS (hot reload): edit() adds that entry.

CLAUDE_CODE_PLUGIN_DIRS (the settings "env" block) is a list of plugin folders. Claude Code splits it with
Node's path.delimiter, which is ":" on macOS (confirmed in the claude binary: split(delimiter) over the
value, each entry trimmed, "~" expanded, absolute paths only). Entries are compared after expanduser/normpath.
"""
import hashlib, json, os, shutil, stat, subprocess, time

import jebhome

KEY = "CLAUDE_CODE_PLUGIN_DIRS"
MARKET = "jeb"
PLUGIN_ID = "jeb@jeb"
OLD_ID = "jeb@inline"       # the id the mod had while it loaded through CLAUDE_CODE_PLUGIN_DIRS


def settings_path():
    return os.environ.get("JEB_SETTINGS") or os.path.expanduser("~/.claude/settings.json")


def backup_dir():
    return os.environ.get("JEB_BACKUPS") or os.path.expanduser("~/.claude/backups/jeb")


def norm(p):
    return os.path.normpath(os.path.abspath(os.path.expanduser(p.strip())))


def same(a, b):
    """Same folder: equal after expanduser/normpath, or the same inode (macOS volumes ignore case)."""
    a, b = norm(a), norm(b)
    try:
        return a == b or os.path.samefile(a, b)
    except OSError:
        return False


def load(path):
    if not os.path.exists(path):
        return {}
    try:
        data = json.load(open(path))
    except ValueError as e:
        raise SystemExit(f"{path} is not valid JSON ({e}); fix it first, nothing changed")
    if not isinstance(data, dict):
        raise SystemExit(f"{path} is not a JSON object; nothing changed")
    return data


def current(data):
    env = data.get("env")
    if env is None:
        return None
    if not isinstance(env, dict):
        raise SystemExit('settings "env" is not an object; nothing changed')
    v = env.get(KEY)
    if v is not None and not isinstance(v, str):
        raise SystemExit(f"{KEY} is not a string in settings; nothing changed")
    return v


def plan(value, mod, remove):
    """(action, new_value): action is set | append | keep | remove | drop | absent; new_value None means delete the key."""
    parts = [e for e in (value or "").split(os.pathsep) if e.strip()]
    mine = [e for e in parts if same(e, mod)]
    if remove:
        if not mine:
            return "absent", value
        rest = [e for e in parts if e not in mine]
        return ("remove", os.pathsep.join(rest)) if rest else ("drop", None)
    if mine:
        return "keep", value
    if not parts:
        return "set", mod
    return "append", os.pathsep.join(parts + [mod])


def backup(path):
    os.makedirs(backup_dir(), mode=0o700, exist_ok=True)
    stem = os.path.join(backup_dir(), "settings." + time.strftime("%Y%m%d-%H%M%S"))
    dest, n = stem + ".json", 1
    while os.path.exists(dest):     # two edits in one second keep both backups
        n += 1
        dest = f"{stem}-{n}.json"
    shutil.copy2(path, dest)
    return dest


def edit(mod, remove, dry, say):
    """Adds (or removes) mod in the settings' CLAUDE_CODE_PLUGIN_DIRS. Backs up first when it writes."""
    path = settings_path()
    data = load(path)
    action, new = plan(current(data), mod, remove)
    say(f"settings {path}: {KEY} {action}" + (f" -> {new}" if new else ""))
    if action in ("keep", "absent"):
        return action
    if dry:
        say("  (dry run: not written)")
        return action
    if os.path.exists(path):
        say("  backup: " + backup(path))
    else:
        os.makedirs(os.path.dirname(path), exist_ok=True)
    env = data.get("env") if isinstance(data.get("env"), dict) else {}     # a null env counts as missing
    data["env"] = env
    if new is None:
        del env[KEY]
        if not env:
            del data["env"]
    else:
        env[KEY] = new
    real = os.path.realpath(path)       # a symlinked settings.json stays a symlink; the target is rewritten
    tmp = real + ".jeb-tmp"
    try:
        os.unlink(tmp)                  # a stale (or planted) temp file never gets written through
    except FileNotFoundError:
        pass
    mode = stat.S_IMODE(os.stat(real).st_mode) if os.path.exists(real) else 0o600
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        os.fchmod(fd, mode)             # the original's mode before any content is written
        with os.fdopen(fd, "w") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.write("\n")
        os.replace(tmp, real)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
    return action


# ---- Claude Code's plugin system ----

def store_dir():
    return os.environ.get("JEB_STORE_DIR") or os.path.expanduser("~/.claude/plugins/store")


def store_name(pid):
    """Claude Code's store file for a plugin id: the id with @ -> _, then the first 12 hex of its sha256."""
    return pid.replace("@", "_") + "-" + hashlib.sha256(pid.encode()).hexdigest()[:12] + ".json"


def store_path():
    """jeb@jeb's file; the jeb@inline one while that is all there is; else the new one (the mod creates it)."""
    new, old = (os.path.join(store_dir(), store_name(i)) for i in (PLUGIN_ID, OLD_ID))
    return old if not os.path.exists(new) and os.path.exists(old) else new


def legacy_entries():
    """The CLAUDE_CODE_PLUGIN_DIRS entries that are Jeb's own release install (under ~/.jeb: current, versions, repo). Never a dev clone."""
    try:
        v = current(load(settings_path()))
    except SystemExit:
        return []
    root = os.path.realpath(jebhome.jeb_dir())
    out = []
    for e in (v or "").split(os.pathsep):
        if e.strip() and os.path.realpath(norm(e)).startswith(root + os.sep):
            out.append(e.strip())
    return out


def claude(*args, timeout=120, input_text=None):
    """(returncode, output) of `claude plugin <args>`; (None, reason) when claude is missing or does not answer."""
    cl = jebhome.find_claude()
    if not cl:
        return None, "claude was not found"
    env = {k: v for k, v in os.environ.items() if k != KEY}
    try:
        r = subprocess.run([cl, "plugin", *args], capture_output=True, text=True, timeout=timeout, env=env, input=input_text, stdin=None if input_text else subprocess.DEVNULL)
    except (OSError, subprocess.SubprocessError) as e:
        return None, str(e)
    return r.returncode, (r.stdout + r.stderr).strip()


def _json_list(*args):
    rc, out = claude(*args, "--json")
    if rc != 0:
        return None
    try:
        data = json.loads(out)
    except ValueError:
        return None
    return [d for d in data if isinstance(d, dict)] if isinstance(data, list) else None


def info():
    """(claude path, jeb@jeb's entry from `plugin list`, the "jeb" marketplace entry); the entries are None when absent or unreadable."""
    cl = jebhome.find_claude()
    if not cl:
        return None, None, None
    plugins, markets = _json_list("list"), _json_list("marketplace", "list")
    plug = next((p for p in plugins or [] if p.get("id") == PLUGIN_ID), None)
    mkt = next((m for m in markets or [] if m.get("name") == MARKET), None)
    return cl, plug, mkt


def _options():
    """The options set while the mod was jeb@inline (settings pluginConfigs, read only), as {key: single-line string}."""
    try:
        opts = ((load(settings_path()).get("pluginConfigs") or {}).get(OLD_ID) or {}).get("options") or {}
    except (SystemExit, AttributeError):
        return {}
    return {k: str(v).lower() if isinstance(v, bool) else str(v) for k, v in opts.items() if isinstance(v, (bool, str, int, float)) and "\n" not in str(v)}


def _present(entries):
    """The entries actually listed in CLAUDE_CODE_PLUGIN_DIRS now."""
    try:
        parts = [p for p in (current(load(settings_path())) or "").split(os.pathsep) if p.strip()]
    except SystemExit:
        return []
    return [e for e in dict.fromkeys(entries) if any(same(e, p) for p in parts)]


def remove_entries(entries, dry, say):
    for e in entries:
        edit(e, True, dry, say)


def register(source, dry, say, extra=()):
    """Registers the mod with Claude Code: the "jeb" marketplace at source (a folder holding .claude-plugin/marketplace.json), then
    jeb@jeb installed (options carried over from jeb@inline) or updated. Only once that worked are Jeb's legacy CLAUDE_CODE_PLUGIN_DIRS
    entries (and extra, e.g. an old clone's) removed. Returns ok | no-claude | conflict | failed (the legacy entry stays: Jeb keeps loading)."""
    cl, plug, mkt = info()
    if not cl:
        say("claude was not found; the plugin is not registered (Jeb keeps loading the old way if it was)")
        return "no-claude"
    if mkt and not same(mkt.get("path") or mkt.get("installLocation") or "/nonexistent", source):
        say(f'marketplace "{MARKET}" already points at {mkt.get("path")}, not {source}; left alone')
        return "conflict"
    old, new = (os.path.join(store_dir(), store_name(i)) for i in (OLD_ID, PLUGIN_ID))
    if dry:
        say(f"would register {PLUGIN_ID} from {source}" + (" (marketplace added)" if not mkt else ""))
        return "ok"
    if not mkt:
        rc, out = claude("marketplace", "add", source)
        if rc != 0:
            say(f"claude plugin marketplace add failed: {out[-200:]}")
            return "failed"
    if os.path.isfile(old) and not os.path.exists(new):
        os.makedirs(os.path.dirname(new), exist_ok=True)
        shutil.copy2(old, new)      # the farm and live records move with the plugin id
        os.chmod(new, 0o600)
        say(f"store: copied {os.path.basename(old)} to {os.path.basename(new)}")
    opts = _options()
    if plug:
        rc, out = claude("update", PLUGIN_ID)
    else:
        rc, out = claude("install", PLUGIN_ID, "--scope", "user", *[a for k, v in opts.items() for a in ("--config", f"{k}={v}")])
    if rc != 0:
        say(f"claude plugin {'update' if plug else 'install'} failed: {out[-200:]}")
        return "failed"
    legacy = _present(legacy_entries() + [x for x in extra if x])
    if legacy:
        remove_entries(legacy, dry, say)
        say("moved Jeb off CLAUDE_CODE_PLUGIN_DIRS (settings backed up)")
    if opts and not plug and legacy:
        # While the legacy entry was still listed, the same plugin loaded twice and --config was not applied: set the options now.
        rc, out = claude("configure", PLUGIN_ID, "--values-stdin", input_text=json.dumps(opts))
        say("options carried over from jeb@inline" if rc == 0 else f"could not carry the options over: {out[-200:]}")
    return "ok"


def sync():
    """After an update: refresh the marketplace and jeb@jeb. True when both commands ran clean (or Jeb is not registered)."""
    cl, plug, mkt = info()
    if not cl or not plug:
        return True
    a, _ = claude("marketplace", "update", MARKET)
    b, _ = claude("update", PLUGIN_ID)
    return a == 0 and b == 0


def unregister(purge_farm, dry, say, source=None):
    """Uninstall jeb@jeb (its data kept unless purge_farm) and remove the "jeb" marketplace when it is Jeb's own, then drop Jeb's legacy
    CLAUDE_CODE_PLUGIN_DIRS entries. Jeb's store files are backed up first and put back if Claude Code deleted one (unless purging)."""
    files = sorted(f for f in (os.path.join(store_dir(), n) for n in (os.listdir(store_dir()) if os.path.isdir(store_dir()) else []))
                   if os.path.basename(f).startswith(("jeb_jeb-", "jeb_inline-")) and f.endswith(".json"))
    saved = {}
    for f in files:
        try:
            saved[f] = open(f, "rb").read()
        except OSError:
            pass
    if files and not dry:
        os.makedirs(backup_dir(), mode=0o700, exist_ok=True)
        for f in files:
            shutil.copy2(f, os.path.join(backup_dir(), os.path.basename(f)[:-5] + "." + time.strftime("%Y%m%d-%H%M%S") + ".json"))
    cl, plug, mkt = info()
    if not cl:
        say("claude was not found; the plugin was not uninstalled from Claude Code")
    else:
        root = os.path.realpath(jebhome.jeb_dir())
        if plug:
            say("uninstalling " + PLUGIN_ID if not dry else "would uninstall " + PLUGIN_ID)
            if not dry:
                rc, out = claude("uninstall", PLUGIN_ID, *([] if purge_farm else ["--keep-data"]))
                if rc != 0:
                    say(f"claude plugin uninstall failed: {out[-200:]}")
        mp = (mkt or {}).get("path") or ""
        if mkt and (os.path.realpath(mp).startswith(root + os.sep) or (source and same(mp, source))):
            say(("removing" if not dry else "would remove") + f' marketplace "{MARKET}"')
            if not dry:
                rc, out = claude("marketplace", "remove", MARKET)
                if rc != 0:
                    say(f"claude plugin marketplace remove failed: {out[-200:]}")
        elif mkt:
            say(f'marketplace "{MARKET}" points at {mp}, not Jeb\'s; left alone')
    if not dry and not purge_farm:
        for f, data in saved.items():
            if not os.path.exists(f):
                with open(os.open(f, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "wb") as w:
                    w.write(data)
                say("restored " + os.path.basename(f))
    remove_entries(legacy_entries(), dry, say)
