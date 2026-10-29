"""jebhome.py: where Jeb's desktop state lives, and the one-time move from the old folder.

The state folder is ~/Library/Application Support/Jeb. Older installs keep it at ~/.claude/jeb-desktop until
migrate() moves it (the old path then stays behind as a symlink, so the running app, its rollback versions and the
LaunchAgents' log paths keep working). Shared by jebctl, updater.py and watchdog.py; the Swift app resolves the
same way in Heartbeat.swift. Stdlib only; paths are computed at call time so tests can point $HOME elsewhere.
Also the install's shared lookups: dev_dir and use_dev_dir (fall back to the Command Line Tools when an unlicensed Xcode
would block git), find_gh,
find_claude, and the standard places ~/.jeb/bin (gh; JEB_TOOLS_DIR), ~/.jeb/versions/<tag> (one unpacked release bundle: its
tree, the universal app and a private Python) and ~/.jeb/current (a symlink to the live one; LaunchAgents and settings only name it).
Also read_bundle, host_arch, macho_archs (a stdlib Mach-O reader) and pin_python.
"""
import fcntl, json, os, plistlib, shutil, struct, subprocess, sys

CLT = "/Library/Developer/CommandLineTools"
SYS_PATH = "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin"


def dev_dir(clt=CLT):
    """The Command Line Tools folder when it has git, else None. Exported as DEVELOPER_DIR it keeps git and xcrun off
    the Xcode license prompt (the CLT never asks for it)."""
    return clt if os.path.isfile(os.path.join(clt, "usr", "bin", "git")) else None


def use_dev_dir():
    """DEVELOPER_DIR = the Command Line Tools only when the selected developer folder fails (an Xcode whose license was
    never accepted); a working Xcode stays in use, so the owner's builds keep its Swift."""
    d = dev_dir()
    if not d or "DEVELOPER_DIR" in os.environ:
        return
    try:
        ok = subprocess.run(["/usr/bin/xcrun", "--find", "git"], capture_output=True, timeout=20).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        ok = False
    if not ok:
        os.environ["DEVELOPER_DIR"] = d


def jeb_dir():
    return os.path.expanduser("~/.jeb")


def tools_dir():
    return os.environ.get("JEB_TOOLS_DIR") or os.path.join(jeb_dir(), "bin")


def current_dir():
    return os.path.join(jeb_dir(), "current")


def versions_dir():
    return os.path.join(jeb_dir(), "versions")


def read_bundle(root):
    """root/bundle.json as a dict (a release bundle), or None (a git clone)."""
    try:
        d = json.load(open(os.path.join(root, "bundle.json")))
    except (OSError, ValueError):
        return None
    return d if isinstance(d, dict) else None


def host_arch():
    """arm64 or x86_64 by the hardware (a Rosetta shell reports x86_64 through platform.machine())."""
    try:
        r = subprocess.run(["/usr/sbin/sysctl", "-n", "hw.optional.arm64"], capture_output=True, text=True, timeout=10)
        return "arm64" if r.returncode == 0 and r.stdout.strip() == "1" else "x86_64"
    except (OSError, subprocess.TimeoutExpired):
        return "x86_64"


CPU_TYPES = {0x0100000c: "arm64", 0x01000007: "x86_64"}


def macho_archs(path):
    """The architectures of a Mach-O file as a set of arm64 / x86_64 (other CPUs are ignored); empty when unreadable.
    Fat files (0xcafebabe, 0xcafebabf) are big-endian, thin 64-bit files (0xfeedfacf) little-endian."""
    try:
        with open(path, "rb") as f:
            head = f.read(8)
            if len(head) < 8:
                return set()
            magic = struct.unpack(">I", head[:4])[0]
            if magic in (0xcafebabe, 0xcafebabf):
                n, size = struct.unpack(">I", head[4:])[0], 20 if magic == 0xcafebabe else 32
                if not 0 < n <= 20:
                    return set()
                body = f.read(n * size)
                if len(body) < n * size:
                    return set()
                cpus = (struct.unpack(">I", body[i * size:i * size + 4])[0] for i in range(n))
                return {CPU_TYPES[c] for c in cpus if c in CPU_TYPES}
            c = struct.unpack("<I", head[4:])[0]
            return {CPU_TYPES[c]} if struct.unpack("<I", head[:4])[0] == 0xfeedfacf and c in CPU_TYPES else set()
    except OSError:
        return set()


def pin_python():
    """A process started through ~/.jeb/current/python re-executes through the real versions/<tag> path, so a flip of `current`
    (an update) never changes the interpreter or stdlib under it. A no-op everywhere else."""
    cur, exe = current_dir() + os.sep, sys.executable
    if not exe or not ((sys.prefix + os.sep).startswith(cur) or exe.startswith(cur)):
        return
    real = os.path.realpath(exe)
    if real == exe:
        return
    os.execv(real, [real] + (["-I"] if sys.flags.isolated else []) + [os.path.realpath(sys.argv[0])] + sys.argv[1:])


def _exe(p):
    return os.path.isfile(p) and os.access(p, os.X_OK)


def find_gh():
    """Absolute path of gh: Jeb's own copy ($JEB_TOOLS_DIR or ~/.jeb/bin), Homebrew's, then anything on PATH."""
    for p in (os.path.join(tools_dir(), "gh"), "/opt/homebrew/bin/gh", "/usr/local/bin/gh"):
        if _exe(p):
            return p
    return shutil.which("gh", path=os.environ.get("PATH", "") + os.pathsep + SYS_PATH)


def find_claude():
    """Claude Code's CLI: on PATH, or where its installers put it."""
    for p in (os.path.expanduser("~/.local/bin/claude"), os.path.expanduser("~/.claude/local/claude")):
        if _exe(p):
            return p
    return shutil.which("claude")

LABEL_PREFIX = "com.jeb.desktop"


def new_path():
    return os.path.expanduser("~/Library/Application Support/Jeb")


def old_path():
    return os.path.expanduser("~/.claude/jeb-desktop")


def _real_dir(p):
    return os.path.isdir(p) and not os.path.islink(p)


def resolve():
    """JEB_HOME; else the new folder if it exists; else the old one if it is a real folder; else the new one."""
    env = os.environ.get("JEB_HOME")
    if env:
        return env
    new, old = new_path(), old_path()
    if os.path.exists(new):
        return new
    return old if _real_dir(old) else new


def _swap_prefix(v, old, new):
    if isinstance(v, str):
        return new + v[len(old):] if v == old or v.startswith(old + "/") else v
    if isinstance(v, list):
        return [_swap_prefix(x, old, new) for x in v]
    if isinstance(v, dict):
        return {k: _swap_prefix(x, old, new) for k, x in v.items()}
    return v


def _rewrite_plist(path, old, new):
    try:
        with open(path, "rb") as f:
            data = plistlib.load(f)
        if not isinstance(data, dict) or not str(data.get("Label", "")).startswith(LABEL_PREFIX):
            return False
        out = _swap_prefix(data, old, new)
        if out == data:
            return False
        tmp = path + ".tmp"
        with open(tmp, "wb") as f:
            plistlib.dump(out, f)
        os.chmod(tmp, 0o644)
        os.replace(tmp, path)
        return True
    except (OSError, ValueError, plistlib.InvalidFileException):
        return False


def _rewrite_plists(old, new):
    agents = os.environ.get("JEB_LAUNCHAGENTS") or os.path.expanduser("~/Library/LaunchAgents")
    for d in (os.path.join(new, "launchd"), agents):
        try:
            names = sorted(os.listdir(d))
        except OSError:
            continue
        for n in names:
            if n.startswith(LABEL_PREFIX) and n.endswith(".plist"):
                _rewrite_plist(os.path.join(d, n), old, new)


def _link_back(old, new, log):
    """Symlink old -> new; if something recreated old as a real folder meanwhile, fold it into new first."""
    for _ in range(3):
        try:
            os.symlink(new, old)
            return True
        except FileExistsError:
            if not _real_dir(old):
                break
            aside = os.path.join(new, "migrate-leftovers")
            for n in os.listdir(old):
                dest = os.path.join(new, n)
                if os.path.lexists(dest):
                    os.makedirs(aside, exist_ok=True)
                    dest = os.path.join(aside, n)
                    if os.path.lexists(dest):
                        dest += ".%d" % os.getpid()
                os.rename(os.path.join(old, n), dest)
            try:
                os.rmdir(old)
            except OSError:
                pass
        except OSError:
            break
    log(f"could not link {old} to {new}; the new folder is used regardless")
    return False


def migrate(log, dry=False):
    """Move the old state folder to the new place once. Returns "n/a", "busy", "would move", "moved" or "failed"."""
    if os.environ.get("JEB_HOME"):
        return "n/a"
    new, old = new_path(), old_path()
    if not _real_dir(old) or os.path.lexists(new):
        return "n/a"
    if dry:
        log(f"would move the state folder {old} to {new}")
        return "would move"
    locks = []
    try:
        for n in ("updater.lock", "release.lock"):
            f = open(os.path.join(old, n), "a")
            locks.append(f)
            try:
                fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except OSError:
                log(f"state folder move postponed: {n} is held; the next run retries")
                return "busy"
        try:
            os.makedirs(os.path.dirname(new), exist_ok=True)
            os.rename(old, new)
        except OSError as e:
            log(f"could not move {old} to {new}: {e}")
            return "failed"
        _link_back(old, new, log)
        _rewrite_plists(old, new)
        log(f"moved the state folder to {new}; {old} now links there")
        return "moved"
    finally:
        for f in locks:
            f.close()
