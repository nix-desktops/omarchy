# Apple TV remote: scripts/run starts backend/remote.py (pyatv) from a venv
# at ~/.local/share/omarchy-apple-tv/venv that scripts/setup fills with pip.
# Pattern: a Python env where the plugin expects its venv.
{ fetchFromGitHub, python3 }:
{
  src = fetchFromGitHub {
    owner = "therealasclepius";
    repo = "omarchy-apple-tv";
    rev = "668bf55d8bf8482825013450095d676c03459138";
    hash = "sha256-F2PlwPpBt4G90m56N2YWrK3QWDSBKDS8ON+3U3PD9ZI=";
  };
  home.".local/share/omarchy-apple-tv/venv" = python3.withPackages (ps: [ ps.pyatv ]);
  meta.description = "Apple TV remote (its venv: python3 with pyatv)";
}
