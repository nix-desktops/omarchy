# Home Assistant: light controls. The widget talks to a Python controller
# (controller/, aiohttp + keyring) over $XDG_RUNTIME_DIR/omarchy-ha/controller.sock;
# controller/install.sh makes it a systemd user unit from a venv, puts
# hass-cli in ~/.local/share/omarchy-home-assistant/hass-cli-venv and links
# bin/omarchy-ha into ~/.local/bin. Pattern: a user unit and links in the
# home.
{ lib, runCommand, fetchFromGitHub, python3, home-assistant-cli }:
let
  src = fetchFromGitHub {
    owner = "iuliansafta";
    repo = "omarchy-home-assistant-bar";
    rev = "4638b5e9cdf6d0912220ebea43f308a2dc5f9024";
    hash = "sha256-ck07U3kbOw69x4azmNBWWyBJJZo2c6mKq6/RqtjhZCM=";
  };

  python = python3.withPackages (ps: [ ps.aiohttp ps.keyring ]);
  # The unit as install.sh renders it (its own renderer).
  unit = runCommand "omarchy-home-assistant.service" { } ''
    bash ${src}/controller/render_systemd_unit.sh \
      ${python.interpreter} ${src}/controller/omarchy_ha_controller.py > $out
  '';
in
{
  inherit src;
  home.".config/systemd/user/omarchy-home-assistant.service" = unit;
  home.".config/systemd/user/graphical-session.target.wants/omarchy-home-assistant.service" = unit;
  home.".local/share/omarchy-home-assistant/hass-cli-venv" = home-assistant-cli;
  home.".local/bin/omarchy-ha" = "${src}/bin/omarchy-ha";
  meta.description = "Home Assistant lights (its controller as a user unit, hass-cli)";
}
