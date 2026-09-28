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
#   - package-manager calls: pacman queries (answered by the pacman shim,
#     omarchy.pacmanShim.enable), packages it installs or asks the user to
#     install (named in nixpkgs), and the rest (updates, removal, the sync
#     database: Arch-only); mentions in messages and comments don't count;
#   - native builds the plugin uses: won't work here as is;
# and prints the NixOS line that adds what's missing.
#
# Usage: omarchy plugin doctor [id|path ...] [--json] [--available FILE]
#                             [--assume-envfs] [--assume-usr-share] [--assume-pacman-shim]
#   With no argument: every third-party plugin in ~/.config/omarchy/plugins.
#
# Environment (set by the NixOS package; each optional):
#   OMARCHY_PROGRAMS_DB    programs.sqlite
#   OMARCHY_QML_MODULES    file listing the QML modules the shell can import
#   OMARCHY_PY_PACKAGES    file listing python3Packages attribute names
#   OMARCHY_NIX_ATTRS      file listing nixpkgs attribute names (top level,
#                          kdePackages.*, …) to check package names against
#   OMARCHY_ARCH_PACKAGES  data/arch-packages.json: Arch name → nixpkgs attribute
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
ARCH_RE = re.compile(r"(?<![\w.-])(pacman|yay|paru|makepkg|checkupdates|expac|pactree|paccache|pikaur|trizen|pamac|aura|reflector|arch-audit|informant|pacdiff|vercmp)(?![\w.-])")
# Reading pacman's own state: Arch-only when code does it.
ARCH_PATH_RE = re.compile(r"/var/lib/pacman|/etc/pacman\.(?:conf|d)|/var/cache/pacman|/var/log/pacman\.log|(?<![\w-])pacman-conf(?![\w-])")
# Package managers whose first argument is an operation (-S, -Q, …); a
# bare mention ("pacman" in a game, asusctl's `aura` subcommand) isn't a call.
PKG_MANAGERS = {"pacman", "yay", "paru", "pikaur", "trizen", "aura"}
# What pkgs/pacman-shim answers (omarchy.pacmanShim.enable): pacman's local
# queries, expac -Q and vercmp.
SHIM_TOOLS = {"pacman", "expac", "vercmp"}
# Lines that show a command to the user rather than run it.
MESSAGE_RE = re.compile(
    r"""(\becho\b|\bprintf\b|\bprint\s*\(|console\.\w+\s*\(|\bgum\s+(?:style|log|format|confirm)|notify-send|omarchy-notification-send"""
    r"""|\b(?:text|label|title|subtitle|description|hint|tooltip|placeholderText|message|msg|body|summary|detail|details|help"""
    r"""|usage|reason|note|notes|error|warning|status|instructions?|installHint|installCommand|fix|suggestion|advice)\s*[:=]"""
    r"""|\b(?:log|warn|die|fail|info|err|error|msg|say|note|hint|notify|toast|showError|showMessage|setStatus|raise\s+\w+|Exception)\s*\(?\s*f?["'`]"""
    r"""|\b(?:install(?:ed)?\s+(?:it|with|them|via|using|manually|first|by)|e\.g\.|run:|try:|Install:|please|On Arch|from the AUR"""
    r"""|requires?|required|missing|not found|not installed|fehlt|install it|installieren)\b)""", re.I)
USR_RE = re.compile(r"(?<![\w.~$}\)-])(/usr/(?:bin|sbin|share|lib|lib64|libexec|local)(?:/[A-Za-z0-9._+@-]+)*|/bin/[A-Za-z0-9._+-]+|/sbin/[A-Za-z0-9._+-]+)")
NATIVE_FILES = {"CMakeLists.txt": "CMake", "meson.build": "Meson", "Cargo.toml": "Cargo (Rust)",
                "go.mod": "Go module", "build.zig": "Zig", "configure.ac": "autotools", "setup.py": "Python build (setup.py)"}
NATIVE_EXT = {".c": "C", ".cc": "C++", ".cpp": "C++", ".cxx": "C++", ".rs": "Rust", ".go": "Go",
              ".zig": "Zig", ".so": "prebuilt library (.so)"}
NATIVE_BUILD_CMDS = re.compile(r"(?<![\w-])(cargo\s+build|cmake\s|make\s+(-j|install|all)|go\s+build|gcc\s|g\+\+\s|clang\s|c\+\+\s|cc\s+-|meson\s+setup|ninja\s|npm\s+(ci|install)|pnpm\s+install|bun\s+install|pip3?\s+install|pipx\s+install|uv\s+(pip|sync))")

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
    "lua": "lua5_4", "luac": "lua5_4", "ruby": "ruby", "perl": "perl", "php": "php", "deno": "deno", "bun": "bun",
}
# Words that read like commands in shell text but are English; never
# offered as packages from text (nixpkgs has `only`, `the`, …).
STOPWORDS = set("""
a an the only all any some none now then than this that these those it its is are was be been being to of in on
at by for from with without into onto over under up down out off not no yes ok done here there when where what
which who why how also just still even more most less least very too so such same other else each every both
either neither first last next previous new old see use using used run running made get got set show open
close start stop wait try again please note check fix install installed update upgrade remove enable disable
error warning info debug default value values name names file files dir path paths list item items one two three
""".split())
# Language package sets: a word from shell text found only there is prose.
LANG_SETS = re.compile(r"^(haskellPackages|perl\d*Packages|python\d*Packages|nodePackages\w*|rubyPackages\w*|lua\w*Packages"
                       r"|ocamlPackages\w*|php\d*(Packages|Extensions)|emacsPackages|vimPlugins|texlive|rPackages|chickenPackages\w*"
                       r"|idrisPackages|coqPackages\w*|elmPackages|beamPackages|akkuPackages|octavePackages|juliaPackages"
                       r"|agdaPackages|sbclPackages|lispPackages|tree-sitter-grammars|azure-sdk-for-cpp)\.")
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
    "ivpn": "services.ivpn.enable = true",
    "zerotier-cli": "services.zerotierone.enable = true", "zerotier-one": "services.zerotierone.enable = true",
    "kdeconnect-cli": "programs.kdeconnect.enable = true", "kdeconnect-app": "programs.kdeconnect.enable = true",
    "kdeconnect-indicator": "programs.kdeconnect.enable = true", "kdeconnect-settings": "programs.kdeconnect.enable = true",
    "kdeconnectd": "programs.kdeconnect.enable = true", "kdeconnect-sms": "programs.kdeconnect.enable = true",
    "steam": "programs.steam.enable = true",
}
# QML modules the shell lacks, and the Qt package (nixos-unstable's
# kdePackages, the shell's Qt) that has them, for omarchy.qmlModules.
QML_PACKAGES = {
    "QtWebSockets": "qtwebsockets", "QtWebEngine": "qtwebengine", "QtWebView": "qtwebview",
    "QtWebChannel": "qtwebchannel", "QtCharts": "qtcharts", "QtQuick3D": "qtquick3d", "QtLocation": "qtlocation",
    "QtPositioning": "qtpositioning", "QtSensors": "qtsensors", "QtTextToSpeech": "qtspeech", "QtGraphs": "qtgraphs",
    "QtDataVisualization": "qtdatavis3d", "QtVirtualKeyboard": "qtvirtualkeyboard", "Qt.labs.lottieqt": "qtlottie",
    "QtRemoteObjects": "qtremoteobjects", "QtScxml": "qtscxml", "QtSerialPort": "qtserialport",
    "QtNetworkAuth": "qtnetworkauth", "QtBluetooth": "qtconnectivity", "QtNfc": "qtconnectivity",
    "QtMultimedia": "qtmultimedia", "Qt5Compat": "qt5compat", "QtSvg": "qtsvg", "QtQuick.Timeline": "qtquicktimeline",
    "QtQuick3D.Physics": "qtquick3dphysics", "QtPdf": "qtwebengine", "QtQuick.Pdf": "qtwebengine",
    "QtHttpServer": "qthttpserver", "QtGrpc": "qtgrpc", "QtProtobuf": "qtgrpc",
    "QtMqtt": "qtmqtt", "QtStateMachine": "qtscxml",
}
# Folders of developer tooling a plugin's runtime never uses (a build
# file or source there isn't something the plugin needs built).
DEV_DIRS = {"tools", "tool", "experiments", "experiment", "diagnostics", "standalone", "demo", "demos",
            "examples", "example", "bench", "benches", "benchmark", "benchmarks", "dev", "devtools",
            "packaging", "ci", "fixtures", "spec", "specs", "maintainer", "prototype", "prototypes", "e2e"}
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
    return (base.startswith(("tst_", "test_", "test-")) or base.endswith(("_test.py", "_test.sh"))
            or re.search(r"[-_.](test|spec|tests)\.[cm]?[jt]s$", base) is not None)


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
    if path.endswith((".qml", ".js", ".mjs", ".cjs")):
        return "qml"
    if text.startswith("#!"):
        # Another interpreter (ruby, node, perl, …): only its shebang and
        # fixed paths are read.
        return "other"
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
            probe = None
            if bare in ("command", "builtin") and idx + 1 < len(words) and words[idx + 1] in ("-v", "-V"):
                probe = idx + 2
            elif bare in ("which", "hash", "type") and idx + 1 < len(words):
                probe = idx + 1
                while probe < len(words) and words[probe].startswith("-"):
                    probe += 1
            if probe is not None:
                # Every name checked for (`command -v a b`): optional, unless
                # the check stops the script (`command -v x || die …`).
                line_end = text.find("\n", s)
                rest = text[s:len(text) if line_end == -1 else line_end]
                required = re.search(r"\|\|\s*\{?\s*(die|fail|fatal|abort|exit|error|err|return\s+1)\b", rest)
                while probe < len(words) and re.match(r"^[\"']?[A-Za-z_][\w.+-]*[\"']?$", words[probe]):
                    results.append((words[probe].strip("\"'"), s, "run" if required else "probe"))
                    probe += 1
                idx = len(words)
                break
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
        if name == "which" and a1 and not a1.startswith("-"):
            out.append((a1, m.start(), "probe", "array"))
            continue
        if name == "command" and a1 in ("-v", "-V") and a2:
            out.append((a2, m.start(), "probe", "array"))
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


# ------------------------------------------------------------ Arch use
def _blank(m):
    return re.sub(r"[^\n]", " ", m.group(0))


def _hash_comment_col(line):
    """Column where a # comment starts in a shell/Python line, or -1."""
    quote = None
    i = 0
    while i < len(line):
        c = line[i]
        if quote:
            if c == "\\" and quote == '"':
                i += 2
                continue
            if c == quote:
                quote = None
        elif c in "'\"":
            quote = c
        elif c == "#" and (i == 0 or line[i - 1] in " \t;"):
            return i
        i += 1
    return -1


def code_only(text, kind):
    """The text with comments (and Python docstrings, shell here-documents)
    blanked, offsets kept."""
    if kind == "qml":
        text = re.sub(r"/\*.*?\*/", _blank, text, flags=re.S)
        return re.sub(r"(?m)(^|[^:\"'\\])(//.*)$", lambda m: m.group(1) + " " * len(m.group(2)), text)
    if kind == "py":
        text = re.sub(r"(?ms)^(\s*)[rRbBuU]?(\"\"\"|''').*?\2",
                      lambda m: m.group(1) + re.sub(r"[^\n]", " ", m.group(0)[len(m.group(1)):]), text)
    elif kind in ("sh", "other"):
        text = strip_heredocs(text)
    out = []
    for ln in text.split("\n"):
        col = _hash_comment_col(ln) if not ln.startswith("#!") else 0
        out.append(ln if col < 0 else ln[:col] + " " * (len(ln) - col))
    return "\n".join(out)


PROBE_BEFORE = re.compile(r"(command\s+-v|\bwhich|\bhash|\btype\s+-p|shutil\.which\(|\bhave|\bhas_cmd|\bneed_cmd|\brequire\w*|\bcommandExists)\s*\(?\s*[\"']?$")
EXEC_CONTEXT = re.compile(r"(\bcommand\b|\bexec|Process|spawn|startDetached|\brun\w*\s*\(|Popen|check_output|check_call|\bcall\s*\(|system\s*\(|\[\s*[\"']|\bsh\b|\bbash\b|terminal|launch|\bcmd\b|script)", re.I)
PKG_NAME = re.compile(r"^[a-z0-9][a-z0-9@._+-]*$")
LONG_OPS = {"--query": "Q", "--sync": "S", "--remove": "R", "--upgrade": "U", "--database": "D",
            "--files": "F", "--deptest": "T", "--version": "V"}


def arg_tokens(after):
    """A command's arguments as written after it, up to where the command
    (or the sentence showing it) ends."""
    frag = re.split(r"[;|&)`\]\n]|\$\(", after, maxsplit=1)[0]
    # An array (["pacman", "-R", "--", package]): unquoted items are variables.
    array = re.match(r"\s*[\"']\s*,", frag) is not None
    toks, drop, last = [], False, 0
    for m in re.finditer(r"[^\s\"',\[\]]+", frag):
        gap = frag[last:m.start()]
        last = m.end()
        if array and not re.search(r"[\"']\s*$", gap):
            continue
        if toks and (re.search(r"[.:!?·;]", gap) or ("," in gap and not re.search(r"[\"']", gap))
                     or (not array and re.search(r"[\"']\s*[,+)]", gap))):
            break  # prose goes on, or the string holding the command ended
        t = m.group(0)
        if t == "+":
            drop = True
            continue
        if drop or any(ch in t for ch in "${}()<>*"):
            drop = False
            continue
        end = t[-1] in ".:!?"
        t = t.rstrip(".:!?")
        if t:
            toks.append(t)
        if end:
            break
    return toks


def package_args(args):
    """Package names among a package manager's arguments: options skipped,
    prose ends them."""
    names = []
    for a in args:
        if a.startswith("-"):
            continue
        if not PKG_NAME.match(a) or a in STOPWORDS:
            break
        names.append(a)
    return names


def at_command_start(before):
    b = re.sub(r"[\w./-]*/$", "", before.rstrip())
    if re.search(r"\[\s*[\"']$", b):
        return True
    return bool(re.search(r"(^|[;&|({`]|\$\(|\b(?:then|do|else|if|while|until|sudo|doas|pkexec|exec|command|nohup|env|timeout\s+\S+))\s*[\"']?$", b))


def classify_arch(tool, args, start):
    """(form, names): form is "query" (answered by the pacman shim),
    "install" (installs packages: names), "manager" (anything else: updates,
    removal, the sync database), or None (a word, not a call)."""
    opts = [a for a in args if a.startswith("-")]
    if tool in PKG_MANAGERS:
        if not args or not args[0].startswith("-"):
            if tool in ("yay", "paru", "pikaur", "trizen") and start == "bare":
                return "manager", []  # bare yay: a system update
            return None, []
        letters, op = "", None
        for o in opts:
            if o.startswith("--"):
                op = op or LONG_OPS.get(o.split("=")[0])
                letters += {"--upgrades": "u", "--info": "i", "--search": "s", "--refresh": "y",
                            "--sysupgrade": "u", "--file": "p", "--clean": "c"}.get(o.split("=")[0], "")
            else:
                for ch in o[1:]:
                    if ch in "QSRUDFTV" and op is None:
                        op = ch
                    else:
                        letters += ch
        if tool == "aura" and op is None and "A" in letters:
            op = "S"
        names = package_args(args)
        if op in ("Q", "T", "V"):
            if tool != "pacman" or "u" in letters or "p" in letters:
                return "manager", []
            return "query", []
        if op == "S":
            if set(letters) & set("sicglw") or (set(letters) & set("yu") and not names):
                return "manager", []  # the sync database, updates
            return "install", names
        if op == "R" and names:
            return "remove", names  # taking out its own dependencies again
        if op in ("R", "U", "D", "F"):
            return "manager", []
        return None, []
    if not start:
        return None, []
    if tool == "pamac":
        if args and args[0] in ("install", "build"):
            return "install", package_args(args[1:])
        return ("manager", []) if args else (None, [])
    if tool == "expac":
        if any(o in ("-S", "--sync") or (not o.startswith("--") and "S" in o[1:]) for o in opts):
            return "manager", []
        return "query", []
    if tool == "vercmp":
        return "query", []
    if tool == "makepkg":
        return "build", []
    return "manager", []


def arch_uses(text, kind):
    """Package-manager use in a file: what, offset, form, names and whether
    it's only shown to the user (a hint)."""
    code = code_only(text, kind)
    out = []
    for m in ARCH_RE.finditer(code):
        tool = m.group(1)
        ls = code.rfind("\n", 0, m.start()) + 1
        le = code.find("\n", m.end())
        le = len(code) if le == -1 else le
        before, after = code[ls:m.start()], code[m.end():le]
        if after[:1] and after[:1] not in " \t\"'`,])":
            continue  # aura/…, pacman.js, reflector/MS, (pacman|yay): not a command
        if after[:1] == ")" and "(" not in before:
            continue  # a case label: `reflector)`
        if PROBE_BEFORE.search(before):
            continue  # checked for, not run
        start = at_command_start(before)
        if start and kind == "sh" and re.match(r"\s*($|[;&#)])", after) and (not before.strip() or before[-1:] in " \t"):
            start = "bare"
        form, names = classify_arch(tool, arg_tokens(after), start)
        if form is None:
            continue
        hint = bool(MESSAGE_RE.search(before))
        if not hint and kind in ("qml", "py"):
            # A string built over several lines ("text: …" + "  yay -S x").
            hint = bool(MESSAGE_RE.search("\n".join(code[:m.start()].split("\n")[-3:])))
        if not hint and kind in ("qml", "py") and not start:
            # In a JS/Python string: run only where a command is built.
            ctx = "\n".join(code[:le].split("\n")[-4:])
            hint = not EXEC_CONTEXT.search(ctx)
        what = tool if form != "install" else f"{tool} (installs)"
        out.append({"what": what, "offset": m.start(), "form": form, "names": names, "hint": hint})
    for m in ARCH_PATH_RE.finditer(code):
        ls = code.rfind("\n", 0, m.start()) + 1
        hint = bool(MESSAGE_RE.search(code[ls:m.start()]))
        out.append({"what": m.group(0), "offset": m.start(), "form": "manager", "names": [], "hint": hint})
    for m in re.finditer(r"(?<![\w-])omarchy(?:-pkg-(?:aur-)?add|\s+pkg\s+(?:aur\s+)?add)(?![\w-])", code):
        le = code.find("\n", m.end())
        names = package_args(arg_tokens(code[m.end():len(code) if le == -1 else le]))
        if names:
            ls = code.rfind("\n", 0, m.start()) + 1
            out.append({"what": "omarchy-pkg-add", "offset": m.start(), "form": "install", "names": names,
                        "hint": bool(MESSAGE_RE.search(code[ls:m.start()]))})
    return out


# -------------------------------------------------------------- lookups
class Env:
    def __init__(self, available_file=None, assume_envfs=False, assume_usr_share=False, assume_pacman_shim=False):
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
        self.nixattrs = self.read_set("OMARCHY_NIX_ATTRS")
        self.arch_map = {}
        p = os.environ.get("OMARCHY_ARCH_PACKAGES")
        if p and os.path.exists(p):
            try:
                with open(p) as f:
                    self.arch_map = json.load(f).get("map", {})
            except (OSError, ValueError):
                pass
        # pkgs/pacman-shim (omarchy.pacmanShim.enable): pacman's queries,
        # expac -Q and vercmp answered from the NixOS system.
        self.pacman_shim = assume_pacman_shim or self.shim_on_path()

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

    def shim_on_path(self):
        for d in self.path_dirs:
            p = os.path.join(d, "pacman")
            if os.path.exists(p):
                return "omarchy-pacman-shim" in os.path.realpath(p)
        return False

    def has(self, cmd):
        if self.pacman_shim and cmd in SHIM_TOOLS:
            return True
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

    def package_present(self, attr):
        """Whether a package's commands (programs.sqlite) are already there."""
        if self.db is None:
            return False
        try:
            names = [r[0] for r in self.db.execute(
                "select name from Programs where package = ? and system = ?", (attr, SYSTEM))]
        except sqlite3.Error:
            return False
        return any(self.has(n) for n in names)

    def attr_exists(self, attr):
        return self.nixattrs is None or attr in self.nixattrs

    def arch_package(self, name):
        """The nixpkgs attribute for an Arch/AUR package name, or None."""
        m = self.arch_map
        if name in m:
            return m[name]
        if name.startswith(("python-", "python3-")):
            mod = name.split("-", 1)[1]
            for cand in (mod, mod.replace("_", "-"), "python-" + mod):
                if self.pypkgs is None or cand in self.pypkgs:
                    return "python3Packages." + cand
            return None
        q = re.match(r"^qt([56])-(.+)$", name)
        if q:
            attr = ("kdePackages.qt" if q.group(1) == "6" else "libsForQt5.qt") + q.group(2)
            return attr if self.attr_exists(attr) else None
        if name.endswith(("-dkms", "-headers")) or name.startswith("lib32-"):
            return None
        for suffix in ("-bin", "-git", "-appimage", "-nightly"):
            if name.endswith(suffix):
                base = name[:-len(suffix)]
                if base in m:
                    return m[base]
                if self.nixattrs is not None and base in self.nixattrs:
                    return base
                return None
        if self.nixattrs is not None:
            return name if name in self.nixattrs else None
        return name

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
def is_elf(path):
    try:
        with open(path, "rb") as f:
            return f.read(4) == b"\x7fELF"
    except OSError:
        return False


def in_dev_dir(rel):
    parts = rel.split(os.sep)[:-1]
    return any(p.lower() in DEV_DIRS for p in parts)


BUILD_FILES = {"Makefile", "makefile", "GNUmakefile", "CMakeLists.txt", "meson.build", "Cargo.toml", "go.mod",
               "build.zig", "configure", "configure.ac", "build.sh"}
# The build command and the file that has to exist for it to build this plugin.
BUILD_NEEDS = [(r"cargo\s", {"Cargo.toml"}), (r"go\s+build", {"go.mod", ".go"}), (r"cmake\s", {"CMakeLists.txt"}),
               (r"make\s", {"Makefile", "makefile", "GNUmakefile"}), (r"(gcc|g\+\+|clang|c\+\+|cc)\s", {".c", ".cc", ".cpp", ".cxx"}),
               (r"meson\s", {"meson.build"}), (r"ninja\s", {"build.ninja", "meson.build", "CMakeLists.txt"}),
               (r"(npm|pnpm|bun)\s", {"package.json"})]


def product_names(path, text):
    """Names a build file's outputs go by (what a plugin runs)."""
    base = os.path.basename(path)
    names = set()
    if base == "Cargo.toml":
        names |= set(re.findall(r"(?m)^\s*name\s*=\s*\"([^\"]+)\"", text))
    elif base == "go.mod":
        m = re.search(r"(?m)^module\s+(\S+)", text)
        if m:
            names.add(m.group(1).rstrip("/").split("/")[-1])
    elif base == "CMakeLists.txt":
        names |= set(re.findall(r"add_(?:executable|library)\s*\(\s*([\w.-]+)", text))
    elif base == "meson.build":
        names |= set(re.findall(r"(?:executable|shared_library|project)\s*\(\s*'([\w.-]+)'", text))
    elif base in ("Makefile", "makefile", "GNUmakefile"):
        names |= set(re.findall(r"(?m)^(?:TARGET|BIN|PROG|NAME|OUT|BINARY)\s*[:?]?=\s*([\w./-]+)", text))
        names |= {n.split("/")[-1] for n in re.findall(r"\s-o\s+([\w.$()/-]+)", text)}
    else:
        names.add(os.path.splitext(base)[0])
    return {n.split("/")[-1] for n in names if len(n) > 2}


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
    rels = {os.path.relpath(p, root) for p in files}
    exts = {os.path.splitext(p)[1] for p in rels}
    basenames = {os.path.basename(p) for p in rels}

    cmds = {}        # name -> {kind, where}
    fixed = {}       # path -> [where]
    arch = []        # package-manager calls that run (Arch-only)
    arch_queries = []  # pacman queries that run (the shim answers them)
    arch_install = []  # Arch use in install/dev scripts (notes)
    arch_pkgs = []   # packages it installs or tells the user to install
    native_cand = []
    pymods = {}
    qmlmods = {}
    functions = set()   # shell functions defined anywhere in the plugin

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
        if name in functions and how not in ("array", "shebang", "path", "python"):
            return
        e = cmds.setdefault(name, {"kinds": set(), "where": set(), "how": set(), "files": set()})
        e["kinds"].add(kind)
        e["where"].add(where)
        e["how"].add(how)
        e["files"].add(where.split(":")[0])

    # Pass 1: what each file is.
    info = {}
    node_bundled = any(os.path.isdir(os.path.join(root, d, "node_modules")) for d in
                       {os.path.dirname(r) for r in rels} | {""})
    for p in files:
        rel = os.path.relpath(p, root)
        base = os.path.basename(p)
        ext = os.path.splitext(base)[1]
        dev = in_dev_dir(rel)
        if base in NATIVE_FILES and not dev:
            native_cand.append({"what": NATIVE_FILES[base], "file": rel, "path": p, "build": True})
        if ext in NATIVE_EXT and not dev:
            if ext == ".so":
                if is_elf(p):
                    native_cand.append({"what": NATIVE_EXT[ext], "file": rel, "path": p, "prebuilt": True})
            else:
                native_cand.append({"what": NATIVE_EXT[ext] + " source", "file": rel, "path": p, "source": True})
        if base == "qmldir" and not dev:
            if re.search(r"(?m)^\s*plugin\s", read(p) or ""):
                native_cand.append({"what": "C++ QML plugin (qmldir)", "file": rel, "path": p, "qml": True})
        if base == "package.json" and not dev:
            try:
                if json.loads(read(p) or "{}").get("dependencies"):
                    native_cand.append({"what": "Node dependencies (npm install)", "file": rel, "path": p, "npm": True})
            except ValueError:
                pass
        text = read(p)
        if text is None or "\0" in text[:2048]:
            if os.access(p, os.X_OK) and os.path.isfile(p) and ext not in CODE_EXT and not dev and is_elf(p):
                native_cand.append({"what": "prebuilt executable", "file": rel, "path": p, "prebuilt": True})
            continue
        kind = script_kind(p, text)
        if kind is None or is_test_file(p):
            continue
        if kind == "sh":
            functions |= set(re.findall(r"(?m)^\s*(?:function\s+)?([A-Za-z_][\w:-]*)\s*\(\s*\)", text))
            functions |= set(re.findall(r"(?m)^\s*function\s+([A-Za-z_][\w:-]*)", text))
        # The UI (QML, and JS it imports) always loads; scripts count when
        # something that runs names them (dev and install scripts don't).
        ui = kind == "qml" and not text.startswith("#!") and not dev
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
    install_steps = {p for p in pending if not in_dev_dir(info[p]["rel"]) and
                     re.match(r"(install|setup|build|bootstrap|postinstall)", os.path.basename(p), re.I)}

    def arch_where(rel, text, off):
        return f"{rel}:{line_of(text, off)}"

    # Pass 2: what the used files run and need.
    native_cmds = []
    for p, f in info.items():
        rel, text, kind = f["rel"], f["text"], f["kind"]
        in_use = p in used
        install_step = p in install_steps
        if in_use or install_step:
            code = code_only(text, kind if kind != "qml" else "qml")
            for m in NATIVE_BUILD_CMDS.finditer(code):
                ls = code.rfind("\n", 0, m.start()) + 1
                before = code[ls:m.start()]
                if MESSAGE_RE.search(before) or PROBE_BEFORE.search(before):
                    continue
                if kind == "qml" and "command" not in code[max(0, m.start() - 80):m.start()]:
                    continue
                if kind == "py" and not EXEC_CONTEXT.search(code[ls:m.end()]):
                    continue
                cmd = m.group(1).strip()
                needs = next((n for pat, n in BUILD_NEEDS if re.match(pat, cmd + " ")), None)
                if needs and not (needs & basenames or needs & exts):
                    continue  # builds something the plugin doesn't ship (a user's project, a missing tree)
                if needs == {"package.json"} and node_bundled:
                    continue
                native_cmds.append({"what": "builds or installs code: " + cmd, "file": f"{rel}:{line_of(text, m.start())}"})
        for u in arch_uses(text, kind if kind in ("sh", "py", "qml") else "sh"):
            where = arch_where(rel, text, u["offset"])
            for n in u["names"] if u["form"] != "remove" else []:
                arch_pkgs.append({"arch": n, "file": where})
            if u["hint"] or u["form"] in ("install", "remove"):
                continue
            entry = {"what": u["what"], "file": where}
            if u["form"] == "build":
                if in_use or install_step:
                    native_cmds.append({"what": "builds an Arch package (makepkg)", "file": where})
                continue
            if not in_use:
                arch_install.append(entry)
            elif u["form"] == "query":
                arch_queries.append(entry)
            else:
                arch.append(entry)
        if not in_use:
            continue
        if text.startswith("#!"):
            shebang = text.split("\n", 1)[0][2:].strip().split()
            if shebang:
                interp = shebang[0]
                if os.path.basename(interp) == "env":
                    args = [a for a in shebang[1:] if not a.startswith("-") and "=" not in a]
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

    # Native parts count when the plugin uses them: a build file or source
    # whose folder or product the running code (or an install step) names,
    # a prebuilt binary, a compiled QML plugin. Developer tooling, sample
    # sources nothing builds, committed bundles and node_modules don't.
    ref_text = "\n".join(info[p]["text"] for p in used | install_steps)
    build_dirs = {os.path.dirname(r) for r in rels if os.path.basename(r) in BUILD_FILES}

    def referenced(word):
        # As a command or file name (not a folder of a longer path).
        return bool(word) and re.search(r"(?<![\w-])" + re.escape(word) + r"(?![\w/-])", ref_text) is not None

    def referenced_dir(d):
        return bool(d) and re.search(r"(?<![\w-])" + re.escape(d) + r"/", ref_text) is not None

    # Node packages matter only where the plugin runs Node (QML's own
    # JavaScript can't load them).
    node_runs = bool(set(cmds) & {"node", "npm", "npx", "bun", "pnpm", "yarn", "deno", "nodejs"})
    npm_deps = any(c.get("npm") for c in native_cand)
    kept = []
    for n in native_cmds:
        m = re.match(r"builds or installs code: (npm|pnpm|bun)", n["what"])
        if m:
            f, _, ln = n["file"].rpartition(":")
            line = (info.get(os.path.join(root, f)) or {}).get("text", "").split("\n")[int(ln) - 1] if ln.isdigit() else ""
            named = re.search(r"(?:npm|pnpm|bun)\s+(?:ci|install)\s+(?:-\S+\s+)*[@\w]", line)
            if not node_runs or not (npm_deps or named):
                continue
        kept.append(n)
    native_cmds = kept

    def unit_of(rel):
        d = os.path.dirname(rel)
        while True:
            if d in build_dirs:
                return d
            if not d:
                return None
            d = os.path.dirname(d)

    # A helper the running code calls that isn't in the repository: built
    # (or downloaded) at install time.
    helper_missing = []
    for m in re.finditer(r"(?<![\w.~-])(?:\./)?((?:bin|build|target/(?:release|debug)|out|zig-out/bin|native|engine|helpers?|daemon|\.local/bin)/[A-Za-z0-9_+-][\w.+-]*)", ref_text):
        rel = m.group(1)
        pre = ref_text[max(0, m.start() - 30):m.start()]
        if not rel.startswith(".local/") and not re.search(r"\+\s*[\"'`]/$", pre) and \
                re.search(r"(^|[^\w.}$)~-])/((usr|opt|run|nix|etc)/[\w./-]*)?$", pre):
            continue  # an absolute path (/usr/bin/env, /run/current-system/sw/bin/x)
        if rel.startswith(".local/bin/") or not (os.path.exists(os.path.join(root, rel)) or re.search(
                r"\.(sh|py|js|mjs|qml|json|md|png|svg|txt|toml|conf|lua)$", rel)):
            if not rel.startswith(".local/bin/") or not os.path.exists(os.path.join(root, "bin", os.path.basename(rel))):
                helper_missing.append(rel)

    native = list(native_cmds)
    units = {}
    for c in native_cand:
        rel = c["file"]
        if c.get("prebuilt") or c.get("qml"):
            native.append({"what": c["what"], "file": rel})
            continue
        if c.get("npm"):
            d = os.path.dirname(rel)
            full = os.path.join(root, d)
            if os.path.isdir(os.path.join(full, "node_modules")):
                continue  # committed
            if any(os.path.isdir(os.path.join(full, b)) for b in ("dist", "build", "out", "bundle", "vendor", "lib")) or \
                    any(re.search(r"(\.bundle\.|bundle\.|\.min\.)[cm]?js$", os.path.basename(r)) for r in rels
                        if os.path.dirname(r).startswith(d)):
                continue  # a committed bundle the plugin runs
            if not node_runs or (d and not referenced_dir(d)):
                continue
            native.append({"what": c["what"], "file": rel})
            continue
        if os.path.basename(rel) == "setup.py":
            text = read(c["path"]) or ""
            if not (re.search(r"\bsetup\s*\(", text) and re.search(r"setuptools|distutils|skbuild", text)):
                continue  # the plugin's own module named setup.py
        unit = os.path.dirname(rel) if c.get("build") else unit_of(rel)
        if unit is None:
            # Sources no build file covers: sample code or data, unless
            # something compiles them or runs what they'd become.
            if native_cmds or helper_missing:
                native.append({"what": c["what"], "file": rel})
            continue
        units.setdefault(unit, []).append(c)
    for unit, cands in units.items():
        names = {os.path.basename(unit)} if unit else set()
        for r in rels:
            if os.path.dirname(r) == unit and os.path.basename(r) in BUILD_FILES:
                names |= product_names(os.path.join(root, r), read(os.path.join(root, r)) or "")
        names -= {"src", "lib", "app", "main", "build", "core", "common"}
        if native_cmds or helper_missing or any(referenced(n) for n in names) or \
                referenced_dir(unit) or re.search(r"target/(release|debug)|zig-out", ref_text):
            cands.sort(key=lambda c: not c.get("build"))
            native.extend({"what": c["what"], "file": c["file"]} for c in cands)

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
                    # Nor a language's package set (haskellPackages.only).
                    pk = [p for p in pk if p.split(".")[-1] == name and not LANG_SETS.match(p)] \
                        if name not in STOPWORDS else []
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
            top = next((k for k in sorted(QML_PACKAGES, key=len, reverse=True)
                        if mod == k or mod.startswith(k + ".")), None)
            qml_missing.append({"module": mod, "package": QML_PACKAGES.get(top), "where": sorted(where)[:3]})
    qml_modules = sorted({q["package"] for q in qml_missing if q["package"]})

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
    py_attrs = {p["package"] for p in python if p["package"]}
    # Packages it installs (pacman -S, yay -S, omarchy-pkg-add) or tells
    # the user to install, by their nixpkgs names.
    arch_packages = []
    for a in arch_pkgs:
        name = a["arch"]
        if name in local_names or any(x["arch"] == name for x in arch_packages) or \
                name in PKG_MANAGERS or name in SHIM_TOOLS or name.startswith("omarchy") or name in ("npm", "pip"):
            continue  # Arch's own tools, Omarchy itself (the desktop has it)
        attr = env.arch_package(name)
        arch_packages.append({"arch": name, "nixpkgs": attr, "file": a["file"]})
        if not attr or attr.startswith(("kdePackages.qt", "libsForQt5.qt", "qt6.")):
            continue  # nothing in nixpkgs, or a QML module (see qmlMissing)
        if env.has(name) or env.has(attr.split(".")[-1]) or env.package_present(attr):
            continue
        if attr.startswith("python3Packages."):
            py_attrs.add(attr.split(".", 1)[1])
        else:
            need.append(attr)
    py_attrs = sorted(py_attrs)
    options = sorted({c["option"] for c in commands if c["status"] == "service"})
    unknown_py = sorted({p["module"] for p in python if not p["package"]})

    flags = []
    if arch or (arch_queries and not env.pacman_shim):
        flags.append("arch-only")
    if arch_queries:
        flags.append("pacman-queries")
    if native:
        flags.append("native-build")
    if need or py_attrs or options:
        flags.append("needs-packages")
    if any(c["status"] in ("unknown", "not-in-omarchy") and c["kind"] == "run" for c in commands) or unknown_py:
        flags.append("missing-commands")
    if any(not q["package"] for q in qml_missing):
        flags.append("missing-qml")
    elif qml_missing:
        flags.append("needs-qml-modules")
    if any(f["status"] in ("needs-envfs", "needs-link", "envfs-missing") for f in fixed_paths):
        flags.append("fixed-paths")
    if "arch-only" in flags:
        verdict = "arch-only"
    elif "native-build" in flags:
        verdict = "native-build"
    elif "missing-qml" in flags or "missing-commands" in flags:
        verdict = "incomplete"
    elif "needs-packages" in flags or "needs-qml-modules" in flags:
        verdict = "needs-packages"
    else:
        verdict = "ok"

    declared = os.path.islink(os.path.join(PLUGINS_DIR, pid)) and os.path.realpath(
        os.path.join(PLUGINS_DIR, pid)).startswith("/nix/store/")
    return {
        "id": pid, "path": root, "name": manifest.get("name"), "kinds": manifest.get("kinds"),
        "declared": declared, "verdict": verdict, "flags": flags,
        "commands": commands, "fixedPaths": fixed_paths, "archOnly": arch, "archInstall": arch_install,
        "pacmanQueries": arch_queries, "pacmanShim": env.pacman_shim, "archPackages": arch_packages,
        "native": native, "unusedScripts": unused_scripts,
        "python": python, "qmlMissing": qml_missing, "qmlModules": qml_modules,
        "packages": sorted(set(need)), "pythonPackages": py_attrs, "options": options,
        "nixos": nixos_line(pid, sorted(set(need)), py_attrs),
        "qmlLine": ("omarchy.qmlModules = with omarchyUnstable.kdePackages; [ "
                    + " ".join(sorted({"qt5compat", "qtmultimedia"} | set(qml_modules))) + " ];") if qml_modules else None,
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
            pk = f"→ omarchy.qmlModules: kdePackages.{q['package']}" if q["package"] else "(no Qt package known)"
            print(f"    {q['module']:<24} {pk}   {q['where'][0]}")
    bad_paths = [f for f in r["fixedPaths"] if f["status"] not in ("ok", "envfs", "search-dir") or verbose]
    if bad_paths:
        print("  Fixed paths:")
        notes = {"ok": "exists", "envfs": "resolved by envfs from PATH", "search-dir": "a search directory",
                 "envfs-missing": "envfs is on, but the command isn't on PATH",
                 "needs-envfs": "missing (turn on omarchy.envfs.enable)",
                 "needs-link": "missing (turn on omarchy.usrShare.enable)", "missing": "doesn't exist on NixOS"}
        for f in bad_paths:
            print(f"    {f['path']:<40} {notes[f['status']]}   {f['where'][0]}")
    if r["pacmanQueries"]:
        whats = ", ".join(sorted({a["file"] for a in r["pacmanQueries"]})[:3])
        if r["pacmanShim"]:
            print(f"  pacman queries ({whats}): answered from NixOS by the pacman shim")
        else:
            print("  " + color(f"pacman queries ({whats}): turn on omarchy.pacmanShim.enable", "33"))
    if r["archPackages"]:
        print("  Packages it installs or asks for (Arch names):")
        for a in r["archPackages"]:
            nix = a["nixpkgs"] or "no nixpkgs package"
            print(f"    {a['arch']:<24} → {nix}   {a['file']}")
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
    if r["nixos"] or r["options"] or r["qmlLine"]:
        print("  Add to your NixOS configuration (then rebuild):")
        if r["nixos"]:
            print("    " + r["nixos"])
        if r["qmlLine"]:
            print("    " + r["qmlLine"] + "   # Home Manager")
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
    assume_envfs = assume_usr_share = assume_pacman_shim = False
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
        elif a == "--assume-pacman-shim":
            assume_pacman_shim = True
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
    env = Env(available, assume_envfs, assume_usr_share, assume_pacman_shim)
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
