# Omarchy's Neovim config (omarchy-nvim): the LazyVim starter with
# Omarchy's options, theme hot-reload and transparency, as its PKGBUILD
# assembles it. It's a config, not a program: the Home Manager module seeds
# ~/.config/nvim from share/omarchy-nvim/config once, and lazy.nvim fetches
# the plugins on first start (Omarchy's Arch package pre-fetches them at
# build time, which a Nix build can't).
{ lib, stdenvNoCC, inputs }:
let
  pkgbuild = "${inputs.omarchy-pkgs}/pkgbuilds/omarchy-nvim";
in
stdenvNoCC.mkDerivation {
  pname = "omarchy-nvim";
  version = lib.removePrefix "pkgver=" (lib.findFirst (lib.hasPrefix "pkgver=") "pkgver=0"
    (lib.splitString "\n" (builtins.readFile "${pkgbuild}/PKGBUILD")));
  src = inputs.lazyvim-starter;

  installPhase = ''
    runHook preInstall
    config=$out/share/omarchy-nvim/config
    mkdir -p $config
    cp -r . $config/
    rm -rf $config/.git
    cp -r ${pkgbuild}/lua ${pkgbuild}/plugin $config/
    cp ${pkgbuild}/lazyvim.json $config/
    chmod -R u+w $config
    runHook postInstall
  '';

  meta = {
    description = "Omarchy's LazyVim-based Neovim configuration";
    homepage = "https://github.com/omacom/omarchy-pkgs/tree/master/pkgbuilds/omarchy-nvim";
    license = lib.licenses.mit;
  };
}
