# Scaffold a per-project dev environment from the nix-templates/dev set
# (plus this repo's framework layers), baked into the store at build time.
# The NixOS answer to omarchy-install-dev-env: instead of `mise use --global
# <tool>`, each project gets a reproducible devShell + direnv .envrc, with
# LSP, linters, formatters and scanners already wired into VS Code/Neovim.
#
#   omarchy-dev-env            pick a template (Omarchy menu)
#   omarchy-dev-env <name>     scaffold that template
lang="${1-}"

# Nerd Font glyph per template for the picker; anything unlisted gets the
# generic code glyph.
icon_for() {
  # Private-use BMP glyphs are written as \u escapes: as literal
  # characters they get dropped by some tools and the icon goes blank.
  case "$1" in
    ruby) printf '' ;;
    node) printf '' ;;
    js | javascript) printf '' ;;
    typescript | ts) printf '' ;;
    bun | deno) printf '' ;;
    go) printf '' ;;
    php | laravel | symfony) printf '' ;;
    python | jupyter) printf '' ;;
    elixir | phoenix) printf '' ;;
    rust) printf '' ;;
    java | kotlin | groovy | scala) printf '' ;;
    zig) printf '' ;;
    ocaml) printf '' ;;
    csharp | dotnet | fsharp) printf '' ;;
    clojure) printf '' ;;
    haskell | purescript) printf '' ;;
    lua) printf '' ;;
    nix) printf '' ;;
    c | cpp | c-cpp) printf '' ;;
    swift) printf '' ;;
    dart) printf '' ;;
    docker | kubernetes | k8s) printf '' ;;
    terraform | tf | hashi) printf '' ;;
    shell | sh) printf '' ;;
    markdown | md | docs) printf '' ;;
    web | graphql) printf '' ;;
    sql) printf '' ;;
    latex | typst) printf '' ;;
    julia) printf '' ;;
    erlang | gleam) printf '' ;;
    elm) printf '' ;;
    github-actions | gha) printf '' ;;
    *) printf '' ;;
  esac
}

if [ -z "$lang" ]; then
  mapfile -t rows < <(while IFS=$'\t' read -r name desc; do
    printf '%s\t%s\t%s\n' "$(icon_for "$name")" "$name" "$desc"
  done <"$OMARCHY_DEV_TEMPLATES/index.tsv")
  choice=$(omarchy-menu-select "New project" "${rows[@]}") || exit 0
  [ -z "$choice" ] && exit 0
  lang="${choice%%$'\t'*}"
fi

if [ ! -d "$OMARCHY_DEV_TEMPLATES/$lang" ]; then
  echo "Unknown template '$lang'. Templates: $(cut -f1 "$OMARCHY_DEV_TEMPLATES/index.tsv" | tr '\n' ' ')" >&2
  exit 1
fi

# The directory prompt needs a terminal; from the menu there is none.
if [ ! -t 0 ]; then
  exec omarchy-launch-floating-terminal-with-presentation "omarchy-dev-env '$lang'"
fi

echo ":: New $lang project"
dir=$(gum input --prompt "Project directory: " --value "$HOME/Projects/") || exit 0
[ -z "$dir" ] && exit 0

if [ -e "$dir" ] && [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then
  echo "Directory '$dir' exists and is not empty." >&2
  exit 1
fi

# Same as `nix flake new -t`, minus the flake evaluation: copy the template
# out of the store and make it writable.
mkdir -p "$dir"
cp -r --no-preserve=mode,ownership "$OMARCHY_DEV_TEMPLATES/$lang/." "$dir/"

if command -v direnv >/dev/null; then
  direnv allow "$dir" 2>/dev/null || true
fi

echo
echo ":: Created $dir"
echo "   cd $dir      # direnv drops you into the devShell automatically"
echo "   nix develop  # or enter it manually"
echo
echo "   lint / fmt / scan   run every linter, formatter and security scanner"
echo "   Neovim: needs vim.o.exrc = true to load .nvim.lua (then :trust)"
echo "   VS Code: install mkhl.direnv; the project recommends the rest"
echo
echo "   First entry downloads the toolchain; later entries are instant."
