# Packaged community plugins (the registry)

Community shell plugins that need something built or placed for them on
NixOS: a helper compiled from their own source (Rust, C, Go, …), a Python
env where they expect a venv, a patched path, a Hyprland compositor
plugin. One directory per plugin, named by its **manifest id**:

```
pkgs/plugins/
  default.nix                     the registry (finds the directories; don't edit to add one)
  io.github.bitshiftxr.atrium/    Rust helper inside the plugin's tree (bin/atriumd)
  io.github.lolu13.onote/         Rust helper linked at ~/.local/bin/onote-helper
  seigliva.ha-watch/              a Python env where the plugin expects its venv
  <id>/default.nix                yours
```

Adding a directory is all it takes: nothing shared to edit. The flake
exposes the registry as

- `omarchy.plugins."<id>".enable = true;` (NixOS or Home Manager, no `src`):
  installs the plugin from its entry, with helpers, links and packages;
- `legacyPackages.<system>.plugins."<id>"`: the plugin as the shell loads it
  (its files plus helpers), `.home` the home links as a tree, `.entry` the
  entry;
- `lib.plugins`: the registry as data for the Configurator (url, rev, hash,
  description, helper paths, home paths, package names).

`omarchy plugin add` of a plugin in the registry still works, but says to
declare it instead (it can't get Nix-built helpers).

## An entry

`<id>/default.nix` is a function called like a package
(`lib.callPackageWith`: ask for what you need by name) returning an
attribute set. Only `src` is required.

```nix
# One line on what the plugin is and which pattern it uses.
{ lib, fetchFromGitHub, rustPlatform }:
let
  src = fetchFromGitHub {
    owner = "acme";
    repo = "omarchy-weather";
    rev = "<final.json's commit>";       # the commit the survey tested
    hash = "sha256-…";
  };
  weatherd = rustPlatform.buildRustPackage {
    pname = "weatherd";
    version = "0.1.0-unstable-<short rev>";
    inherit src;
    sourceRoot = "${src.name}/daemon";   # where Cargo.lock is
    cargoHash = "sha256-…";
    meta.mainProgram = "weatherd";
  };
in
{
  inherit src;
  helpers."bin/weatherd" = lib.getExe weatherd;
  packages = [ ];                        # on the shell's PATH
  meta.description = "Weather panel (weatherd built from daemon/)";
}
```

| Attribute | What it does |
| --- | --- |
| `src` | the plugin's files, pinned (`fetchFromGitHub` with `rev` + `hash`) |
| `helpers` | `{ "<path in the plugin>" = <file or dir>; }`: copied into the plugin's tree (the validator refuses symlinks) |
| `home` | `{ "<path under $HOME>" = <file or dir>; }`: Home Manager links (`home.file`) |
| `packages` | installed for the user: on the shell's PATH (and envfs' `/usr/bin`) |
| `patches`, `postPatch` | applied to the plugin's own files before it's validated |
| `hyprlandPlugins` | compositor plugins loaded by the generated hyprland.lua |
| `hyprlandConfig` | Hyprland Lua for it, after the plugins load |
| `qmlModules` | QML modules added to the shell's import path (Quickshell's Qt) |
| `userServices` | `{ "<unit>" = <file or text or { source/text; wantedBy; }>; }`: systemd user units (services, sockets, timers, `<unit>.d/x.conf` drop-ins), installed in ~/.config/systemd/user and enabled per their `[Install]` |
| `extraGroups` | groups the user must be in (`[ "input" ]` for /dev/input); the NixOS module adds them |
| `services` | NixOS options the plugin needs on (`[ "hardware.bluetooth.enable" ]`): a hint, the NixOS module warns when one is off |
| `section` | bar section when it's first switched on (else the manifest's) |
| `meta.description` | one line, for `lib.plugins` |

Arguments besides Nixpkgs 26.05 (`pkgs`):

| Argument | |
| --- | --- |
| `omarchyUnstable` | nixos-unstable's Nixpkgs. **Anything Qt** (a C++ QML plugin, a Qt app the plugin embeds) builds against `omarchyUnstable.kdePackages` / `omarchyUnstable.qt6`: Quickshell's Qt. Qt from 26.05 won't load into the shell. |
| `hyprland` | the Hyprland the desktop runs (`programs.hyprland.package`, nixos-unstable's by default) |
| `mkHyprlandPlugin` | nixpkgs' `hyprlandPlugins.mkHyprlandPlugin` against that `hyprland` |
| `mkPlugin` | `lib.mkPlugin` (the registry calls it for you) |

Everything else (Rust, Go, Python, C toolchains, libraries) comes from
26.05, the system's own Nixpkgs.

## Where the plugin looks, and how to say it

Read the QML (and the scripts it runs) to see where the helper is
expected; `review/native-build.jsonl` in the survey state has the path for
each plugin.

| The plugin runs | Entry |
| --- | --- |
| `<plugin dir>/bin/x`, `Qt.resolvedUrl("bin/x")` | `helpers."bin/x" = lib.getExe x;` |
| `<plugin>/engine/target/release/x` | `helpers."engine/target/release/x" = lib.getExe x;` |
| `~/.local/bin/x` | `home.".local/bin/x" = lib.getExe x;` |
| a venv, `~/.local/share/<name>/venv/bin/python` | `home.".local/share/<name>/venv" = python3.withPackages (ps: [ … ]);` (has bin/python and bin/python3) |
| `x` on PATH | `packages = [ x ];` |
| an env var naming the binary (`FOO_BIN`) with a fallback download | `postPatch` setting the default to the store path |
| a download step, `pip install`, `cargo build` at first run | `postPatch` (`substituteInPlace … --replace-fail`) pointing it at the store path, plus the helper |
| `/usr/bin/foo` inside the helper's own source | the helper's `postPatch` with `${foo}/bin/foo` (atrium's secret-tool) |
| a Hyprland plugin (`hyprctl plugin load`, hyprpm) | `hyprlandPlugins = [ (mkHyprlandPlugin { … }) ];` and patch out its own build/load step |
| a systemd user unit its setup writes and enables | `userServices."x.service" = <the unit, ExecStart pointed at the store>;` |
| a daemon reading /dev/input (evdev) | `extraGroups = [ "input" ];` |
| a system service or driver (bluetoothd, fprintd) | `services = [ "hardware.bluetooth.enable" ];` (the host turns it on) |

Prefer `helpers` or `home` (the plugin's files unchanged) over patches;
patch when the path isn't fixed (a download, a venv the plugin creates, a
build step) or a check would refuse the Nix-built binary (a provenance
stamp, a checksum). `--replace-fail` so an update that moves the text
fails the build instead of silently doing nothing.

A Hyprland compositor plugin:

```nix
{ lib, fetchFromGitHub, mkHyprlandPlugin }:
let
  src = fetchFromGitHub { … };
  frames = mkHyprlandPlugin {
    pluginName = "omaframes";            # installs lib/libomaframes.so
    version = "0-unstable-<short rev>";
    inherit src;
    sourceRoot = "${src.name}/hyprland-plugin";
    # A Makefile / CMake / meson build; install the .so as
    # $out/lib/lib${pluginName}.so (what hl.plugin.load is given).
    installPhase = "install -Dm755 omaframes.so $out/lib/libomaframes.so";
    meta.description = "…";
  };
in
{
  inherit src;
  hyprlandPlugins = [ frames ];
  # e.g. the plugin's setup script that compiled and hyprctl-loaded it:
  postPatch = "substituteInPlace setup.sh --replace-fail 'hyprctl plugin load' 'true #'";
}
```

It's built against the desktop's own Hyprland and loaded by
`hl.plugin.load` in the generated `~/.config/hypr/hyprland.lua`, so a
Hyprland update rebuilds it (a plugin only loads into the Hyprland it was
compiled against). It takes effect at the next login (or `hyprctl reload`).

## User units

`userServices` takes the unit as upstream ships it (`"${src}/systemd/x.service"`),
a `runCommand`/`substitute` of it with `ExecStart=` pointed at the store,
or its text. Home Manager links it into `~/.config/systemd/user` (so a
switch starts, restarts or stops it) and it's enabled the way `systemctl
--user enable` would: links in `<target>.wants/` for its `[Install]`
WantedBy=/RequiredBy=, Alias= links, a template's DefaultInstance. A unit
without `[Install]` is installed, not enabled (the panel starts it).
`{ source = …; wantedBy = [ ]; }` overrides that: a socket-activated
service whose socket is the one enabled (Bose 700).

A service with `ReadWritePaths=` fails with 226/NAMESPACE while one of
those directories is missing (upstream's install script makes them), so
the unit gets `ExecStartPre=-+mkdir -p -m 0700 <paths>` added: "+" runs it
outside the unit's sandbox. Don't add your own.

Don't link units with `home.".config/systemd/user/…"`: that skips the
enabling, the mkdir, and Home Manager's start/stop on switch.

## Patterns and pitfalls (from packaging the first 126)

- **`fetchFromGitHub` drops `export-ignore` paths.** It fetches GitHub's
  tarball, which leaves out whatever the repo's `.gitattributes` marks
  `export-ignore` (a `core/` source dir, tests). If a path the build needs
  is missing from `src` but in the repo, fetch with `fetchgit` (a real
  checkout) instead (io.github.ilyazar.syncthing).
- **Shipped binaries.** A committed static (musl, static-pie, Go) binary
  runs as is: no entry needed. A glibc one runs through nix-ld
  (`omarchy.nixLd`); rebuild it from the repo's source when the source is
  there (the survey commit's), so it isn't a blob. A binary checked by a
  checksum or a signature the plugin verifies: leave it, a Nix build would
  fail the check.
- **Provenance gates and stamps.** Plugins that build on first run often
  keep a stamp (source hash, `cc --version`, a build attestation) and
  rebuild when it doesn't match. Write the stamp the gate expects (hashing
  the same files the same way, by relative path) or patch the gate out.
- **Which Qt.** Anything loaded into the shell (a compiled QML module, a
  QtWebEngine view) must be Quickshell's Qt: `omarchyUnstable.kdePackages`.
  A helper that is its own process (a Qt app, a daemon) uses 26.05's `qt6`.
- **"quickshell" by name.** Nixpkgs' Quickshell runs as
  `.quickshell-wrapped`: shims or launchers that match the process name
  `quickshell` need both (ttt.olook's argc shim).
- **Venvs.** A plugin that runs `~/.local/share/<name>/venv/bin/python`
  gets a `python3.withPackages` linked there (`home`). One that creates the
  venv or pip-installs at first run: patch that step to the store path.
  Checks that the venv is the user's own (`-O`) or pins exact versions
  need patching or `pythonRelaxDeps`.
- **Fixed paths in helpers.** `/usr/bin/kill`, `/usr/bin/pactl`, … in a
  helper's source or its tests: `substituteInPlace` to the store, and skip
  the tests that exec them (`checkFlags = [ "--skip=…" ]`).
- **Hyprland plugins** are built against the desktop's Hyprland
  (`mkHyprlandPlugin`); patch out the plugin's own `hyprpm`/`hyprctl
  plugin load`/header checks, or point its header check at
  `${hyprland.dev}/include`.
- **Not an entry:** root daemons and system services (eBPF, uinput, polkit
  helpers, `/etc/systemd/system` units), kernel modules (DKMS), udev
  rules, Fcitx5 addons and input methods: those belong in the host's NixOS
  configuration (`services` names what to turn on). Python or npm packages
  nixpkgs lacks can be built in the entry when they're small and pure
  (gkeepapi); a whole SDK (depthai, livekit) isn't worth it.

## Pinning

- `rev`: the commit the survey tested: `final.json`'s `commit` for the
  plugin in the survey state (`/tmp/claude-1000/plugin-survey`). Don't
  follow a branch.
- `hash`: `nix flake prefetch --json github:<owner>/<repo>/<rev>` prints it
  (`.hash`), or write `lib.fakeHash`, build, and take the `got:` hash.
- `cargoHash` / `vendorHash` / `npmDepsHash`: `lib.fakeHash`, build, take
  the `got:` hash. `vendorHash = null` for a Go module without
  dependencies. Don't use `cargoLock.lockFile = "${src}/…"`: that reads a
  fetched file at evaluation time (import from derivation).
- `version`: `<upstream version>-unstable-<short rev>` (or the tag).

## Testing

```sh
# the plugin with its helpers (the tree the shell loads)
nix build '.#plugins."<id>"' && ls result/bin
# its home links
nix build '.#plugins."<id>".home' && ls -la result/.local/bin
# every entry declared in one home: helpers present, links, user units,
# packages/compositor plugins/QML modules built, shell.json, groups
nix build .#checks.x86_64-linux.plugin-registry
# in a logged-in VM, declared (the survey declares registry plugins itself)
scripts/plugin-survey/survey.py --state /tmp/claude-1000/my-survey \
  --catalog /tmp/claude-1000/plugin-survey/catalog.json --id <id>
```

A helper's own test suite may run programs by fixed paths the sandbox
doesn't have (`/usr/bin/cat`): skip those tests (`checkFlags = [
"--skip=…" ]`), don't disable the whole suite. A helper that needs the
network or hardware at test time: `doCheck = false` with a comment.

The survey puts a registry plugin in a batch of its own whose VM declares
it (`omarchy.plugins.<id>.enable = true`), without the doctor's packages
(the entry must bring what it needs), and records it as "works packaged"
when it loads without errors. Screenshots and errors are in the state
dir's `results.jsonl`. "Loads" is what the survey can see: check the
screenshot shows data where the helper provides it.
