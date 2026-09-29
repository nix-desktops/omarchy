# OmaKindle: Kindle highlights. Service.qml runs
# ~/.local/lib/omakindle/omakindle-backend (Rust, backend/: wreq, a
# browser-like TLS stack on BoringSSL), which scripts/backend.sh builds
# there, and signs in with `uv run --locked scripts/authorize.py`
# (Playwright driving the installed browser). Built with nixos-unstable's
# Rust (it asks for 1.98), and the sign-in run with a Python that has
# Playwright. Pattern: a link in the home, and a uv step patched to a store
# path.
{ lib, fetchFromGitHub, omarchyUnstable, cmake, go, perl, git, python3 }:
let
  src = fetchFromGitHub {
    owner = "minholi";
    repo = "omakindle";
    rev = "459bf1c71d21d16ccdaf0c059d4960634395db5f";
    hash = "sha256-uJFecdeOR/zWXvAp5SKx5BEZ5QkhM/Gc6Md7uFeHNHU=";
  };

  backend = omarchyUnstable.rustPlatform.buildRustPackage {
    pname = "omakindle-backend";
    version = "0-unstable-459bf1c";
    inherit src;
    sourceRoot = "${src.name}/backend";
    cargoHash = "sha256-TOatfmMcqWvz2kafls2RkiOHn0p3G8spdKCbAFTp1RQ=";
    # BoringSSL (btls-sys) builds with CMake, Go and Perl, bindgen, and
    # git to apply its patches.
    nativeBuildInputs = [ cmake go perl git omarchyUnstable.rustPlatform.bindgenHook ];
    dontUseCmakeConfigure = true;
    meta.mainProgram = "omakindle-backend";
  };
  python = python3.withPackages (ps: [ ps.playwright ]);
in
{
  inherit src;
  home.".local/lib/omakindle/omakindle-backend" = lib.getExe backend;
  postPatch = ''
    substituteInPlace Service.qml \
      --replace-fail '"uv", "run", "--locked", "--quiet",' '"${python.interpreter}",'
  '';
  meta.description = "Kindle highlights (its backend built from backend/, sign-in with Playwright)";
}
