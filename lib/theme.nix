# Theme registry + current selection, in Omarchy's own theme format.
#
#   built-in    every themes/<name>/ in upstream Omarchy (the `omarchy`
#               flake input): the 22 themes Omarchy ships.
#   community   the extra themes from Omarchy's manual, installed from the
#               menu (Install > Theme). The host's theme.json (in
#               omarchy.stateDir) pins each installed repo
#               (owner, repo, rev, narHash); data/community-themes.json is the
#               catalog to pick from.
#
# A theme directory provides colors.toml (or, for older community themes,
# only alacritty.toml), backgrounds/, a preview image, and usually a
# neovim.lua. modules/home runs Omarchy's own template renderer
# over each one (shell.toml, kitty.conf, neovim.lua, btop.theme, …) and lays
# them out as Omarchy does: ~/.config/omarchy/themes/<name>/ per theme,
# ~/.local/state/omarchy/current/theme → the active one.
#
# This file resolves the same colors in Nix, for what needs them at
# evaluation time: the Stylix base16 scheme (GTK/Qt/btop/bat/fzf/…) and the
# palette the Nix-generated configs use (hyprland, kitty, rofi, the
# starship prompt, and the Apple Silicon bar). Selecting a theme
# (omarchy-theme-set) writes theme.json and rebuilds.
#
# Arguments: `omarchy` (the upstream source) and `stateDir` (the host's
# directory holding theme.json). Flake users call `omarchy.lib.theme
# { stateDir = ./omarchy; }`.
{ omarchy, stateDir, ... }:
let
  state = builtins.fromJSON (builtins.readFile (stateDir + "/theme.json"));
  selection = state.theme;

  subdirs = dir:
    let entries = builtins.readDir dir; in
    builtins.mapAttrs (name: _: dir + "/${name}")
      (builtins.removeAttrs entries
        (builtins.filter (n: entries.${n} != "directory") (builtins.attrNames entries)));

  builtin = subdirs (omarchy + "/themes");

  # Pinned by omarchy-theme-install; fetchTree with rev + narHash is locked,
  # so this stays pure.
  community = builtins.mapAttrs
    (_: p: (builtins.fetchTree {
      type = "github";
      inherit (p) owner repo rev narHash;
    }).outPath)
    (state.installed or { });

  # ---- hex helpers (Omarchy's mix_color, in Nix) -------------------------
  hexDigits = { "0" = 0; "1" = 1; "2" = 2; "3" = 3; "4" = 4; "5" = 5; "6" = 6; "7" = 7;
                "8" = 8; "9" = 9; a = 10; b = 11; c = 12; d = 13; e = 14; f = 15; };
  byte = s: i: hexDigits.${builtins.substring i 1 s} * 16 + hexDigits.${builtins.substring (i + 1) 1 s};
  toHex2 = n: let d = "0123456789abcdef"; in
    builtins.substring (n / 16) 1 d + builtins.substring (n - (n / 16) * 16) 1 d;
  # A color value → bare lowercase "rrggbb", or null if it isn't one.
  # Accepts "#rrggbb" and alacritty's "0xrrggbb".
  hex = v:
    let m = if builtins.isString v
      then builtins.match "(#|0[xX])?([0-9a-fA-F]{6})" v else null;
    in if m == null then null else builtins.replaceStrings
      [ "A" "B" "C" "D" "E" "F" ] [ "a" "b" "c" "d" "e" "f" ] (builtins.elemAt m 1);
  # mix a b t: t = 0 → a, t = 100 → b (percent).
  mix = a: b: t:
    let ch = i: (byte a i * (100 - t) + byte b i * t + 50) / 100;
    in toHex2 (ch 0) + toHex2 (ch 2) + toHex2 (ch 4);
  luminance = c: byte c 0 + byte c 2 + byte c 4;

  # ---- theme files → raw color keys ---------------------------------------
  # alacritty.toml → the legacy colorN palette, as
  # omarchy-theme-colors-from-alacritty generates it.
  fromAlacritty = file:
    let
      c = (builtins.fromTOML (builtins.readFile file)).colors or { };
      get = section: key: hex ((c.${section} or { }).${key} or null);
      names = [ "black" "red" "green" "yellow" "blue" "magenta" "cyan" "white" ];
      normal = map (get "normal") names;
      bright = map (get "bright") names;
      background = let v = get "primary" "background"; in
        if v == null then builtins.elemAt normal 0 else v;
      foreground = let v = get "primary" "foreground"; in
        if v == null then builtins.elemAt normal 7 else v;
      color = i: if i == 0 then background else if i == 7 then foreground
        else if i < 8 then builtins.elemAt normal i
        else let b = builtins.elemAt bright (i - 8); in
          if b == null then color (i - 8) else b;
      selection = let v = get "selection" "background"; in
        if v == null then foreground else v;
    in
    assert builtins.all (v: v != null) normal ||
      throw "${toString file}: alacritty.toml lacks the 8 normal colors";
    builtins.listToAttrs (builtins.genList (i: { name = "color${toString i}"; value = color i; }) 16)
    // { inherit background foreground selection; accent = color 4; };

  readTheme = dir:
    let files = builtins.readDir dir; in
    if files ? "colors.toml" then
      let raw = builtins.fromTOML (builtins.readFile (dir + "/colors.toml")); in
      # Plain colors only; a few themes also carry Hyprland gradient
      # strings (hyprland_active_border) nothing here consumes.
      builtins.removeAttrs (builtins.mapAttrs (_: hex) raw)
        (builtins.filter (n: hex raw.${n} == null) (builtins.attrNames raw))
      // (if raw ? mode then { inherit (raw) mode; }
          else if raw ? theme_type then { mode = raw.theme_type; } else { })
    else if files ? "alacritty.toml" then fromAlacritty (dir + "/alacritty.toml")
    else throw "theme ${toString dir} has neither colors.toml nor alacritty.toml";

  # ---- raw keys → resolved Omarchy keys -----------------------------------
  # The fallback cascade from omarchy-theme-color: legacy short names and
  # ANSI colorN aliases first, then derived shades.
  resolve = dir: raw:
    let
      has = k: raw ? ${k} && raw.${k} != null;
      pick = ks: fallback:
        let found = builtins.filter has ks; in
        if found == [ ] then fallback else raw.${builtins.head found};

      background = pick [ "background" "bg" "color0" ] null;
      foreground = pick [ "foreground" "fg" "color7" ] null;
      c0 = background;
      c7 = foreground;
      red = pick [ "red" "color1" ] null;
      green = pick [ "green" "color2" ] null;
      yellow = pick [ "yellow" "color3" ] null;
      blue = pick [ "blue" "color4" ] null;
      magenta = pick [ "magenta" "color5" "purple" ] null;
      cyan = pick [ "cyan" "color6" ] null;
      # bright_<k>, else its ANSI slot, else <k> lifted 20% toward white.
      lift = k: slot: base: pick [ "bright_${k}" slot ] (mix base "ffffff" 20);

      light_foreground = pick [ "light_foreground" "light_fg" ] c7;
      bright_foreground = pick [ "bright_foreground" "bright_fg" "color15" ] foreground;
      lighter_background = pick [ "lighter_background" "lighter_bg" ] c0;
      dark_foreground = pick [ "dark_foreground" "dark_fg" "color8" ] foreground;
      muted = pick [ "muted" "color8" ] dark_foreground;
      selection = pick [ "selection" "selection_background" "color8" ] c0;
      orange = pick [ "orange" ] yellow;

      explicitMode = raw.mode or null;
      mode = if explicitMode != null then explicitMode
        else if (builtins.readDir dir) ? "light.mode" then "light"
        else if luminance background > 382 then "light" else "dark";
    in
    assert background != null && foreground != null ||
      throw "theme ${toString dir}: no background/foreground color";
    {
      inherit mode background foreground red green yellow blue magenta cyan orange
        light_foreground bright_foreground lighter_background dark_foreground muted selection;
      accent = pick [ "accent" ] blue;
      dark_background = pick [ "dark_background" "dark_bg" ] (mix background "000000" 25);
      darker_background = pick [ "darker_background" "darker_bg" ] (mix background "000000" 50);
      brown = pick [ "brown" ] (mix orange "000000" 50);
      bright_red = lift "red" "color9" red;
      bright_green = lift "green" "color10" green;
      bright_yellow = lift "yellow" "color11" yellow;
      bright_blue = lift "blue" "color12" blue;
      bright_magenta = pick [ "bright_magenta" "color13" "bright_purple" ] (mix magenta "ffffff" 20);
      bright_cyan = lift "cyan" "color14" cyan;
    };

  # ---- resolved keys → this repo's palette schema --------------------------
  # The names every colors.nix consumer uses. `red`/`red1` are the accent
  # slots (kept for the existing consumers); real red is `danger`.
  schema = k: {
    bg        = k.background;
    bgDark    = k.darker_background;
    bgAlt     = k.dark_background;
    surface   = k.lighter_background;
    selection = k.selection;
    border    = mix k.lighter_background k.muted 50;
    muted     = k.muted;
    comment   = k.dark_foreground;
    dim       = mix k.dark_foreground k.foreground 35;
    fgDim     = mix k.foreground k.background 20;
    fg        = k.foreground;
    fgBright  = k.light_foreground;
    fgWhite   = k.bright_foreground;

    accent    = k.accent;
    red       = k.accent;
    red1      = mix k.accent k.background 30;

    danger    = k.red;
    warning   = k.yellow;
    info      = k.blue;
    success   = k.green;

    magenta   = k.magenta;
    purple    = k.magenta;
    blue      = k.blue;
    cyan      = k.cyan;
    teal      = k.cyan;
    green     = k.green;
    yellow    = k.yellow;
    orange    = k.orange;
    brown     = k.brown;
  };

  # ANSI 16, as Omarchy's kitty/alacritty templates map them.
  ansi = k: [
    k.background k.red k.green k.yellow k.blue k.magenta k.cyan k.foreground
    k.muted k.bright_red k.bright_green k.bright_yellow k.bright_blue k.bright_magenta k.bright_cyan k.bright_foreground
  ];

  isImage = n: builtins.match ".*\\.(png|jpe?g|webp|gif|bmp|PNG|JPE?G|WEBP|GIF|BMP)" n != null;

  backgroundsOf = dir:
    if (builtins.readDir dir) ? backgrounds
    then builtins.sort builtins.lessThan
      (builtins.filter isImage (builtins.attrNames (builtins.readDir (dir + "/backgrounds"))))
    else [ ];

  load = source: name: dir:
    let
      k = resolve dir (readTheme dir);
      backgrounds = backgroundsOf dir;
    in {
      inherit name dir source;
      mode = k.mode;
      palette = k;
      colors = schema k;
      ansi = ansi k;
      # Relative to $HOME, through the current-theme link home.nix deploys.
      # Themes without backgrounds fall back to Omarchy's default theme's.
      wallpaper = if backgrounds == [ ]
        then ".config/omarchy/themes/tokyo-night/backgrounds/${builtins.head (backgroundsOf builtin.tokyo-night)}"
        else ".local/state/omarchy/current/theme/backgrounds/${builtins.head backgrounds}";
    };

  # Built-in wins if a community theme reuses a shipped name.
  themes = builtins.mapAttrs (load "community") community
    // builtins.mapAttrs (load "built-in") builtin;

  current = themes.${selection} or (throw
    "theme.json selects unknown theme '${selection}'. Available: ${toString (builtins.attrNames themes)}");
in
current // {
  names = builtins.attrNames themes;
  all = themes;
}
