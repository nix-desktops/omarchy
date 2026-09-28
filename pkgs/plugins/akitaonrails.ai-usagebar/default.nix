# AI Usage: a panel over the ai-usagebar CLI (Rust, the repo's own crate),
# which Panel.qml runs from PATH (`/usr/bin/env ai-usagebar usage --json`).
# Pattern: a package on PATH.
{ lib, fetchFromGitHub, rustPlatform, makeWrapper, nasm, procps, xdg-utils }:
let
  src = fetchFromGitHub {
    owner = "akitaonrails";
    repo = "ai-usagebar";
    rev = "9e871950a4bfd7bf244ab4171647fdbe04089075";
    hash = "sha256-DygZ69qCFTkXzT/C8cVh8AcleGs674e1NR7+jVSEKzM=";
  };

  ai-usagebar = rustPlatform.buildRustPackage {
    pname = "ai-usagebar";
    version = "1.26.0-unstable-9e87195";
    inherit src;
    cargoHash = "sha256-V7pV5oIayurOVY5gM+L3N16hS2SXNvZBpu8FvGgvyz8=";
    nativeBuildInputs = [ nasm makeWrapper ];
    # As upstream's nix/package.nix: these run /usr/bin/tar.
    checkFlags = [ "--skip=claude_desktop::app::tests" ];
    postInstall = ''
      rm -f $out/bin/ai-usagebar-tray
      for p in ai-usagebar ai-usagebar-tui; do
        wrapProgram $out/bin/$p --prefix PATH : ${lib.makeBinPath [ procps xdg-utils ]}
      done
    '';
    meta.mainProgram = "ai-usagebar";
  };
in
{
  inherit src;
  packages = [ ai-usagebar ];
  meta.description = "AI plan usage panel (ai-usagebar built from the repo, on PATH)";
}
