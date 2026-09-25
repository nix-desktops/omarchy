# The dev-environment template set behind Install > Development and the
# flake's `templates` output. Every template comes from nix-templates/dev
# (toolchain + LSP + linters + formatters + scanners, wired into direnv,
# VS Code and Neovim); ./templates only adds framework layers it lacks.
# Upstream wins on a name clash, so local dirs only fill gaps.
{ lib, src, local }:
let
  dirsOf = dir: lib.attrNames (lib.filterAttrs
    (name: type: type == "directory" && !lib.hasPrefix "." name)
    (builtins.readDir dir));

  # Each template's own flake.nix carries a one-line summary of its tooling;
  # drop the boilerplate prefix so it reads well in the rofi menu.
  entry = dir: name: {
    path = dir + "/${name}";
    description = lib.removePrefix "A Nix-flake-based "
      (import (dir + "/${name}/flake.nix")).description;
  };

  fromDir = dir: lib.genAttrs (dirsOf dir) (entry dir);

  # Local framework layers and the upstream template each sits on. Their
  # flake.nix pulls the upstream devShell in via inputsFrom; `base` lets
  # home.nix copy the upstream editor files (.nvim.lua, .vscode, ...) under
  # the layer when it bakes the menu's template dir.
  bases = {
    laravel = "php";
    symfony = "php";
    phoenix = "elixir";
  };
  layers = lib.mapAttrs
    (name: t: t // lib.optionalAttrs (bases ? ${name}) { base = src + "/${bases.${name}}"; })
    (fromDir local);

  # Real templates only: what the menu lists.
  templates = layers // fromDir src;

  # Upstream's aliases, plus `dotnet` for the name this repo used before.
  aliases = lib.mapAttrs (_: target: templates.${target}) {
    c = "c-cpp";
    cpp = "c-cpp";
    docs = "markdown";
    md = "markdown";
    gha = "github-actions";
    js = "node";
    ts = "typescript";
    k8s = "kubernetes";
    sh = "shell";
    tf = "terraform";
    dotnet = "csharp";
  };
in
{
  inherit templates;
  all = templates // aliases // { default = templates.empty; };
}
