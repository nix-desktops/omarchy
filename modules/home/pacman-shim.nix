# `pacman` (with expac and vercmp) for shell plugins written for Arch:
# the query forms they use (pacman -Q, -Qq, -Qi, -Qo, -Ql, -Qe/-Qm/-Qn,
# versioned -Q "<pkg>>=<ver>", -T; expac -Q), answered from the NixOS
# system and the user's profiles (pkgs/pacman-shim). Upstream's own menu
# needs it too: its guards (MenuModel.js guardHelpers) ask `pacman -Qq` and
# `pacman -Qi` for what's installed. Installs and updates fail with what to
# add to the configuration instead.
{ inputs }:
{ config, lib, pkgs, osConfig ? null, ... }:
let
  cfg = config.omarchy;
  shim = pkgs.callPackage ../../pkgs/pacman-shim {
    omarchyVersion = lib.removeSuffix "\n" (builtins.readFile (inputs.omarchy + "/version"));
  };

  # Name, version, description, homepage and licenses of the declared
  # packages, for `pacman -Qi` (store paths only carry name and version).
  discard = builtins.unsafeDiscardStringContext;
  str = s: if builtins.isString s then discard s else "";
  metaOf = p:
    let
      m = p.meta or { };
      home = m.homepage or "";
      x = {
        name = str (p.name or "");
        pname = str (p.pname or (builtins.parseDrvName (p.name or "")).name);
        description = str (m.description or "");
        homepage = str (if builtins.isList home then (if home == [ ] then "" else builtins.head home) else home);
        license = map (l: str (if builtins.isString l then l else l.spdxId or l.shortName or "")) (lib.toList (m.license or [ ]));
      };
      r = builtins.tryEval (builtins.deepSeq x x);
    in if r.success then [ r.value ] else [ ];
  declared = config.home.packages
    ++ lib.optionals (osConfig != null) (osConfig.environment.systemPackages or [ ]);
in
{
  options.omarchy.pacmanShim.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      A `pacman` (with `expac` and `vercmp`) that answers the package
      queries shell plugins and upstream's menu make, from the NixOS system:
      `pacman -Q[q] [pkg…]` (exit status per package), `-Qi` (pacman's
      format, with Provides), versioned `-Q "pkg>=1.2"`, `-Qe/-Qd/-Qm/-Qn`,
      `-Qo <file>`, `-Ql <pkg>`, `-Qs`, `-T`, `expac -Q`. Installed means
      what /run/current-system/sw, the user's profiles and the system's
      closure hold, by store path name; Arch names are mapped
      (data/arch-packages.json: python-foo, qt6-base, brave-bin, …), and a
      name that is also a command on PATH counts. Installs, removals,
      updates and repository queries (-S, -R, -U, -Si, -Ss, -Qu) fail with
      what to add to the configuration instead. On PATH, and at
      /usr/bin/pacman through envfs (`omarchy.envfs.enable`).
    '';
  };

  config = lib.mkIf (cfg.enable && cfg.pacmanShim.enable) {
    # Low priority: nixpkgs' real pacman, when installed, wins.
    home.packages = [ (lib.lowPrio shim) ];
    xdg.dataFile."omarchy-pacman/declared.json".text = builtins.toJSON (lib.concatMap metaOf declared);
  };
}
