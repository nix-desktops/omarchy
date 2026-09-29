# pacman, expac and vercmp answering the query forms shell plugins use,
# from the NixOS system (pacman.py; omarchy.pacmanShim.enable).
#
#   pkgs            the nixpkgs the Arch→nixpkgs map (data/arch-packages.json)
#                   resolves against: each mapped attribute's pname, which is
#                   what store paths are named by
#   omarchyVersion  upstream Omarchy's version (`pacman -Q omarchy`)
{ lib, pkgs, runCommand, writeText, python3, bash, omarchyVersion ? null }:
let
  archMap = (lib.importJSON ../../data/arch-packages.json).map;
  discard = builtins.unsafeDiscardStringContext;
  pnameOf = attr:
    let
      r = builtins.tryEval (
        let p = lib.attrByPath (lib.splitString "." attr) null pkgs; in
        if p == null || !(lib.isDerivation p) then null
        else discard (p.pname or (builtins.parseDrvName p.name).name));
    in if r.success then r.value else null;
  mapFile = writeText "omarchy-arch-packages.json" (builtins.toJSON
    (lib.mapAttrs (_: attr: if attr == null then null else { inherit attr; pname = pnameOf attr; }) archMap));

  wrapper = name: flag: ''
    cat >$out/bin/${name} <<'EOF'
    #!${bash}/bin/sh
    export OMARCHY_PACMAN_MAP=${mapFile}
    ${lib.optionalString (omarchyVersion != null) "export OMARCHY_VERSION=${lib.escapeShellArg omarchyVersion}"}
    exec ${python3}/bin/python3 -I -S ${./pacman.py} ${flag} "$@"
    EOF
    chmod +x $out/bin/${name}
  '';
in
runCommand "omarchy-pacman-shim" {
  passthru = { inherit mapFile; };
  meta = {
    description = "pacman, expac and vercmp answering package queries from the NixOS system, for Omarchy's shell plugins";
    mainProgram = "pacman";
  };
} ''
  mkdir -p $out/bin
  ${wrapper "pacman" ""}
  ${wrapper "expac" "--expac"}
  ${wrapper "vercmp" "--vercmp"}
''
