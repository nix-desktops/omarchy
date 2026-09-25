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
#   - the default bar layout drops the pacman update checker (Arch only).
#   - desktop files are looked up in the NixOS profiles too, not just
#     ~/.local, ~/.nix-profile and /usr; app launchers find apps on PATH
#     instead of /usr/bin.
#   - the system defaults upstream installs under /usr/share (MIME handlers,
#     the terminal preference list) go to $out/share, which the profile
#     puts on XDG_DATA_DIRS.
{ lib, stdenvNoCC, src, bash, python3, perl, jq, replacements ? [ ], plugins ? [ ] }:

stdenvNoCC.mkDerivation {
  pname = "omarchy";
  version = "${lib.removeSuffix "\n" (builtins.readFile (src + "/version"))}-${builtins.substring 0 7 (src.rev or "dirty")}";
  inherit src;

  # patchShebangs resolves interpreters from the host inputs.
  buildInputs = [ bash (python3.withPackages (_: [ ])) perl ];
  nativeBuildInputs = [ jq ];
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

    for plugin in ${lib.escapeShellArgs plugins}; do
      cp -r "$plugin"/share/omarchy/shell/plugins/. $share/shell/plugins/
    done

    for pkg in ${lib.escapeShellArgs replacements}; do
      for f in "$pkg"/bin/omarchy-*; do
        rm -f "$share/bin/$(basename "$f")"
        cp "$f" "$share/bin/"
      done
    done

    chmod -R u+w $share

    # System defaults, where upstream puts them under /usr/share.
    install -Dm644 default/applications/mimeapps.list $out/share/applications/mimeapps.list
    install -Dm644 default/xdg-terminal-exec/hyprland-xdg-terminals.list \
      $out/share/xdg-terminal-exec/hyprland-xdg-terminals.list

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

    patchShebangs --host $share/bin $share/shell

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
