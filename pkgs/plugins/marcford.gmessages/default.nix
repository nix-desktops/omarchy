# Google Messages: GmClient.qml starts gmessagesd.service (systemctl --user)
# and talks to the Go daemon over a socket; `make install` puts it at
# ~/.local/bin/gmessagesd with the unit. go.mod wants Go 1.27. Pattern: the
# daemon built with Nix and its user unit linked into the home.
{ lib, fetchFromGitHub, buildGoModule, go_1_27, coreutils, runCommand }:
let
  src = fetchFromGitHub {
    owner = "MarcFord";
    repo = "gmessages-omarchy-plugin";
    rev = "ec821ce86c09b1a1107ed9feeceb252322ce951b";
    hash = "sha256-DQJx8Ir2th/D2FjO7TfuDJeMn6UpUWqjfq7Yk4WbX6I=";
  };

  gmessagesd = (buildGoModule.override { go = go_1_27; }) {
    pname = "gmessagesd";
    version = "0-unstable-ec821ce";
    inherit src;
    vendorHash = "sha256-7rXWjhI7lOrWoHhIWUyFyDajncv4JyifcgBF6capN64=";
    subPackages = [ "cmd/gmessagesd" ];
    meta.mainProgram = "gmessagesd";
  };

  # systemd/gmessagesd.service with the store's daemon, and the data dir
  # its ReadWritePaths= needs made first (`make install` does that).
  service = runCommand "gmessagesd.service" { } ''
    substitute ${src}/systemd/gmessagesd.service $out \
      --replace-fail 'ExecStart=%h/.local/bin/gmessagesd' \
        'ExecStartPre=+${coreutils}/bin/mkdir -p %h/.local/share/gmessages-omarchy
    ExecStart=${lib.getExe gmessagesd}'
  '';
in
{
  inherit src;
  home.".local/bin/gmessagesd" = lib.getExe gmessagesd;
  home.".config/systemd/user/gmessagesd.service" = service;
  meta.description = "Google Messages (gmessagesd built from cmd/gmessagesd, its user unit linked)";
}
