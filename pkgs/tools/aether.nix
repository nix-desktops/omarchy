# Aether, Omarchy's theme designer: a Wails (Go + web frontend) app. Like
# Omarchy's PKGBUILD this takes the release binary; the desktop entry and
# icon come from the source.
{ lib, stdenv, inputs, fetchurl, autoPatchelfHook, wrapGAppsHook3
, webkitgtk_4_1, gtk3, glib-networking }:
let
  version = "4.30.0";
  binary = {
    x86_64-linux = fetchurl {
      url = "https://github.com/omacom/aether/releases/download/v${version}/aether-linux-amd64";
      sha256 = "75bda600ddd3ecab3338de5c0c5d5e2c9f08cfc0c465b63f8e6cb9c5cb60d68e";
    };
    aarch64-linux = fetchurl {
      url = "https://github.com/omacom/aether/releases/download/v${version}/aether-linux-arm64";
      sha256 = "a91d800736def74d86e19d8acbecc4bda3d7c3e64fb95273f809707104c3a5bc";
    };
  }.${stdenv.hostPlatform.system} or (throw "aether: no release binary for ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation {
  pname = "aether";
  inherit version;
  src = inputs.aether;

  nativeBuildInputs = [ autoPatchelfHook wrapGAppsHook3 ];
  buildInputs = [ webkitgtk_4_1 gtk3 glib-networking ];
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 ${binary} $out/bin/aether
    install -Dm644 build/linux/aether.desktop $out/share/applications/aether.desktop
    install -Dm644 li.oever.aether.url-handler.desktop $out/share/applications/li.oever.aether.url-handler.desktop
    install -Dm644 assets/aether-icon-512.png $out/share/icons/hicolor/512x512/apps/aether.png
    runHook postInstall
  '';

  meta = {
    description = "Theme designer for Omarchy: extract colors from wallpapers and apply cohesive themes";
    homepage = "https://github.com/omacom/aether";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "aether";
    platforms = [ "x86_64-linux" "aarch64-linux" ];
  };
}
