# The world-clock bar widget: an Omarchy shell plugin (omacom.elsewhen),
# installed into the shell's plugins directory by the omarchy package.
{ lib, stdenvNoCC, inputs }:

stdenvNoCC.mkDerivation {
  pname = "elsewhen";
  version = "1.0.0";
  src = inputs.elsewhen;

  installPhase = ''
    runHook preInstall
    grep -Eq '"id"[[:space:]]*:[[:space:]]*"omacom\.elsewhen"' manifest.json
    dir=$out/share/omarchy/shell/plugins/omacom.elsewhen
    mkdir -p $dir
    cp manifest.json cities.json world.json worldclock-data.py *.qml *.js $dir/
    runHook postInstall
  '';

  meta = {
    description = "World clock plugin for the Omarchy shell";
    homepage = "https://github.com/omacom/elsewhen";
    license = lib.licenses.mit;
  };
}
