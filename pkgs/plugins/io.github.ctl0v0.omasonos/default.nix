# OmaSonos: Sonos control. Service.qml runs <plugin>/sonos-backend, which
# creates a venv in ~/.local/share and pip-installs SoCo (requirements.lock)
# before starting sonos_service.py; it wants Python 3.14. Pattern: the
# launcher patched to run a Nix Python env.
{ lib, fetchFromGitHub, python314 }:
let
  src = fetchFromGitHub {
    owner = "ctl0v0";
    repo = "omasonos";
    rev = "fa098ac4c24b1732fd120a93c83491cd4b73f0ab";
    hash = "sha256-rxoEPGGTCTex/q3sOGbFFPVJ4DNATETJs48V/8w2yAo=";
  };
  python = python314.withPackages (ps: [ ps.soco ps.requests ]);
in
{
  inherit src;
  postPatch = ''
    substituteInPlace sonos-backend \
      --replace-fail 'PYTHON_BIN="''${OMASONOS_PYTHON:-python3}"' \
        'exec ${lib.getExe python} -u "$PLUGIN_DIR/sonos_service.py"'
  '';
  meta.description = "Sonos control (sonos-backend runs python 3.14 with SoCo)";
}
