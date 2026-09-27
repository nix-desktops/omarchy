# Upstream Omarchy (the `omarchy` flake input) as a package: the Quickshell
# shell, the omarchy-* commands, the default configs/templates and the
# themes, laid out under $out/share/omarchy — the OMARCHY_PATH everything
# upstream expects — with the commands also linked into $out/bin.
#
# NixOS adjustments, kept as small as possible so this tracks upstream:
#   - shebangs: #!/bin/bash and #!/usr/bin/python3 don't exist here.
#   - `replacements`: packages whose bin/omarchy-* are installed OVER the
#     upstream command of the same name. That's how the Arch-specific
#     commands (pacman installs, self-update, theme switching by copying
#     into ~/.local/state, …) get their declarative NixOS versions, with one
#     omarchy-<name> on PATH per name.
#   - `plugins`: shell plugins packaged separately upstream (the elsewhen
#     world clock), installed into share/omarchy/shell/plugins as Omarchy's
#     own packages do.
#   - `declaredPlugins`: the user's third-party plugins (omarchy.plugins),
#     switched on in the default shell.json (they're installed into
#     ~/.config/omarchy/plugins, where the shell looks for them).
#   - the default bar layout drops the pacman update checker (Arch only).
#   - desktop files are looked up in the NixOS profiles too, not just
#     ~/.local, ~/.nix-profile and /usr; app launchers find apps on PATH
#     instead of /usr/bin.
#   - `branding`: another name's wordmark (pkgs/branding.nix) as logo.txt,
#     which the screensaver, About screen and omarchy-show-logo draw.
#   - the system defaults upstream installs under /usr/share (MIME handlers,
#     the terminal preference list) go to $out/share, which the profile
#     puts on XDG_DATA_DIRS.
{ lib, stdenvNoCC, writeText, src, bash, python3, perl, jq, replacements ? [ ], plugins ? [ ], branding ? null
, menu ? null, terminal ? "foot.desktop", browser ? "chromium.desktop", droppedApps ? [ ]
, declaredPlugins ? [ ] }:

stdenvNoCC.mkDerivation {
  pname = "omarchy";
  version = "${lib.removeSuffix "\n" (builtins.readFile (src + "/version"))}-${builtins.substring 0 7 (src.rev or "dirty")}";
  inherit src;

  # patchShebangs resolves interpreters from the host inputs.
  buildInputs = [ bash (python3.withPackages (_: [ ])) perl ];
  nativeBuildInputs = [ jq python3 ];
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    share=$out/share/omarchy
    mkdir -p $share $out/bin
    cp -r applications bin config default shell themes version icon.* logo.* $share/

    # The pacman update checker out of the default bar layout.
    jq '.bar.layout |= with_entries(.value |= map(select(.id != "omarchy.system-update")))' \
      config/omarchy/shell.json >$share/config/omarchy/shell.json

    ${lib.optionalString (declaredPlugins != [ ]) ''
      # The user's declared plugins (omarchy.plugins) switched on in the
      # default layout, which the shell uses until the user has a
      # shell.json of their own (then activation adds them there once).
      python3 ${./plugins-shell-json.py} defaults ${writeText "omarchy-declared-plugins.json" (builtins.toJSON
        (map (p: { inherit (p) id section; manifest = "${p.dir}/manifest.json"; }) declaredPlugins))} \
        $share/config/omarchy/shell.json
    ''}

    for plugin in ${lib.escapeShellArgs plugins}; do
      cp -r "$plugin"/share/omarchy/shell/plugins/. $share/shell/plugins/
    done

    # Upstream's live theme switch, kept for the NixOS omarchy-theme-set
    # (which records the pick in theme.json, then runs this): it stages the
    # theme into ~/.local/state/omarchy/current and retints the running
    # apps. The themes come from the read-only store here, so the staged
    # copy has to be made writable (the next switch deletes it).
    mkdir -p $share/libexec
    cp bin/omarchy-theme-set $share/libexec/omarchy-theme-set
    substituteInPlace $share/libexec/omarchy-theme-set \
      --replace-fail 'cp -r "$OMARCHY_THEMES_PATH/$THEME_NAME/"*' 'cp -r --no-preserve=mode "$OMARCHY_THEMES_PATH/$THEME_NAME/"*' \
      --replace-fail 'cp -r "$USER_THEMES_PATH/$THEME_NAME/"*' 'cp -r --no-preserve=mode "$USER_THEMES_PATH/$THEME_NAME/"*'

    for pkg in ${lib.escapeShellArgs replacements}; do
      for f in "$pkg"/bin/omarchy-*; do
        rm -f "$share/bin/$(basename "$f")"
        cp "$f" "$share/bin/"
      done
    done

    chmod -R u+w $share
    ${lib.optionalString (branding != null) "cp ${branding}/logo.txt $share/logo.txt"}

    ${lib.optionalString (menu != null) ''
      # The NixOS layer over the menu (lib/menu.nix): complete entries
      # appended to the shipped menu, where a repeated id replaces the
      # earlier one in place. ~/.config/omarchy/extensions stays the user's.
      python3 - ${writeText "omarchy-menu-nixos.json" menu} $share/default/omarchy/omarchy-menu.jsonc <<'PY'
      import json, sys
      overrides = json.load(open(sys.argv[1]))
      path = sys.argv[2]
      text = open(path).read().rstrip()
      assert text.endswith("}"), "omarchy-menu.jsonc doesn't end with }"
      body = text[:-1].rstrip()
      if body.endswith(","):
          body = body[:-1]
      lines = ["", "  // NixOS (nix-desktops/omarchy lib/menu.nix): these replace the entries above."]
      lines += ["  %s: %s," % (json.dumps(k), json.dumps(v)) for k, v in overrides.items()]
      open(path, "w").write(body + ",\n" + "\n".join(lines) + "\n}\n")
      PY
    ''}

    # System defaults, where upstream puts them under /usr/share: the MIME
    # handlers (the browser `browser`, none for default apps left out) and
    # the terminal preference (`terminal`).
    mkdir -p $out/share/applications $out/share/xdg-terminal-exec
    grep -v -E ${lib.escapeShellArg "=(${lib.concatMapStringsSep "|" lib.escapeRegex ([ "chromium.desktop" ] ++ droppedApps)})$"} \
      default/applications/mimeapps.list >$out/share/applications/mimeapps.list || true
    ${lib.optionalString (browser != null) ''
      for scheme in x-scheme-handler/http x-scheme-handler/https; do
        echo "$scheme=${browser}" >>$out/share/applications/mimeapps.list
      done
    ''}
    ${lib.optionalString (terminal != null) ''
      echo ${lib.escapeShellArg terminal} >$out/share/xdg-terminal-exec/hyprland-xdg-terminals.list
    ''}

    # App launchers and installers check and run /usr/bin/<app>; on NixOS
    # apps are on PATH.
    sed -i -E \
      -e 's#\[\[ -x /usr/bin/([A-Za-z0-9._-]+) \]\]#command -v \1 >/dev/null#' \
      -e 's#uwsm-app -- /usr/bin/#uwsm-app -- #' \
      -e 's#pkexec /usr/bin/env #pkexec env #' \
      $share/bin/omarchy-launch-* $share/bin/omarchy-install-*

    # Browser lookup: packages live in the NixOS profiles.
    for f in omarchy-launch-browser omarchy-launch-webapp; do
      substituteInPlace $share/bin/$f --replace-fail \
        '{~/.local,~/.nix-profile,/usr}/share/applications/' \
        '{~/.local,~/.nix-profile,/etc/profiles/per-user/$USER,/run/current-system/sw,/usr}/share/applications/'
    done

    patchShebangs --host $share/bin $share/libexec $share/shell

    for f in $share/bin/*; do
      ln -s "$f" $out/bin/
    done

    runHook postInstall
  '';

  meta = {
    description = "Omarchy's Quickshell desktop shell, commands and themes, adapted for NixOS";
    homepage = "https://omarchy.org";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
