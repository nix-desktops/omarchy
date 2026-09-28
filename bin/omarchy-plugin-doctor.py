#!/usr/bin/env python3
# omarchy plugin doctor: what an Omarchy shell plugin needs on NixOS.
#
# Reads a plugin's files (never runs them) and reports:
#   - the external commands it runs (Process `command: [...]` arrays,
#     execDetached, `sh -c` strings, its own shell and Python scripts,
#     shebangs, /usr/bin/<cmd> paths), which of them are missing from the
#     shell's PATH, and the nixpkgs package providing each (nixpkgs'
#     programs.sqlite, the command-not-found database);
#   - Python modules its scripts import that the standard library lacks;
#   - QML modules it imports that the shell can't load;
#   - fixed Arch paths (/usr/share/omarchy, /usr/lib/...) and whether this
#     system provides them;
#   - pacman/AUR usage and native builds: Arch-only, won't work here;
# and prints the NixOS line that adds what's missing.
#
# Usage: omarchy plugin doctor [id|path ...] [--json] [--available FILE]
#   With no argument: every third-party plugin in ~/.config/omarchy/plugins.
#
# Environment (set by the NixOS package; each optional):
#   OMARCHY_PROGRAMS_DB    programs.sqlite
#   OMARCHY_QML_MODULES    file listing the QML modules the shell can import
#   OMARCHY_PY_PACKAGES    file listing python3Packages attribute names
import json
import os
import re
import sqlite3
import subprocess
import sys

HOME = os.path.expanduser("~")
PLUGINS_DIR = os.path.join(HOME, ".config/omarchy/plugins")
SYSTEM = os.environ.get("OMARCHY_SYSTEM") or (os.uname().machine + "-linux")

SKIP_DIRS = {".git", "node_modules", "tests", "test", "__pycache__", ".github", "docs", "screenshots", "assets"}
CODE_EXT = (".qml", ".js", ".mjs", ".sh", ".bash", ".py", ".zsh")
MAX_FILE = 512 * 1024

# Shell words that are not external commands.
SHELL_WORDS = set("""
if then else elif fi for while until do done case esac in function select time
return exit break continue local export declare typeset readonly set unset shift
cd pwd source . eval exec trap wait let read mapfile readarray getopts alias unalias
umask shopt pushd popd dirs jobs fg bg disown caller compgen complete hash type ulimit
builtin command echo printf test [ [[ ]] ] : true false { } ( ) ! kill enable help
coproc logout suspend times
""".split())
# Wrappers whose next word is the command.
WRAPPERS = {"sudo", "exec", "nohup", "setsid", "env", "timeout", "nice", "ionice", "stdbuf",
            "time", "xargs", "doas", "pkexec", "chrt", "taskset", "flock", "systemd-run",
            "uwsm-app", "uwsm", "unbuffer", "script", "watch", "runuser", "setpriv"}
# Arch's package tools.
ARCH_RE = re.compile(r"(?<![\w.-])(pacman|yay|paru|makepkg|checkupdates|expac|pactree|paccache|pikaur|trizen|pamac|aura|reflector|arch-audit|informant|pacdiff)(?![\w.-])")
ARCH_PATH_RE = re.compile(r"/var/lib/pacman|/etc/pacman|/var/cache/pacman|archlinux\.org/packages|aur\.archlinux\.org")
USR_RE = re.compile(r"(?<![\w.~$}\)-])(/usr/(?:bin|sbin|share|lib|lib64|libexec|local)(?:/[A-Za-z0-9._+@-]+)*|/bin/[A-Za-z0-9._+-]+|/sbin/[A-Za-z0-9._+-]+)")
NATIVE_FILES = {"CMakeLists.txt": "CMake", "meson.build": "Meson", "Cargo.toml": "Cargo (Rust)",
                "go.mod": "Go module", "build.zig": "Zig", "configure.ac": "autotools", "setup.py": "Python build (setup.py)"}
NATIVE_EXT = {".c": "C", ".cc": "C++", ".cpp": "C++", ".cxx": "C++", ".rs": "Rust", ".go": "Go",
              ".zig": "Zig", ".so": "prebuilt library (.so)"}
NATIVE_BUILD_CMDS = re.compile(r"(?<![\w-])(cargo\s+build|cmake\s|make\s+(-j|install|all)|go\s+build|gcc\s|g\+\+\s|clang\s|meson\s+setup|ninja\s|npm\s+(ci|install)|pnpm\s+install|bun\s+install|pip3?\s+install|pipx\s+install|uv\s+(pip|sync))")

# Commands whose nixpkgs package isn't the obvious one in programs.sqlite.
PREFERRED = {
    "python3": "python3", "python": "python3", "pip": "python3Packages.pip", "pip3": "python3Packages.pip",
    "node": "nodejs", "npm": "nodejs", "npx": "nodejs", "hyprctl": "hyprland", "Hyprland": "hyprland",
    "pkg-config": "pkg-config", "sqlite3": "sqlite",
    "notify-send": "libnotify", "nmcli": "networkmanager", "gdbus": "glib", "busctl": "systemd",
    "systemctl": "systemd", "journalctl": "systemd", "loginctl": "systemd", "timedatectl": "systemd",
    "pactl": "pulseaudio", "wpctl": "wireplumber", "pw-cli": "pipewire", "pw-dump": "pipewire",
    "xdg-open": "xdg-utils", "wl-copy": "wl-clipboard", "wl-paste": "wl-clipboard",
    "convert": "imagemagick", "magick": "imagemagick", "identify": "imagemagick",
    "ffprobe": "ffmpeg", "ffmpeg": "ffmpeg", "sensors": "lm_sensors",
    "secret-tool": "libsecret", "gsettings": "glib", "dig": "dnsutils", "nslookup": "dnsutils",
    "ip": "iproute2", "ss": "iproute2", "iwctl": "iwd", "bluetoothctl": "bluez", "upower": "upower",
    "powerprofilesctl": "power-profiles-daemon", "brightnessctl": "brightnessctl", "xkbcli": "libxkbcommon",
    "qdbus": "kdePackages.qttools", "qmlscene": "kdePackages.qtdeclarative", "zenity": "zenity",
    "docker": "docker", "podman": "podman", "tailscale": "tailscale", "wg": "wireguard-tools",
    "wg-quick": "wireguard-tools", "curl": "curl", "wget": "wget", "jq": "jq", "yq": "yq-go",
}
# Commands that come with a NixOS service or driver, not a package.
SERVICES = {
    "nvidia-smi": 'hardware.nvidia (services.xserver.videoDrivers = [ "nvidia" ])',
    "fprintd-list": "services.fprintd.enable = true", "fprintd-enroll": "services.fprintd.enable = true",
    "fprintd-verify": "services.fprintd.enable = true", "fprintd-delete": "services.fprintd.enable = true",
    "asusctl": "services.asusd.enable = true", "supergfxctl": "services.supergfxd.enable = true",
    "tailscale": "services.tailscale.enable = true", "keyd": "services.keyd.enable = true",
    "monitor-sensor": "hardware.sensor.iio.enable = true", "openvpn3": "programs.openvpn3.enable = true",
    "docker": "virtualisation.docker.enable = true", "podman": "virtualisation.podman.enable = true",
    "flatpak": "services.flatpak.enable = true", "ollama": "services.ollama.enable = true",
    "powerprofilesctl": "services.power-profiles-daemon.enable = true", "tlp": "services.tlp.enable = true",
    "bluetoothctl": "hardware.bluetooth.enable = true", "iwctl": "networking.wireless.iwd.enable = true",
    "snapper": "services.snapper", "fwupdmgr": "services.fwupd.enable = true",
}
# Python import name → python3Packages attribute, where they differ.
PY_ALIASES = {
    "yaml": "pyyaml", "PIL": "pillow", "dbus": "dbus-python", "gi": "pygobject3", "bs4": "beautifulsoup4",
    "cv2": "opencv4", "serial": "pyserial", "usb": "pyusb", "dateutil": "python-dateutil",
    "Crypto": "pycryptodome", "Cryptodome": "pycryptodomex", "jwt": "pyjwt", "dotenv": "python-dotenv",
    "magic": "python-magic", "sklearn": "scikit-learn", "attr": "attrs", "google": "protobuf",
    "zmq": "pyzmq", "OpenSSL": "pyopenssl", "fitz": "pymupdf", "docx": "python-docx", "pptx": "python-pptx",
    "telegram": "python-telegram-bot", "Xlib": "xlib", "evdev": "evdev", "pynvml": "nvidia-ml-py",
    "websocket": "websocket-client", "icalendar": "icalendar", "feedparser": "feedparser", "mpd": "python-mpd2",
    "pulsectl": "pulsectl", "psutil": "psutil", "requests": "requests", "httpx": "httpx", "aiohttp": "aiohttp",
    "gpiozero": "gpiozero", "smbus": "smbus2", "pydbus": "pydbus", "keyring": "keyring", "tzlocal": "tzlocal",
    "sdbus": "python-sdbus", "pyudev": "pyudev", "notify2": "notify2", "numpy": "numpy",
}


def read(path):
    try:
        if os.path.getsize(path) > MAX_FILE:
            return None
        with open(path, "r", errors="replace") as f:
            return f.read()
    except OSError:
        return None


def line_of(text, pos):
    return text.count("\n", 0, pos) + 1


# ------------------------------------------------------------------ files
def plugin_files(root):
    for dirpath, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS and not d.startswith(".")]
        for f in files:
            yield os.path.join(dirpath, f)


def is_test_file(path):
    base = os.path.basename(path)
    return base.startswith("tst_") or base.endswith((".test.js", ".spec.js", "_test.py")) or base.startswith("test_")


def script_kind(path, text):
    if path.endswith((".sh", ".bash", ".zsh")):
        return "sh"
    if path.endswith(".py"):
        return "py"
    if text.startswith("#!"):
        first = text.split("\n", 1)[0]
        if re.search(r"python", first):
            return "py"
        if re.search(r"\b(ba|z|da|k)?sh\b", first):
            return "sh"
    if path.endswith((".qml", ".js", ".mjs")):
        return "qml"
    return None


# ------------------------------------------------------------ shell words
def strip_heredocs(text):
    # Drop here-document bodies (data, not commands).
    out, lines, skip = [], text.split("\n"), None
    for ln in lines:
        if skip is not None:
            if ln.strip() == skip:
                skip = None
            out.append(" " * len(ln))  # same length: offsets stay true
            continue
        m = re.search(r"<<-?\s*['\"]?([A-Za-z_][A-Za-z0-9_]*)['\"]?", ln)
        if m:
            skip = m.group(1)
        out.append(ln)
    return "\n".join(out)


def command_starts(text):
    """Offsets where a command starts in shell text, from a small lexer:
    quotes, comments, $( ) and ( ) nesting, separators."""
    n, i = len(text), 0
    starts = [0]
    stack = []      # quote state to restore at the matching ")"
    quote = None
    while i < n:
        c = text[i]
        if quote == "'":
            if c == "'":
                quote = None
            i += 1
            continue
        if quote == '"':
            if c == "\\":
                i += 2
                continue
            if c == '"':
                quote = None
            elif text.startswith("$((", i):
                i += 3
                continue
            elif text.startswith("$(", i):
                stack.append('"')
                quote = None
                i += 2
                starts.append(i)
                continue
            i += 1
            continue
        if c == "\\":
            i += 2
            continue
        if c == "#" and (i == 0 or text[i - 1] in " \t\n;|&("):
            j = text.find("\n", i)
            i = n if j == -1 else j
            continue
        if c in "'\"":
            quote = c
        elif text.startswith("$((", i) or text.startswith("((", i):
            # Arithmetic, not commands.
            j = text.find("))", i)
            i = n if j == -1 else j + 2
            continue
        elif text.startswith("$(", i):
            stack.append(None)
            i += 2
            starts.append(i)
            continue
        elif c == "(":
            stack.append(None)
            starts.append(i + 1)
        elif c == ")":
            if stack:
                quote = stack.pop()
        elif c in ";&|\n{`":
            starts.append(i + 1)
        i += 1
    return starts


TOKEN = re.compile(r"""(?:"(?:[^"\\]|\\.)*"|'[^']*'|[^\s;&|()<>`"'])+\)?""")
KEYWORDS = {"if", "then", "else", "elif", "do", "while", "until", "!", "time", "{", "}", "(", "fi", "done", "esac", "coproc"}
CASE_PATTERN = re.compile(r"""[ \t]*\(?[ \t]*[^\s()"';|]+([ \t]*\|[ \t]*[^\s()"';|]+)*[ \t]*\)""")


def shell_commands(text):
    """(word, offset, kind) for the commands a shell snippet runs; kind is
    "run" or "probe" (command -v / which / hash / type X)."""
    text = strip_heredocs(text)
    # (( arithmetic )), kept the same length.
    text = re.sub(r"\(\([^()\n]*(\([^()\n]*\)[^()\n]*)*\)\)", lambda m: " " * len(m.group(0)), text)
    functions = set(re.findall(r"(?m)^\s*(?:function\s+)?([A-Za-z_][\w:-]*)\s*\(\s*\)", text))
    functions |= set(re.findall(r"(?m)^\s*function\s+([A-Za-z_][\w:-]*)", text))
    results = []
    case_end = {}
    for s in sorted(set(command_starts(text))):
        line_start = text.rfind("\n", 0, s) + 1
        line_end = text.find("\n", s)
        if line_start not in case_end:
            pat = CASE_PATTERN.match(text, line_start, len(text) if line_end == -1 else line_end)
            case_end[line_start] = pat.end() if pat else -1
        if s < case_end[line_start]:
            continue  # a case pattern ("start|stop)"), not a command
        seg = text[s:(len(text) if line_end == -1 else line_end)][:300]
        if seg.lstrip().startswith("("):
            continue  # (( arithmetic )), or a subshell whose own start is counted
        words = [m.group(0) for m in TOKEN.finditer(seg)]
        idx, kind = 0, "run"
        while idx < len(words):
            w = words[idx]
            bare = w.strip("\"'")
            if bare in KEYWORDS:
                idx += 1
                continue
            if re.match(r"^[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?\+?=", w):  # VAR=value
                idx += 1
                continue
            if bare in ("command", "builtin") and idx + 1 < len(words) and words[idx + 1] in ("-v", "-V"):
                kind = "probe"
                idx += 2
                continue
            if bare in ("which", "hash", "type") and idx + 1 < len(words):
                kind = "probe"
                idx += 1
                while idx < len(words) and words[idx].startswith("-"):
                    idx += 1
                continue
            if bare in ("command", "builtin", "exec", "nohup"):
                idx += 1
                while idx < len(words) and words[idx].startswith("-"):
                    idx += 1
                continue
            if bare in WRAPPERS:
                results.append((bare, s, kind))
                idx += 1
                # Options, VAR=..., a duration (timeout), "--", "app" (uwsm app).
                while idx < len(words) and (words[idx].startswith("-") or "=" in words[idx]
                                            or re.match(r"^\d+(\.\d+)?[smhd]?$", words[idx]) or words[idx] in ("app", "--")):
                    idx += 1
                continue
            break
        if idx >= len(words):
            continue
        w = words[idx]
        if w.endswith(")") or "$" in w or "`" in w:
            continue
        results.append((w.strip("\"'"), s, kind))
    return [(w, off, kind) for w, off, kind in results if w not in functions]


# -------------------------------------------------------------- QML / JS
STR = r"""(?:"((?:[^"\\\n]|\\.)*)"|'((?:[^'\\\n]|\\.)*)'|`((?:[^`\\]|\\.)*)`)"""
ARRAY_START = re.compile(r"\[\s*" + STR + r"(\s*,\s*" + STR + r")?(\s*,\s*" + STR + r")?", re.S)
CONTEXT = re.compile(r"(\bcommand\s*[:=]|\bcommands\s*[:=]|\bexec\w*\s*\(|\bspawn\w*\s*\(|\bstartDetached\s*\(|\bexecFile\w*\s*\(|\bconcat\s*\()\s*\(?\s*\{?\s*(command\s*:\s*)?$")


def first(groups):
    for g in groups:
        if g is not None:
            return g
    return None


def unescape(s):
    return s.replace("\\n", "\n").replace('\\"', '"').replace("\\'", "'").replace("\\\\", "\\")


def qml_commands(text):
    """(word, offset, kind, how) from QML/JS."""
    # Comments (whole-line // and /* */ blocks), kept the same length.
    text = re.sub(r"/\*.*?\*/", lambda m: re.sub(r"[^\n]", " ", m.group(0)), text, flags=re.S)
    text = re.sub(r"(?m)^[ \t]*//.*$", lambda m: " " * len(m.group(0)), text)
    out = []
    # The plugin's own functions named like a command runner
    # (`function exec(args, cb) { db(args, cb) }`): an array passed to one
    # is a command only when the function hands its argument straight to a
    # process (`command = args`, `execDetached(args)`); otherwise it's the
    # plugin's own subcommands (`exec(["start", task])`).
    wrappers = set()
    for d in re.finditer(r"\bfunction\s+(\w+)\s*\(\s*(\w*)|\b(\w+)\s*[:=]\s*(?:function\s*)?\(\s*(\w*)[^)]*\)\s*(?:=>)?\s*\{", text):
        name, param = d.group(1) or d.group(3), d.group(2) or d.group(4)
        body = text[d.end():d.end() + 600]
        direct = param and re.search(r"\bcommand\s*[:=]\s*" + re.escape(param) + r"\b|\b(?:exec\w*|startDetached|spawn\w*)\s*\(\s*" + re.escape(param) + r"\b", body)
        if not direct:
            wrappers.add(name)
    for m in ARRAY_START.finditer(text):
        before = text[max(0, m.start() - 60):m.start()]
        ctx = CONTEXT.search(before)
        if not ctx:
            continue
        called = re.match(r"(\w+)\s*\(", ctx.group(1))
        if called and called.group(1) in wrappers:
            continue
        g = m.groups()
        a0 = first(g[0:3])
        a1 = first(g[4:7]) if g[3] else None
        a2 = first(g[8:11]) if g[7] else None
        if a0 is None:
            continue
        a0 = a0.strip()
        if "${" in a0 or " " in a0 or not a0:
            continue
        name = a0
        shell_c = name in ("sh", "bash", "zsh", "dash", "/bin/sh", "/bin/bash", "/usr/bin/bash", "/usr/bin/sh") and a1 in ("-c", "-lc", "-ic", "-euc", "-ec", "-lic")
        if before.rstrip().endswith("concat(") and not shell_c:
            continue  # arguments appended to a command held elsewhere
        if name in ("sh", "bash", "zsh", "dash", "/bin/sh", "/bin/bash", "/usr/bin/bash", "/usr/bin/sh") and a1 in ("-c", "-lc", "-ic", "-euc", "-ec", "-lic"):
            out.append((os.path.basename(name), m.start(), "run", "array"))
            if a2:
                for w, off, kind in shell_commands(unescape(a2)):
                    out.append((w, m.start(), kind, "sh -c"))
            continue
        out.append((name, m.start(), "run", "array"))
    # Shell kept in strings (a script variable, lines joined into one):
    # literals that read like shell, parsed with less certainty.
    for m in re.finditer(STR, text):
        s = first(m.groups())
        if s and 12 < len(s) < 4000 and re.search(r"(>\s*/dev/null|2>&1|\$\(|\bcommand -v\b)", s):
            for w, off, kind in shell_commands(unescape(s)):
                out.append((w, m.start(), kind, "shell text"))
    for m in re.finditer(r"Qt\.openUrlExternally\s*\(", text):
        out.append(("xdg-open", m.start(), "run", "openUrlExternally"))
    return out


def qml_imports(text):
    return [(m.group(1), m.start()) for m in re.finditer(r"(?m)^\s*import\s+([A-Z][A-Za-z0-9_.]*)", text)]


# ------------------------------------------------------------------ Python
def py_commands(text):
    out = []
    for m in re.finditer(r"(?<![\w.])(?:subprocess\.|asyncio\.)?(?:run|Popen|call|check_call|check_output|getoutput|getstatusoutput|create_subprocess_exec|create_subprocess_shell)\s*\(\s*\[?\s*" + STR, text):
        s = first(m.groups())
        if not s:
            continue
        if re.search(r"\s", s.strip()) or re.search(r"[|;&]", s):
            for w, off, kind in shell_commands(s):
                out.append((w, m.start(), kind, "python"))
        else:
            out.append((s.strip(), m.start(), "run", "python"))
    for m in re.finditer(r"os\.(?:system|popen)\s*\(\s*f?" + STR, text):
        s = first(m.groups())
        if s:
            for w, off, kind in shell_commands(s):
                out.append((w, m.start(), kind, "python"))
    for m in re.finditer(r"shutil\.which\s*\(\s*" + STR, text):
        s = first(m.groups())
        if s:
            out.append((s, m.start(), "probe", "python"))
    return out


def py_imports(text):
    mods = []
    for m in re.finditer(r"(?m)^\s*(?:from\s+([A-Za-z_][\w]*)[\w.]*\s+import\b|import\s+([A-Za-z_][\w]*(?:\s*,\s*[A-Za-z_][\w.]*)*))", text):
        if m.group(1):
            mods.append((m.group(1), m.start()))
        else:
            for part in m.group(2).split(","):
                mods.append((part.strip().split(".")[0], m.start()))
    return mods


# -------------------------------------------------------------- lookups
class Env:
    def __init__(self, available_file=None, assume_envfs=False, assume_usr_share=False):
        self.path_dirs = []
        self.available = None
        if available_file:
            with open(available_file) as f:
                self.available = {l.strip() for l in f if l.strip()}
        else:
            path = self.shell_path() or os.environ.get("PATH", "")
            self.path_dirs = [d for d in path.split(":") if d]
        db = os.environ.get("OMARCHY_PROGRAMS_DB")
        self.db = None
        if db and os.path.exists(db):
            try:
                self.db = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
            except sqlite3.Error:
                self.db = None
        self.qml = self.read_set("OMARCHY_QML_MODULES")
        self.pypkgs = self.read_set("OMARCHY_PY_PACKAGES")
        self.envfs = assume_envfs or self.usr_bin_is_envfs()
        self.usr_share_omarchy = assume_usr_share or os.path.isdir("/usr/share/omarchy/shell")

    @staticmethod
    def read_set(var):
        p = os.environ.get(var)
        if not p or not os.path.exists(p):
            return None
        with open(p) as f:
            return {l.strip() for l in f if l.strip()}

    @staticmethod
    def shell_path():
        # The shell's PATH (the omarchy-shell user unit's), which its
        # plugins inherit; falls back to this process's.
        try:
            out = subprocess.run(["systemctl", "--user", "show", "-p", "Environment", "omarchy-shell.service"],
                                 capture_output=True, text=True, timeout=5).stdout
            m = re.search(r"(?:^|\s)PATH=(\S+)", out)
            return m.group(1) if m else None
        except (OSError, subprocess.SubprocessError):
            return None

    @staticmethod
    def usr_bin_is_envfs():
        try:
            with open("/proc/self/mounts") as f:
                for line in f:
                    parts = line.split()
                    if len(parts) > 2 and parts[1] == "/usr/bin" and ("envfs" in line or parts[2].startswith("fuse")):
                        return True
        except OSError:
            pass
        # Whatever serves it: /usr/bin/<cmd> resolves for commands on PATH.
        return os.path.exists("/usr/bin/ls") and os.path.exists("/usr/bin/env")

    def has(self, cmd):
        if self.available is not None:
            return cmd in self.available
        for d in self.path_dirs:
            p = os.path.join(d, cmd)
            if os.access(p, os.X_OK) and not os.path.isdir(p):
                return True
        return False

    def packages(self, cmd):
        if cmd in PREFERRED:
            return [PREFERRED[cmd]]
        if self.db is None:
            return None
        try:
            rows = [r[0] for r in self.db.execute(
                "select package from Programs where name = ? and system = ?", (cmd, SYSTEM))]
        except sqlite3.Error:
            return None

        def score(p):
            bad = any(x in p for x in ("Minimal", "bootstrap", "FreeThreading", "unwrapped", "-tod", "_bin", "-bin", "Full",
                                        "busybox", "toybox"))
            return (p != cmd, bad, p.count("."), not p.startswith(cmd), len(p), p)
        return sorted(set(rows), key=score)[:3]

    def py_package(self, mod):
        attr = PY_ALIASES.get(mod, mod.lower().replace("_", "-"))
        if self.pypkgs is not None:
            if attr in self.pypkgs:
                return attr
            alt = mod.lower()
            return alt if alt in self.pypkgs else None
        return attr


# Where a command name certainly is a command (not a word in a string).
SURE = {"array", "sh -c", "shebang", "python", "openUrlExternally", "path"}
STDLIB = set(getattr(sys, "stdlib_module_names", ())) | {"__future__"}


# --------------------------------------------------------------- analysis
def analyse(root, env):
    root = os.path.realpath(root)
    manifest = {}
    try:
        with open(os.path.join(root, "manifest.json")) as f:
            manifest = json.load(f)
    except (OSError, ValueError):
        pass
    pid = manifest.get("id") or os.path.basename(root)
    local_names = set()
    files = []
    for p in plugin_files(root):
        local_names.add(os.path.basename(p))
        local_names.add(os.path.splitext(os.path.basename(p))[0])
        files.append(p)

    cmds = {}        # name -> {kind, where}
    fixed = {}       # path -> [where]
    arch = []
    arch_install = []
    native = []
    pymods = {}
    qmlmods = {}

    def add_cmd(name, where, kind, how):
        if not name:
            return
        if name.startswith("/"):
            name = name.rstrip(".")
            if not re.match(r"^/(usr|bin|sbin|opt)(/[A-Za-z0-9._+@-]+)+$", name):
                return
            fixed.setdefault(name, set()).add(where)
            if re.match(r"^/(usr/)?s?bin/[^/]+$", name):
                name = os.path.basename(name)
                how = "path"
            else:
                return
        if "/" in name or name.startswith(("$", "-", ".", "~")) or not re.match(r"^[A-Za-z0-9_][A-Za-z0-9_.+-]*$", name):
            return
        if name in SHELL_WORDS or name in local_names or re.match(r"^\d", name):
            return
        e = cmds.setdefault(name, {"kinds": set(), "where": set(), "how": set(), "files": set()})
        e["kinds"].add(kind)
        e["where"].add(where)
        e["how"].add(how)
        e["files"].add(where.split(":")[0])

    # Pass 1: what each file is.
    info = {}
    for p in files:
        rel = os.path.relpath(p, root)
        base = os.path.basename(p)
        ext = os.path.splitext(base)[1]
        if base in NATIVE_FILES:
            native.append({"what": NATIVE_FILES[base], "file": rel})
        if ext in NATIVE_EXT:
            native.append({"what": NATIVE_EXT[ext] + " source" if ext != ".so" else NATIVE_EXT[ext], "file": rel})
        if base == "qmldir":
            if re.search(r"(?m)^\s*plugin\s", read(p) or ""):
                native.append({"what": "C++ QML plugin (qmldir)", "file": rel})
        if base == "package.json":
            try:
                if json.loads(read(p) or "{}").get("dependencies"):
                    native.append({"what": "Node dependencies (npm install)", "file": rel})
            except ValueError:
                pass
        text = read(p)
        if text is None or "\0" in text[:2048]:
            if os.access(p, os.X_OK) and os.path.isfile(p) and ext not in CODE_EXT:
                native.append({"what": "prebuilt executable", "file": rel})
            continue
        kind = script_kind(p, text)
        if kind is None or is_test_file(p):
            continue
        # The UI (QML, and JS it imports) always loads; scripts count when
        # something that runs names them (dev and install scripts don't).
        ui = kind == "qml" and not text.startswith("#!")
        info[p] = {"rel": rel, "text": text, "kind": kind, "ui": ui}

    used = {p for p, f in info.items() if f["ui"]}
    pending = [p for p in info if p not in used]
    patterns = {}
    for p in pending:
        base = os.path.basename(p)
        patterns[p] = re.compile(r"(?<![\w.-])" + re.escape(base) + r"(?![\w-])")
    changed = True
    while changed:
        changed = False
        for p in list(pending):
            if any(patterns[p].search(info[u]["text"]) for u in used):
                used.add(p)
                pending.remove(p)
                changed = True
    unused_scripts = sorted(info[p]["rel"] for p in pending)

    # Pass 2: what the used files run and need.
    for p, f in info.items():
        rel, text, kind = f["rel"], f["text"], f["kind"]
        in_use = p in used
        install_step = re.match(r"(install|setup|build|bootstrap|postinstall)", os.path.basename(p), re.I)
        for m in NATIVE_BUILD_CMDS.finditer(text):
            if not (in_use or install_step):
                break
            if kind in ("sh", "py") or "command" in text[max(0, m.start() - 80):m.start()]:
                native.append({"what": "builds or installs code: " + m.group(1).strip(),
                               "file": f"{rel}:{line_of(text, m.start())}"})
        arch_hits = []
        for m in ARCH_RE.finditer(text):
            ln = text[text.rfind("\n", 0, m.start()) + 1:text.find("\n", m.start())]
            if re.match(r"\s*(#|//)", ln):
                continue
            arch_hits.append({"what": m.group(1), "file": f"{rel}:{line_of(text, m.start())}"})
        for m in ARCH_PATH_RE.finditer(text):
            arch_hits.append({"what": m.group(0), "file": f"{rel}:{line_of(text, m.start())}"})
        if not in_use:
            # An install or dev script: installing dependencies with pacman
            # there is a note, not a verdict.
            arch_install.extend(arch_hits)
            continue
        arch.extend(arch_hits)
        if text.startswith("#!"):
            shebang = text.split("\n", 1)[0][2:].strip().split()
            if shebang:
                interp = shebang[0]
                if os.path.basename(interp) == "env":
                    args = [a for a in shebang[1:] if not a.startswith("-")]
                    if args:
                        add_cmd(args[0], f"{rel}:1", "run", "shebang")
                else:
                    add_cmd(interp, f"{rel}:1", "run", "shebang")
        found = []
        if kind == "sh":
            found = [(w, o, k, "shell text") for w, o, k in shell_commands(text)]
        elif kind == "py":
            found = py_commands(text)
            for mod, off in py_imports(text):
                if mod in STDLIB or mod in local_names:
                    continue
                pymods.setdefault(mod, set()).add(f"{rel}:{line_of(text, off)}")
        elif kind == "qml":
            found = qml_commands(text)
            if p.endswith(".qml"):
                for mod, off in qml_imports(text):
                    qmlmods.setdefault(mod, set()).add(f"{rel}:{line_of(text, off)}")
        for w, off, k, how in found:
            add_cmd(w, f"{rel}:{line_of(text, off)}", k, how)
        for m in USR_RE.finditer(text):
            if re.search(r"\+\s*[\"'`]$", text[max(0, m.start() - 6):m.start()]):
                continue  # appended to a directory held elsewhere ("dir + "/bin/x")
            path = m.group(1).rstrip(".")
            if re.match(r"^/(usr/)?s?bin/[^/]+$", path):
                add_cmd(path, f"{rel}:{line_of(text, m.start())}", "run", "path")
            else:
                fixed.setdefault(path, set()).add(f"{rel}:{line_of(text, m.start())}")

    # ---- verdicts per command
    commands = []
    for name, e in sorted(cmds.items()):
        present = env.has(name)
        # Checked for first (command -v, which, shutil.which): optional, or
        # one of alternatives.
        kind = "optional" if "probe" in e["kinds"] else "run"
        entry = {"name": name, "kind": kind, "present": present, "files": sorted(e["files"]),
                 "where": sorted(e["where"])[:5], "how": sorted(e["how"])}
        if not present:
            if ARCH_RE.fullmatch(name):
                entry["status"] = "arch-only"
            elif name.startswith("omarchy-"):
                entry["status"] = "not-in-omarchy"
            elif name in SERVICES:
                entry["status"] = "service"
                entry["option"] = SERVICES[name]
            else:
                pk = env.packages(name)
                sure = bool(e["how"] & SURE)
                if pk and not sure and name not in PREFERRED:
                    # Parsed from shell text: English words in a string
                    # can look like commands, so only a package named
                    # like the command counts.
                    pk = [p for p in pk if p.split(".")[-1] == name] or []
                entry["packages"] = pk or []
                if pk:
                    entry["status"] = "missing"
                elif pk is None:
                    entry["status"] = "missing-no-db"
                else:
                    # Unknown words from shell text are often variables or
                    # functions sourced from elsewhere: only arrays,
                    # shebangs and paths are sure to be commands.
                    entry["status"] = "unknown" if sure else "unsure"
        else:
            entry["status"] = "ok"
        commands.append(entry)

    fixed_paths = []
    for path, where in sorted(fixed.items()):
        status = "missing"
        if re.match(r"^/(usr/)?s?bin/[^/]+$", path):
            cmd = os.path.basename(path)
            if cmd in ("env", "sh"):
                status = "ok"
            elif env.envfs:
                status = "envfs" if env.has(cmd) else "envfs-missing"
            else:
                status = "ok" if os.path.exists(path) else "needs-envfs"
        elif path.startswith("/usr/share/omarchy"):
            status = "ok" if env.usr_share_omarchy else "needs-link"
        elif os.path.exists(path):
            status = "ok"
        elif path.rstrip("/") in ("/usr/bin", "/usr/local/bin", "/usr/share", "/usr/lib", "/usr/local/share", "/usr/local"):
            status = "search-dir"
        fixed_paths.append({"path": path, "status": status, "where": sorted(where)[:3]})

    python = []
    for mod, where in sorted(pymods.items()):
        attr = env.py_package(mod)
        python.append({"module": mod, "package": attr, "where": sorted(where)[:3]})

    qml_missing = []
    if env.qml is not None:
        for mod, where in sorted(qmlmods.items()):
            if mod in env.qml or mod.startswith("qs.") or mod in ("Qt", "Quickshell._Window"):
                continue
            qml_missing.append({"module": mod, "where": sorted(where)[:3]})

    def first_seen(c):
        # The alternative a plugin tries first: its earliest mention.
        spots = []
        for w in c["where"]:
            f, _, ln = w.rpartition(":")
            spots.append((f, int(ln) if ln.isdigit() else 0))
        return min(spots) if spots else ("", 0)

    need = []
    for c in commands:
        if c["status"] != "missing" or not c["packages"]:
            continue
        if c["kind"] == "optional":
            # One of alternatives: suggested only when none of the
            # alternatives checked for in the same files is there.
            others = [o for o in commands if o["kind"] == "optional" and o is not c
                      and set(o["files"]) & set(c["files"])]
            if any(o["present"] for o in others) or any(
                    first_seen(o) < first_seen(c) and o["status"] == "missing" and o["packages"] for o in others):
                c["suggested"] = False
                continue
        c["suggested"] = True
        need.append(c["packages"][0])
    py_attrs = sorted({p["package"] for p in python if p["package"]})
    options = sorted({c["option"] for c in commands if c["status"] == "service"})
    unknown_py = sorted({p["module"] for p in python if not p["package"]})

    flags = []
    if arch:
        flags.append("arch-only")
    if native:
        flags.append("native-build")
    if need or py_attrs or options:
        flags.append("needs-packages")
    if any(c["status"] in ("unknown", "not-in-omarchy") and c["kind"] == "run" for c in commands) or unknown_py:
        flags.append("missing-commands")
    if qml_missing:
        flags.append("missing-qml")
    if any(f["status"] in ("needs-envfs", "needs-link", "envfs-missing") for f in fixed_paths):
        flags.append("fixed-paths")
    if "arch-only" in flags:
        verdict = "arch-only"
    elif "native-build" in flags:
        verdict = "native-build"
    elif "missing-qml" in flags or "missing-commands" in flags:
        verdict = "incomplete"
    elif "needs-packages" in flags:
        verdict = "needs-packages"
    else:
        verdict = "ok"

    declared = os.path.islink(os.path.join(PLUGINS_DIR, pid)) and os.path.realpath(
        os.path.join(PLUGINS_DIR, pid)).startswith("/nix/store/")
    return {
        "id": pid, "path": root, "name": manifest.get("name"), "kinds": manifest.get("kinds"),
        "declared": declared, "verdict": verdict, "flags": flags,
        "commands": commands, "fixedPaths": fixed_paths, "archOnly": arch, "archInstall": arch_install,
        "native": native, "unusedScripts": unused_scripts,
        "python": python, "qmlMissing": qml_missing,
        "packages": sorted(set(need)), "pythonPackages": py_attrs, "options": options,
        "nixos": nixos_line(pid, sorted(set(need)), py_attrs),
    }


def nixos_line(pid, pkgs, py):
    items = list(pkgs)
    if py:
        items = [p for p in items if p != "python3"]
        items.append("(python3.withPackages (ps: with ps; [ " + " ".join(py) + " ]))")
    if not items:
        return None
    return f'omarchy.plugins."{pid}".packages = with pkgs; [ ' + " ".join(items) + " ];"


# ----------------------------------------------------------------- output
def color(s, code):
    return f"\033[{code}m{s}\033[0m" if sys.stdout.isatty() else s


def print_report(r, verbose=False):
    title = r["name"] or r["id"]
    print(color(f"{title} ({r['id']})", "1"), "  " + r["path"])
    verdicts = {
        "ok": color("works as is, as far as its files tell", "32"),
        "needs-packages": color("needs packages", "33"),
        "incomplete": color("needs things NixOS can't provide from nixpkgs as named", "33"),
        "arch-only": color("Arch-only: won't work on NixOS", "31"),
        "native-build": color("native build: won't work as is", "31"),
    }
    print("  " + verdicts[r["verdict"]])
    run = [c for c in r["commands"] if c["status"] != "unsure" or verbose]
    if run:
        print("  Commands:")
        for c in run:
            where = c["where"][0] if c["where"] else ""
            probe = " (optional: checked for first)" if c["kind"] == "optional" else ""
            if c["status"] == "ok":
                if verbose:
                    print(f"    {c['name']:<24} ok{probe}")
                continue
            if c["status"] == "missing":
                alt = f" (or {', '.join(c['packages'][1:])})" if len(c["packages"]) > 1 else ""
                msg = color("missing", "33") + f" → nixpkgs: {c['packages'][0]}{alt}"
            elif c["status"] == "missing-no-db":
                msg = color("missing", "33") + " (no command database here; search https://search.nixos.org)"
            elif c["status"] == "service":
                msg = color("missing", "33") + f" → {c['option']}"
            elif c["status"] == "arch-only":
                msg = color("Arch-only", "31")
            elif c["status"] == "not-in-omarchy":
                msg = color("missing", "33") + " (not a command of this Omarchy: newer upstream, or Arch/hardware-specific)"
            elif c["status"] == "unknown":
                msg = color("missing", "33") + " (no nixpkgs package provides it)"
            else:
                msg = "not found (maybe a variable or function)"
            print(f"    {c['name']:<24} {msg}{probe}   {where}")
        if not any(c["status"] != "ok" for c in run):
            print("    all on the shell's PATH")
    if r["python"]:
        print("  Python modules:")
        for p in r["python"]:
            pk = f"python3Packages.{p['package']}" if p["package"] else "no python3Packages attribute found"
            print(f"    {p['module']:<24} → {pk}   {p['where'][0]}")
    if r["qmlMissing"]:
        print("  QML modules the shell can't load:")
        for q in r["qmlMissing"]:
            print(f"    {q['module']:<24} {q['where'][0]}")
    bad_paths = [f for f in r["fixedPaths"] if f["status"] not in ("ok", "envfs", "search-dir") or verbose]
    if bad_paths:
        print("  Fixed paths:")
        notes = {"ok": "exists", "envfs": "resolved by envfs from PATH", "search-dir": "a search directory",
                 "envfs-missing": "envfs is on, but the command isn't on PATH",
                 "needs-envfs": "missing (turn on omarchy.envfs.enable)",
                 "needs-link": "missing (turn on omarchy.usrShare.enable)", "missing": "doesn't exist on NixOS"}
        for f in bad_paths:
            print(f"    {f['path']:<40} {notes[f['status']]}   {f['where'][0]}")
    if r["archOnly"]:
        print("  " + color("Arch-only (won't work on NixOS):", "31"))
        seen = set()
        for a in r["archOnly"]:
            if a["what"] in seen:
                continue
            seen.add(a["what"])
            print(f"    {a['what']:<24} {a['file']}")
    if r["archInstall"]:
        whats = sorted({a["what"] for a in r["archInstall"]})
        files = sorted({a["file"].split(":")[0] for a in r["archInstall"]})
        print(f"  Its install/dev scripts use {', '.join(whats)} ({', '.join(files[:3])}): Arch-only;")
        print("    install what they would with Nix instead (the packages above).")
    if verbose and r["unusedScripts"]:
        print("  Scripts nothing at runtime runs (not checked): " + ", ".join(r["unusedScripts"][:8]))
    if r["native"]:
        print("  " + color("Native build (won't work as is: nothing builds it on NixOS):", "31"))
        for n in r["native"][:6]:
            print(f"    {n['what']:<40} {n['file']}")
    if r["nixos"] or r["options"]:
        print("  Add to your NixOS configuration (then rebuild):")
        if r["nixos"]:
            print("    " + r["nixos"])
        for o in r["options"]:
            print("    " + (o if o.endswith(";") or "(" in o else o + ";"))
    print()


def resolve_target(arg):
    if os.path.isdir(arg):
        return arg
    p = os.path.join(PLUGINS_DIR, arg)
    if os.path.isdir(p):
        return p
    return None


def main(argv):
    as_json = False
    verbose = False
    available = None
    assume_envfs = assume_usr_share = False
    targets = []
    it = iter(argv)
    for a in it:
        if a == "--json":
            as_json = True
        elif a in ("-v", "--verbose"):
            verbose = True
        elif a == "--available":
            # For checking a plugin for another system (the survey): the
            # commands on that system's shell PATH, one per line.
            available = next(it, None)
        elif a == "--assume-envfs":
            assume_envfs = True
        elif a == "--assume-usr-share":
            assume_usr_share = True
        elif a in ("-h", "--help"):
            print("Usage: omarchy plugin doctor [id|path ...] [--json] [--verbose] [--available FILE]")
            print("Reads a plugin's files and says what it needs on NixOS: missing commands and the")
            print("nixpkgs packages providing them, Python and QML modules, Arch-only parts.")
            return 0
        else:
            targets.append(a)
    if not targets:
        if os.path.isdir(PLUGINS_DIR):
            targets = sorted(os.path.join(PLUGINS_DIR, d) for d in os.listdir(PLUGINS_DIR)
                             if not d.startswith(".") and os.path.isfile(os.path.join(PLUGINS_DIR, d, "manifest.json")))
        if not targets:
            print("No third-party plugins in ~/.config/omarchy/plugins.", file=sys.stderr)
            return 0
    env = Env(available, assume_envfs, assume_usr_share)
    reports = []
    rc = 0
    for t in targets:
        d = resolve_target(t)
        if d is None:
            print(f"omarchy-plugin-doctor: no plugin '{t}' (an id in {PLUGINS_DIR}, or a folder)", file=sys.stderr)
            rc = 1
            continue
        reports.append(analyse(d, env))
    if as_json:
        print(json.dumps(reports if len(reports) != 1 or len(targets) > 1 else reports[0], indent=1))
    else:
        if env.db is None:
            print("(No command database: package names can't be looked up.)\n")
        for r in reports:
            print_report(r, verbose)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
