# Read Aloud: Edge neural text-to-speech. bin/read-aloud runs share/service.py
# with the venv bin/setup fills with pip (edge-tts) at
# ~/.local/share/read-aloud/venv, and no other Python. Pattern: a Python env
# where the plugin expects its venv.
{ fetchFromGitHub, python3 }:
{
  src = fetchFromGitHub {
    owner = "calebhat";
    repo = "omarchy-read-aloud";
    rev = "019c457c97ad92637d81f50360db8b46f02e60ff";
    hash = "sha256-xJSoxgJ8Ek3WOADbEWnvD2l+9Sq3wyCNN4c9FjfcE0Q=";
  };
  home.".local/share/read-aloud/venv" = python3.withPackages (ps: [ ps.edge-tts ]);
  meta.description = "Text to speech (its venv: python3 with edge-tts)";
}
