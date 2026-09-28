# OmaYap: reads text aloud with Piper. Service.qml runs its worker with
# ~/.local/share/omayap-read-aloud/venv/bin/python, which bin/setup creates
# with uv (Python 3.13, piper-tts, onnxruntime, OpenVINO) before downloading
# the default voice. Pattern: a Python env where the plugin expects its
# venv, and bin/setup patched to use it; run bin/setup once for the voice
# and the F10 binds, as upstream says. OpenVINO (an optional faster path) is
# left out.
{ fetchFromGitHub, python3, piper-tts, wtype, pipewire, wl-clipboard, tesseract }:
let
  src = fetchFromGitHub {
    owner = "Ray-4Ws";
    repo = "OmaYap";
    rev = "f9ac24b2245f9217a0e7208186b731db8b60543d";
    hash = "sha256-GCBC/m8O+MSfy5niNOnnpLl/oUMK3RHWlf1OMP4bWac=";
  };
  piper = python3.pkgs.toPythonModule (piper-tts.override {
    withTrain = false;
    withHTTP = false;
    withAlignment = false;
  });
in
{
  inherit src;
  postPatch = ''
    sed -i '/^  uv python install 3.13/,/could not disable OpenVINO telemetry"$/c\  [[ -x "$VENV/bin/python" ]] || die "the Nix Python env is missing at $VENV"' bin/setup
    grep -q 'the Nix Python env is missing' bin/setup
    ! grep -q 'uv pip sync' bin/setup
  '';
  home.".local/share/omayap-read-aloud/venv" = python3.withPackages (ps: [ piper ps.onnxruntime ps.numpy ps.pathvalidate ]);
  # Typing, playback, the clipboard, OCR (bin/capture-ocr).
  packages = [ wtype pipewire wl-clipboard tesseract ];
  meta.description = "Read aloud with Piper (its venv: python3 with piper-tts and onnxruntime)";
}
