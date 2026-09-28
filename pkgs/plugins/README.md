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
# every entry declared in one home: helpers present, links, shell.json
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
