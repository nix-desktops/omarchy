# Nanit: baby camera. Every command goes through <plugin>/bin/nanit, which
# runs bin/nanit.py from a venv at ~/.local/share/omarchy-nanit/venv that
# `nanit setup` fills with pip (aionanit, a Nanit cloud client nixpkgs
# lacks). Pattern: a Python env where the plugin expects its venv.
{ fetchFromGitHub, fetchPypi, python3 }:
let
  aionanit = python3.pkgs.buildPythonPackage rec {
    pname = "aionanit";
    version = "1.12.2";
    format = "wheel";
    src = fetchPypi {
      inherit pname version;
      format = "wheel";
      dist = "py3";
      python = "py3";
      hash = "sha256-kLwgRB0HQyXmj1McGJimYBEobFKtegzLnaKTdjZ9Gt4=";
    };
    dependencies = [ python3.pkgs.aiohttp python3.pkgs.protobuf ];
    pythonImportsCheck = [ "aionanit" ];
  };
in
{
  src = fetchFromGitHub {
    owner = "GruperTal";
    repo = "omarchy-nanit";
    rev = "add8665407c6b31bfae9e4de70da28f8a9ba3c96";
    hash = "sha256-ozqI9j9QGKUaD1Bcpe3yfSm44fOLnCRS6UA16a5WFNQ=";
  };
  home.".local/share/omarchy-nanit/venv" = python3.withPackages (ps: [ ps.aiohttp ps.protobuf aionanit ]);
  meta.description = "Nanit camera (its venv: python3 with aiohttp and aionanit)";
}
