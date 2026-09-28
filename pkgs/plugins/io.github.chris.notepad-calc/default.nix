# Notepad Calc: RatesRefresh.qml prefers <plugin>/bin/notepad-calc-rates (Rust,
# src/rates-refresh; build.sh), then a curl script, then bundled rates.
# Pattern: a helper inside the plugin's tree.
{ lib, fetchFromGitHub, rustPlatform, curl }:
let
  src = fetchFromGitHub {
    owner = "ccdwyer";
    repo = "omarchy-notepad-calc";
    rev = "8c444d16f5014d0ecd89e4f3a6b5a23c021d69c8";
    hash = "sha256-Bl29qre68msj1WttiVk/4kv6kpPQRuHMUTPpMACQKIw=";
  };

  rates = rustPlatform.buildRustPackage {
    pname = "notepad-calc-rates";
    version = "1.0.0-unstable-8c444d1";
    inherit src;
    sourceRoot = "${src.name}/src/rates-refresh";
    cargoHash = "sha256-BGDxFay2M2H8xTcCkdDHGY+FmVQbE7bdmx5kN8jShQ4=";
    meta.mainProgram = "notepad-calc-rates";
  };
in
{
  inherit src;
  helpers."bin/notepad-calc-rates" = lib.getExe rates;
  # Two QML slips that log errors on the shell's Qt: a TextInput with a
  # textFormat (the sheet switcher's, the only one indented so), and the
  # panel window, not its content item, as an Item's parent.
  postPatch = ''
    substituteInPlace Panel.qml \
      --replace-fail ${lib.escapeShellArg "\n                textFormat: Text.PlainText\n"} ${lib.escapeShellArg "\n"} \
      --replace-fail 'testWin.contentItem : panel' 'testWin.contentItem : panel.contentItem'
  '';
  packages = [ curl ];
  meta.description = "Notepad calculator (the exchange-rate helper built from src/rates-refresh)";
}
