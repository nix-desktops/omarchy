# OmaSpotify: browsing and remote control work through the Web API; local
# playback is a librespot backend run as a user unit. playback-runtime.sh
# accepts it when ~/.local/lib/omaspotify holds the binary with its source
# id and hash, and ~/.config/systemd/user/omaspotify.service is what
# render-unit.sh prints (made $HOME-free with systemd's %h here).
# Pattern: links in the home.
{ lib, fetchFromGitHub, rustPlatform, runCommand, writeText, pkg-config, openssl, libpulseaudio, alsa-lib, dbus }:
let
  src = fetchFromGitHub {
    owner = "jeremylanger";
    repo = "omaspotify";
    rev = "2de4676b23bf9e7e3a5b17a83ba7c28672a19a79";
    hash = "sha256-Gnt8cXgFqnVo6QbrILsJSMN1+Sbzau3Jfl5Dgv1qutw=";
  };

  backend = rustPlatform.buildRustPackage {
    pname = "omaspotify-backend";
    version = "2.0.1-unstable-2de4676";
    inherit src;
    sourceRoot = "${src.name}/backend";
    cargoHash = "sha256-zfIrboiW+/2Q/iHR3aI6GhjrsqHLBnsytjQin6YPml4=";
    nativeBuildInputs = [ pkg-config ];
    buildInputs = [ openssl libpulseaudio alsa-lib dbus ];
    meta.mainProgram = "omaspotify-backend";
  };

  # What scripts/backend-source-id.sh computes over the plugin's files.
  sourceId = runCommand "omaspotify-backend-source.sha256" { } ''
    cd ${src}
    export LC_ALL=C
    files=(backend/Cargo.toml backend/Cargo.lock rust-toolchain.toml backend/src/*.rs)
    sha256sum -- "''${files[@]}" | sha256sum | cut -d' ' -f1 > $out
  '';
  binaryHash = runCommand "omaspotify-backend-binary.sha256" { } ''
    sha256sum ${lib.getExe backend} | cut -d' ' -f1 > $out
  '';
  unit = runCommand "omaspotify.service" { } ''
    sed -e 's|@BACKEND_BINARY@|%h/.local/lib/omaspotify/omaspotify-backend|g' \
        -e 's|@CONFIG_FILE@|%h/.config/omaspotify/playback.conf|g' \
        ${src}/systemd/omaspotify.service > $out
  '';
in
{
  inherit src;
  postPatch = ''
    # Spotify Connect's cipher dlopens libcrypto by soname.
    substituteInPlace scripts/spotify-connect-device.py \
      --replace-fail 'ctypes.CDLL("libcrypto.so.3")' 'ctypes.CDLL("${lib.getLib openssl}/lib/libcrypto.so.3")'
    substituteInPlace scripts/render-unit.sh \
      --replace-fail 'runtime_dir=''${OMASPOTIFY_RUNTIME_DIR:-"$HOME/.local/lib/omaspotify"}' 'runtime_dir=%h/.local/lib/omaspotify' \
      --replace-fail 'config_root=''${XDG_CONFIG_HOME:-"$HOME/.config"}' 'config_root=%h/.config'
  '';
  home = {
    ".local/lib/omaspotify/omaspotify-backend" = lib.getExe backend;
    ".local/lib/omaspotify/backend-source.sha256" = sourceId;
    ".local/lib/omaspotify/backend-binary.sha256" = binaryHash;
    ".config/systemd/user/omaspotify.service" = unit;
  };
  meta.description = "Spotify panel (the librespot playback backend built from backend/, as a user unit)";
}
