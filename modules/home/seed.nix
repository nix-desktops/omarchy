# Files that are the user's, as upstream Omarchy treats them: Omarchy copies
# its defaults into ~/.config once and the user (and Omarchy's own tools:
# the monitor scale, the font switcher, btop's settings, …) edit them from
# then on. Home Manager links would be read-only store files, so these are
# regular files instead:
#
#   - seeded from the default when missing (delete one to get the default
#     back on the next activation);
#   - kept up to date with the default while the user hasn't touched them
#     (the last seeded copy is remembered in ~/.local/state/omarchy/seeded);
#   - never overwritten once edited;
#   - an older link into the store (Home Manager's, from before they were
#     seeded) becomes a copy of what it pointed at;
#   - left alone when the host's own Home Manager config manages the path
#     (home.file / xdg.configFile).
#
# Other modules declare them in `omarchy.seededFiles`, keyed by the path
# relative to $HOME.
{ config, lib, pkgs, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.omarchy;
  home = config.home.homeDirectory;

  managedTargets = map (f: f.target)
    (lib.filter (f: f.enable) (lib.attrValues config.home.file));
  files = lib.filterAttrs (target: _: !(lib.elem target managedTargets)) cfg.seededFiles;
  list = lib.mapAttrsToList (target: f: { inherit target; inherit (f) source legacy adopt; }) files;

  state = "${config.xdg.stateHome}/omarchy";
  stash = "${state}/seed-stash";
  record = "${state}/seeded";
  cmp = "${pkgs.diffutils}/bin/cmp";
  q = lib.escapeShellArg;
  isStoreLink = p: ''[ -L ${p} ] && [[ "$(readlink -f ${p})" == ${builtins.storeDir}/* ]]'';
in
{
  options.omarchy.seededFiles = mkOption {
    internal = true;
    default = { };
    type = types.attrsOf (types.submodule {
      options = {
        source = mkOption {
          type = types.path;
          description = "The default content.";
        };
        adopt = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Whether an older link into the store at this path (Home
            Manager's, from before the file was seeded) becomes the user's
            copy. Off where that content was generated for the old layout
            (a Home Manager ~/.zshrc, the old menu layer), which is then
            replaced by the default.
          '';
        };
        legacy = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = ''
            Another path (relative to $HOME) where the user may have kept
            their own copy; it's moved here when this file is still the
            default.
          '';
        };
      };
    });
    description = "Files seeded once into the home directory and owned by the user from then on (relative to $HOME).";
  };

  config = lib.mkIf (cfg.enable && files != { }) {
    # Before Home Manager removes the old generation's links, keep what they
    # pointed at.
    home.activation.omarchySeedStash = lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ]
      (lib.concatMapStrings (f: let p = q "${home}/${f.target}"; in lib.optionalString f.adopt ''
        if ${isStoreLink p} && [ -e ${p} ]; then
          run install -D -m 644 ${p} ${q "${stash}/${f.target}"}
        fi
      '') list);

    home.activation.omarchySeed = lib.hm.dag.entryAfter [ "linkGeneration" ]
      (lib.concatMapStrings (f:
        let
          p = q "${home}/${f.target}";
          s = q "${stash}/${f.target}";
          r = q "${record}/${f.target}";
          src = q "${f.source}";
        in ''
          # ${f.target}
          if ${isStoreLink p}; then
            ${lib.optionalString f.adopt "[ -e ${p} ] && run install -D -m 644 ${p} ${s}"}
            run rm -f ${p}
          fi
          ${lib.optionalString (f.legacy != null) (let l = q "${home}/${f.legacy}"; in ''
            if [ -f ${l} ] && [ ! -L ${l} ]; then
              if { [ ! -e ${p} ] && [ ! -L ${p} ]; } || ${cmp} -s ${p} ${src}; then
                run rm -f ${p}
                run install -D -m 644 ${l} ${p}
                # The user's own content: never refreshed from the default.
                run rm -f ${l} ${s} ${r}
              else
                warnEcho "${f.legacy} and ${f.target} both exist and ${f.legacy} is the one loaded; merge them and remove one."
              fi
            fi
          '')}
          if [ ! -e ${p} ] && [ ! -L ${p} ]; then
            if [ -f ${s} ]; then
              run install -D -m 644 ${s} ${p}
              run install -D -m 644 ${s} ${r}
            else
              run install -D -m 644 ${src} ${p}
              run install -D -m 644 ${src} ${r}
            fi
          elif [ -f ${p} ] && [ ! -L ${p} ] && [ -f ${r} ] && ${cmp} -s ${p} ${r} && ! ${cmp} -s ${src} ${r}; then
            # Untouched since it was seeded, and the default moved on.
            run install -m 644 ${src} ${p}
            run install -D -m 644 ${src} ${r}
          fi
          run rm -f ${s}
        '') list);
  };
}
