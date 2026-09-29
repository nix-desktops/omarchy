# Apple TV Remote: every action runs ./apple-tv-remote, which uses pyatv from
# a venv at ~/.local/share/io.github.teevans.apple-tv-remote/venv and
# pip-installs pyatv 0.18.0 into it unless that's the version there. Nixpkgs
# has pyatv 0.17: the check is pointed at it (the plugin uses scan, connect,
# pair and atvremote, all in 0.17). Pattern: a Python env where the plugin
# expects its venv, and a pip step patched to it.
{ fetchFromGitHub, python3 }:
let
  python = python3.withPackages (ps: [ ps.pyatv ps.ifaddr ]);
in
{
  src = fetchFromGitHub {
    owner = "teevans";
    repo = "omarchy-apple-tv-remote";
    rev = "fe6a054522d94b883d589b3098910f45dc3bf68f";
    hash = "sha256-PJ3KZ1WJK7bgsw+x6rH6Cg/uO8AL0zIzkHYWarOWx2A=";
  };
  home.".local/share/io.github.teevans.apple-tv-remote/venv" = python;
  postPatch = ''
    substituteInPlace apple-tv-remote \
      --replace-fail 'PYATV_VERSION="0.18.0"' 'PYATV_VERSION="${python3.pkgs.pyatv.version}"'
  '';
  meta.description = "Apple TV remote (its venv: python3 with pyatv)";
}
