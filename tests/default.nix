# Flake checks (`nix flake check`, run by CI on every PR and push):
#
#   package   the Omarchy package, shebangs patched, patches applied
#   home      an example Home Manager config with the desktop enabled: the
#             NixOS commands (shellchecked by writeShellApplication), the
#             menu layer (which fails on entries without icons) and the
#             shell service
#   themes    every built-in theme through Omarchy's own renderer
#   tools     every package of Omarchy's own tools (pkgs/tools)
#   catalog   lib/catalog.nix matches upstream: every app and web-app bind
#             upstream defines belongs to an entry, and every entry's bind
#             exists upstream
#   ecosystem-home  the example home with the whole ecosystem and some
#             agents and tools on
#   host      the host template (examples/host) evaluates and its system
#             builds, with a stand-in hardware config
#   plugin-doctor  `omarchy plugin doctor` builds (its command database) and
#             gets tests/plugin-doctor's small plugins right
#   pacman-shim  the pacman shim answers the query forms plugins and
#             upstream's menu guards run (tests/pacman-shim/test.sh)
#   catalog-plugins  lib.catalog's shell plugins fetch and validate
#   plugins-shell-json  declared plugins switched on/off in shell.json
#   plugin-registry  every packaged plugin (pkgs/plugins) declared by id in
#             one home: helpers in their trees, home links, user units (and
#             their wants links), packages, compositor plugins and QML
#             modules built, the hyprland.lua loading compositor plugins;
#             the NixOS module adding a plugin's extraGroups
#   plugins   a NixOS VM with shell plugins: `omarchy plugin add` of local
#             git repos (python3 via envfs), a declared plugin, the doctor,
#             /usr/share/omarchy, removal
#   vm        a NixOS VM set up like the host template (the NixOS module
#             wiring the desktop for its user): login screen, PAM services,
#             the shell's unit and the commands in place for the user;
#             screenshots saved (menu command, PRINT, `save`), the recorder
#             found and stopped, the sleep lock and crash watch running
{ inputs, pkgs, self }:
let
  inherit (pkgs.stdenv.hostPlatform) system;

  # Upstream's screenshot command hands off to omasnap on its development
  # branch; the v4.0 releases (the stable channel) run a grim script.
  omasnapScreenshots = pkgs.lib.hasInfix "omasnap" (
    builtins.readFile "${inputs.omarchy}/bin/omarchy-capture-screenshot"
  );

  exampleHome = {
    home.username = "omarchy";
    home.homeDirectory = "/home/omarchy";
    home.stateVersion = "26.05";
    omarchy = {
      enable = true;
      stateDir = ./state;
      stateDirPath = "/home/omarchy/nixos/omarchy";
      configDir = "/home/omarchy/nixos";
    };
  };

  home = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [ self.homeManagerModules.default exampleHome ];
  };

  ecosystemHome = inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = import inputs.nixpkgs { inherit system; config.allowUnfree = true; };
    modules = [
      self.homeManagerModules.default
      exampleHome
      {
        omarchy.ecosystem.enable = true;
        # A few of each (from nixpkgs and nixos-unstable): the wiring, not
        # every upstream package, is what's under test.
        omarchy.agents = [ "claude" "codex" "agy" ];
        omarchy.tools = [ "gh" "hunk" ];
      }
    ];
  };

  # Every plugin of the registry declared by id, and a compositor plugin.
  registryHome = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [
      self.homeManagerModules.default
      exampleHome
      {
        omarchy.plugins = pkgs.lib.genAttrs (builtins.attrNames self.lib.plugins) (_: { enable = true; });
        omarchy.hyprland.plugins = [ "/run/test/libexample.so" ];
      }
    ];
  };

  # The NixOS side of declared registry plugins: the groups they need
  # (extraGroups) added to the user.
  registryUserGroups = (inputs.nixpkgs.lib.nixosSystem {
    modules = [
      inputs.home-manager.nixosModules.home-manager
      self.nixosModules.default
      {
        nixpkgs.hostPlatform = system;
        fileSystems."/" = { device = "/dev/disk/by-label/nixos"; fsType = "ext4"; };
        boot.loader.grub.device = "nodev";
        system.stateVersion = "26.05";
        omarchy = { enable = true; stateDir = ./state; users = [ "omarchy" ]; };
        users.users.omarchy.isNormalUser = true;
        home-manager.users.omarchy.home.stateVersion = "26.05";
        omarchy.plugins."mrai.keyguide".enable = true;
      }
    ];
  }).config.users.users.omarchy.extraGroups;

  # Run a command the way the shell's menu runs an action: in the
  # omarchy-shell service's cgroup, as the user, with the shell's
  # environment, through `bash -lc` (Quickshell's execDetached).
  menuAction = pkgs.writeShellScript "menu-action" ''
    pid=$(systemctl --user -M omarchy@ show -p MainPID --value omarchy-shell.service)
    cg=$(systemctl --user -M omarchy@ show -p ControlGroup --value omarchy-shell.service)
    echo $$ >"/sys/fs/cgroup$cg/cgroup.procs"
    mapfile -d "" envs <"/proc/$pid/environ"
    cd /home/omarchy
    exec setpriv --reuid=1000 --regid=100 --init-groups env -i "''${envs[@]}" bash -lc "$1"
  '';

  # Community plugins from omarchyplugins.com, pinned, for the plugins test:
  # lib.catalog's (fetched as omarchy.plugins fetches a url) and two more.
  fromCatalog = id: pkgs.fetchgit { inherit (self.lib.catalog.plugins.${id}) url rev hash; };
  plugin = owner: repo: rev: hash: pkgs.fetchFromGitHub { inherit owner repo rev hash; };
  fixtures = {
    # A bar widget whose helper runs as /usr/bin/python3 with PATH=/usr/bin
    # and a cleared environment.
    myjournal = fromCatalog "io.github.mohuddle.myjournal";
    # A plain bar widget (moon phase).
    moon-arc = fromCatalog "io.github.rookepoole.moon-arc";
    # A bar widget running a `#!/usr/bin/python3` script: declared.
    logi-battery = fromCatalog "io.github.proxy1967.logi-battery";
    # For the doctor: a command nixpkgs has (setxkbmap) missing, and one
    # that tells you to `yay -S` its missing command.
    typist = plugin "sanjuanjor" "typist" "2d2e0e3d8f46c7aef304c47cffcaf7ef4a5a0d3a"
      "sha256-O06R/X4AH1R0ObZFiQkvJXOIdYuJ3BTqffYjR/nfQ0k=";
    kefctl = plugin "douglas" "omarchy-kefctl" "d7bea30ee9aa7327828936ac4324318994c685c8"
      "sha256-kccZ00Jdmt/HlROHc4dlVFvZX9ouTWU7l0YkS6ub1z0=";
  };

  catalog = self.lib.catalog;
  catalogBinds = pkgs.writeText "catalog-binds.json" (builtins.toJSON
    (pkgs.lib.concatMap (e: e.binds)
      (pkgs.lib.concatMap builtins.attrValues [ catalog.tuis catalog.apps catalog.webapps ])));
in
{
  package = self.packages.${system}.omarchy;

  home = home.activationPackage;

  themes = home.config.omarchy.themes;

  # The doctor builds (its command database) and judges small plugins
  # right (tests/plugin-doctor: hints vs calls, pacman queries, Arch names,
  # commands, native-build false positives).
  plugin-doctor = pkgs.runCommand "omarchy-plugin-doctor-check" {
    nativeBuildInputs = [ pkgs.python3 ];
  } ''
    bash ${./plugin-doctor/fixtures.sh} fixtures
    printf '%s\n' python3 bash sh cp dirname >available
    python3 ${./plugin-doctor/check.py} ${self.packages.${system}.plugin-doctor}/bin/omarchy-plugin-doctor \
      fixtures available
    touch $out
  '';

  # The pacman shim against the query forms plugins run (tests/pacman-shim).
  pacman-shim = let
    inherit (pkgs) lib;
    shim = self.packages.${system}.pacman-shim;
    systemEnv = pkgs.buildEnv {
      name = "system-path";
      paths = with pkgs; [ hello jq ripgrep (python3.withPackages (ps: [ ps.requests ])) kdePackages.qtbase ];
    };
    userEnv = pkgs.buildEnv { name = "user-environment"; paths = [ pkgs.cowsay ]; };
    closure = pkgs.closureInfo { rootPaths = [ systemEnv userEnv ]; };
    meta = pkgs.writeText "declared.json" (builtins.toJSON [{
      name = builtins.unsafeDiscardStringContext pkgs.jq.name;
      pname = "jq";
      inherit (pkgs.jq.meta) description homepage;
      license = [ "MIT" ];
    }]);
    # Upstream's guard prelude (MenuModel.js guardHelpers()), as the menu
    # and its forks run it.
    guard = pkgs.runCommand "guard-helpers.sh" { nativeBuildInputs = [ pkgs.nodejs ]; } ''
      node -e '
        const src = require("fs").readFileSync(process.argv[1], "utf8");
        const m = src.match(/function guardHelpers\(\) \{[\s\S]*?\n\}/);
        if (!m) process.exit(1);
        eval(m[0]);
        process.stdout.write(guardHelpers());
      ' ${inputs.omarchy}/shell/plugins/menu/MenuModel.js >$out
      grep -q "pacman -Qq" $out
    '';
  in pkgs.runCommand "omarchy-pacman-shim-check" {
    nativeBuildInputs = [ shim systemEnv userEnv ] ++ (with pkgs; [ bash coreutils gawk gnugrep gnused findutils jq ]);
    OMARCHY_PACMAN_PROFILES = "${systemEnv}:${userEnv}";
    OMARCHY_PACMAN_SYSTEM = systemEnv;
    OMARCHY_PACMAN_CLOSURE = "${closure}/store-paths";
    OMARCHY_PACMAN_META = meta;
    OMARCHY_ARCH_PACKAGES = ../data/arch-packages.json;
    OMARCHY_VERSION = lib.removeSuffix "\n" (builtins.readFile (inputs.omarchy + "/version"));
    JQ_DESC = pkgs.jq.meta.description;
    JQ_URL = pkgs.jq.meta.homepage;
    GUARD = guard;
    PKG_PRESENT = ../bin/omarchy-pkg-present.sh;
  } ''
    export HOME=$TMPDIR/home OMARCHY_PACMAN_CACHE=$TMPDIR/cache
    mkdir -p $HOME $TMPDIR/bin
    printf '#!${pkgs.bash}/bin/bash\nexec ${pkgs.bash}/bin/bash ${../bin/omarchy-pkg-attr.sh} "$@"\n' >$TMPDIR/bin/omarchy-pkg-attr
    chmod +x $TMPDIR/bin/omarchy-pkg-attr
    export PATH=$TMPDIR/bin:$PATH
    bash ${./pacman-shim/test.sh}
    touch $out
  '';

  catalog = pkgs.runCommand "omarchy-catalog-check" { nativeBuildInputs = [ pkgs.jq ]; } ''
    upstream=$(jq -c '[.[] | select(.layer != "core") | .keys] | sort' ${self.packages.${system}.keybinds}/keybinds.json)
    ours=$(jq -c 'sort' ${catalogBinds})
    missing=$(jq -rn --argjson u "$upstream" --argjson o "$ours" '$u - $o | .[]')
    stale=$(jq -rn --argjson u "$upstream" --argjson o "$ours" '$o - $u | .[]')
    [ -z "$missing" ] || { echo "Upstream binds not in lib/catalog.nix:"; echo "$missing"; exit 1; }
    [ -z "$stale" ] || { echo "Binds in lib/catalog.nix that upstream no longer has:"; echo "$stale"; exit 1; }
    touch $out
  '';

  ecosystem-home = ecosystemHome.activationPackage;

  tools = pkgs.linkFarm "omarchy-tools" (map (name: { inherit name; path = self.packages.${system}.${name}; })
    (builtins.attrNames (import ../pkgs/tools { inherit pkgs inputs; })));

  host = (inputs.nixpkgs.lib.nixosSystem {
    modules = [
      inputs.home-manager.nixosModules.home-manager
      self.nixosModules.default
      "${../examples/host}/configuration.nix"
      {
        # What nixos-generate-config would write.
        nixpkgs.hostPlatform = system;
        fileSystems."/" = { device = "/dev/disk/by-label/nixos"; fsType = "ext4"; };
        fileSystems."/boot" = { device = "/dev/disk/by-label/boot"; fsType = "vfat"; };
      }
    ];
  }).config.system.build.toplevel;

  # lib.catalog's plugins fetch and pass upstream's validator (lib.mkPlugin).
  catalog-plugins = pkgs.linkFarm "omarchy-catalog-plugins" (pkgs.lib.mapAttrsToList (id: p: {
    name = id;
    path = self.lib.mkPlugin { inherit pkgs id; src = pkgs.fetchgit { inherit (p) url rev hash; }; };
  }) catalog.plugins);

  plugin-registry = let
    cfg = registryHome.config;
    files = cfg.home-files;
    entries = self.lib.plugins;
  in pkgs.runCommand "omarchy-plugin-registry" { nativeBuildInputs = [ pkgs.jq ]; } ''
    set -eu
    ${pkgs.lib.concatStrings (pkgs.lib.mapAttrsToList (id: e: ''
      echo "== ${id}"
      tree=${files}/.config/omarchy/plugins/${id}
      test "$(jq -r .id $tree/manifest.json)" = ${pkgs.lib.escapeShellArg id}
      # A helper is a file or a directory (copied, not linked).
      ${pkgs.lib.concatMapStrings (h: ''
        test -e $tree/${h} -a ! -L $tree/${h} || { echo "${id}: helper ${h} missing"; exit 1; }
      '') e.helpers}
      ${pkgs.lib.concatMapStrings (h: ''
        test -e ${files}/${h} || { echo "${id}: ~/${h} missing"; exit 1; }
      '') e.home}
      ${pkgs.lib.concatMapStrings (u: ''
        test -e ${files}/.config/systemd/user/${u} || { echo "${id}: user unit ${u} missing"; exit 1; }
      '') e.userServices}
    '') entries)}
    # Every entry's packages, compositor plugins and QML modules build
    # (the home's profile has the packages).
    echo ${cfg.home.path} ${pkgs.lib.escapeShellArgs (map toString cfg.omarchy.hyprland.plugins)} \
      ${pkgs.lib.escapeShellArgs (map toString cfg.omarchy.internal.pluginQmlModules)} >/dev/null
    # User units: enabled per their [Install] (or `wantedBy`), ReadWritePaths made first.
    units=${files}/.config/systemd/user
    test -e $units/graphical-session.target.wants/nagori.service
    test -e $units/sockets.target.wants/bose-700.socket
    test ! -e $units/graphical-session.target.wants/bose-700.service
    test ! -e $units/default.target.wants/omaspotify.service
    grep -qx 'ExecStartPre=-+.*/bin/mkdir -p -m 0700 %h/.local/share/omostrich %h/.local/state/omarchy/omostrich' $units/omostrich.service
    test -e $units/omarchy-shell.service.d/olook-argcshim.conf
    # Groups: the NixOS module puts the user in the ones plugins declare.
    test ${if builtins.elem "input" registryUserGroups then "yes" else "no:${pkgs.lib.concatStringsSep "," registryUserGroups}"} = yes
    # Switched on in the package's default layout.
    for id in ${pkgs.lib.escapeShellArgs (builtins.attrNames entries)}; do
      grep -q "$id" ${cfg.omarchy.package}/share/omarchy/config/omarchy/shell.json
    done
    grep -qF 'hl.plugin.load("/run/test/libexample.so")' ${files}/.config/hypr/hyprland.lua
    touch $out
  '';

  # The declared-plugin bookkeeping in shell.json (pkgs/plugins-shell-json.py).
  plugins-shell-json = pkgs.runCommand "omarchy-plugins-shell-json" { nativeBuildInputs = [ pkgs.python3 pkgs.jq ]; } ''
    py="python3 ${../pkgs/plugins-shell-json.py}"
    mkdir w && cd w
    echo '{"kinds":["bar-widget"],"barWidget":{"defaultSection":"right"}}' >widget.json
    echo '{"kinds":["service"]}' >service.json
    echo '[{"id":"a.widget","section":null,"manifest":"widget.json"},{"id":"a.service","section":null,"manifest":"service.json"}]' >both.json
    echo '[{"id":"a.widget","section":null,"manifest":"widget.json"}]' >widget-only.json
    # Defaults: the widget after the tray (the shell's anchor), the service in plugins[].
    cp ${inputs.omarchy}/config/omarchy/shell.json defaults.json
    chmod u+w defaults.json
    $py defaults both.json defaults.json
    jq -e '.bar.layout.right[0].id == "omarchy.tray" and .bar.layout.right[1].id == "a.widget"' defaults.json
    jq -e '.plugins == [{"id":"a.service"}]' defaults.json
    # No user file: nothing written but the state.
    $py activate both.json user.json state.json
    test ! -e user.json && jq -e '.enabled == ["a.service","a.widget"]' state.json
    # The user's file (the shell wrote one), where they switched the widget off:
    # it stays off.
    jq 'del(.bar.layout.right[1])' defaults.json >user.json
    $py activate both.json user.json state.json
    jq -e '[.bar.layout[][] | .id] | index("a.widget") == null' user.json
    # A plugin declared later is switched on once; one no longer declared, off.
    rm state.json
    jq '.plugins = []' defaults.json >user.json
    echo '{"enabled":["a.widget"]}' >state.json
    $py activate both.json user.json state.json
    jq -e '.plugins == [{"id":"a.service"}]' user.json
    $py activate widget-only.json user.json state.json
    jq -e '.plugins == []' user.json
    jq -e '.enabled == ["a.widget"]' state.json
    touch $out
  '';

  # Shell plugins: upstream's `omarchy plugin` commands on NixOS (a local
  # git repo added and enabled, removed), a declared plugin (omarchy.plugins),
  # /usr/bin/<cmd> through envfs, /usr/share/omarchy, and the doctor.
  plugins = pkgs.testers.runNixOSTest {
    name = "omarchy-plugins";
    nodes.machine = { pkgs, ... }: {
      imports = [
        self.nixosModules.default
        inputs.home-manager.nixosModules.home-manager
      ];
      omarchy = {
        enable = true;
        stateDir = ./state;
        users = [ "omarchy" ];
        configDir = "/home/omarchy/nixos";
        login.autoLogin = "omarchy";
        # Declared at the NixOS level, passed to the user's Home Manager.
        plugins."io.github.proxy1967.logi-battery" = {
          src = fixtures.logi-battery;
          # A user unit whose ReadWritePaths don't exist yet (made first),
          # enabled from its [Install]; a group for the user.
          userServices."plugin-test.service" = ''
            [Service]
            Type=oneshot
            RemainAfterExit=yes
            ProtectHome=read-only
            ReadWritePaths=%h/.local/share/plugin-test
            ExecStart=${pkgs.coreutils}/bin/touch %h/.local/share/plugin-test/ran

            [Install]
            WantedBy=default.target
          '';
          extraGroups = [ "input" ];
        };
      };
      users.users.omarchy.isNormalUser = true;
      home-manager.users.omarchy.home.stateVersion = "26.05";
      environment.systemPackages = [ pkgs.jq ];
      environment.etc = pkgs.lib.mapAttrs' (name: src:
        pkgs.lib.nameValuePair "plugin-fixtures/${name}" { source = src; }) fixtures;
      virtualisation.memorySize = 4096;
    };
    testScript = ''
      import json
      start_all()
      home = "/home/omarchy"
      user = "su - omarchy -c"
      env = "XDG_RUNTIME_DIR=/run/user/1000 HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/1000/hypr | head -1)"
      machine.wait_for_unit("home-manager-omarchy.service")
      machine.wait_until_succeeds("systemctl --user -M omarchy@ is-active omarchy-shell.service", timeout=180)
      machine.wait_until_succeeds(f"{user} '{env} hyprctl version'", timeout=120)
      # The VM draws in software: reloading plugins can keep the shell busy
      # past omarchy-shell's 2 s IPC timeout.
      session = env + " WAYLAND_DISPLAY=$(cd /run/user/1000 && ls wayland-? | head -1) OMARCHY_SHELL_IPC_TIMEOUT=20s"
      def run(cmd):
          return machine.succeed(f"{user} '{session} {cmd}'")
      def plugins():
          return {p["id"]: p for p in json.loads(run("omarchy plugin list --json"))}
      def bar():
          return {w["id"]: w for w in json.loads(run("omarchy-shell shell debugBarGeometry"))}
      def qml_errors(pid):
          log = machine.succeed("journalctl --no-pager -o cat _SYSTEMD_USER_UNIT=omarchy-shell.service")
          return [l for l in log.splitlines() if pid in l and any(w in l for w in
                  ("rror", "failed", "not installed", "not a type", "is not defined", "Cannot", "Unable"))]
      machine.wait_until_succeeds(f"{user} '{session} omarchy-shell shell listPlugins' | grep -q omarchy.clock", timeout=60)

      # ---- Paths plugins written for Arch expect --------------------------
      # envfs: /usr/bin/<cmd> from the caller's PATH, also for a process
      # that clears its environment to PATH=/usr/bin (as My Journal's helper
      # does: envfs falls back to the process's own original PATH).
      print(machine.succeed("findmnt /usr/bin; findmnt /bin"))
      machine.succeed("findmnt -n /usr/bin | grep -q envfs")
      run("/usr/bin/python3 -c \"print(42)\" | grep -qx 42")
      run("env -i HOME=/home/omarchy PATH=/usr/bin LC_ALL=C /usr/bin/python3 -I -S -c \"print(42)\" | grep -qx 42")
      run("/usr/bin/omarchy-cmd-present jq")
      machine.succeed("test -x /usr/bin/env && /bin/sh -c true && /usr/bin/bash -c true")
      # What isn't on the caller's PATH stays missing.
      machine.fail("env -i PATH=/nowhere /usr/bin/python3 -c 1")
      # Omarchy's files at Arch's OMARCHY_PATH.
      machine.succeed("test -f /usr/share/omarchy/shell/shell.qml && test -f /usr/share/omarchy/config/omarchy/shell.json")
      machine.succeed("test -e /usr/share/zoneinfo/Europe/Amsterdam")
      # The pacman shim (omarchy.pacmanShim): /usr/bin/pacman answers from
      # the system, by Arch name; installs fail saying what to declare.
      run("/usr/bin/pacman -Q omarchy bash jq qt6-base")
      run("/usr/bin/pacman -Qqe | grep -qx hyprland")
      run("LC_ALL=C /usr/bin/pacman -Qi quickshell | grep -q ^Version")
      run("pacman -Qqo \"$(command -v jq)\" | grep -qx jq")
      run("omarchy-pkg-present hyprland-bin jq")
      machine.fail(f"{user} 'pacman -Q no-such-package'")
      out = machine.fail(f"{user} 'pacman -S --noconfirm foo 2>&1'")
      assert "only answers queries; add foo" in out, out

      # ---- A declared plugin (omarchy.plugins, from the NixOS module) ----
      declared = "io.github.proxy1967.logi-battery"
      link = f"{home}/.config/omarchy/plugins/{declared}"
      machine.succeed(f"test -L {link} && readlink -f {link} | grep -q '^/nix/store/'")
      # Its user unit ran at login (its ReadWritePaths made first), and the
      # user is in the group it declares.
      machine.wait_until_succeeds(f"test -f {home}/.local/share/plugin-test/ran", timeout=60)
      machine.succeed("systemctl --user -M omarchy@ is-active plugin-test.service")
      machine.succeed("id -nG omarchy | grep -qw input")
      machine.wait_until_succeeds(f"{user} '{session} omarchy plugin list --json' | jq -e 'any(.[]; .id == \"{declared}\" and .enabled)'", timeout=60)
      machine.wait_until_succeeds(f"{user} '{session} omarchy-shell shell debugBarGeometry' | jq -e 'any(.[]; .id == \"{declared}\")'", timeout=60)
      # Its reader is a #!/usr/bin/python3 script: it runs (no mouse here,
      # so it reports none) instead of failing on the interpreter.
      out = machine.succeed(f"{user} '{session} {link}/logi-battery 2>&1 || true'")
      print(out)
      assert "bad interpreter" not in out and "No such file" not in out, out
      # upstream's update leaves it alone: it's no git checkout.
      run(f"omarchy plugin update {declared} --yes 2>&1 | grep -q \"not a git checkout\"")

      # ---- `omarchy plugin add` from a local git repo ---------------------
      for name in ["myjournal", "moon-arc"]:
          run(f"cp -rL --no-preserve=mode /etc/plugin-fixtures/{name} /tmp/{name} && cd /tmp/{name} && git init -q && git add -A && git -c user.name=t -c user.email=t@t commit -qm import")
      out = run("omarchy plugin add /tmp/myjournal --yes --enable 2>&1")
      assert "Added io.github.mohuddle.myjournal" in out, out
      run("omarchy plugin add /tmp/moon-arc --yes --enable 2>&1")
      for pid in ["io.github.mohuddle.myjournal", "io.github.rookepoole.moon-arc"]:
          machine.succeed(f"test -d {home}/.config/omarchy/plugins/{pid}/.git")
          machine.wait_until_succeeds(f"{user} '{session} omarchy plugin list --json' | jq -e 'any(.[]; .id == \"{pid}\" and .enabled)'", timeout=60)
          machine.wait_until_succeeds(f"{user} '{session} omarchy-shell shell debugBarGeometry' | jq -e 'any(.[]; .id == \"{pid}\" and .itemWidth > 0)'", timeout=60)
      # Enabling wrote the user's shell.json, which kept the declared plugin.
      machine.succeed(f"jq -e '[.bar.layout[][] | .id] | index(\"{declared}\") != null' {home}/.config/omarchy/shell.json")
      # My Journal's store helper, run exactly as its Service does.
      helper = f"{home}/.config/omarchy/plugins/io.github.mohuddle.myjournal/bin/journal-store.py"
      run(f"env -i HOME={home} PATH=/usr/bin LC_ALL=C /usr/bin/python3 -I -S {helper} read")
      machine.sleep(5)
      for pid in [declared, "io.github.mohuddle.myjournal", "io.github.rookepoole.moon-arc"]:
          errors = qml_errors(pid)
          assert not errors, f"{pid}: " + "\n".join(errors)
      machine.succeed("systemctl --user -M omarchy@ is-active omarchy-shell.service")
      machine.screenshot("plugins-bar")

      # ---- The doctor -----------------------------------------------------
      out = run("omarchy plugin doctor /etc/plugin-fixtures/typist 2>&1")
      assert "setxkbmap" in out and "nixpkgs: setxkbmap" in out, out
      assert 'omarchy.plugins."io.github.sanjuanjor.typist".packages = with pkgs; [ setxkbmap ];' in out, out
      out = run("omarchy plugin doctor /etc/plugin-fixtures/kefctl 2>&1")
      # Its `yay -S kefctl` is a hint in a message: named, not Arch-only.
      assert "Arch-only" not in out and "kefctl" in out and "no nixpkgs package" in out, out
      report = json.loads(run("omarchy plugin doctor io.github.mohuddle.myjournal --json"))
      assert report["verdict"] == "ok", report
      assert any(c["name"] == "python3" and c["status"] == "ok" for c in report["commands"]), report["commands"]
      report = json.loads(run(f"omarchy plugin doctor {declared} --json"))
      assert report["declared"] and report["verdict"] == "ok", report

      # ---- Switched off by the user, kept off by the next activation ------
      run(f"omarchy plugin disable {declared}")
      machine.wait_until_succeeds(f"{user} '{session} omarchy plugin list --json' | jq -e 'any(.[]; .id == \"{declared}\" and (.enabled | not))'", timeout=30)
      machine.succeed("systemctl restart home-manager-omarchy.service")
      machine.succeed(f"jq -e '[.bar.layout[][] | .id] | index(\"{declared}\") == null' {home}/.config/omarchy/shell.json")

      # ---- Removal --------------------------------------------------------
      run("omarchy plugin remove io.github.rookepoole.moon-arc --yes")
      machine.fail(f"test -e {home}/.config/omarchy/plugins/io.github.rookepoole.moon-arc")
      machine.wait_until_succeeds(f"{user} '{session} omarchy plugin list --json' | jq -e 'all(.[]; .id != \"io.github.rookepoole.moon-arc\")'", timeout=30)
      machine.succeed("systemctl --user -M omarchy@ is-active omarchy-shell.service")
    '';
  };

  vm = pkgs.testers.runNixOSTest {
    name = "omarchy";
    # machine: the essentials, as the host template sets them up.
    # ecosystem: the ecosystem layers on, keeping only some picks.
    defaults = {
      imports = [
        self.nixosModules.default
        inputs.home-manager.nixosModules.home-manager
      ];
      omarchy = {
        enable = true;
        stateDir = ./state;
        users = [ "omarchy" ];
        configDir = "/home/omarchy/nixos";
        # Straight into the session, to check it comes up.
        login.autoLogin = "omarchy";
      };
      users.users.omarchy = {
        isNormalUser = true;
        linger = true;
      };
      home-manager.users.omarchy.home.stateVersion = "26.05";
      virtualisation.memorySize = 4096;
    };
    nodes.machine = { lib, pkgs, ... }: {
      # For the test script's checks (run as root).
      environment.systemPackages = [ pkgs.jq ];
      # The menu's rebuilds: the user may sudo (as on a real install), and
      # "rebuilding" switches to a prebuilt generation the way nixos-rebuild
      # does (switch-to-configuration in its own transient unit). That
      # generation is what the host's flake would build after the menu
      # edits in this test: helix added to apps.json, catppuccin picked.
      users.users.omarchy.extraGroups = [ "wheel" ];
      security.sudo.wheelNeedsPassword = false;
      omarchy.rebuildCommand =
        "sudo systemd-run --collect --no-ask-password --pipe --quiet --service-type=exec "
        + "--unit=nixos-rebuild-switch-to-configuration --wait "
        + "/run/booted-system/specialisation/rebuilt/bin/switch-to-configuration test"
        # Only reached when the rebuild's terminal survives the switch.
        + " && touch /tmp/rebuild-finished";
      # A non-US keyboard, as the installer sets it: Hyprland takes it.
      services.xserver.xkb.layout = "de";
      specialisation.rebuilt.configuration.omarchy.stateDir = lib.mkForce ./state-rebuilt;
      # The menu's Timezone entry goes through polkit, whose agent (the
      # shell) would ask for the password on screen.
      security.polkit.extraConfig = ''
        polkit.addRule(function(action, subject) {
          if (action.id == "org.freedesktop.timedate1.set-timezone" && subject.user == "omarchy")
            return polkit.Result.YES;
        });
      '';
    };
    nodes.ecosystem = { pkgs, ... }: {
      # A declared time zone: the menu's Timezone entry points to the config.
      time.timeZone = "Europe/Amsterdam";
      omarchy.ecosystem.enable = true;
      # bash instead of zsh; foot, Nautilus and btop left out, Alacritty as
      # the terminal (the installer's choices).
      omarchy.shell = "bash";
      home-manager.users.omarchy = {
        home.packages = [ pkgs.alacritty ];
        omarchy = {
          apps.picks = [ "pinta" "omacalc" ];
          webapps.picks = [ "youtube" ];
          defaultApps.foot.enable = false;
          defaultApps.nautilus.enable = false;
          defaultApps.btop.enable = false;
          terminal = "Alacritty.desktop";
        };
      };
    };
    testScript = ''
      start_all()
      machine.wait_for_unit("multi-user.target")
      machine.wait_for_unit("home-manager-omarchy.service")

      # Omarchy's login screen.
      machine.wait_for_unit("display-manager.service")
      machine.succeed("test -f /run/current-system/sw/share/sddm/themes/omarchy/Main.qml")

      # Lock-screen PAM service, as the shell requires.
      machine.succeed("test -f /etc/pam.d/omarchy-lock-password")

      # The shell's unit and the NixOS command layer, for the user.
      home = "/home/omarchy"
      machine.succeed(f"test -f {home}/.config/systemd/user/omarchy-shell.service")
      machine.succeed(f"test -e {home}/.local/share/omarchy/shell/shell.qml")
      machine.succeed(f"test -f {home}/.local/state/omarchy/current/theme/shell.toml")
      machine.succeed(f"test -f {home}/.config/omarchy/extensions/omarchy-menu.jsonc")
      machine.succeed("su - omarchy -c 'omarchy-pkg-present bash'")
      machine.fail("su - omarchy -c 'omarchy-pkg-present definitely-not-installed'")
      machine.succeed("su - omarchy -c 'omarchy-theme-set --help >/dev/null 2>&1 || true'")

      # The session: Hyprland from the auto-login, Omarchy's config loading
      # without errors, and the shell running.
      user = "su - omarchy -c"
      shell = "systemctl --user -M omarchy@ is-active omarchy-shell.service"
      machine.wait_until_succeeds(shell, timeout=180)
      # Hyprland answers on its socket (the instance directory appears
      # before it listens; slower machines see the gap).
      env = "XDG_RUNTIME_DIR=/run/user/1000 HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/1000/hypr | head -1)"
      hyprland = f"{user} '{env} hyprctl version'"
      machine.wait_until_succeeds(hyprland, timeout=120)
      errors = machine.succeed(f"{user} '{env} hyprctl configerrors'").strip()
      assert errors in ("", "no errors"), f"Hyprland config errors:\n{errors}"
      machine.sleep(10)
      machine.succeed(shell)

      # Core apps: Omarchy's defaults resolve on NixOS.
      term = machine.succeed(f"{user} 'xdg-terminal-exec --print-id'").strip()
      assert term.startswith("foot.desktop"), f"default terminal: {term}"
      browser = machine.succeed(f"{user} 'xdg-mime query default x-scheme-handler/https'").strip()
      assert browser == "chromium.desktop", f"default browser: {browser}"
      machine.succeed(f"{user} 'command -v chromium nautilus nvim imv mpv evince btop lazygit'")

      # The CLI setup: zsh as the login shell with Omarchy's aliases,
      # functions and prompt; git's defaults under the user's own config.
      machine.succeed("getent passwd omarchy | grep -q '/zsh$'")
      zsh = machine.succeed(f"{user} 'zsh -ic \"alias ls; whence -w zd tdl compress; echo \\$EDITOR\"' 2>&1")
      assert "eza" in zsh and "zd: function" in zsh and "tdl: function" in zsh, zsh
      assert "omarchy-launch-editor" in zsh, zsh
      machine.succeed(f"{user} 'git config --get pull.rebase' | grep -qx true")
      machine.succeed(f"{user} 'command -v bat eza rg lazygit starship'")

      # Omarchy's own tools in place of the old workarounds: omasnap for
      # screenshots, ttfx for the screensaver, the elsewhen bar widget, and
      # Omarchy's Neovim config seeded with the theme linked.
      machine.succeed(f"{user} 'command -v omasnap ttfx owed'")
      machine.succeed(f"test -f {home}/.local/share/omarchy/shell/plugins/omacom.elsewhen/manifest.json")
      machine.succeed(f"test -f {home}/.config/nvim/lazyvim.json")
      machine.succeed(f"test -L {home}/.config/nvim/lua/plugins/theme.lua")

      # SUPER+RETURN opens the terminal.
      machine.send_key("meta_l-ret")
      machine.wait_until_succeeds(f"{user} '{env} hyprctl clients' | grep -q 'class: foot'", timeout=60)
      machine.sleep(2)
      machine.screenshot("session")

      # Capture tools, run in the session's environment as the menu and
      # the keybinds run them. The folders Omarchy saves into exist.
      machine.succeed(f"test -d {home}/Pictures && test -d {home}/Videos && test -d {home}/Downloads")
      # The shell answers the menu's IPC slowly on a loaded CI runner and
      # right after a rebuild restarts it: wait longer than its 2 s default.
      session = env + " WAYLAND_DISPLAY=$(cd /run/user/1000 && ls wayland-? | head -1) OMARCHY_SHELL_IPC_TIMEOUT=20s"
      # Upstream's screenshot command: omasnap on its development branch,
      # a grim script in the v4.0 releases the stable channel follows.
      omasnap = ${if omasnapScreenshots then "True" else "False"}
      shots = f"{home}/Pictures/Screenshots" if omasnap else f"{home}/Pictures"
      # Capture > Screenshot: copies to the clipboard and saves (omasnap:
      # with auto-save); fullscreen needs no selection.
      machine.succeed(f"{user} '{session} timeout 60 omarchy-capture-screenshot fullscreen'")
      machine.wait_until_succeeds(f"ls {shots}/screenshot-*.png", timeout=30)
      machine.succeed(f"{user} '{session} wl-paste --list-types' | grep -qx image/png")
      if omasnap:
          # PRINT, then Ctrl+A (the whole monitor) in Omasnap's picker: the
          # keybind path, saved the same way.
          count = int(machine.succeed(f"ls {shots} | wc -l").strip())
          machine.send_key("print")
          machine.sleep(3)
          machine.send_key("ctrl-a")
          machine.wait_until_succeeds(f"test $(ls {shots} | wc -l) -gt {count}", timeout=30)
      # Quick output saves when asked: `save`.
      count = int(machine.succeed(f"ls {shots} | wc -l").strip())
      machine.succeed(f"{user} '{session} timeout 60 omarchy-capture-screenshot fullscreen save'")
      machine.wait_until_succeeds(f"test $(ls {shots} | wc -l) -gt {count}", timeout=30)
      machine.succeed(f"{user} 'file {shots}/screenshot-*.png' | grep -q 'PNG image data'")

      # Screen recording: Omarchy finds the running recorder by its process
      # name (the bar indicator, Stop, the toggle). gpu-screen-recorder
      # refuses the VM's software OpenGL, so the recorder's own wrapper runs
      # a sleeping Python in its place: started under the name Omarchy
      # looks for, and stopped (SIGINT) by Omarchy's command.
      machine.succeed(
        "mkdir -p /tmp/gsr && py=$(su - omarchy -c 'readlink -f $(command -v python3)') "
        "&& sed -E \"s#^exec -a gpu-screen-recorder \\\"[^\\\"]*\\\"#exec -a gpu-screen-recorder $py#\" "
        "\"$(su - omarchy -c 'readlink -f $(command -v gpu-screen-recorder)')\" </dev/null >/tmp/gsr/gpu-screen-recorder "
        "&& chmod +x /tmp/gsr/gpu-screen-recorder && grep -q '^exec -a gpu-screen-recorder /nix/store/.*python' /tmp/gsr/gpu-screen-recorder"
      )
      machine.succeed("systemd-run --user -M omarchy@ --unit=fake-recorder /tmp/gsr/gpu-screen-recorder -c 'import time; time.sleep(300)'")
      machine.wait_until_succeeds("pgrep -f '^gpu-screen-recorder'", timeout=30)
      machine.succeed(f"{user} '{session} omarchy-capture-screenrecording --stop-recording'")
      machine.wait_until_fails("pgrep -f '^gpu-screen-recorder'", timeout=30)

      # Upstream's user units: lock before suspend, crash capture.
      machine.succeed("systemctl --user -M omarchy@ is-active omarchy-sleep-lock.service omarchy-crash-watch.service")
      machine.succeed("systemd-inhibit --list | grep -q 'Lock screen before suspend'")
      # Commands the capture and share tools call by name.
      machine.succeed(f"{user} 'command -v v4l2-ctl hyprpicker grim slurp tesseract zbarimg wl-copy localsend lspci'")

      # ---- The user's own files --------------------------------------------
      # Upstream's config/hypr files, seeded once as regular files the user
      # owns and edits (the menu opens them); hyprland.lua stays generated.
      hypr = f"{home}/.config/hypr"
      userfiles = ["monitors.lua", "input.lua", "bindings.lua", "looknfeel.lua", "autostart.lua", "hyprsunset.conf"]
      for f in userfiles:
          machine.succeed(f"test -f {hypr}/{f} && test ! -L {hypr}/{f}")
          machine.succeed(f"test $(stat -c %U {hypr}/{f}) = omarchy")
          machine.succeed(f"{user} 'test -w {hypr}/{f}'")
      machine.succeed(f"test -L {hypr}/hyprland.lua")
      upstream = machine.succeed(f"readlink -f {home}/.local/share/omarchy").strip()
      machine.succeed(f"cmp {hypr}/input.lua {upstream}/config/hypr/input.lua")
      # The menu's Setup > Monitors / Input / Keybindings and Style > Hyprland
      # are upstream's own entries again: they open these files.
      # The NixOS menu layer lives in the package's menu; the extension file
      # is the user's (upstream's commented template).
      ext = f"{home}/.config/omarchy/extensions/omarchy-menu.jsonc"
      machine.succeed(f"test -f {ext} && test ! -L {ext} && cmp {ext} {upstream}/config/omarchy/extensions/omarchy-menu.jsonc")
      nixos_menu = machine.succeed(f"sed -n '/NixOS (nix-desktops/,$p' {upstream}/default/omarchy/omarchy-menu.jsonc")
      assert '"setup.config.hyprland"' in nixos_menu and '"install.package"' in nixos_menu, nixos_menu
      for entry in ["setup.monitors", "setup.input", "setup.keybindings", "style.hyprland"]:
          assert f'"{entry}"' not in nixos_menu, f"{entry} is still overridden"

      # Omarchy's program configs and ~/.zshrc are the user's files too.
      configs = [".config/foot/foot.ini", ".config/starship.toml", ".config/tmux/tmux.conf",
                 ".config/btop/btop.conf", ".config/lazygit/config.yml", ".config/fastfetch/config.jsonc",
                 ".config/alacritty/alacritty.toml", ".config/ghostty/config", ".config/kitty/kitty.conf",
                 ".zshrc", ".zshenv"]
      for f in configs:
          machine.succeed(f"test -f {home}/{f} && test ! -L {home}/{f} && test $(stat -c %U {home}/{f}) = omarchy")
      btop_theme = f"cmp {home}/.config/btop/themes/current.theme {home}/.local/state/omarchy/current/theme/btop.theme"
      machine.succeed(btop_theme)
      # Omarchy's font switcher edits them in place (sed -i), and the next
      # activation still succeeds and keeps the edit.
      machine.succeed(f"{user} '{session} DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus omarchy-font-set \"Liberation Mono\"'")
      machine.succeed(f"grep -q '^font=Liberation Mono' {home}/.config/foot/foot.ini")
      machine.succeed(f"{user} 'echo \"alias hi=\\\"echo hi\\\"\" >> ~/.zshrc'")

      # The system's keyboard layout (services.xserver.xkb.layout).
      layout = machine.succeed(f"{user} '{env} hyprctl getoption input:kb_layout'")
      assert "de" in layout, layout
      # (The font switch restarted the shell: retry until its menu answers.)
      for _ in range(12):
          machine.execute(f"{user} '{session} omarchy-menu summon setup.monitors'")
          if machine.execute(f"sleep 5; pgrep -u omarchy -f 'nvim.*{hypr}/monitors.lua'")[0] == 0:
              break
      else:
          raise Exception("Setup > Monitors didn't open monitors.lua")
      machine.succeed("pkill -u omarchy -f 'nvim.*monitors.lua'")

      # Edits survive Home Manager re-activation (every rebuild runs it).
      machine.succeed(f"{user} 'echo \"-- my input tweak\" >> {hypr}/input.lua'")
      # Omarchy's scale command writes the scale into monitors.lua.
      machine.succeed(f"{user} '{session} omarchy-hyprland-monitor-scaling 2'")
      machine.succeed(f"grep -qx 'local omarchy_monitor_scale = 2' {hypr}/monitors.lua")
      scale = f"{user} '{env} hyprctl monitors -j' | jq -e '.[0].scale == 2'"
      machine.succeed(scale)
      # A copy made in ~/.local/state/hypr (loaded first) moves to
      # ~/.config/hypr when that one is untouched; an older link into the
      # store becomes a copy.
      machine.succeed(f"{user} 'mkdir -p ~/.local/state/hypr && cp {hypr}/looknfeel.lua ~/.local/state/hypr/ && chmod u+w ~/.local/state/hypr/looknfeel.lua && echo \"-- my look\" >> ~/.local/state/hypr/looknfeel.lua'")
      machine.succeed(f"{user} 'rm {hypr}/autostart.lua && ln -s {upstream}/config/hypr/autostart.lua {hypr}/autostart.lua'")
      machine.succeed("systemctl restart home-manager-omarchy.service")
      machine.succeed("systemctl is-active home-manager-omarchy.service")
      machine.succeed(f"grep -qx -- '-- my input tweak' {hypr}/input.lua")
      machine.succeed(f"grep -qx -- '-- my look' {hypr}/looknfeel.lua")
      machine.succeed(f"grep -q '^font=Liberation Mono' {home}/.config/foot/foot.ini")
      machine.succeed(f"{user} 'zsh -ic hi' | grep -qx hi")
      machine.succeed(f"test ! -e {home}/.local/state/hypr/looknfeel.lua")
      machine.succeed(f"test -f {hypr}/autostart.lua && test ! -L {hypr}/autostart.lua")
      machine.succeed(f"grep -qx 'local omarchy_monitor_scale = 2' {hypr}/monitors.lua")
      machine.succeed(f"{user} '{env} hyprctl reload'")
      machine.sleep(2)
      machine.succeed(scale)
      errors = machine.succeed(f"{user} '{env} hyprctl configerrors'").strip()
      assert errors in ("", "no errors"), f"Hyprland config errors:\n{errors}"

      # ---- XDG user directories ---------------------------------------------
      for d in ["Documents", "Downloads", "Music", "Pictures", "Projects", "Videos"]:
          machine.succeed(f"test -d {home}/{d}")
      dirs = machine.succeed(f"cat {home}/.config/user-dirs.dirs")
      assert 'XDG_PICTURES_DIR="$HOME/Pictures"' in dirs, dirs
      # As upstream: Desktop, Templates and Public are the home directory.
      assert 'XDG_DESKTOP_DIR="$HOME"' in dirs, dirs
      # The user's file (xdg-user-dirs-update can change it).
      machine.succeed(f"test -f {home}/.config/user-dirs.dirs && test ! -L {home}/.config/user-dirs.dirs")
      pictures = machine.succeed(f"{user} 'xdg-user-dir PICTURES'").strip()
      assert pictures == f"{home}/Pictures", pictures
      machine.succeed(f"grep -qx 'file://{home}/Downloads Downloads' {home}/.config/gtk-3.0/bookmarks")

      # ---- The cursor -------------------------------------------------------
      machine.succeed(f"test -f {home}/.local/share/icons/Bibata-Modern-Classic/cursors/left_ptr")
      machine.succeed("grep -qx 'CursorTheme=Bibata-Modern-Classic' /etc/sddm.conf.d/00-nixos.conf")
      machine.succeed("grep -q '^CompositorCommand=.*XCURSOR_THEME=Bibata-Modern-Classic' /etc/sddm.conf.d/00-nixos.conf")
      foot = machine.succeed("pgrep -u omarchy -x foot | head -1").strip()
      fenv = machine.succeed(f"tr '\\0' '\\n' < /proc/{foot}/environ")
      for var in ["XCURSOR_THEME=Bibata-Modern-Classic", "XCURSOR_SIZE=24",
                  "HYPRCURSOR_THEME=Bibata-Modern-Classic", "HYPRCURSOR_SIZE=24"]:
          assert var in fenv.splitlines(), f"{var} not in the session: {fenv}"
      bus = "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"
      theme = machine.succeed(f"{user} '{bus} dconf read /org/gnome/desktop/interface/cursor-theme'").strip()
      assert theme == "'Bibata-Modern-Classic'", theme
      # The pointer on screen, over the desktop between the window and the
      # edge (the monitor is at scale 2 now: 640x400 logical). The VM draws
      # it in software, so QEMU's screendump shows it.
      machine.succeed(f"{user} '{env} hyprctl eval \"hl.dispatch(hl.dsp.cursor.move({{ x = 5, y = 200 }}))\"'")
      machine.succeed(f"{user} '{env} hyprctl cursorpos' | grep -qx '5, 200'")
      machine.sleep(1)
      machine.screenshot("cursor")
      machine.succeed(f"{user} '{session} grim -c /tmp/cursor-grim.png'")
      machine.copy_from_machine("/tmp/cursor-grim.png", "")

      # ---- Theme switching, live --------------------------------------------
      # The config the menu edits, as on a real install: a writable copy.
      machine.succeed(f"{user} 'mkdir -p ~/nixos && cp -r --no-preserve=mode ${./state} ~/nixos/omarchy'")
      theme_json = f"{home}/nixos/omarchy/theme.json"
      machine.succeed(f"test -f {theme_json}")
      current = f"{home}/.local/state/omarchy/current"
      border = f"{user} '{env} hyprctl getoption general:col.active_border'"
      before = machine.succeed(border)
      gen = machine.succeed("readlink /run/current-system").strip()
      machine.succeed(f"{user} '{session} {bus} omarchy-theme-set catppuccin'")
      machine.succeed(f"jq -e '.theme == \"catppuccin\"' {theme_json}")
      machine.succeed(f"grep -qx catppuccin {current}/theme.name")
      machine.succeed(f"cmp {current}/theme/colors.toml {home}/.config/omarchy/themes/catppuccin/colors.toml")
      icons = machine.succeed(f"{user} '{bus} dconf read /org/gnome/desktop/interface/icon-theme'").strip()
      assert icons == "'Yaru-purple'", icons
      machine.succeed(btop_theme)
      machine.succeed(f"readlink -f {current}/background | grep -q '^{current}/theme/backgrounds/'")
      for _ in range(30):
          if machine.succeed(border) != before:
              break
          machine.sleep(1)
      else:
          raise Exception(f"Hyprland's border kept the old theme's color: {before}")
      assert machine.succeed("readlink /run/current-system").strip() == gen, "the theme switch rebuilt"
      # The switch reloaded Hyprland; the edited monitors file stayed.
      machine.succeed(scale)
      machine.succeed(f"grep -qx 'local omarchy_monitor_scale = 2' {hypr}/monitors.lua")
      # Re-activating the same generation keeps the live pick.
      machine.succeed("systemctl restart home-manager-omarchy.service")
      machine.succeed(f"grep -qx catppuccin {current}/theme.name")
      machine.succeed(f"cmp {current}/theme/colors.toml {home}/.config/omarchy/themes/catppuccin/colors.toml")

      # ---- Install > Package, then the wrapper again ------------------------
      # Install > Package: the menu runs `xdg-terminal-exec … omarchy-pkg-install`
      # from inside the shell's service, and the wrapper edits apps.json and
      # rebuilds (here: switches to the prebuilt generation, which also has a
      # new theme, so the shell restarts mid-rebuild). The search needs
      # nixpkgs online, so the wrapper runs with the pick (helix) as the
      # search would, in the shell's cgroup and environment, as the menu's
      # action does.
      terminals = f"{user} '{env} hyprctl clients -j' | jq '[.[] | select(.class == \"org.omarchy.terminal\")] | length'"
      shell_pid = machine.succeed("systemctl --user -M omarchy@ show -p MainPID --value omarchy-shell.service").strip()
      machine.succeed("${menuAction} 'xdg-terminal-exec --app-id=org.omarchy.terminal omarchy-pkg-install helix' >/dev/null 2>&1 &")
      machine.wait_until_succeeds(f"readlink /run/current-system | grep -qv {gen}", timeout=300)
      # The wrapper's terminal outlived the shell's restart and finished.
      machine.wait_until_succeeds("test -e /tmp/rebuild-finished", timeout=120)
      # The shell came back (restarted for the new theme), not stuck
      # stopping behind the wrapper's sudo.
      machine.wait_until_succeeds(f"test \"$(systemctl --user -M omarchy@ show -p MainPID --value omarchy-shell.service)\" != {shell_pid}", timeout=120)
      machine.wait_until_succeeds(shell, timeout=60)
      machine.wait_until_succeeds(f"{user} 'command -v hx'", timeout=120)
      machine.succeed(f"jq -e '.packages | index(\"helix\")' {home}/nixos/omarchy/apps.json")
      machine.wait_for_unit("home-manager-omarchy.service")
      machine.sleep(5)
      # The rebuild kept the theme (theme.json's now) and the user's files.
      machine.succeed(f"grep -qx catppuccin {current}/theme.name")
      machine.succeed(f"grep -qx 'local omarchy_monitor_scale = 2' {hypr}/monitors.lua")
      machine.succeed(f"grep -qx -- '-- my input tweak' {hypr}/input.lua")
      machine.succeed(f"{user} '{env} hyprctl reload'")
      machine.sleep(2)
      machine.succeed(scale)
      # Install > Package opens its wrapper again after the rebuild.
      machine.succeed(shell)
      count = int(machine.succeed(terminals).strip())
      machine.wait_until_succeeds(f"{user} '{session} omarchy-menu summon install.package'", timeout=90)
      machine.wait_until_succeeds(f"test $({terminals}) -gt {count}", timeout=60)
      machine.succeed("pgrep -u omarchy -f 'omarchy-pkg-install$'")
      machine.screenshot("install-wrapper")

      # ---- Timezone ---------------------------------------------------------
      machine.fail("test -e /etc/omarchy/time-zone")
      machine.succeed(f"{user} '{session} omarchy-menu-timezone Europe/Amsterdam'")
      machine.succeed("timedatectl show -p Timezone --value | grep -qx Europe/Amsterdam")

      # The ecosystem node: kept picks installed and bound, the rest not.
      eco = ecosystem
      eco.wait_for_unit("home-manager-omarchy.service")
      eco.wait_for_unit("docker.service")
      eco.succeed("id -nG omarchy | grep -qw docker")
      eco.succeed(f"{user} 'command -v lazydocker pinta omacalc bat mise'")
      eco.fail(f"{user} 'command -v obsidian'")
      eco.succeed(f"{user} 'ls ~/.nix-profile/share/applications /etc/profiles/per-user/omarchy/share/applications 2>/dev/null | grep -q YouTube.desktop'")
      eco.fail(f"{user} 'ls ~/.nix-profile/share/applications /etc/profiles/per-user/omarchy/share/applications 2>/dev/null | grep -q HEY.desktop'")
      eco.wait_until_succeeds(shell, timeout=180)
      eco.wait_until_succeeds(hyprland, timeout=120)
      binds = eco.succeed(f"{user} '{env} hyprctl binds -j | jq -r \".[].description\"'")
      for kept in ["YouTube", "Docker", "Terminal"]:
          assert kept in binds.splitlines(), f"missing bind: {kept}"
      for dropped in ["X", "Email", "Obsidian", "Omawrite", "Herdr"]:
          assert dropped not in binds.splitlines(), f"bind not dropped: {dropped}"
      errors = eco.succeed(f"{user} '{env} hyprctl configerrors'").strip()
      assert errors in ("", "no errors"), f"Hyprland config errors:\n{errors}"
      # bash as the shell: Omarchy's setup in the user's ~/.bashrc, no zsh.
      eco.succeed("getent passwd omarchy | grep -q '/bash$'")
      eco.succeed(f"test -f {home}/.bashrc && test ! -L {home}/.bashrc && test ! -e {home}/.zshrc")
      eco.fail(f"{user} 'command -v zsh'")
      alias = eco.succeed(f"{user} 'bash -ic \"alias ls\"' 2>&1")
      assert "eza" in alias, alias
      # Default apps left out: not installed, their binds and MIME defaults
      # gone; the terminal bind launches the chosen terminal.
      for app in ["foot", "nautilus", "btop"]:
          eco.fail(f"{user} 'command -v {app}'")
      for dropped in ["File manager", "Activity"]:
          assert dropped not in binds.splitlines(), f"bind not dropped: {dropped}"
      eco_term = eco.succeed(f"{user} 'xdg-terminal-exec --print-id'").strip()
      assert eco_term.startswith("Alacritty.desktop"), eco_term
      mime = f"$(readlink -f {home}/.local/share/omarchy)/../applications/mimeapps.list"
      eco.succeed(f"grep -q chromium.desktop {mime}")
      eco.fail(f"grep -q Nautilus {mime}")
      eco.fail(f"test -e {home}/.config/foot/foot.ini")
      # A declared time zone: the menu's Timezone entry says where to change it.
      eco.succeed("grep -qx Europe/Amsterdam /etc/omarchy/time-zone")
      out = eco.fail(f"{user} 'omarchy-menu-timezone Europe/Berlin 2>&1'")
      assert "time.timeZone" in out, out
      eco.succeed("timedatectl show -p Timezone --value | grep -qx Europe/Amsterdam")
    '';
  };
}
