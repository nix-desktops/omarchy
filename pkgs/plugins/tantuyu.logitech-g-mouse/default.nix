# Logitech G Mouse: DPI, battery and profiles over HID++. Service.qml runs
# <plugin>/bin/logitech-g-daemon, a Rust daemon shipped prebuilt
# (glibc-dynamic: it'd need nix-ld). Built from the repo's crate instead.
# It opens /dev/hidraw*, which needs the user to have access (uaccess or a
# udev rule, as upstream's README says). Pattern: a helper inside the
# plugin's tree, replacing a shipped binary.
{ lib, fetchFromGitHub, rustPlatform }:
let
  src = fetchFromGitHub {
    owner = "ttymayor";
    repo = "oma-logitech-g-mouse";
    rev = "c425241cb1e8fddfcc2cebb2eb3e5c1acd13a435";
    hash = "sha256-OdW3cRCZZQCdrZsuUk2ldB1WWWoyUA5WdPFf9ekeTz8=";
  };

  daemon = rustPlatform.buildRustPackage {
    pname = "logitech-g-daemon";
    version = "0.2.0-unstable-c425241";
    inherit src;
    cargoHash = "sha256-7uWuzx82hf5WOF44FIHRiqYkc6uWXU3l9GuvqD2fdeQ=";
    meta.mainProgram = "logitech-g-daemon";
  };
in
{
  inherit src;
  helpers."bin/logitech-g-daemon" = lib.getExe daemon;
  meta.description = "Logitech G mice (logitech-g-daemon built from source)";
}
