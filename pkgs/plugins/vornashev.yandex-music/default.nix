# Yandex Music: WidgetLogic.qml runs bootstrap.sh, i.e. install.sh
# --backend-only: a venv at ~/.local/share/omarchy-yandex-music filled with
# pip (and the vendored yandex-music wheel), backend.py and a CLI copied
# next to it, and a user service. Pattern: those files as home links (the
# unit enabled), bootstrap.sh patched to start the service.
{ fetchFromGitHub, runCommand, python3, coreutils, mpv }:
let
  src = fetchFromGitHub {
    owner = "vornashev";
    repo = "omarchy-yandex-music";
    rev = "f2b51d3eaa772ed8d6d6fed6449ac64f23c20fad";
    hash = "sha256-qMuAuyvZegGvrw1dYZWcfmbCd69VHRNsinstei3DIPs=";
  };
  yandex-music = python3.pkgs.buildPythonPackage {
    pname = "yandex-music";
    version = "3.1.0b2";
    format = "wheel";
    src = "${src}/vendor/yandex_music-3.1.0b2-py3-none-any.whl";
    dependencies = with python3.pkgs; [ requests pysocks typing-extensions ];
    pythonImportsCheck = [ "yandex_music" ];
  };
  # It starts mpv as /usr/bin/mpv (the service has no PATH of the shell's).
  backend = runCommand "omarchy-yandex-music-backend.py" { } ''
    substitute ${src}/backend/backend.py $out --replace-fail '"/usr/bin/mpv"' '"${mpv}/bin/mpv"'
  '';
  # Its ReadWritePaths must exist (install.sh creates it); "+" runs this
  # outside the unit's sandbox.
  unit = runCommand "omarchy-yandex-music.service" { } ''
    substitute ${src}/systemd/omarchy-yandex-music.service $out --replace-fail '[Service]' '[Service]
    ExecStartPre=+${coreutils}/bin/mkdir -p -m 700 %h/.config/omarchy-yandex-music'
  '';
  app = ".local/share/omarchy-yandex-music";
in
{
  inherit src;
  postPatch = ''
    substituteInPlace bootstrap.sh \
      --replace-fail 'exec "$ROOT/install.sh" --backend-only' 'systemctl --user start omarchy-yandex-music.service'
  '';
  home."${app}/venv" = python3.withPackages (ps: [ ps.requests ps.dbus-next yandex-music ]);
  home."${app}/backend.py" = backend;
  home.".local/bin/omarchy-yandex-music" = "${src}/bin/omarchy-yandex-music";
  home.".config/systemd/user/omarchy-yandex-music.service" = unit;
  home.".config/systemd/user/default.target.wants/omarchy-yandex-music.service" = unit;
  packages = [ mpv ];
  meta.description = "Yandex Music player (its backend's venv with the vendored yandex-music, a user service)";
}
