# Google TV Remote: services/RemoteService.qml runs bin/google-tv-remote,
# which builds a venv with pip on first run and execs the plugin's own
# Python backend (src/google_tv_remote). Pattern: the launcher replaced by
# the backend built with Nix.
{ lib, fetchFromGitHub, python3Packages }:
let
  src = fetchFromGitHub {
    owner = "AdrianKlm";
    repo = "omagoogletv";
    rev = "6705366472b8b1116439b0c44f07c06f93c2b54d";
    hash = "sha256-vJoVtekyW+FEiSlclvjmqMaejoJj/aFEb7ykPcuk87k=";
  };

  backend = python3Packages.buildPythonApplication {
    pname = "google-tv-remote";
    version = "0.1.0-unstable-6705366";
    pyproject = true;
    inherit src;
    build-system = [ python3Packages.setuptools ];
    dependencies = with python3Packages; [ androidtvremote2 zeroconf ];
    # Pinned exactly upstream; nixpkgs' are a patch release apart.
    pythonRelaxDeps = true;
    pythonImportsCheck = [ "google_tv_remote" ];
    meta.mainProgram = "google-tv-remote";
  };
in
{
  inherit src;
  helpers."bin/google-tv-remote" = lib.getExe backend;
  meta.description = "Google TV remote (its Python backend built with Nix instead of the venv)";
}
