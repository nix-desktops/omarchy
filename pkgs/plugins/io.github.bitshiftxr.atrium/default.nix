# Atrium: a Home Assistant panel. Its daemon (Rust, daemon/) holds the
# websocket; Service.qml runs it as <plugin>/bin/atriumd, which upstream's
# `setup` builds with cargo. Pattern: a helper inside the plugin's tree.
{ lib, fetchFromGitHub, rustPlatform, libsecret }:
let
  src = fetchFromGitHub {
    owner = "bitshiftxr";
    repo = "atrium";
    rev = "d54e28559e974f8b90cf53a44903b14efe1173e2";
    hash = "sha256-NlC1VsEbQJ9L5S8A7viUSBAGSobi7xXnizc0yljQD9Y=";
  };

  atriumd = rustPlatform.buildRustPackage {
    pname = "atriumd";
    version = "0.1.0-unstable-d54e285";
    inherit src;
    sourceRoot = "${src.name}/daemon";
    cargoHash = "sha256-KJb5MCjCYKrtkb/9albQTtU1sO9RuEdqyjm/n4+6mM0=";
    # The token is kept with secret-tool, looked up at /usr/bin with
    # PATH=/usr/bin:/bin: point it at the store.
    postPatch = ''
      substituteInPlace src/keyring.rs \
        --replace-fail '"/usr/bin/secret-tool"' '"${libsecret}/bin/secret-tool"'
    '';
    meta.mainProgram = "atriumd";
  };
in
{
  inherit src;
  helpers."bin/atriumd" = lib.getExe atriumd;
  meta.description = "Home Assistant panel (atriumd built from daemon/)";
}
