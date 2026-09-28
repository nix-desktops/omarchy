# checks.plugin-doctor: the doctor's verdicts on tests/plugin-doctor's fixtures.
import json, subprocess, sys

doctor, fixtures, available = sys.argv[1:4]


def report(name, *flags):
    out = subprocess.run([doctor, "--json", "--available", available, "--assume-envfs", *flags,
                          f"{fixtures}/{name}"], capture_output=True, text=True, check=True).stdout
    return json.loads(out)


def cmd(r, name):
    return next((c for c in r["commands"] if c["name"] == name), None)


r = report("hints")
assert r["verdict"] == "needs-packages", r
assert not r["archOnly"] and r["packages"] == ["solaar"], r
assert cmd(r, "aura") is None, r["commands"]

r = report("queries")
assert r["verdict"] == "arch-only" and r["pacmanQueries"], r
r = report("queries", "--assume-pacman-shim")
assert r["verdict"] == "ok", r

r = report("installs", "--assume-pacman-shim")
assert r["verdict"] == "needs-packages", r
assert "github-cli" in r["packages"] or "gh" in r["packages"], r
assert r["pythonPackages"] == ["pygobject3"], r
assert not any(p.startswith("kdePackages") for p in r["packages"]), r

r = report("updates", "--assume-pacman-shim")
assert r["verdict"] == "arch-only" and r["archOnly"][0]["what"] == "checkupdates", r

r = report("commands")
assert cmd(r, "ruby")["status"] == "missing" and cmd(r, "ruby")["packages"][0] == "ruby", r["commands"]
assert "lua5_4" in r["packages"], r["packages"]
assert cmd(r, "snapshot") is None and cmd(r, "only") is None, r["commands"]
assert cmd(r, "jq")["kind"] == "run", cmd(r, "jq")
assert "programs.kdeconnect.enable = true" in r["options"], r["options"]
assert r["qmlModules"] == ["qtwebsockets"] and "qtwebsockets" in r["qmlLine"], r

r = report("nativefp")
assert r["verdict"] in ("ok", "needs-packages") and not r["native"], r["native"]

r = report("native")
assert r["verdict"] == "native-build", r
print("plugin-doctor fixtures: ok")
