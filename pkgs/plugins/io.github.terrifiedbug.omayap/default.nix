# OmaYap: on-device dictation and meeting transcription (sherpa-onnx). Its
# daemon runs from a venv at ~/.local/share/omayap/venv with speech models
# in models/, all made by setup.sh (pip, two downloads, a user unit,
# ~/.local/bin/omayap). bin/omayap runs the daemon with that venv's python,
# checking it's the user's own. Pattern: a Python env instead of the venv
# (bin/omayap patched to it), the models fetched by Nix and linked where
# setup.sh puts them, the user unit (userServices).
{ lib, stdenvNoCC, fetchFromGitHub, fetchurl, writeText, python3
, pipewire, pulseaudio, wl-clipboard, systemd }:
let
  src = fetchFromGitHub {
    owner = "TerrifiedBug";
    repo = "omayap";
    rev = "29e33ae5cdbc9c84c34a88e4320e542eeb3f99a6";
    hash = "sha256-yrLeqZ61LVx8r5kJizm/lhruPZxQHUFWffAJR1EAcwY=";
  };

  python = python3.withPackages (ps: [ ps.sherpa-onnx ]);

  # setup.sh's pinned model (its sha256) and what it extracts from it.
  parakeet = stdenvNoCC.mkDerivation {
    pname = "sherpa-onnx-nemo-parakeet-tdt-ctc-110m-int8";
    version = "36000";
    src = fetchurl {
      url = "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemo-parakeet_tdt_ctc_110m-en-36000-int8.tar.bz2";
      hash = "sha256-F/lFAHtSzNi3IA/8fFZS6ejpYd/fR5zvyr0Gz1cDYws=";
    };
    installPhase = "mkdir -p $out; cp model.int8.onnx tokens.txt $out/";
  };
  silero = fetchurl {
    url = "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx";
    hash = "sha256-niRJ4Qh0ltjUyrqQfyPgvT942R+lUkebucI6wJy7H9Y=";
  };

  # setup.sh's unit.
  service = writeText "omayap.service" ''
    [Unit]
    Description=omayap dictation and meeting recorder
    PartOf=graphical-session.target
    After=graphical-session.target

    [Service]
    ExecStart=%h/.config/omarchy/plugins/io.github.terrifiedbug.omayap/bin/omayap daemon
    Restart=on-failure
    RestartSec=2
    Environment=XDG_RUNTIME_DIR=%t

    [Install]
    WantedBy=graphical-session.target
  '';
in
{
  inherit src;
  # The interpreter is the store's, not a venv the user owns; the daemon is
  # recognised by the real interpreter the env's wrapper runs. The tools it
  # runs by absolute path (it clears PATH), from the store.
  postPatch = ''
    substituteInPlace bin/omayap \
      --replace-fail 'python=$HOME/.local/share/omayap/venv/bin/python' 'python=${python}/bin/python3' \
      --replace-fail '[[ -O ''${python%/*} ]] || fail "the omayap venv is not yours"' 'true' \
      --replace-fail '[[ /proc/$1/exe -ef $python ]]' '[[ /proc/$1/exe -ef ${python3.interpreter} ]]'
    substituteInPlace omayap/proc.py \
      --replace-fail '"/usr/bin/pw-record",' '"${pipewire}/bin/pw-record",' \
      --replace-fail '"/usr/bin/pw-dump",' '"${pipewire}/bin/pw-dump",' \
      --replace-fail '"/usr/bin/pactl",' '"${pulseaudio}/bin/pactl",' \
      --replace-fail '"/usr/bin/wl-copy",' '"${wl-clipboard}/bin/wl-copy",' \
      --replace-fail '"/usr/bin/wl-paste",' '"${wl-clipboard}/bin/wl-paste",' \
      --replace-fail '"/usr/bin/busctl",' '"${systemd}/bin/busctl",'
  '';
  home.".local/share/omayap/models/parakeet-tdt-ctc-110m" = parakeet;
  home.".local/share/omayap/models/silero_vad.onnx" = silero;
  userServices."omayap.service" = service;
  meta.description = "Dictation and meeting transcription (sherpa-onnx env, models fetched, user service)";
}
