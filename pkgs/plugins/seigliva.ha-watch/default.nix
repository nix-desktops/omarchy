# Home Assistant Watch: its bridge (bridge.py, aiohttp) runs from a venv
# at ~/.local/share/seigliva.ha-watch/venv that setup.sh fills with pip
# (run-bridge.sh checks it imports aiohttp). Pattern: a Python env where the
# plugin expects its venv.
{ fetchFromGitHub, python3, libsecret, ffmpeg, xdg-utils }:
{
  src = fetchFromGitHub {
    owner = "Seigliva";
    repo = "omarchy-ha-watch";
    rev = "befc01388e208e560c8b4d2302d82c3b960cac1c";
    hash = "sha256-a9KjDynlF6eK+2lggB2FicfScqpQPi4dvdKCJ9pczUo=";
  };
  # bin/python and bin/python3, like a venv.
  home.".local/share/seigliva.ha-watch/venv" = python3.withPackages (ps: [ ps.aiohttp ]);
  # The token (secret-tool), camera media (ffmpeg, ffprobe), links.
  packages = [ libsecret ffmpeg xdg-utils ];
  meta.description = "Home Assistant watch (its venv: python3 with aiohttp)";
}
