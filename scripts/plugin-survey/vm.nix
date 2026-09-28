# The plugin survey's VM: a logged-in Omarchy desktop from this flake (as
# the host template sets one up), with the packages the doctor named for
# the plugins of one batch, and the batch script (runtime.py) as the test
# script. Built by survey.py; its driver runs outside the Nix sandbox so the
# VM has the network (plugins fetch weather, prices, …):
#
#   nix build --impure -f scripts/plugin-survey/vm.nix driver \
#     --argstr flake "$PWD" --argstr packages '["cava"]' --argstr python '["requests"]'
#   SURVEY_BATCH=batch.json SURVEY_OUT=out result/bin/nixos-test-driver -o out
#
# `registry` (a JSON list of ids) declares plugins from the flake's
# registry (pkgs/plugins): `omarchy.plugins.<id>.enable = true`, installed
# with their helpers at build time instead of `omarchy plugin add`. nix-ld
# is on (omarchy.nixLd, the NixOS module's default), as on a user's machine.
#
# `available` lists every command on the shell's PATH in the VM without
# extra packages, for the doctor's static pass (--available).
{ flake ? toString ../.., packages ? "[]", python ? "[]", registry ? "[]", system ? builtins.currentSystem }:
let
  self = builtins.getFlake flake;
  inherit (self) inputs;
  pkgs = import inputs.nixpkgs { inherit system; config.allowUnfree = true; };
  inherit (pkgs) lib;

  # nixpkgs attribute paths as the doctor names them; anything missing or
  # failing to evaluate (broken, insecure) is left out.
  evaluates = v: (builtins.tryEval (builtins.seq (v.drvPath or null) true)).success;
  resolve = name:
    let path = lib.splitString "." name; in
    if lib.hasAttrByPath path pkgs && evaluates (lib.getAttrFromPath path pkgs)
    then [ (lib.getAttrFromPath path pkgs) ] else [ ];
  names = builtins.fromJSON packages;
  modules = builtins.fromJSON python;
  pyPackages = ps: lib.concatMap (m: lib.optional (ps ? ${m} && evaluates ps.${m}) ps.${m}) modules;
  extra = lib.concatMap resolve names
    ++ lib.optional (modules != [ ]) (pkgs.python3.withPackages pyPackages);
  # One package, above the desktop's (its python3 is low priority, so a
  # python with modules wins); collisions between the extras are ignored.
  extraEnv = pkgs.buildEnv { name = "plugin-survey-packages"; paths = extra; ignoreCollisions = true; };

  test = pkgs.testers.runNixOSTest {
    name = "omarchy-plugin-survey";
    nodes.machine = { lib, ... }: {
      imports = [
        self.nixosModules.default
        inputs.home-manager.nixosModules.home-manager
      ];
      omarchy = {
        enable = true;
        stateDir = self + "/tests/state";
        users = [ "omarchy" ];
        configDir = "/home/omarchy/nixos";
        login.autoLogin = "omarchy";
        plugins = lib.genAttrs (builtins.fromJSON registry) (_: { enable = true; });
      };
      users.users.omarchy = { isNormalUser = true; extraGroups = [ "wheel" ]; };
      security.sudo.wheelNeedsPassword = false;
      home-manager.users.omarchy = {
        home.stateVersion = "26.05";
        home.packages = lib.optional (extra != [ ]) (lib.hiPrio extraEnv);
        # Stay awake (what `omarchy toggle idle stay-awake` writes): no
        # screensaver at 150 s and no lock at 300 s in the middle of a batch,
        # which would blank the screenshots and hang grim.
        xdg.stateFile."omarchy/indicators/stay-awake".text = "";
      };
      environment.systemPackages = [ pkgs.jq ];
      # No test VLAN: one VM, and parallel drivers' VDE switches don't
      # always come up.
      virtualisation.vlans = lib.mkForce [ ];
      virtualisation.memorySize = 4096;
      virtualisation.cores = 2;
      # Room for the plugins' copies, clones and what they download (the
      # default 1 GB filled up); the image is sparse.
      virtualisation.diskSize = 8192;
      virtualisation.resolution = { x = 1920; y = 1080; };
      # The network, when the driver runs outside the sandbox: QEMU's user
      # networking on the first interface, which NetworkManager brings up.
      virtualisation.qemu.networkingOptions = lib.mkForce [
        "-net nic,netdev=user.0,model=virtio"
        "-netdev user,id=user.0,\"$QEMU_NET_OPTS\""
      ];
    };
    testScript = builtins.readFile ./runtime.py;
  };
in
{
  inherit (test) driver;

  available = pkgs.runCommand "omarchy-shell-commands" { } ''
    for d in ${test.nodes.machine.home-manager.users.omarchy.home.path}/bin \
             ${test.nodes.machine.system.path}/bin ${test.nodes.machine.system.path}/sbin; do
      [ -d "$d" ] && ls "$d"
    done | sort -u >$out
    ${lib.concatMapStrings (w: "echo ${w} >>$out\n") (lib.attrNames test.nodes.machine.security.wrappers)}
  '';
}
