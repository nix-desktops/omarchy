#!/usr/bin/env python3
"""Survey Omarchy's community shell plugins on NixOS (this flake).

For the plugins in omarchyplugins.com's catalog that `omarchy plugin add`
can install (optionally a slice, a random sample or a list of ids):

  static   shallow clone (cached; nothing from the repo runs on the host),
           upstream's `omarchy-plugin-validate`, and `omarchy plugin doctor`
           against the survey VM's PATH (missing commands → nixpkgs
           packages, Arch-only, native builds);
  runtime  batches of plugins in logged-in Omarchy VMs (vm.nix +
           runtime.py), the doctor's packages installed: each plugin added
           with `omarchy plugin add --enable`, checked (listed, on the bar,
           QML errors in the journal, crash), photographed and removed.

Results go to <state>/results.jsonl, one line per plugin, appended as each
finishes; a rerun skips the plugins already there (--redo to repeat). The
summary (by category) is printed and written to <state>/summary.md.

See README.md next to this script.
"""
import argparse
import base64
import collections
import concurrent.futures as cf
import json
import os
import random
import re
import shutil
import subprocess
import sys
import threading
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
FLAKE = os.path.dirname(os.path.dirname(HERE))
CATALOG_URL = "https://omarchyplugins.com/catalog.json"
CATEGORIES = [
    ("works-as-is", "works as is"),
    ("works-with-packages", "works with packages (the doctor's)"),
    ("arch-only", "Arch-only"),
    ("native-build", "native build"),
    ("fails-to-load", "fails to load"),
    ("crashes-shell", "crashes the shell"),
    ("validation-failed", "validation failed"),
    ("clone-failed", "clone failed"),
    ("harness-error", "harness error"),
]
lock = threading.Lock()


def log(*a):
    with lock:
        print(time.strftime("%H:%M:%S"), *a, flush=True)


def slug_of(repo):
    return re.sub(r"[^A-Za-z0-9._-]+", "__", re.sub(r"^https?://(github\.com/)?", "", repo).rstrip("/").removesuffix(".git"))


def nix_build(args, cwd=None):
    r = subprocess.run(["nix", "build", "--no-link", "--print-out-paths", *args],
                       capture_output=True, text=True, cwd=cwd)
    if r.returncode != 0:
        raise RuntimeError(f"nix build {' '.join(args)} failed:\n{r.stderr[-3000:]}")
    return r.stdout.strip().splitlines()[-1]


# ------------------------------------------------------------------ catalog
def load_catalog(state, source, refresh):
    path = os.path.join(state, "catalog.json")
    if source and os.path.exists(source):
        path = source
    elif refresh or not os.path.exists(path):
        log("fetching", source or CATALOG_URL)
        with urllib.request.urlopen(source or CATALOG_URL, timeout=60) as r:
            data = r.read()
        with open(path, "wb") as f:
            f.write(data)
    with open(path) as f:
        plugins = json.load(f)["plugins"]
    out = []
    for p in plugins:
        if not p.get("installAvailable"):
            continue
        cmd = p.get("installCommand", "").split()
        url = next((w for w in cmd if w.startswith(("https://", "http://", "git@"))), p.get("repo"))
        out.append({"id": p["id"], "name": p.get("name"), "repo": p.get("repo"), "url": url,
                    "kind": p.get("kind"), "category": p.get("category"), "slug": slug_of(p.get("repo") or url)})
    return out


def select(plugins, a):
    if a.ids or a.id:
        wanted = list(a.id or [])
        if a.ids:
            with open(a.ids) as f:
                wanted += [l.strip() for l in f if l.strip() and not l.startswith("#")]
        norm = lambda s: s.rstrip("/").removesuffix(".git").lower()
        by = {}
        for p in plugins:
            by[p["id"].lower()] = p
            by[norm(p["repo"] or "")] = p
        chosen, missing = [], []
        for w in wanted:
            p = by.get(w.lower()) or by.get(norm(w))
            (chosen.append(p) if p else missing.append(w))
        if missing:
            log(f"{len(missing)} not in the catalog (or not installable): {', '.join(missing[:10])}")
        plugins = chosen
    if a.random:
        plugins = random.Random(a.seed).sample(plugins, min(a.random, len(plugins)))
    plugins = plugins[a.start:]
    if a.count is not None:
        plugins = plugins[:a.count]
    return plugins


# ------------------------------------------------------------------- static
class Tools:
    def __init__(self, flake):
        log("building the doctor, the survey VM's command list and upstream's validator")
        self.doctor = nix_build([f"{flake}#plugin-doctor"]) + "/bin/omarchy-plugin-doctor"
        self.jq = nix_build(["--inputs-from", flake, "nixpkgs#jq"]) + "/bin"
        omarchy = subprocess.run(
            ["nix", "eval", "--raw", "--impure", "--expr", f'(builtins.getFlake "{flake}").inputs.omarchy.outPath'],
            capture_output=True, text=True, check=True).stdout.strip()
        self.validate = os.path.join(omarchy, "bin/omarchy-plugin-validate")
        self.available = nix_build(["--impure", "-f", os.path.join(HERE, "vm.nix"), "available",
                                    "--argstr", "flake", flake])


def clone(p, repos):
    d = os.path.join(repos, p["slug"])
    if os.path.isdir(os.path.join(d, ".git")):
        return d, None
    url = p["url"]
    # As omarchy-git-url-check allows, and only over the network.
    if not re.match(r"^https://[A-Za-z0-9.-]+/", url):
        return None, f"not an https URL: {url}"
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0", GIT_LFS_SKIP_SMUDGE="1", GIT_CONFIG_NOSYSTEM="1",
               GIT_CONFIG_GLOBAL="/dev/null", GIT_ASKPASS="true")
    # GitHub throttles anonymous clones by answering "Repository not
    # found", so a GitHub token (GH_TOKEN or GITHUB_TOKEN, as `gh` and
    # Actions provide) goes along as a header, through the environment so
    # it never shows on a command line, and throttled clones are retried.
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if token and url.startswith("https://github.com/"):
        auth = base64.b64encode(f"x-access-token:{token}".encode()).decode()
        env.update(GIT_CONFIG_COUNT="1", GIT_CONFIG_KEY_0="http.https://github.com/.extraheader",
                   GIT_CONFIG_VALUE_0=f"AUTHORIZATION: basic {auth}")
    tmp = d + ".tmp"
    for attempt in range(5):
        shutil.rmtree(tmp, ignore_errors=True)
        # Nothing from the repository runs: no hooks, no submodules, no LFS
        # filters, no checkout-time helpers.
        r = subprocess.run(["git", "-c", "core.hooksPath=/dev/null", "-c", "protocol.allow=never",
                            "-c", "protocol.https.allow=always", "-c", "core.symlinks=true",
                            "clone", "--quiet", "--depth", "1", "--no-tags", "--single-branch",
                            "--no-recurse-submodules", "--", url, tmp],
                           env=env, capture_output=True, text=True, timeout=180)
        if r.returncode == 0:
            break
        # With a token, "not found" means gone or private; 401 and 403 are
        # GitHub throttling a burst of clones.
        throttled = re.search(r"rate limit|429|HTTP 40[13]" if token else r"not found|rate limit|429|Authentication failed",
                              r.stderr, re.I)
        if not throttled or attempt == 4:
            shutil.rmtree(tmp, ignore_errors=True)
            return None, (r.stderr.strip() or "git clone failed")[-500:]
        time.sleep(15 * 2 ** attempt)
    os.rename(tmp, d)
    return d, None


def static_one(p, tools, state):
    path = os.path.join(state, "static", p["slug"] + ".json")
    if os.path.exists(path):
        with open(path) as f:
            s = json.load(f)
        # Reused while the clone is there and the doctor is the same build.
        if os.path.isdir(s.get("path") or "") and s.get("doctorBuild") in (None, tools.doctor) \
                and (s.get("doctorBuild") or s["static"] in ("clone-failed", "validation-failed")):
            return s
    s = {"id": p["id"], "slug": p["slug"], "repo": p["repo"], "url": p["url"]}
    try:
        d, err = clone(p, os.path.join(state, "repos"))
    except subprocess.TimeoutExpired:
        d, err = None, "git clone timed out"
    if d is None:
        s.update(static="clone-failed", error=err)
    else:
        s["path"] = d
        s["commit"] = subprocess.run(["git", "-C", d, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
        env = dict(os.environ, PATH=tools.jq + ":" + os.environ.get("PATH", ""))
        v = subprocess.run(["bash", tools.validate, d], capture_output=True, text=True, env=env, timeout=60)
        if v.returncode != 0:
            s.update(static="validation-failed", error=(v.stderr or v.stdout).strip()[-500:])
        else:
            try:
                with open(os.path.join(d, "manifest.json")) as f:
                    m = json.load(f)
                s["manifestId"] = m.get("id")
                s["kinds"] = m.get("kinds") or []
            except (OSError, ValueError):
                s["kinds"] = []
            r = subprocess.run([tools.doctor, "--json", "--available", tools.available,
                                "--assume-envfs", "--assume-usr-share", d],
                               capture_output=True, text=True, timeout=300)
            try:
                doc = json.loads(r.stdout)
            except ValueError:
                doc = {"verdict": "doctor-failed", "error": r.stderr[-500:]}
            s["doctorBuild"] = tools.doctor
            s["doctor"] = {k: doc.get(k) for k in ("verdict", "flags", "packages", "pythonPackages", "options", "nixos",
                                                   "archOnly", "archInstall", "native", "qmlMissing")}
            s["doctor"]["missing"] = [c["name"] for c in doc.get("commands", [])
                                      if c.get("status") in ("missing", "unknown", "not-in-omarchy", "arch-only")]
            s["static"] = doc.get("verdict", "doctor-failed")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(s, f, indent=1)
    return s


# ------------------------------------------------------------------ runtime
def category(s, rt):
    if s.get("static") == "clone-failed":
        return "clone-failed"
    if s.get("static") == "validation-failed":
        return "validation-failed"
    if rt is None:
        return None
    if rt.get("crashed") or rt.get("vmDied"):
        return "crashes-shell"
    if rt.get("harnessError") and not rt.get("listed"):
        return "harness-error"
    if s.get("static") == "arch-only":
        return "arch-only"
    if s.get("static") == "native-build":
        return "native-build"
    kinds = s.get("kinds") or []
    loaded = rt.get("listed") and rt.get("enabled") is not False and not rt.get("errors")
    if "bar-widget" in kinds and "bar" not in kinds and not (rt.get("bar") or {}).get("itemWidth"):
        # A widget that isn't drawn: loaded if nothing failed and it chose
        # to hide (itemVisible false), else not.
        if rt.get("bar") is None and rt.get("barQuery") == "failed" and loaded:
            # The shell never answered: that says nothing about the plugin.
            return "harness-error"
        loaded = loaded and rt.get("bar") is not None
    if not loaded:
        return "fails-to-load"
    d = s.get("doctor") or {}
    if d.get("packages") or d.get("pythonPackages") or d.get("options"):
        return "works-with-packages"
    return "works-as-is"


def record(s, rt, cat):
    d = s.get("doctor") or {}
    return {
        "id": s["id"], "repo": s.get("repo"), "commit": s.get("commit"), "category": cat,
        "static": s.get("static"), "staticError": s.get("error"),
        "runtime": None if rt is None else (
            "crash" if rt.get("crashed") or rt.get("vmDied") else
            "not-added" if (rt.get("add") or {}).get("status") not in (0, None) else
            "errors" if rt.get("errors") else
            "loaded" if rt.get("listed") else "not-listed"),
        "errors": (rt or {}).get("errors", []), "packages": d.get("packages") or [],
        "pythonPackages": d.get("pythonPackages") or [], "options": d.get("options") or [],
        "missing": d.get("missing") or [],
        "nixos": d.get("nixos"), "archOnly": sorted({a["what"] for a in d.get("archOnly") or []}),
        "native": sorted({n["what"] for n in d.get("native") or []})[:5],
        "screenshot": (rt or {}).get("screenshotPath"), "bar": (rt or {}).get("bar"), "barQuery": (rt or {}).get("barQuery"),
        "kinds": s.get("kinds"), "addOutput": ((rt or {}).get("add") or {}).get("output", "")[-600:],
        "crashLog": (rt or {}).get("crashLog"), "harnessError": (rt or {}).get("harnessError"),
        "seconds": (rt or {}).get("seconds"),
    }


def append_result(state, rec):
    with lock:
        with open(os.path.join(state, "results.jsonl"), "a") as f:
            f.write(json.dumps(rec) + "\n")


def run_batch(n, items, a, state):
    bdir = os.path.join(state, "batches", f"{time.strftime('%Y%m%d-%H%M%S')}-{n:04d}")
    out = os.path.join(bdir, "out")
    os.makedirs(out, exist_ok=True)
    pkgs = sorted({p for s in items for p in (s.get("doctor") or {}).get("packages") or []})
    py = sorted({p for s in items for p in (s.get("doctor") or {}).get("pythonPackages") or []})
    batch = {"plugins": [{"id": s["id"], "slug": s["slug"], "path": s["path"], "kinds": s.get("kinds")} for s in items],
             "timeout": a.plugin_timeout, "settle": a.settle}
    with open(os.path.join(bdir, "batch.json"), "w") as f:
        json.dump(batch, f, indent=1)
    t0 = time.time()
    log(f"batch {n}: {len(items)} plugins, {len(pkgs)} packages, {len(py)} python modules; building the VM")
    try:
        driver = nix_build(["--impure", "-f", os.path.join(HERE, "vm.nix"), "driver",
                            "--argstr", "flake", a.flake, "--argstr", "packages", json.dumps(pkgs),
                            "--argstr", "python", json.dumps(py)])
    except RuntimeError as e:
        log(f"batch {n}: VM build failed; retrying without the extra packages")
        with open(os.path.join(bdir, "build-error.log"), "w") as f:
            f.write(str(e))
        driver = nix_build(["--impure", "-f", os.path.join(HERE, "vm.nix"), "driver", "--argstr", "flake", a.flake])
        pkgs, py = [], []
    built = time.time()
    vmtmp = os.path.join(bdir, "vm")
    os.makedirs(vmtmp, exist_ok=True)
    env = dict(os.environ, TMPDIR=vmtmp, SURVEY_BATCH=os.path.join(bdir, "batch.json"), SURVEY_OUT=out)
    limit = 600 + len(items) * (a.plugin_timeout * 3 + a.settle + 30)
    rc = None
    for attempt in range(2):
        with open(os.path.join(bdir, "driver.log"), "a") as logf:
            proc = subprocess.Popen([os.path.join(driver, "bin/nixos-test-driver"), "-o", out],
                                    env=env, stdout=logf, stderr=subprocess.STDOUT)
            started = time.time()
            while proc.poll() is None:
                time.sleep(5)
                booted = os.path.exists(os.path.join(out, "batch.jsonl"))
                # A VM that isn't logged in within 10 minutes won't be.
                if (not booted and time.time() - started > 600) or time.time() - started > limit:
                    proc.kill()
                    proc.wait()
                    rc = "timeout" if booted else "boot-timeout"
                    break
            else:
                rc = proc.returncode
        if rc != "boot-timeout":
            break
        log(f"batch {n}: the VM didn't come up; trying once more")
    done = time.time()
    shutil.rmtree(vmtmp, ignore_errors=True)
    results = {}
    try:
        with open(os.path.join(out, "runtime.jsonl")) as f:
            for line in f:
                r = json.loads(line)
                results[r["id"]] = r
    except OSError:
        pass
    started = []
    try:
        with open(os.path.join(out, "progress.jsonl")) as f:
            started = [json.loads(l)["id"] for l in f]
    except OSError:
        pass
    finished = 0
    for s in items:
        rt = results.get(s["id"])
        if rt is None and started and started[-1] == s["id"]:
            # Started, never finished: it took the VM (or the driver) down.
            rt = {"vmDied": True, "harnessError": f"driver exit {rc}"}
        if rt is None:
            continue  # never reached; a rerun retries it
        if rt.get("screenshot"):
            rt["screenshotPath"] = os.path.join(out, rt["screenshot"])
        append_result(state, record(s, rt, category(s, rt)))
        finished += 1
    with lock:
        with open(os.path.join(state, "timings.jsonl"), "a") as f:
            f.write(json.dumps({"batch": bdir, "plugins": len(items), "finished": finished, "exit": rc,
                                "build": round(built - t0, 1), "run": round(done - built, 1),
                                "packages": len(pkgs), "python": len(py)}) + "\n")
    log(f"batch {n}: {finished}/{len(items)} done in {done - t0:.0f}s (build {built - t0:.0f}s), driver exit {rc}")


# ------------------------------------------------------------------ summary
def summarize(state, ids=None):
    latest = {}
    try:
        with open(os.path.join(state, "results.jsonl")) as f:
            for line in f:
                r = json.loads(line)
                latest[r["id"]] = r
    except OSError:
        pass
    rows = [r for i, r in latest.items() if ids is None or i in ids]
    counts = collections.Counter(r["category"] for r in rows)
    lines = [f"# Omarchy plugin survey on NixOS", "", f"{len(rows)} plugins, {time.strftime('%Y-%m-%d')}", "",
             "| Category | Plugins | Share |", "| --- | ---: | ---: |"]
    for key, label in CATEGORIES:
        if counts.get(key):
            lines.append(f"| {label} | {counts[key]} | {100 * counts[key] / max(1, len(rows)):.0f}% |")
    lines += ["", "| Plugin | Category | Runtime | Packages | Notes |", "| --- | --- | --- | --- | --- |"]
    for r in sorted(rows, key=lambda r: ([k for k, _ in CATEGORIES].index(r["category"]) if r["category"] in dict(CATEGORIES) else 99, r["id"])):
        notes = []
        if r.get("archOnly"):
            notes.append("uses " + ", ".join(r["archOnly"]))
        if r.get("native"):
            notes.append("; ".join(r["native"][:2]))
        if r.get("errors"):
            notes.append(r["errors"][0][:140].replace("|", "\\|"))
        if r.get("staticError"):
            notes.append(r["staticError"][:140].replace("|", "\\|").replace("\n", " "))
        if r.get("missing") and not r.get("packages"):
            notes.append("missing: " + ", ".join(r["missing"][:5]))
        pk = ", ".join((r.get("packages") or []) + [f"python3Packages.{p}" for p in r.get("pythonPackages") or []]
                       + (r.get("options") or []))
        lines.append(f"| {r['id']} | {r['category']} | {r.get('runtime') or ''} | {pk} | {'; '.join(notes)} |")
    text = "\n".join(lines) + "\n"
    with open(os.path.join(state, "summary.md"), "w") as f:
        f.write(text)
    return text, counts


def estimate(state):
    try:
        with open(os.path.join(state, "timings.jsonl")) as f:
            t = [json.loads(l) for l in f]
    except OSError:
        return None
    t = [x for x in t if x["finished"]]
    if not t:
        return None
    per = sum(x["run"] for x in t) / sum(x["finished"] for x in t)
    build = sum(x["build"] for x in t) / len(t)
    return per, build


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--catalog", help=f"catalog.json path or URL (default: {CATALOG_URL}, cached in the state dir)")
    ap.add_argument("--refresh-catalog", action="store_true")
    ap.add_argument("--state", default="/tmp/claude-1000/plugin-survey", help="clones, results, screenshots")
    ap.add_argument("--flake", default=FLAKE, help="this flake (default: the checkout the script is in)")
    ap.add_argument("--from", dest="start", type=int, default=0, help="skip the first N selected plugins")
    ap.add_argument("--count", type=int, help="take N plugins")
    ap.add_argument("--random", type=int, help="a random sample of N")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--ids", help="file of plugin ids or repo URLs, one per line")
    ap.add_argument("--id", action="append", help="a plugin id or repo URL (repeatable)")
    ap.add_argument("-j", "--jobs", type=int, default=4, help="VMs at once (default 4)")
    ap.add_argument("--clone-jobs", type=int, default=8)
    ap.add_argument("--batch", type=int, default=50, help="plugins per VM boot (default 50)")
    ap.add_argument("--plugin-timeout", type=int, default=60)
    ap.add_argument("--settle", type=int, default=5, help="seconds to wait after enabling")
    ap.add_argument("--static-only", action="store_true")
    ap.add_argument("--redo", action="store_true", help="repeat plugins already in results.jsonl")
    ap.add_argument("--summary", action="store_true", help="only print the summary of results.jsonl")
    a = ap.parse_args()
    a.flake = os.path.abspath(a.flake)
    state = os.path.abspath(a.state)
    for d in ("repos", "static", "batches"):
        os.makedirs(os.path.join(state, d), exist_ok=True)

    if a.summary:
        print(summarize(state)[0])
        return 0

    plugins = select(load_catalog(state, a.catalog, a.refresh_catalog), a)
    ids = {p["id"] for p in plugins}
    done = set()
    if not a.redo and os.path.exists(os.path.join(state, "results.jsonl")):
        with open(os.path.join(state, "results.jsonl")) as f:
            latest = {r["id"]: r for r in map(json.loads, f)}
        # A clone that failed is tried again (it may have been throttled).
        done = {i for i, r in latest.items() if r["category"] != "clone-failed"}
    todo = [p for p in plugins if p["id"] not in done]
    log(f"{len(plugins)} selected, {len(plugins) - len(todo)} already done, {len(todo)} to go")

    tools = Tools(a.flake)
    t0 = time.time()
    with cf.ThreadPoolExecutor(a.clone_jobs) as ex:
        statics = list(ex.map(lambda p: static_one(p, tools, state), todo))
    log(f"static pass: {time.time() - t0:.0f}s")
    runnable = []
    for s in statics:
        if s["static"] in ("clone-failed", "validation-failed"):
            append_result(state, record(s, None, category(s, None)))
        elif a.static_only:
            continue
        else:
            runnable.append(s)
    if a.static_only:
        c = collections.Counter(s["static"] for s in statics)
        print(json.dumps(c, indent=1))
        return 0

    batches = [runnable[i:i + a.batch] for i in range(0, len(runnable), a.batch)]
    with cf.ThreadPoolExecutor(max(1, a.jobs)) as ex:
        futures = [ex.submit(run_batch, n, b, a, state) for n, b in enumerate(batches)]
        for f in cf.as_completed(futures):
            try:
                f.result()
            except Exception as e:  # noqa: BLE001
                log("batch failed:", e)

    text, counts = summarize(state, ids)
    print(text)
    est = estimate(state)
    if est:
        per, build = est
        log(f"about {per:.1f}s per plugin in a VM (plus {build:.0f}s to build a batch's VM); "
            f"all 3668 at -j{a.jobs}: ~{3668 * per / max(1, a.jobs) / 3600:.1f} h")
    return 0


if __name__ == "__main__":
    sys.exit(main())
