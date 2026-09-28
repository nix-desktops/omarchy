# Limitless Library: the panel runs scripts/limitless-omarchy-runtime,
# which pip-installs a venv (cryptography, jsonschema and the two bundled
# wheels) under ~/.local/share/limitless-omarchy/runtime and runs its
# limitless-omarchy CLI. Pattern: the script patched to use a Python env
# built from the bundled wheels.
{ lib, fetchFromGitHub, python3 }:
let
  src = fetchFromGitHub {
    owner = "Univeracity";
    repo = "limitless-omarchy";
    rev = "6c888ae7c5e7b20ac7a4ae714a1af0a9332805c1";
    hash = "sha256-P+/Pm8bJ+ulsnbAwrt9jow4EvOu//hkAe/WL8WUj3/Q=";
  };

  wheel = pname: version: file: python3.pkgs.buildPythonPackage {
    inherit pname version;
    format = "wheel";
    src = "${src}/runtime/wheels/${file}";
    dependencies = with python3.pkgs; [ cryptography jsonschema ];
    # Pinned to cryptography 50; Nixpkgs has another release.
    dontCheckRuntimeDeps = true;
  };
  runtime = python3.withPackages (_: [
    (wheel "limitless-library" "0.1.0a0" "limitless_library-0.1.0a0-py3-none-any.whl")
    (wheel "limitless-omarchy" "0.1.1" "limitless_omarchy-0.1.1-py3-none-any.whl")
  ]);
in
{
  inherit src;
  postPatch = ''
    substituteInPlace scripts/limitless-omarchy-runtime \
      --replace-fail 'runtime_cli=$runtime/bin/limitless-omarchy' 'runtime_cli=${runtime}/bin/limitless-omarchy' \
      --replace-fail 'runtime_available() {' 'runtime_available() { [[ -x $runtime_cli ]]; }
    runtime_available_upstream() {' \
      --replace-fail 'setup_runtime() {' 'setup_runtime() { :; }
    setup_runtime_upstream() {'
  '';
  meta.description = "Limitless Library adapter (its runtime: the bundled wheels with cryptography and jsonschema)";
}
