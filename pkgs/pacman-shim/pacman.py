#!/usr/bin/env python3
# pacman, expac and vercmp for Omarchy on NixOS: the query forms shell
# plugins and upstream's menu use, answered from the NixOS system.
#
# "Installed" is what the system and the user's profiles hold: the direct
# contents of /run/current-system/sw, /etc/profiles/per-user/$USER and
# ~/.nix-profile ("explicitly installed"), plus the rest of the system's
# closure ("installed as a dependency"). Names and versions come from store
# path names (qtbase-6.9.1 → qtbase 6.9.1-1). Plugins ask by Arch name, so
# every package also answers to the Arch names data/arch-packages.json maps
# to it, python3.13-foo to python-foo, qtbase to qt6-base, Omarchy's own
# package to `omarchy` (upstream's version), and a name that is none of
# these to a command of that name on PATH. The aliases are what -Qi lists
# as Provides.
#
# The index is cached in ~/.cache/omarchy/pacman/, keyed by the profiles'
# store paths, so it's rebuilt only when one of them changes.
#
# Anything that would change the system (-S, -R, -U, -D) or reads the sync
# databases (-Si, -Ss, -Sl, -Qu, -F) fails with pacman's error status and
# says what to do on NixOS instead.
#
# Environment (all optional; set by the package, or by tests):
#   OMARCHY_PACMAN_MAP       JSON {arch name: {attr, pname}} (the package's)
#   OMARCHY_PACMAN_META      JSON [{name, pname, version, description,
#                            homepage, license}] of the declared packages;
#                            default ~/.local/share/omarchy-pacman/declared.json
#                            (the Home Manager module writes it)
#   OMARCHY_VERSION          upstream Omarchy's version
#   OMARCHY_PACMAN_SYSTEM    the system (closure root), default /run/current-system
#   OMARCHY_PACMAN_PROFILES  colon-separated profiles (explicit packages)
#   OMARCHY_PACMAN_CLOSURE   file listing store paths to use as the closure
#                            (instead of asking nix-store)
#   OMARCHY_PACMAN_CACHE     cache directory
import hashlib
import json
import os
import re
import subprocess
import sys
import time

PROG = os.path.basename(sys.argv[0])
STORE = "/nix/store/"
OUTPUTS = {"out", "bin", "dev", "lib", "man", "doc", "info", "devdoc", "debug", "static", "py", "qml",
           "locale", "tools", "data", "modules", "sbin", "libexec", "terminfo", "icons", "fonts", "dist",
           "examples", "shell_integration", "nc", "udev", "env"}
JUNK_PREFIX = ("nixos-system-", "home-manager-generation", "home-manager-files", "home-manager-path",
               "system-path", "system-units", "user-units", "unit-", "hm_", "hm-", "X-", "etc-", "user-environment",
               "initrd-", "extra-utils", "nixos-manual", "nixos-configuration-reference")
INDEX_VERSION = 6

QUERY_FAIL = ("pacman on NixOS only answers queries; add {pkgs} to your configuration "
              "(omarchy.plugins.{id}.packages or environment.systemPackages)")


def err(msg):
    print(f"error: {msg}", file=sys.stderr)


# ----------------------------------------------------------------- vercmp
def _rpmvercmp(a, b):
    # libalpm's rpmvercmp (lib/libalpm/version.c).
    if a == b:
        return 0
    i = j = 0
    pi = pj = 0
    n, m = len(a), len(b)
    while i < n and j < m:
        while i < n and not a[i].isalnum():
            i += 1
        while j < m and not b[j].isalnum():
            j += 1
        if not (i < n and j < m):
            break
        if (i - pi) != (j - pj):
            return -1 if (i - pi) < (j - pj) else 1
        pi, pj = i, j
        if a[pi].isdigit():
            while pi < n and a[pi].isdigit():
                pi += 1
            while pj < m and b[pj].isdigit():
                pj += 1
            isnum = True
        else:
            while pi < n and a[pi].isalpha():
                pi += 1
            while pj < m and b[pj].isalpha():
                pj += 1
            isnum = False
        s1, s2 = a[i:pi], b[j:pj]
        if not s1:
            return -1
        if not s2:
            return 1 if isnum else -1
        if isnum:
            s1, s2 = s1.lstrip("0"), s2.lstrip("0")
            if len(s1) != len(s2):
                return 1 if len(s1) > len(s2) else -1
        if s1 != s2:
            return -1 if s1 < s2 else 1
        i, j = pi, pj
    one, two = a[i:], b[j:]
    if not one and not two:
        return 0
    if (not one and not two[:1].isalpha()) or one[:1].isalpha():
        return -1
    return 1


def _evr(v):
    k = 0
    while k < len(v) and v[k].isdigit():
        k += 1
    if k < len(v) and v[k] == ":":
        epoch, rest = v[:k] or "0", v[k + 1:]
    else:
        epoch, rest = "0", v
    rel = None
    if "-" in rest:
        rest, rel = rest.rsplit("-", 1)
    return epoch, rest, rel


def vercmp(a, b):
    if a == b:
        return 0
    e1, v1, r1 = _evr(a)
    e2, v2, r2 = _evr(b)
    ret = _rpmvercmp(e1, e2)
    if ret == 0:
        ret = _rpmvercmp(v1, v2)
        if ret == 0 and r1 is not None and r2 is not None:
            ret = _rpmvercmp(r1, r2)
    return ret


DEP_RE = re.compile(r"^(.+?)(>=|<=|=|<|>)(.+)$")


def satisfies(version, op, want):
    c = vercmp(version, want)
    return {"=": c == 0, ">=": c >= 0, "<=": c <= 0, ">": c > 0, "<": c < 0}[op]


# ------------------------------------------------------------ store names
def parse_store_name(path):
    """/nix/store/<hash>-<name> → (pname, version, output) or None."""
    if not path.startswith(STORE):
        return None
    base = path[len(STORE):].split("/", 1)[0]
    if len(base) < 34 or base[32] != "-":
        return None
    rest = base[33:]
    # builtins.parseDrvName: the name ends at the first dash followed by
    # something that isn't a letter.
    for k in range(len(rest) - 1):
        if rest[k] == "-" and not rest[k + 1].isalpha():
            name, version = rest[:k], rest[k + 1:]
            break
    else:
        return (rest, "", "out")
    output = "out"
    if "-" in version:
        head, tail = version.rsplit("-", 1)
        if tail in OUTPUTS:
            version, output = head, tail
    return (name, version, output)


def store_root(path):
    if not path.startswith(STORE):
        return None
    return STORE + path[len(STORE):].split("/", 1)[0]


def arch_version(v):
    # Arch versions have no dashes but the one before pkgrel.
    v = v.replace("-", ".") or "0"
    return v + "-1"


# ------------------------------------------------------------------ index
def user_name():
    return os.environ.get("USER") or os.environ.get("LOGNAME") or ""


def profiles():
    env = os.environ.get("OMARCHY_PACMAN_PROFILES")
    if env is not None:
        return [p for p in env.split(":") if p]
    home = os.path.expanduser("~")
    return ["/run/current-system/sw", f"/etc/profiles/per-user/{user_name()}",
            os.path.join(home, ".nix-profile"), os.path.join(home, ".local/state/nix/profile")]


def system_root():
    return os.environ.get("OMARCHY_PACMAN_SYSTEM", "/run/current-system")


def real(p):
    try:
        r = os.path.realpath(p)
        return r if os.path.exists(r) else None
    except OSError:
        return None


def nix_store(args):
    for exe in ("nix-store", "/run/current-system/sw/bin/nix-store"):
        try:
            r = subprocess.run([exe] + args, capture_output=True, text=True, timeout=60)
        except OSError:
            continue
        except subprocess.SubprocessError:
            return None
        return r.stdout.split() if r.returncode == 0 else None
    return None


def meta_file():
    m = os.environ.get("OMARCHY_PACMAN_META")
    if m is not None:
        return m
    base = os.environ.get("XDG_DATA_HOME") or os.path.join(os.path.expanduser("~"), ".local/share")
    return os.path.join(base, "omarchy-pacman", "declared.json")


def profile_contents(prof):
    """The store paths a profile (a buildEnv, or a `nix profile`) holds."""
    refs = nix_store(["--query", "--references", prof])
    if refs is not None:
        return [r for r in refs if r != prof]
    # No store database here (tests): the packages its links point into.
    out = set()
    for sub in ("bin", "sbin", "share/applications", "lib"):
        d = os.path.join(prof, sub)
        try:
            names = os.listdir(d)
        except OSError:
            continue
        for n in names:
            try:
                t = os.path.realpath(os.path.join(d, n))
            except OSError:
                continue
            r = store_root(t)
            if r and r != prof:
                out.add(r)
    return sorted(out)


def load_json(path, default):
    if not path:
        return default
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def cache_dir():
    d = os.environ.get("OMARCHY_PACMAN_CACHE")
    if d:
        return d
    base = os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache")
    return os.path.join(base, "omarchy", "pacman")


def build_index(roots, profs):
    explicit = []
    for p in profs:
        explicit.extend(profile_contents(p))
    closure_file = os.environ.get("OMARCHY_PACMAN_CLOSURE")
    if closure_file:
        with open(closure_file) as f:
            closure = [l.strip() for l in f if l.strip().startswith(STORE)]
    else:
        closure = nix_store(["--query", "--requisites"] + roots) or []
    closure = sorted(set(closure) | set(explicit))
    sizes = {}
    got = nix_store(["--query", "--size"] + closure) if closure and not closure_file else None
    if got and len(got) == len(closure):
        sizes = dict(zip(closure, (int(s) for s in got)))
    explicit = set(explicit)
    meta = {}
    for m in load_json(meta_file(), []):
        if m.get("pname"):
            meta.setdefault(m["pname"], m)
        if m.get("name"):
            meta.setdefault(m["name"], m)

    pk = {}
    for path in closure:
        parsed = parse_store_name(path)
        if not parsed:
            continue
        name, version, output = parsed
        if not version or name.startswith(JUNK_PREFIX) or name.endswith((".drv", ".patch")):
            continue
        e = pk.setdefault(name, {"versions": {}})
        v = e["versions"].setdefault(version, {"paths": [], "explicit": False, "size": 0})
        v["paths"].append(path)
        v["explicit"] = v["explicit"] or path in explicit
        v["size"] += sizes.get(path, 0)

    pkgs = {}
    for name, e in pk.items():
        vs = e["versions"]
        # One version per name, as pacman has: an explicit one first, then
        # the newest.
        ver = None
        for cand, info in vs.items():
            # explicit first, then a plain version (6.11.2 over
            # 6.11.2-only-plugins), then the newest
            if ver is None or (info["explicit"], "-" not in cand, vercmp(cand, ver)) > (
                    vs[ver]["explicit"], "-" not in ver, 0):
                ver = cand
        info = vs[ver]
        store_name = os.path.basename(sorted(info["paths"])[0])[33:]
        m = meta.get(store_name) or meta.get(name) or {}
        pkgs[name] = {
            "version": arch_version(ver), "paths": sorted(info["paths"]), "explicit": info["explicit"],
            "size": info["size"], "description": m.get("description") or "", "url": m.get("homepage") or "",
            "licenses": m.get("license") or [], "installed": min(
                (os.lstat(p).st_ctime for p in info["paths"] if os.path.lexists(p)), default=0),
        }

    # Omarchy: upstream's version, not the flake's store name.
    ov = os.environ.get("OMARCHY_VERSION")
    if not ov:
        for d in (os.environ.get("OMARCHY_PATH"), os.path.expanduser("~/.local/share/omarchy"), "/usr/share/omarchy"):
            try:
                with open(os.path.join(d or "", "version")) as f:
                    ov = f.read().strip()
                    break
            except OSError:
                continue
    if "omarchy" in pkgs or ov:
        o = pkgs.setdefault("omarchy", {"paths": [], "explicit": True, "size": 0, "installed": 0})
        o.update({"version": arch_version(ov or o.get("version", "0").rsplit("-", 1)[0]), "explicit": True,
                  "description": "Omarchy: an opinionated Hyprland desktop (nix-desktops/omarchy)",
                  "url": "https://omarchy.org", "licenses": ["MIT"]})

    # Aliases: names a package also answers to.
    alias = {}
    archnames = set()

    def add(a, target, arch=False):
        if a and a != target and a not in pkgs and a not in alias:
            alias[a] = target
            if arch:
                archnames.add(a)

    lower = {}
    for name in pkgs:
        lower.setdefault(name.lower(), name)
    for name in list(pkgs):
        add(name.lower(), name)
        m = re.match(r"^python3(?:\.\d+)?-(.+)$", name)
        if m:
            base = m.group(1).lower().replace("_", "-")
            for a in (f"python-{base}", f"python3-{base}"):
                add(a, name, True)
        m = re.match(r"^qt(.+)$", name)
        ver = pkgs[name]["version"]
        if m and ver[:1] in ("5", "6") and name not in ("qt5ct", "qt6ct"):
            add(f"qt{ver[0]}-{m.group(1)}", name, True)
    amap = load_json(os.environ.get("OMARCHY_PACMAN_MAP"), {})
    for arch, e in amap.items():
        if not e or not e.get("pname"):
            continue
        pn, attr = e["pname"], e.get("attr") or ""
        target = None
        if attr.startswith("python3Packages."):
            target = alias.get("python3-" + pn.lower().replace("_", "-"))
        else:
            target = pn if pn in pkgs else lower.get(pn.lower())
        if target:
            add(arch, target, True)
            add(attr, target, True)
            add(attr.rsplit(".", 1)[-1], target, True)
    # Commands of explicitly installed packages: `pacman -Q vim` finds gvim
    # on Arch through what it provides.
    for name, p in pkgs.items():
        if not p["explicit"]:
            continue
        for path in p["paths"]:
            try:
                for c in os.listdir(os.path.join(path, "bin")):
                    if not c.startswith("."):
                        add(c, name)
            except OSError:
                pass
    provides = {}
    for a, t in alias.items():
        if a.lower() != t.lower() or a != a.lower():
            provides.setdefault(t, []).append(a)
    for t in provides:
        provides[t].sort()
    return {"v": INDEX_VERSION, "pkgs": pkgs, "alias": alias, "provides": provides,
            "archnames": sorted(a for a in archnames if a in provides.get(alias[a], []))}


def load_index():
    roots = [r for r in (real(system_root()),) if r]
    profs = [r for r in (real(p) for p in profiles()) if r]
    profs = list(dict.fromkeys(profs))
    key = json.dumps([INDEX_VERSION, roots, profs, os.environ.get("OMARCHY_PACMAN_MAP"),
                      real(meta_file()), os.environ.get("OMARCHY_VERSION"),
                      os.environ.get("OMARCHY_PACMAN_CLOSURE")])
    h = hashlib.sha1(key.encode()).hexdigest()[:16]
    d = cache_dir()
    f = os.path.join(d, f"index-{h}.json")
    idx = load_json(f, None)
    if idx and idx.get("v") == INDEX_VERSION:
        return idx
    idx = build_index(roots, profs)
    try:
        os.makedirs(d, exist_ok=True)
        for old in os.listdir(d):
            if old.startswith("index-") and old != os.path.basename(f):
                try:
                    os.unlink(os.path.join(d, old))
                except OSError:
                    pass
        tmp = f"{f}.{os.getpid()}"
        with open(tmp, "w") as out:
            json.dump(idx, out)
        os.replace(tmp, f)
    except OSError:
        pass
    return idx


class Db:
    def __init__(self):
        self.idx = load_index()
        self.pkgs = self.idx["pkgs"]
        self.alias = self.idx["alias"]
        self.amap = None
        self.names = {id(e): n for n, e in self.pkgs.items()}

    def arch_map(self):
        if self.amap is None:
            self.amap = load_json(os.environ.get("OMARCHY_PACMAN_MAP"), {})
        return self.amap

    def resolve(self, name):
        """A package entry for a name, or None: (display name, entry)."""
        if name in self.pkgs:
            return name, self.pkgs[name]
        for n in (name, name.lower()):
            if n in self.alias:
                return name, self.pkgs[self.alias[n]]
        m = re.match(r"^(.+?)-(bin|git|appimage|nightly)$", name)
        if m:
            r = self.resolve(m.group(1))
            if r:
                return name, r[1]
        return self.command(name)

    def command(self, name):
        # A command of that name on PATH (or in the profiles): the package
        # whose main program it is.
        if "/" in name or not name:
            return None
        dirs = os.environ.get("PATH", "").split(":") + [os.path.join(p, "bin") for p in profiles()]
        for d in dirs:
            if not d:
                continue
            c = os.path.join(d, name)
            if os.access(c, os.X_OK) and not os.path.isdir(c):
                t = real(c)
                parsed = parse_store_name(t) if t else None
                if parsed and parsed[0] in self.pkgs:
                    return name, self.pkgs[parsed[0]]
                root = store_root(t) if t else None
                return name, {"version": arch_version(parsed[1] if parsed else ""), "paths": [root] if root else [],
                              "explicit": True, "size": 0, "description": "", "url": "", "licenses": [],
                              "installed": 0}
        return None

    def real_name(self, entry):
        return self.names.get(id(entry))

    def provides(self, name):
        return self.idx["provides"].get(name, [])

    def nix_attr(self, name):
        """The nixpkgs attribute to suggest for an Arch name."""
        e = self.arch_map().get(name)
        if e and e.get("attr"):
            return e["attr"]
        m = re.match(r"^python-(.+)$", name)
        if m:
            return "python3Packages." + m.group(1)
        m = re.match(r"^qt6-(.+)$", name)
        if m:
            return "kdePackages.qt" + m.group(1)
        m = re.match(r"^qt5-(.+)$", name)
        if m:
            return "libsForQt5.qt" + m.group(1)
        m = re.match(r"^(.+?)-(bin|git|appimage)$", name)
        if m:
            return self.nix_attr(m.group(1))
        return name


def nix_attr_plain(name):
    """nix_attr without loading the index (for refusals)."""
    amap = load_json(os.environ.get("OMARCHY_PACMAN_MAP"), {})
    e = amap.get(name)
    if e and e.get("attr"):
        return e["attr"]
    for pat, rep in ((r"^python-(.+)$", "python3Packages.{}"), (r"^qt6-(.+)$", "kdePackages.qt{}"),
                     (r"^qt5-(.+)$", "libsForQt5.qt{}"), (r"^(.+?)-(?:bin|git|appimage)$", "{}")):
        m = re.match(pat, name)
        if m:
            return rep.format(m.group(1))
    return name


# ----------------------------------------------------------- formatting
def human(n, unit=None):
    units = ["B", "KiB", "MiB", "GiB", "TiB"]
    f = float(n)
    k = 0
    if unit:
        k = {"B": 0, "K": 1, "M": 2, "G": 3, "T": 4}.get(unit.upper()[:1], 0)
        f = n / (1024 ** k)
    else:
        while f >= 2048 and k < len(units) - 1:
            f /= 1024
            k += 1
    return f"{f:.2f} {units[k]}"


def date(t):
    if not t:
        t = 1
    return time.strftime("%a %d %b %Y %I:%M:%S %p %Z", time.localtime(t))


def listval(xs, sep="  "):
    return sep.join(xs) if xs else "None"


def info_block(db, shown, e, name_for_provides):
    arch = os.uname().machine
    rows = [
        ("Name", shown),
        ("Version", e["version"]),
        ("Description", e.get("description") or "None"),
        ("Architecture", arch),
        ("URL", e.get("url") or "None"),
        ("Licenses", listval(e.get("licenses") or [])),
        ("Groups", "None"),
        ("Provides", listval(db.provides(name_for_provides) if name_for_provides else [])),
        ("Depends On", "None"),
        ("Optional Deps", "None"),
        ("Required By", "None"),
        ("Optional For", "None"),
        ("Conflicts With", "None"),
        ("Replaces", "None"),
        ("Installed Size", human(e.get("size") or 0)),
        ("Packager", "nixpkgs <https://github.com/NixOS/nixpkgs>"),
        ("Build Date", date(1)),
        ("Install Date", date(e.get("installed"))),
        ("Install Reason", "Explicitly installed" if e.get("explicit") else "Installed as a dependency for another package"),
        ("Install Script", "No"),
        ("Validated By", "None"),
    ]
    return "".join(f"{k:<16}: {v}\n" for k, v in rows) + "\n"


# ---------------------------------------------------------- plugin id
def plugin_id():
    pat = re.compile(r"/omarchy/plugins/([^/\s\0]+)")
    m = pat.search(os.getcwd() if os.path.exists(".") else "")
    if m:
        return m.group(1)
    pid = os.getppid()
    for _ in range(4):
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                cmd = f.read().decode(errors="replace")
            m = pat.search(cmd)
            if m:
                return m.group(1)
            with open(f"/proc/{pid}/stat") as f:
                pid = int(f.read().rsplit(")", 1)[1].split()[1])
            if pid <= 1:
                break
        except (OSError, ValueError, IndexError):
            break
    return "<id>"


def refuse(op, targets, mods=""):
    """pacman's error status, and what to do on NixOS instead."""
    names = [t for t in targets if not t.startswith("-")]
    if op == "U":
        # an Arch package file: <name>-<ver>-<rel>-<arch>.pkg.tar.*
        names = [re.sub(r"-[^-]+-[^-]+-[^-]+\.pkg\.tar.*$", "", os.path.basename(t)) for t in names]
    attrs = [nix_attr_plain(t) for t in names]
    q = " ".join(targets) or "<query>"
    say = lambda m: print(m, file=sys.stderr)  # noqa: E731
    if op in "SF" and ("s" in mods or "l" in mods or op == "F"):
        say("pacman on NixOS only answers queries about what's installed; there is no package database "
            f"to search: nix search nixpkgs {q} (or https://search.nixos.org/packages"
            f"?query={'+'.join(targets)})")
    elif (op == "S" and not attrs) or (op == "Q" and "u" in mods):
        say("pacman on NixOS only answers queries; the system is updated by rebuilding it: "
            "omarchy update (or nixos-rebuild switch)")
    else:
        msg = QUERY_FAIL.replace("add {pkgs} to", "remove {pkgs} from") if op == "R" else QUERY_FAIL
        say(msg.format(pkgs=" ".join(attrs) if attrs else "the package", id=plugin_id()))
        if op == "S" and "i" in mods:
            say(f"  (nixpkgs' packages: https://search.nixos.org/packages?query={'+'.join(attrs)})")
    return 1


# ------------------------------------------------------------- pacman
LONG = {
    "query": "Q", "sync": "S", "remove": "R", "upgrade": "U", "database": "D", "files": "F",
    "deptest": "T", "version": "V", "help": "h",
    "quiet": "q", "info": "i", "list": "l", "owns": "o", "explicit": "e", "deps": "d", "foreign": "m",
    "native": "n", "unrequired": "t", "upgrades": "u", "search": "s", "groups": "g", "check": "k",
    "file": "p", "changelog": "c", "refresh": "y", "sysupgrade": "u", "clean": "c", "downloadonly": "w",
    "nodeps": "d", "recursive": "s", "print": "p",
}
VALUE_LONG = {"color", "config", "dbpath", "root", "arch", "cachedir", "gpgdir", "hookdir", "logfile",
              "sysroot", "assume-installed", "ignore", "ignoregroup", "overwrite", "print-format"}
VALUE_SHORT = {"b", "r"}


def parse_pacman(argv):
    op, mods, targets = None, [], []
    i = 0
    only_targets = False
    while i < len(argv):
        a = argv[i]
        i += 1
        if only_targets or not a.startswith("-") or a == "-":
            targets.append(a)
            continue
        if a == "--":
            only_targets = True
            continue
        if a.startswith("--"):
            name = a[2:].split("=", 1)[0]
            if name in VALUE_LONG:
                if "=" not in a:
                    i += 1
                continue
            letter = LONG.get(name)
            if letter is None:
                continue  # --noconfirm, --needed, --debug, ...
            if letter in "QSRUDFTVh" and name in ("query", "sync", "remove", "upgrade", "database", "files",
                                                  "deptest", "version", "help"):
                op = op or letter
            else:
                mods.append(letter)
            continue
        for k, c in enumerate(a[1:]):
            if c in "QSRUDFTV" or (c == "h" and op is None):
                op = op or c
            elif c in VALUE_SHORT:
                if k == len(a) - 2:
                    i += 1
                break
            else:
                mods.append(c)
    return op, mods, targets


def pacman(argv):
    op, mods, targets = parse_pacman(argv)
    if op == "V":
        print("pacman (Omarchy on NixOS): answers queries from the NixOS system")
        return 0
    if op == "h" or op is None:
        if op is None:
            err("no operation specified (use -h for help)")
            return 1
        print("usage:  pacman -Q [options] [package(s)]   (queries only on NixOS)")
        print("        -Q[q] [pkg...], -Qi, -Qo <file>, -Ql <pkg>, -Qs <regex>, -Qe/-Qd/-Qm/-Qn/-Qt, -T <dep...>")
        return 0
    if op in "SRUDF":
        return refuse(op, targets, "".join(mods))
    db = Db()
    if op == "T":
        missing = []
        for t in targets:
            m = DEP_RE.match(t)
            name, opx, want = (m.group(1), m.group(2), m.group(3)) if m else (t, None, None)
            r = db.resolve(name)
            if not r or (opx and not satisfies(r[1]["version"], opx, want)):
                missing.append(t)
        for t in missing:
            print(t)
        return 127 if missing else 0
    # -Q
    if "u" in mods:
        return refuse("Q", targets, "u")
    if "p" in mods:
        err("pacman on NixOS can't read Arch package files")
        return 1
    if "k" in mods or "c" in mods:
        err("pacman on NixOS doesn't support -Qk/-Qc")
        return 1
    quiet = "q" in mods
    if "g" in mods:
        if targets:
            for t in targets:
                err(f"group '{t}' was not found")
            return 1
        return 0
    if "o" in mods:
        return query_owns(db, targets, quiet)
    if "s" in mods:
        return query_search(db, targets, quiet, mods)

    def selected(name, e):
        if "e" in mods and not e["explicit"]:
            return False
        if "d" in mods and e["explicit"]:
            return False
        if "m" in mods:
            return False  # nothing is foreign: every package comes from nixpkgs
        if "t" in mods and "d" in mods:
            return False  # no orphans: the garbage collector keeps none
        if "t" in mods and not e["explicit"]:
            return False
        return True

    rc = 0
    if targets:
        found = []
        for t in targets:
            m = DEP_RE.match(t)
            name = m.group(1) if m else t
            r = db.resolve(name)
            if r and m and not satisfies(r[1]["version"], m.group(2), m.group(3)):
                r = None
            if r is None or not selected(name, r[1]):
                err(f"package '{t}' was not found")
                rc = 1
                continue
            found.append((name, r[1]))
    else:
        found = [(n, e) for n, e in sorted(db.pkgs.items()) if selected(n, e)]
        if not found:
            rc = 1  # as pacman: a filter that matches nothing (-Qdt, -Qm) fails
    out = []
    if "l" in mods:
        for name, e in found:
            for root in e["paths"]:
                for p in walk(root):
                    out.append(p if quiet else f"{name} {p}")
    elif "i" in mods:
        for name, e in found:
            real_name = db.real_name(e)
            out.append(info_block(db, name, e, real_name))
        sys.stdout.write("".join(out))
        return rc
    else:
        for name, e in found:
            out.append(name if quiet else f"{name} {e['version']}")
        if not targets and not ("e" in mods or "d" in mods or "t" in mods or "m" in mods):
            # Arch names of installed packages (their Provides), so a plugin
            # grepping the whole list finds what it knows by Arch name.
            for a in db.idx["archnames"]:
                out.append(a if quiet else f"{a} {db.pkgs[db.alias[a]]['version']}")
    if out:
        sys.stdout.write("\n".join(out) + "\n")
    return rc


def walk(root):
    res = []
    if not root or not os.path.exists(root):
        return res
    if not os.path.isdir(root):
        return [root]
    res.append(root + "/")
    for d, dirs, files in os.walk(root):
        dirs.sort()
        for x in dirs:
            res.append(os.path.join(d, x) + "/")
        for x in sorted(files):
            res.append(os.path.join(d, x))
    return res


def query_owns(db, targets, quiet):
    if not targets:
        err("no file was specified for --owns")
        return 1
    rc = 0
    for t in targets:
        path = t
        if "/" not in t:
            for d in os.environ.get("PATH", "").split(":"):
                c = os.path.join(d, t)
                if d and os.path.exists(c):
                    path = c
                    break
            else:
                err(f"failed to find '{t}' in PATH: No such file or directory")
                rc = 1
                continue
        if not os.path.lexists(path):
            err(f"failed to read file '{t}': No such file or directory")
            rc = 1
            continue
        target = real(path) or path
        parsed = parse_store_name(target)
        if not parsed:
            err(f"No package owns {t}")
            rc = 1
            continue
        name = parsed[0]
        e = db.pkgs.get(name)
        ver = e["version"] if e else arch_version(parsed[1])
        print(name if quiet else f"{t} is owned by {name} {ver}")
    return rc


def query_search(db, targets, quiet, mods):
    pats = [re.compile(t, re.I) for t in targets] if targets else []
    rc = 1
    for name, e in sorted(db.pkgs.items()):
        if "e" in mods and not e["explicit"]:
            continue
        text = name + " " + (e.get("description") or "") + " " + " ".join(db.provides(name))
        if all(p.search(text) for p in pats):
            rc = 0
            if quiet:
                print(name)
            else:
                print(f"local/{name} {e['version']}")
                print(f"    {e.get('description') or ''}")
    return rc


# -------------------------------------------------------------- expac
EXPAC_FIELDS = {
    "n": lambda n, e, db, o: n, "v": lambda n, e, db, o: e["version"],
    "d": lambda n, e, db, o: e.get("description") or "", "u": lambda n, e, db, o: e.get("url") or "",
    "m": lambda n, e, db, o: human(e.get("size") or 0, o["H"]) if o["H"] else str(e.get("size") or 0),
    "k": lambda n, e, db, o: "0", "a": lambda n, e, db, o: os.uname().machine,
    "r": lambda n, e, db, o: "local", "p": lambda n, e, db, o: "nixpkgs <https://github.com/NixOS/nixpkgs>",
    "w": lambda n, e, db, o: "explicit" if e.get("explicit") else "dependency",
    "l": lambda n, e, db, o: time.strftime(o["t"], time.localtime(e.get("installed") or 1)),
    "b": lambda n, e, db, o: time.strftime(o["t"], time.localtime(1)),
    "P": lambda n, e, db, o: o["l"].join(db.provides(db.real_name(e) or n)),
    "L": lambda n, e, db, o: o["l"].join(e.get("licenses") or []),
    "e": lambda n, e, db, o: n, "f": lambda n, e, db, o: "",
}


def expac(argv):
    opts = {"H": None, "l": "  ", "d": "\n", "t": "%c"}
    sync = False
    fmt = None
    targets = []
    i = 0
    while i < len(argv):
        a = argv[i]
        i += 1
        if a in ("-Q", "--query"):
            continue
        if a in ("-S", "--sync"):
            sync = True
            continue
        if a in ("-H", "--humansize", "-l", "--listdelim", "-d", "--delim", "-t", "--timefmt"):
            key = {"--humansize": "H", "--listdelim": "l", "--delim": "d", "--timefmt": "t"}.get(a, a[1:])
            opts[key] = argv[i] if i < len(argv) else ""
            i += 1
            continue
        if a.startswith("-") and a != "-" and len(a) > 1 and fmt is None and not a.startswith("--"):
            # clustered short flags (-Qv, -1, ...), values for H/l/d/t inline
            rest = a[1:]
            if rest[:1] in "Hldt" and len(rest) > 1:
                opts[rest[0]] = rest[1:]
            elif "S" in rest:
                sync = True
            continue
        if a.startswith("--"):
            continue
        if fmt is None:
            fmt = a
        else:
            targets.append(a)
    if sync:
        return refuse("S", targets, "s")
    if fmt is None:
        err("missing format string (use -h for help)")
        return 1
    if targets == ["-"]:
        targets = sys.stdin.read().split()
    db = Db()
    rows = []
    if targets:
        for t in targets:
            r = db.resolve(t)
            if r:
                rows.append(r)
    else:
        rows = sorted(db.pkgs.items())

    def render(n, e):
        out, k = [], 0
        while k < len(fmt):
            c = fmt[k]
            if c == "%" and k + 1 < len(fmt):
                f = fmt[k + 1]
                k += 2
                if f == "%":
                    out.append("%")
                elif f in EXPAC_FIELDS:
                    out.append(EXPAC_FIELDS[f](n, e, db, opts))
                else:
                    out.append("")
                continue
            if c == "\\" and k + 1 < len(fmt):
                out.append({"n": "\n", "t": "\t", "\\": "\\", "e": "\033", "a": "\a"}.get(fmt[k + 1], fmt[k + 1]))
                k += 2
                continue
            out.append(c)
            k += 1
        return "".join(out)

    delim = opts["d"].replace("\\n", "\n").replace("\\t", "\t")
    if rows:
        sys.stdout.write(delim.join(render(n, e) for n, e in rows) + ("\n" if delim == "\n" else ""))
    return 0 if len(rows) == len(targets) or not targets else 1


def main():
    argv = sys.argv[1:]
    if PROG == "vercmp" or (argv[:1] == ["--vercmp"]):
        a = argv[1:] if argv[:1] == ["--vercmp"] else argv
        if len(a) != 2:
            print("usage: vercmp <ver1> <ver2>", file=sys.stderr)
            return 1
        print(vercmp(a[0], a[1]))
        return 0
    if PROG == "expac" or argv[:1] == ["--expac"]:
        return expac(argv[1:] if argv[:1] == ["--expac"] else argv)
    try:
        return pacman(argv)
    except BrokenPipeError:
        return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except BrokenPipeError:
        try:
            sys.stdout = None
        except Exception:
            pass
        sys.exit(0)
