# Omarchy's default keybinds as JSON (keybinds.json): what upstream's bind
# modules define, each with its keys, description, action and layer (core,
# apps, webapps), for installers that show and edit binds
# (`omarchy.keybinds`).
{ runCommand, lua5_4, src }:

runCommand "omarchy-keybinds" { nativeBuildInputs = [ lua5_4 ]; } ''
  mkdir $out
  lua ${./keybinds.lua} ${src} >$out/keybinds.json
''
