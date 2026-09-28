# The registry of packaged community plugins: every
# pkgs/plugins/<manifest id>/default.nix (see README.md there). Found by
# reading this directory, so adding a plugin touches no shared file.
#
#   ids                     the plugin ids (no Nixpkgs needed)
#   entries { pkgs, … }     id → the entry, normalised (below)
#   packages { pkgs, … }    id → the plugin built with its helpers (lib.mkPlugin)
#
# An entry file is called like a package (lib.callPackageWith: it asks for
# what it needs by name) with Nixpkgs 26.05 plus:
#   omarchyUnstable   nixos-unstable's Nixpkgs: Quickshell's Qt
#                     (omarchyUnstable.kdePackages.*) and Hyprland's world
#   hyprland          the Hyprland the desktop runs (the NixOS module's
#                     programs.hyprland.package), for compositor plugins
#   mkHyprlandPlugin  nixpkgs' hyprlandPlugins.mkHyprlandPlugin against
#                     that Hyprland
#   mkPlugin          lib.mkPlugin (rarely needed: the registry builds it)
{ lib }:
let
  inherit (builtins) readDir pathExists;

  ids = lib.attrNames (lib.filterAttrs
    (id: type: type == "directory" && pathExists (./. + "/${id}/default.nix"))
    (readDir ./.));

  normalise = id: e:
    assert lib.assertMsg (e ? src) "pkgs/plugins/${id}: an entry needs `src`";
    {
      inherit id;
      inherit (e) src;
      version = e.version or null;
      helpers = e.helpers or { };
      home = e.home or { };
      packages = e.packages or [ ];
      patches = e.patches or [ ];
      postPatch = e.postPatch or "";
      hyprlandPlugins = e.hyprlandPlugins or [ ];
      hyprlandConfig = e.hyprlandConfig or "";
      qmlModules = e.qmlModules or [ ];
      section = e.section or null;
      meta = e.meta or { };
    };

  entries = { pkgs, omarchyUnstable, hyprland ? omarchyUnstable.hyprland, omarchySrc }:
    let
      mkHyprlandPlugin = (omarchyUnstable.hyprlandPlugins.override { inherit hyprland; }).mkHyprlandPlugin;
      mkPlugin = pkgs.callPackage ../plugin.nix { inherit omarchySrc; };
      call = lib.callPackageWith (pkgs // { inherit omarchyUnstable hyprland mkHyprlandPlugin mkPlugin; });
    in
    lib.genAttrs ids (id: normalise id (call (./. + "/${id}/default.nix") { }));

  build = pkgs: omarchySrc: e:
    let mkPlugin = pkgs.callPackage ../plugin.nix { inherit omarchySrc; };
    in (mkPlugin {
      inherit (e) id src version patches postPatch helpers;
    }).overrideAttrs (old: {
      # `nix build .#plugins.<id>.home`: the home links' targets, as a tree
      # laid out like the home.
      passthru = old.passthru // {
        entry = e;
        home = pkgs.linkFarm "omarchy-plugin-${e.id}-home"
          (lib.mapAttrsToList (name: path: { inherit name path; }) e.home);
      };
    });
in
{
  inherit ids entries build;

  packages = args@{ pkgs, omarchySrc, ... }:
    lib.mapAttrs (_: build pkgs omarchySrc) (entries args);

  # For installers (lib.plugins): the registry as data.
  data = args:
    lib.mapAttrs (id: e: {
      inherit id;
      url = e.src.gitRepoUrl or e.src.url or null;
      rev = e.src.rev or null;
      hash = e.src.outputHash or null;
      description = e.meta.description or null;
      helpers = lib.attrNames e.helpers;
      home = lib.attrNames e.home;
      packages = map lib.getName e.packages;
      hyprlandPlugins = map lib.getName e.hyprlandPlugins;
      qmlModules = map lib.getName e.qmlModules;
    }) (entries args);
}
