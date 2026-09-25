# Set and launch the default coding agent (omarchy-default-agent, NixOS
# edition). Upstream installs agents with mise; here an agent that isn't
# installed yet is added to the host's agents.json (omarchy.stateDir, with
# the new default) and the system rebuilds.
#
#   omarchy-default-agent                 print the default agent
#   omarchy-default-agent <agent>         set it (installing first if needed)
agent_file="$HOME/.config/omarchy/defaults/agent"
state="$OMARCHY_STATE/agents.json"

installing=false
if [[ ${1:-} == "--install" ]]; then
  installing=true
  shift
fi

if (($# == 0)); then
  agent=""
  [[ -f $agent_file ]] && read -r agent <"$agent_file"
  # Silent when unset: Omarchy picks no agent for you.
  [[ -n $agent ]] && echo "$agent"
  exit 0
fi

# Upstream's aliases.
case "$1" in
oh-my-pi) agent=omp ;;
open-code) agent=opencode ;;
openrouter) agent=ori ;;
claude-code) agent=claude ;;
antigravity | antigravity-cli | gemini | gemini-cli) agent=agy ;;
github-copilot) agent=copilot ;;
muse-code | musecode) agent=muse ;;
cursor) agent=cursor-agent ;;
*) agent="$1" ;;
esac

case "$agent" in
omp | ori | hermes | muse | openclaw)
  # Upstream agents that don't build on NixOS (lib/catalog.nix).
  omarchy-notification-send -u critical "$agent isn't available on NixOS"
  echo "$agent isn't available on NixOS." >&2
  exit 1
  ;;
esac
if ! jq -e --arg a "$agent" 'has($a)' "$OMARCHY_AGENTS" >/dev/null; then
  echo "Usage: omarchy-default-agent <$(jq -r 'keys | join("|")' "$OMARCHY_AGENTS")>" >&2
  exit 1
fi
name=$(jq -r --arg a "$agent" '.[$a].name' "$OMARCHY_AGENTS")
command=$(jq -r --arg a "$agent" '.[$a].command' "$OMARCHY_AGENTS")

if [[ $(jq -r --arg a "$agent" '.[$a].packaged' "$OMARCHY_AGENTS") != true ]]; then
  omarchy-notification-send -u critical "$name isn't packaged for NixOS yet"
  echo "$name isn't packaged for NixOS yet." >&2
  exit 1
fi

# Record the pick (and the agent, to install it) in the host's state.
record() {
  if [[ ! -f $state ]]; then
    echo '{ "agents": [], "default": null }' >"$state"
    # Flakes only see tracked files.
    git -C "$(dirname "$state")" add --intent-to-add "$(basename "$state")" 2>/dev/null || true
  fi
  local tmp
  tmp=$(mktemp)
  jq --arg a "$agent" --argjson install "$1" \
    '.default = $a | if $install then .agents = ((.agents // []) + [$a] | unique) else . end' \
    "$state" >"$tmp"
  mv "$tmp" "$state"
}

if ! command -v "$command" >/dev/null; then
  if [[ $installing == false ]]; then
    exec omarchy-launch-floating-terminal-with-presentation omarchy-default-agent --install "$agent"
  fi
  echo "Installing $name..."
  record true
  omarchy-nixos-rebuild || exit 1
else
  record false
fi

mkdir -p "$(dirname "$agent_file")"
printf '%s\n' "$agent" >"$agent_file"

if [[ $installing == true ]]; then
  printf '\033[2J\033[3J\033[H'
  exec omarchy-agent --inline
else
  exec omarchy-agent
fi
