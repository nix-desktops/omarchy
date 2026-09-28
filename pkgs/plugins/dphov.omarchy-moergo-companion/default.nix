# MoErgo Companion: a Glove80 panel whose four Rust helpers (keymap-parser/:
# keymap parsing, watcher, settings, status) run from <plugin>/bin, which
# install.sh --ensure fills by downloading a release or with cargo. With
# the four in bin/ it only checks they're there. Pattern: helpers inside
# the plugin's tree.
{ lib, fetchFromGitHub, rustPlatform, glib, zenity, wl-clipboard }:
let
  src = fetchFromGitHub {
    owner = "dphov";
    repo = "omarchy-moergo-companion";
    rev = "e0eef700963f3e9dcef0d2cee090d976d0ba0314";
    hash = "sha256-nqWEVaHVcO14gqoWWKkRZlTCkxQKvcR9GDThdbFx8nQ=";
  };

  keymap-parser = rustPlatform.buildRustPackage {
    pname = "omarchy-moergo-keymap-parser";
    version = "0.1.0-unstable-e0eef70";
    inherit src;
    sourceRoot = "${src.name}/keymap-parser";
    # Needs a user runtime directory (/run/user/<uid>) the sandbox lacks.
    checkFlags = [ "--skip=test_get_runtime_dir_resolves_and_validates" ];
    cargoHash = "sha256-PEKtYsocl8ZC6ZnPu0T/EJzsHUxIT/vMU3ZlReMnNGM=";
  };
in
{
  inherit src;
  helpers = lib.genAttrs'
    [ "omarchy-moergo-keymap-parser" "moergo-watcher" "moergo-companion-settings" "glove80-status" ]
    (name: lib.nameValuePair "bin/${name}" "${keymap-parser}/bin/${name}");
  # gdbus (the keyboard over Bluetooth), zenity (dialogs), wl-copy.
  packages = [ glib zenity wl-clipboard ];
  meta.description = "Glove80 companion (its four helpers built from keymap-parser/)";
}
