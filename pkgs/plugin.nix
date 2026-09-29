# An Omarchy shell plugin as the shell loads it: the plugin's files (a git
# repo with manifest.json at its root) without .git, checked with
# upstream's own validator (omarchy-plugin-validate: schema, entry points,
# no symlinks, no reserved id). By default nothing is patched or built: the
# files are the ones `omarchy plugin add` would clone.
#
#   src        the plugin's source: fetchgit / fetchFromGitHub, a flake input
#              (`flake = false`), a local path
#   id         the manifest id it must have (the shell enables plugins by id)
#   patches    patch files applied to the plugin's files
#   postPatch  shell run in the plugin's files after the patches
#              (substituteInPlace …: a venv or download step pointed at a
#              store path)
#   helpers    { "<path in the plugin>" = <file or directory>; }: Nix-built
#              programs copied into the plugin's tree where it looks for
#              them (`bin/x`, `target/release/x`), dereferenced (the
#              validator refuses symlinks), after the patches
#
# The flake's registry of packaged plugins (pkgs/plugins) builds its
# entries with this.
#
# The flake exports it as `lib.mkPlugin { pkgs, src, id }`, and
# `omarchy.plugins.<id>` uses it for `src` or `url` + `rev` + `hash`.
{ lib, stdenvNoCC, bash, jq, findutils, omarchySrc }:
{ src, id ? null, version ? null, patches ? [ ], postPatch ? "", helpers ? { } }:

stdenvNoCC.mkDerivation {
  pname = "omarchy-plugin-${if id != null then id else "unnamed"}";
  version = if version != null then version else src.rev or src.shortRev or "local";
  inherit src patches postPatch;
  nativeBuildInputs = [ jq findutils ];
  dontConfigure = true;
  dontBuild = true;
  # As cloned: no shebang patching, no stripping.
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r --no-preserve=mode,ownership . $out/
    rm -rf $out/.git
    # Executable bits (scripts the plugin runs) as in the repo.
    (cd . && find . -path ./.git -prune -o -type f -perm -u+x -print0) | (cd $out && xargs -0r chmod +x)
    ${lib.concatStrings (lib.mapAttrsToList (path: helper: ''
      # helper: ${path}
      rm -rf $out/${lib.escapeShellArg path}
      mkdir -p "$(dirname $out/${lib.escapeShellArg path})"
      cp -rL --no-preserve=ownership ${helper} $out/${lib.escapeShellArg path}
      chmod -R u+w $out/${lib.escapeShellArg path}
    '') helpers)}
    ${bash}/bin/bash ${omarchySrc}/bin/omarchy-plugin-validate $out
    ${lib.optionalString (id != null) ''
      actual=$(jq -r .id $out/manifest.json)
      if [ "$actual" != ${lib.escapeShellArg id} ]; then
        echo "omarchy plugin: the manifest's id is '$actual', declared as '${id}'" >&2
        exit 1
      fi
    ''}
    runHook postInstall
  '';

  passthru = { pluginId = id; inherit helpers; };

  meta = {
    description = "Omarchy shell plugin${lib.optionalString (id != null) " ${id}"}";
    platforms = lib.platforms.linux;
  };
}
