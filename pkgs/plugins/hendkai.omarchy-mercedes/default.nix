# Mercedes SoC: the bar widget reads ~/.local/state/omarchy-mercedes/status.json,
# which the connector daemon (the repo's Python package, `omarchy-mercedes
# daemon`) writes; install.sh pip-installs it to ~/.local and enables its
# systemd user unit, which runs ~/.local/bin/omarchy-mercedes. Pattern: a
# Python application linked in the home, with its user unit.
{ lib, fetchFromGitHub, python3 }:
let
  src = fetchFromGitHub {
    owner = "hendkai";
    repo = "omarchy-mercedes";
    rev = "1d746d2f2be6641f7f79a1816146d0e0fb0ecade";
    hash = "sha256-yFfFIksw6BamMwQ/L9hL+DTEwE6DBbBItBgc1AdbYPI=";
  };

  omarchy-mercedes = python3.pkgs.buildPythonApplication {
    pname = "omarchy-mercedes";
    version = "0.1.1-unstable-1d746d2";
    inherit src;
    pyproject = true;
    # Its build system is pinned exactly too.
    postPatch = ''
      substituteInPlace pyproject.toml \
        --replace-fail '"setuptools==80.9.0", "wheel==0.45.1"' '"setuptools"'
    '';
    build-system = [ python3.pkgs.setuptools ];
    dependencies = with python3.pkgs; [ requests protobuf keyring ];
    # Exact pins (requests 2.34.2, protobuf 7.36.1): Nixpkgs' are close.
    pythonRelaxDeps = true;
    pythonImportsCheck = [ "omarchy_mercedes" ];
    meta.mainProgram = "omarchy-mercedes";
  };
in
{
  inherit src;
  home.".local/bin/omarchy-mercedes" = lib.getExe omarchy-mercedes;
  # Enabled as install.sh does; it waits for `omarchy-mercedes login`.
  userServices."omarchy-mercedes.service" = "${src}/systemd/omarchy-mercedes.service";
  packages = [ omarchy-mercedes ]; # `omarchy-mercedes status` from the widget
  meta.description = "Mercedes state of charge (the omarchy-mercedes connector and its user unit)";
}
