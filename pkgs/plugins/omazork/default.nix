# Omazork: Z-machine games in an overlay. Service.qml runs
# scripts/bootstrap.sh on every launch, which downloads the Go engine
# release into bin/omazork (or builds it with go) unless its checksum
# matches; the engine is built here (Go 1.27, nixos-unstable's) and the
# bootstrap told to keep it. Pattern: a helper inside the plugin's tree and
# a download step patched out.
{ lib, fetchFromGitHub, omarchyUnstable }:
let
  src = fetchFromGitHub {
    owner = "lucasbertoni";
    repo = "omazork";
    rev = "4e11e347025f51eb55b1455d86b0f407c9f35985";
    hash = "sha256-3qyoVybt44uyf3QgsAzm3HoqoSyzVtoxL+gYRCht71s=";
  };

  buildGoModule = omarchyUnstable.buildGoModule.override { go = omarchyUnstable.go_1_27; };
  omazork = buildGoModule {
    pname = "omazork";
    version = "0-unstable-4e11e34";
    inherit src;
    vendorHash = "sha256-1htrKGLUKDeS1DepqGKbJRGC+BibDKMU6kaVox0YbrQ=";
    subPackages = [ "cmd/omazork" ];
    meta.mainProgram = "omazork";
  };
in
{
  inherit src;
  helpers."bin/omazork" = lib.getExe omazork;
  postPatch = ''
    substituteInPlace scripts/bootstrap.sh \
      --replace-fail 'mkdir -p bin' 'mkdir -p bin; [ -x bin/omazork ] && exit 0 # Nix-built'
  '';
  meta.description = "Z-machine games (the omazork engine built from cmd/omazork)";
}
