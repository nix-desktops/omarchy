{ lib, stdenv, inputs, meson, ninja, pkg-config, wayland-scanner, wayland
, wayland-protocols, libGL, libepoxy, mpv-unwrapped, ffmpeg, systemdLibs
, socat, makeWrapper }:

stdenv.mkDerivation {
  pname = "owe";
  version = "0.2.6";
  src = inputs.owe;

  nativeBuildInputs = [ meson ninja pkg-config wayland-scanner makeWrapper ];
  buildInputs = [ wayland wayland-protocols libGL libepoxy mpv-unwrapped ffmpeg systemdLibs ];

  postInstall = ''
    install -Dm755 $src/hooks/owe-idle $out/bin/owe-idle
    install -Dm644 $src/hooks/theme-set.d/10-owe-sync $out/share/owe/10-owe-sync
    install -Dm644 $src/config/config.toml $out/share/doc/owe/config.toml.example
    install -Dm644 $src/systemd/owed.service $out/lib/systemd/user/owed.service
    substituteInPlace $out/lib/systemd/user/owed.service \
      --replace-fail '%h/.local/bin/owed' "$out/bin/owed"
    patchShebangs $out/bin/owe-idle
    wrapProgram $out/bin/owe-idle --prefix PATH : ${lib.makeBinPath [ socat ]}
  '';

  meta = {
    description = "Wallpaper engine for Omarchy (video, GIF and still backgrounds)";
    homepage = "https://github.com/omacom/owe";
    license = lib.licenses.mit;
    mainProgram = "owed";
    platforms = lib.platforms.linux;
  };
}
