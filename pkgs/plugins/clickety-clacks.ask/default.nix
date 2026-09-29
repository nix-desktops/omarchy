# Ask: an agent overlay. Conversation.qml runs `node bridge/bridge.js` (an
# ACP bridge to Claude Code / Codex, file and math search) from the
# plugin's tree; the README has you `npm ci` in bridge/. Pattern:
# node_modules built with Nix, copied into the plugin's tree (their prebuilt
# native parts patched for NixOS).
{ lib, stdenv, fetchFromGitHub, buildNpmPackage, autoPatchelfHook, nodejs, ncurses }:
let
  src = fetchFromGitHub {
    owner = "clickety-clacks";
    repo = "omarchy-ask";
    rev = "02921bb13d90e0995cb69bd6652407add14ea861";
    hash = "sha256-CgMAvvF26gLfBx34bOMjhmmoH4lIoAtJ8t+0AayP2XU=";
  };

  bridge = buildNpmPackage {
    pname = "omarchy-ask-bridge";
    version = "0-unstable-02921bb";
    src = "${src}/bridge";
    npmDepsHash = "sha256-8ldi4TaqK5qhQf21Me2HnBrLKgRnuB3LzmZZ3Vk8AfA=";
    dontNpmBuild = true;
    # Prebuilt: the Claude Code and Codex CLIs, fff's search binary, ffi-rs.
    nativeBuildInputs = [ autoPatchelfHook ];
    buildInputs = [ stdenv.cc.cc.lib ncurses ]; # ncurses: the zsh Codex ships
    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r node_modules $out/
      runHook postInstall
    '';
  };
in
{
  inherit src;
  # Copied in (dereferenced) rather than as a helper: the registry check
  # takes helpers to be files.
  postPatch = ''
    cp -rL ${bridge}/node_modules bridge/node_modules
    chmod -R u+w bridge/node_modules
  '';
  packages = [ nodejs ];
  meta.description = "Agent overlay (its Node ACP bridge's node_modules built with Nix)";
}
