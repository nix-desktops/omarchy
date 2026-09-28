# Plugin survey

Tests Omarchy's community shell plugins ([omarchyplugins.com](https://omarchyplugins.com/catalog.json))
on this flake's NixOS desktop, as a pass/fail tally per plugin.

```sh
# 20 at random, 10 per VM boot, 2 VMs at a time
scripts/plugin-survey/survey.py --random 20 --batch 10 -j 2
# a slice of the catalog, or given plugins (ids or repo URLs)
scripts/plugin-survey/survey.py --from 200 --count 100
scripts/plugin-survey/survey.py --ids ids.txt
scripts/plugin-survey/survey.py --id https://github.com/rookepoole/omarchy-moon-arc
# the whole directory (3,668 installable plugins)
scripts/plugin-survey/survey.py -j 4
# only clone, validate and run the doctor
scripts/plugin-survey/survey.py --static-only
# the table of what's done so far
scripts/plugin-survey/survey.py --summary
```

It needs Nix (flakes), git, Python 3, KVM, and the network. State lives in
`--state` (default `/tmp/claude-1000/plugin-survey`): the catalog, the
clones, per-plugin static results, one directory per batch (the VM's log,
screenshots), `results.jsonl`, `timings.jsonl` and `summary.md`.

## What it does

1. **Static, on the host, for every plugin.** A shallow clone of the repo
   the catalog's `installCommand` names (https only; no hooks, submodules,
   LFS or other helpers: nothing from the repository runs on the host),
   upstream's `omarchy-plugin-validate`, and `omarchy plugin doctor --json`
   against the VM's shell PATH (`vm.nix`'s `available`: the commands the
   desktop has without extra packages) with envfs and /usr/share/omarchy
   assumed on, as the NixOS module sets them. Cached in `static/`.
2. **Runtime, in logged-in Omarchy VMs, in batches** (`--batch`, 50 by
   default; `-j` VMs at once, 4 by default). Each batch's VM (`vm.nix`) has
   the packages the doctor named for its plugins (one environment above
   the desktop's, so a `python3.withPackages` wins); its test driver runs
   outside the Nix sandbox, so the VM has the network. `runtime.py`, for
   each plugin in turn: copies the clone in, `omarchy plugin add <repo>
   --yes --enable` as the user, waits `--settle` seconds, then records
   whether it's listed and enabled, its slot on the bar (size), errors and
   warnings in the shell's journal that name it, whether the shell died,
   and a screenshot (the widget cut out of the bar, or the panel/overlay
   summoned, or the screen for a replacement bar); then `omarchy plugin
   remove`, and deletes its copies (`/tmp/survey/<slug>`, the plugin
   directory, remove's backups). The plugin is looked up by its manifest id
   (what `plugin add` installs it as; 7 catalog entries have another id),
   and both ids are recorded.
   - **The shell restarts** after a plugin that crashed it, after a
     replacement bar (`bar` kind: upstream's shell.qml leaves `shell.bar`
     null once one is removed, see HANDOFF.md, so every later widget got no
     slot), and after a session-changing plugin (a lock screen,
     `WlSessionLock`, anything on the background/bottom layer, or a clone
     of `omarchy.lock`/`omarchy.background`). Both kinds run last in their
     batch (`--keep-order` keeps the given order, to test the harness).
   - **No idle:** the VM's user has Omarchy's stay-awake state
     (`xdg.stateFile."omarchy/indicators/stay-awake"`, what `omarchy toggle
     idle stay-awake` writes), so the screensaver (150 s) and the lock
     (300 s) never start mid-batch; `lockedBefore` records the lock state
     before each plugin anyway. The VM has an 8 GB disk (sparse).
   - **Errors vs warnings:** only journal lines that aren't DEBUG, with the
     plugin's ids, slug and file URLs taken out, are matched for error
     words (an id like `mirror-x` contains "rror"). First-run noise goes to
     `warnings`, not `errors`: Quickshell's FileView "Read of … failed: File
     does not exist" for a file under the home, /tmp or /run/user (state and
     cache files a plugin writes later), and "Cannot open: <image>" when the
     image exists by the time the journal is read. Warnings don't make a
     plugin fail.
3. **Results.** `results.jsonl` gets one line per plugin as its batch
   finishes: `id`, `repo`, `commit`, `category`, `static` (the doctor's
   verdict), `manifestId`, `runtime` (`loaded` / `errors` / `not-listed` / `not-added` /
   `crash`), `errors`, `warnings`, `batch`, `restarted`, `packages` and `pythonPackages` (the doctor's),
   `missing`, `archOnly`, `native`, `screenshot`, `bar`, … A rerun skips
   plugins already there (`--redo` to repeat); a plugin whose batch never
   reached it is retried, and one that took the VM down is recorded as a
   crash. `summary.md` groups them:

| Category | Meaning |
| --- | --- |
| works as is | loads without errors, and the doctor found nothing missing |
| works with packages | loads without errors with the packages the doctor named |
| Arch-only | uses pacman/yay/paru/… at runtime (it may load, but that part can't work) |
| native build | needs something built (C++/Rust/Go, a compiled QML plugin, `npm install`, a prebuilt binary) |
| fails to load | not listed or not enabled after `add`, QML errors naming it, or a bar widget that never gets a slot |
| crashes the shell | the shell's process died or restarted (or the VM went down) |
| validation failed | upstream's validator refused it (what `omarchy plugin add` would do) |
| clone failed | the repository is gone, private or unreachable |

"Loads without errors" is what can be checked unattended: a widget that
draws itself and logs no errors. Whether its data is right (a weather
API, a device that isn't in a VM) isn't judged; the screenshots are there
for that.

## Timing and running it in CI

Measured on a 32-core machine (2026-09-27): building a batch's VM takes
20-50 s (the desktop comes from the store; only the extra packages change),
booting to a logged-in shell ~35 s, and each plugin ~9-11 s (settle 5 s).
A 50-plugin batch is ~10 minutes, so the 3,668 installable plugins take
about 74 batches: ~12 h on one VM, ~3 h with `-j 4` (each VM: 4 GB RAM,
2 cores).

GitHub Actions' Linux runners have KVM (enable it with the usual udev rule
for /dev/kvm), 4 cores and 16 GB, and a 6-hour job limit. A scheduled
workflow can run the survey as a matrix of slices (`--from N --count 250`,
~15 jobs of ~1 h each at `-j 2`), upload each slice's `results.jsonl` and
screenshots as artifacts, and a final job can merge them and publish
`summary.md` (e.g. to the Pages site). The binary cache (nix-desktops
cachix) keeps VM builds to downloads.
