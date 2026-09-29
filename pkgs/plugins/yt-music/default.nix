# YouTube Music Lite: Panel.qml runs ~/.local/bin/yt-music-ctl, which
# install.sh writes to run backend/yt_music.py in a pip venv (ytmusicapi,
# browser-cookie3). Pattern: a home link to a wrapper with a Python env.
{ lib, fetchFromGitHub, writeShellScript, python3, mpv, yt-dlp }:
let
  src = fetchFromGitHub {
    owner = "stevenwtlafrance-ship-it";
    repo = "YouTube-Music-Lite";
    rev = "b7b29641ec0f8fa9b83a3684f91ebe585421ab1d";
    hash = "sha256-jnAHz6dLtjg5YWfYn2FWbFlgLy79zYzGCx9sBYDAnGg=";
  };

  python = python3.withPackages (ps: [ ps.ytmusicapi ps.browser-cookie3 ]);
  ctl = writeShellScript "yt-music-ctl" ''
    exec ${python}/bin/python ${src}/backend/yt_music.py "$@"
  '';
in
{
  inherit src;
  home.".local/bin/yt-music-ctl" = ctl;
  packages = [ mpv yt-dlp ];
  meta.description = "YouTube Music player (yt-music-ctl: yt_music.py with ytmusicapi and browser-cookie3)";
}
