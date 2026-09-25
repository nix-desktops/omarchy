# Omarchy's shell setup for zsh, as upstream's omarchy-zsh package lays it
# out: its zsh options, key bindings, completion and fzf widgets (zoptions,
# from omacom/omarchy-zsh), then the shared config (envs, aliases,
# functions and tool init from the omarchy input's default/bash). Generated
# into ~/.zshrc by nix-desktops/omarchy (omarchy.shell = "zsh"); your own
# zsh config runs after it and wins.
#
# Upstream's bash files are sourced as they are wherever zsh can run them:
# envs as POSIX sh, the aliases and functions under ksh emulation, which
# zsh keeps for every function they define (0-based arrays, bash-like word
# splitting). Only default/bash/init is bash-specific; its zsh form is at
# the end.

[[ -o interactive ]] || return

# ---- zoptions (omarchy-zsh): history, completion (with _omarchy), keys
fpath=("@zsh@/shell/completions" $fpath)
source "@zsh@/shell/zoptions"

# ---- envs: EDITOR, BROWSER, bat as MANPAGER, …
emulate sh -c 'source "@bash@/envs"'

# ---- aliases and functions
emulate ksh -c 'source "@bash@/aliases"'
for _omarchy_fn in "@bash@"/fns/*; do
  emulate ksh -c "source ${(q)_omarchy_fn}"
done
unset _omarchy_fn

# ---- init: mise, starship, zoxide, try, fzf
if (( $+commands[mise] )); then
  eval "$(mise activate zsh)"
fi
if [[ ${TERM:-} != dumb ]] && (( $+commands[starship] )); then
  eval "$(starship init zsh)"
fi
if (( $+commands[zoxide] )); then
  eval "$(zoxide init zsh)"
fi
if (( $+commands[try] )); then
  try() {
    unfunction try
    eval "$(SHELL=zsh command try init ~/Work/tries)"
    try "$@"
  }
fi
if (( $+commands[fzf] )); then
  source <(fzf --zsh)
fi
