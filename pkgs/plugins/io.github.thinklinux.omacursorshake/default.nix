# Shake to find: a shake-to-enlarge cursor, a Hyprland plugin (vendored
# hypr-dynamic-cursors) that bin/backend.sh compiles into ~/.local/state
# behind a build attestation and loads with hyprctl. Pattern: a Hyprland
# plugin built by Nix; the backend patched to load it from the store, find
# its tools there, and skip its build and attestation.
{ lib, fetchFromGitHub, mkHyprlandPlugin, hyprland, python3, jq, coreutils, glib }:
let
  src = fetchFromGitHub {
    owner = "thinklinux";
    repo = "omacursorshake";
    rev = "7374e62ed9ac2f07470b0b2f7d16993df2ce47ad";
    hash = "sha256-0HLJ48kpwfjXRwAGvzVZh7TShWxk2nos5hf25BwGVTM=";
  };

  shake = mkHyprlandPlugin {
    pluginName = "omacursorshake";
    version = "0-unstable-7374e62";
    inherit src;
    sourceRoot = "${src.name}/native";
    installPhase = "install -Dm755 out/omacursorshake.so $out/lib/libomacursorshake.so";
    meta.description = "omacursorshake Hyprland plugin";
  };
  trusted = lib.concatMapStringsSep " " (p: "${lib.getBin p}/bin") [ python3 jq coreutils hyprland glib ];
in
{
  inherit src;
  postPatch = ''
    substituteInPlace bin/backend.sh \
      --replace-fail 'TRUSTED_BIN_DIRS=(/usr/bin /bin)' 'TRUSTED_BIN_DIRS=(${trusted} /usr/bin /bin)' \
      --replace-fail 'SO_PATH="$STATE_DIR/omacursorshake.so"' 'SO_PATH="${shake}/lib/libomacursorshake.so"' \
      --replace-fail '"$PY_BIN" -I "$STATEIO" exists "$SO_PATH"' '[[ -f $SO_PATH ]]' \
      --replace-fail 'so_attested_for() {' 'so_attested_for() { return 0; }
    so_attested_for_upstream() {' \
      --replace-fail 'cmd_ensure() {' 'cmd_ensure() { cmd_status; }
    cmd_ensure_upstream() {'
  '';
  meta.description = "Shake to find the cursor (the omacursorshake Hyprland plugin, loaded by its widget)";
}
