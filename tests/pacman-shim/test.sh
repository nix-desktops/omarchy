# checks.pacman-shim: the pacman shim (pkgs/pacman-shim) against the query
# forms community shell plugins and upstream's menu run, each quoted from
# the plugin that runs it (the plugin survey's review of its Arch-only
# plugins). Runs in the build sandbox over a stand-in system: $SYSTEM_ENV
# (hello, jq, ripgrep, python3 with requests, qtbase) and $USER_ENV
# (cowsay), their closure from closureInfo; $GUARD is upstream's
# MenuModel.js guardHelpers() output (35 menu forks carry the same bash).
set -uo pipefail
fail=0
pass=0
ok() { # ok <description> <command...>: the command succeeds
  local d=$1
  shift
  if "$@" >/dev/null 2>&1; then pass=$((pass + 1)); else echo "FAIL: $d"; fail=1; fi
}
no() { # no <description> <command...>: the command fails
  local d=$1
  shift
  if "$@" >/dev/null 2>&1; then echo "FAIL (succeeded): $d"; fail=1; else pass=$((pass + 1)); fi
}
eq() { # eq <description> <expected> <actual>
  if [[ $2 == "$3" ]]; then pass=$((pass + 1)); else
    echo "FAIL: $1"
    echo "  expected: $2"
    echo "  actual:   $3"
    fail=1
  fi
}
has_line() { grep -qx -- "$1"; }

jq_ver=$(pacman -Q jq | awk '{print $2}')

# ---- pacman -Q[q] <pkg>…: exit status per package (79 plugins)
# bitshaker.ring-cameras scripts/setup-native.sh:96, cavacuz.tablet install.sh:69
ok "-Q installed" pacman -Q jq
package=jq; ok 'pacman -Q "$package" >/dev/null 2>&1' bash -c 'pacman -Q "$0" >/dev/null 2>&1' "$package"
no "-Q missing" pacman -Q no-such-package
# io.github.avillagran.omarchy-control-panel Panel.qml:842
eq "-Qq missing (echo yes/no)" no "$(pacman -Qq linux-apfs-rw-dkms >/dev/null 2>&1 && echo yes || echo no)"
# io.github.dominicboettger.prompter Model.js:320
no "-Q several, one missing" sh -c "pacman -Q evdi-dkms displaylink linux-headers >/dev/null 2>&1 || pacman -Q evdi displaylink >/dev/null 2>&1"
# io.github.mirzap.hyprknit omarchy/hyprknit-plugin:76: prints the found, fails for the rest
out=$(pacman -Q jq hello no-such 2>/dev/null)
rc=$?
eq "-Q several: found lines" "jq $jq_ver"$'\n'"hello $(pacman -Q hello | cut -d' ' -f2)" "$out"
eq "-Q several: status" 1 "$rc"
eq "-Q missing: pacman's error" "error: package 'no-such' was not found" "$(pacman -Q no-such 2>&1)"
# Arch names of installed packages
ok "python-requests (python3.x-requests)" pacman -Q python-requests
ok "qt6-base (qtbase 6)" pacman -Qq qt6-base
ok "ripgrep's command as a name" pacman -Q rg
ok "-bin suffix" pacman -Q jq-bin
# io.github.ctl0v0.outfit scripts/outfit.py:6676
eq "-Q omarchy qt6-base" "omarchy $OMARCHY_VERSION-1" "$(pacman -Q omarchy qt6-base | head -1)"
# fans.omarchy.feedback lib/capture.sh:30
eq "omarchy's version" "$OMARCHY_VERSION-1" "$(pacman -Q omarchy 2>/dev/null | awk '{print $2}')"
# io.github.jcarcinogen.gaming-console system/install.sh:99
ok "try-omarchy-runtime || omarchy" sh -c 'pacman -Q try-omarchy-runtime 2>/dev/null || pacman -Q omarchy 2>/dev/null'

# ---- pacman -Qq: every installed name (45 plugins)
# costafot.clippy scripts/clippy-ai:196
n=$(pacman -Qq 2>/dev/null | wc -l)
ok "-Qq lists the closure ($n)" test "$n" -gt 20
ok "-Qq has jq" has_line jq < <(pacman -Qq)
ok "-Qq has the Arch name python-requests" has_line python-requests < <(pacman -Qq)
ok "-Qq has the Arch name qt6-base" has_line qt6-base < <(pacman -Qq)
# icons Panel.qml:412 (a prefix grep over the list)
eq "-Qq | grep ^prefix" "ripgrep" "$(pacman -Qq 2>/dev/null | grep '^ripgre')"
ok "-Q (all) is name version" has_line "jq $jq_ver" < <(pacman -Q)

# ---- the menu's guards: upstream MenuModel.js guardHelpers() (and 35 forks)
guard() { bash -c "source $GUARD; $1"; }
ok "guard: jq present" guard 'omarchy-pkg-present jq'
ok "guard: Arch names present" guard 'omarchy-pkg-present python-requests qt6-base omarchy'
ok "guard: a provided command (rg)" guard 'omarchy-pkg-present rg'
no "guard: missing" guard 'omarchy-pkg-present visual-studio-code-bin'
ok "guard: missing (pkg-missing)" guard 'omarchy-pkg-missing jq no-such'
ok "guard: versioned, satisfied" guard 'omarchy-pkg-present "jq>=1.5"'
no "guard: versioned, not satisfied" guard 'omarchy-pkg-present "jq>=99"'
# Provides lines as the guard's awk reads them, with COLUMNS set
eq "-Qi Provides feed the guard" 1 "$(COLUMNS=40 LC_ALL=C pacman -Qi | awk '/^[A-Za-z]/ { provides = ($0 ~ /^Provides/); sub(/^[^:]*: /, "") } provides && $0 != "None" { n = split($0, p, " "); for (i = 1; i <= n; i++) { sub(/[<>=].*/, "", p[i]); print p[i] } }' | grep -cx python-requests)"

# ---- LC_ALL=C pacman -Qi: pacman's exact format (39 plugins)
info=$(LC_ALL=C pacman -Qi jq)
eq "-Qi Name line" "Name            : jq" "$(head -1 <<<"$info")"
eq "-Qi Version" "$jq_ver" "$(awk -F': +' '/^Version/ {print $2}' <<<"$info")"
eq "-Qi field order" "Name Version Description Architecture URL Licenses Groups Provides Depends On Optional Deps Required By Optional For Conflicts With Replaces Installed Size Packager Build Date Install Date Install Reason Install Script Validated By" \
  "$(sed -n 's/^\([A-Za-z][A-Za-z ]*[A-Za-z]\) *: .*/\1/p' <<<"$info" | paste -sd' ')"
eq "-Qi ends with a blank line" "" "$(tail -c1 <<<"$info" | tr -d '\n')"
eq "-Qi URL from the declared meta" "$JQ_URL" "$(awk -F': +' '/^URL/ {print $2}' <<<"$info")"
eq "-Qi Description from the meta" "$JQ_DESC" "$(awk -F': +' '/^Description/ {print $2}' <<<"$info")"
eq "-Qi Install Reason" "Explicitly installed" "$(awk -F': +' '/^Install Reason/ {print $2}' <<<"$info")"
# rfaile313.menu-search scripts/sync-upstream.sh:27
eq "-Qi omarchy Version" "$OMARCHY_VERSION-1" "$(pacman -Qi omarchy 2>/dev/null | awk -F': +' '/^Version/ {print $2}')"
# io.github.lajosdeme.protonvpn-wireguard install.sh:71
no '-Qi "$pkg" &>/dev/null (missing)' bash -c 'pacman -Qi wireguard-tools &>/dev/null'
eq "-Qi all: a block per package" "$(( $(pacman -Qqe | wc -l) + $(pacman -Qqd | wc -l) ))" "$(LC_ALL=C pacman -Qi | grep -c '^Name ')"
eq "-Qi python-requests Provides" "python-requests" "$(LC_ALL=C pacman -Qi python-requests | awk -F': +' '/^Provides/ {print $2}' | tr -s ' ' '\n' | grep -x python-requests)"

# ---- versioned pacman -Q "<pkg><op><ver>" (16 plugins)
ok 'versioned >=' pacman -Q "jq>=1.0"
ok 'versioned >' pacman -Q "jq>1.0"
no 'versioned <' pacman -Q "jq<1.0"
ok 'versioned = without pkgrel' pacman -Q "jq=${jq_ver%-*}"
no 'versioned = other' pacman -Q "jq=0.1"
ok 'versioned omarchy >= 3' pacman -Q "omarchy>=3.0"

# ---- pacman -Qe/-Qm/-Qn/-Qd/-Qt[q] (13 plugins)
# io.github.thebenwalther.omalab bin/omalab:101, luneth90.omamigrate lib/export.sh:49
explicit=$(pacman -Qqe 2>/dev/null | LC_ALL=C sort -u)
ok "-Qqe has hello" has_line hello <<<"$explicit"
ok "-Qqe has cowsay (user profile)" has_line cowsay <<<"$explicit"
no "-Qqe hasn't a dependency (oniguruma)" has_line oniguruma <<<"$explicit"
ok "-Qqd has the dependency" has_line oniguruma < <(pacman -Qqd)
# io.github.lukebest.omarsync lib/packages.sh:8-9
ok "-Qqen lists" test -n "$(pacman -Qqen)"
eq "-Qqem (foreign) is empty" "" "$(pacman -Qqem)"
no "-Qm fails: nothing foreign" pacman -Qm
# io.github.seangsr.omarchy-cleaner scripts/scan.sh:24 (orphans)
eq "-Qtdq count" 0 "$(pacman -Qtdq 2>/dev/null | awk 'NF { count++ } END { print count+0 }')"
# io.github.jexmarc.tabarchy bin/tabarchy-pkg-search:97
eq "-Qmq" "" "$(pacman -Qmq 2>/dev/null)"

# ---- pacman -Qo[q] <path>: the owner of a file (11 plugins)
jq_bin=$(command -v jq)
# davedes.omcontrol backend/process-info.sh:17
eq "-Qo | awk \$5 \$6" "jq $jq_ver" "$(pacman -Qo "$jq_bin" 2>/dev/null | awk '{print $5, $6}')"
eq "-Qo sentence" "$jq_bin is owned by jq $jq_ver" "$(pacman -Qo "$jq_bin")"
# woodenplastic.workspace-icons scripts/resolve-icons:26
eq "-Qqo -- path" jq "$(pacman -Qqo -- "$jq_bin" 2>/dev/null)"
# fans.omarchy.feedback lib/of_subject.py:148 (a bare name is looked up on PATH)
eq "-Qoq name" jq "$(pacman -Qoq jq)"
no "-Qo a path outside the store" pacman -Qo /etc/hostname-no-such
eq "-Qo missing file" "error: failed to read file '/no/such': No such file or directory" "$(pacman -Qo /no/such 2>&1)"

# ---- pacman -Ql[q] <pkg> (3 plugins)
# woodenplastic.workspace-icons scripts/resolve-icons:28
ok "-Qlq lists the binary" grep -q '/bin/jq$' < <(pacman -Qlq -- jq 2>/dev/null)
# yoyo.system-tidy scripts/backend.sh:18
ok "-Ql | awk \$2 | grep /bin/" grep -q '/bin/rg$' < <(pacman -Ql ripgrep 2>/dev/null | awk '{print $2}' | grep -E '/s?bin/')

# ---- expac -Q <fmt> (4 plugins)
# yoyo.system-tidy scripts/backend.sh:31
ok "expac -H M '%m'" grep -qE '^[0-9]+\.[0-9]{2} MiB$' < <(expac -H M '%m' jq 2>/dev/null)
# io.github.antoniowav.appsweep Panel.qml:64
eq "pacman -Qqe | xargs expac" "hello"$'\t'"$(pacman -Q hello | cut -d' ' -f2)" "$(pacman -Qqe | xargs -r expac -Q '%n\t%v' | grep '^hello')"
eq "expac %n %v" "jq $jq_ver" "$(expac '%n %v' jq)"

# ---- -Qs and -T
ok "-Qs finds by description" grep -q '^local/jq ' < <(pacman -Qs --color=never -- 'JSON processor')
ok "-T satisfied" pacman -T jq "jq>=1"
eq "-T prints the missing" "no-such" "$(pacman -T jq no-such)"

# ---- vercmp (pacman's vercmptest.sh cases, and vercmp(8)'s ordering
# 1.0a < 1.0b < 1.0beta < 1.0p < 1.0pre < 1.0rc < 1.0 < 1.0.a < 1.0.1)
while read -r a b want; do
  eq "vercmp $a $b" "$want" "$(vercmp "$a" "$b")"
done <<'EOF'
1.5.0 1.5.0 0
1.5.1 1.5.0 1
1.5.1 1.5 1
1.5.0-1 1.5.0-2 -1
1.5.0-1 1.5.1-1 -1
1.5-2 1.5.1-1 -1
1.5 1.5-1 0
1.1-1 1.0 1
1.5b-1 1.5-1 -1
1.5b 1.5.1 -1
1:1.0 2.0 1
1.0a 1.0b -1
1.0b 1.0beta -1
1.0beta 1.0p -1
1.0p 1.0pre -1
1.0pre 1.0rc -1
1.0rc 1.0 -1
1.0 1.0.a -1
1.0.a 1.0.1 -1
EOF

# ---- refusals: pacman's error status and what to do instead
err=$(pacman -S --needed --noconfirm python-pillow 2>&1)
rc=$?
eq "-S status" 1 "$rc"
ok "-S message" grep -q "pacman on NixOS only answers queries; add python3Packages.pillow to your configuration (omarchy.plugins.<id>.packages or environment.systemPackages)" <<<"$err"
no "-Syu" pacman -Syu --noconfirm
no "-Rns" pacman -Rns foo
no "-U" pacman -U ./foo-1.0-1-x86_64.pkg.tar.zst
no "-Si" pacman -Si jq
no "-Ss" pacman -Ss jq
no "-Qu" pacman -Qu
no "expac -S" expac -S '%n' jq
ok "-Ss says to search nixpkgs" grep -q "nix search nixpkgs jq" < <(pacman -Ss jq 2>&1)
eq "-S prints nothing on stdout" "" "$(pacman -S foo 2>/dev/null)"
# the plugin's id, from where it runs
mkdir -p "$TMPDIR/home/.config/omarchy/plugins/acme.demo"
ok "-S names the plugin" grep -q "omarchy.plugins.acme.demo.packages" < <(cd "$TMPDIR/home/.config/omarchy/plugins/acme.demo" && pacman -S foo 2>&1)

# ---- the flake's omarchy-pkg-present (apps.json, the shim, commands)
mkdir -p "$TMPDIR/state"
echo '{"packages":["brave"]}' >"$TMPDIR/state/apps.json"
present() { OMARCHY_STATE=$TMPDIR/state bash "$PKG_PRESENT" "$@"; }
ok "pkg-present: installed (shim)" present jq python-requests
ok "pkg-present: in apps.json by Arch name" present brave-bin
no "pkg-present: missing" present visual-studio-code-bin

# ---- the index is cached, and rebuilt when a profile changes
ok "cache written" test -n "$(ls "$OMARCHY_PACMAN_CACHE"/index-*.json)"

echo "pacman shim: $pass passed"
exit $fail
