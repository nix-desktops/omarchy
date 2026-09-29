# Google Notes: Google Keep lists. Panel.qml runs bin/notes-helper (Python),
# which needs gkeepapi and gpsoauth and pip-installs them into a venv under
# its state dir when asked; with them importable it uses its own
# interpreter. gkeepapi isn't in Nixpkgs (pure Python, built here). Pattern:
# the script's interpreter pointed at a Python env.
{ lib, fetchFromGitHub, fetchPypi, python3 }:
let
  src = fetchFromGitHub {
    owner = "M0ebiu5";
    repo = "omarchy-google-notes";
    rev = "4ed5a2acf668c1cc6ac6b3c21a9504304d3fc977";
    hash = "sha256-NlOR7J8qLM5qfaSm0ObEFSy+3xqnn6S6YKZalXBK/jM=";
  };

  # Only a wheel on PyPI. It lists `future`, which it never imports (and
  # which doesn't build for Python 3.13).
  gkeepapi = python3.pkgs.buildPythonPackage rec {
    pname = "gkeepapi";
    version = "0.17.1";
    format = "wheel";
    src = fetchPypi {
      inherit pname version format;
      dist = "py3";
      python = "py3";
      hash = "sha256-jiQrx0VkDICdIes/lccYKsNAqMwrhOXXi51pLCwtNdw=";
    };
    dependencies = [ python3.pkgs.gpsoauth ];
    pythonRemoveDeps = [ "future" ];
    pythonImportsCheck = [ "gkeepapi" ];
  };
  python = python3.withPackages (ps: [ gkeepapi ps.gpsoauth ]);
in
{
  inherit src;
  postPatch = ''
    substituteInPlace bin/notes-helper \
      --replace-fail '#!/usr/bin/env python3' '#!${python.interpreter}'
  '';
  meta.description = "Google Keep lists (notes-helper with gkeepapi and gpsoauth)";
}
