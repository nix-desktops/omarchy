# Omacapture: the capture and annotation editor is a Rust GTK4 app; the
# service looks for `omacapture` in ~/.cargo/bin, ~/.local/bin, … then PATH,
# and keeps its daemon running. Pattern: a package on PATH.
{ lib, fetchFromGitHub, rustPlatform, pkg-config, wrapGAppsHook4, gtk4, libadwaita
, gtk4-layer-shell, grim, wl-clipboard, tesseract, libcanberra-gtk3, xdg-utils }:
let
  src = fetchFromGitHub {
    owner = "diyahir";
    repo = "omacapture";
    rev = "99b9a658ec5d421a2d7deee587184ecec8e5fd11";
    hash = "sha256-bHz8IcaMUAw7DYkCMLTy0pAszr6a97ClkEjNfhJrYh0=";
  };

  omacapture = rustPlatform.buildRustPackage {
    pname = "omacapture";
    version = "0.1.0-unstable-99b9a65";
    inherit src;
    cargoHash = "sha256-bQP/9o3ksTOquDcLkQ2+e8dMaJYeajhHhoPavOPHDEE=";
    nativeBuildInputs = [ pkg-config wrapGAppsHook4 ];
    buildInputs = [ gtk4 libadwaita gtk4-layer-shell ];
    # Needs a display.
    checkFlags = [ "--skip=annotate::canvas::tests::editor_gestures" ];
    # grim, wl-copy, tesseract, canberra-gtk-play, xdg-open.
    preFixup = ''
      gappsWrapperArgs+=(--prefix PATH : ${lib.makeBinPath [ grim wl-clipboard tesseract libcanberra-gtk3 xdg-utils ]})
    '';
    meta.mainProgram = "omacapture";
  };
in
{
  inherit src;
  packages = [ omacapture ];
  meta.description = "Screenshot capture and annotation (omacapture built from the repo, on PATH)";
}
