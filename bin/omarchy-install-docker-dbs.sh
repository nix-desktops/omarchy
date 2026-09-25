# Toggle development database containers (omarchy-install-docker-dbs, NixOS
# edition). Upstream does a loose `docker run`; here the pick is recorded in
# the host's dbs.json (omarchy.stateDir) and the system rebuilds, so each database is a
# virtualisation.oci-containers unit (docker-<name>.service) bound to
# localhost. Disabling removes the container; its data volume is kept.
#
#   omarchy-install-docker-dbs           pick (Omarchy menu, ✓ = enabled)
#   omarchy-install-docker-dbs <name>    toggle one
dbs_json="$OMARCHY_STATE/dbs.json"

enabled() { jq -e --arg d "$1" '.enabled | index($d)' "$dbs_json" >/dev/null; }

db="${1-}"
if [ -z "$db" ]; then
  rows=()
  for entry in "postgres:󰆼:PostgreSQL" "mysql:󰆼:MySQL" "mariadb:󰆼:MariaDB" \
               "redis:󰆼:Redis" "mongodb:󰆼:MongoDB" "mssql:󰆼:MSSQL"; do
    IFS=: read -r id glyph label <<<"$entry"
    [ "$id" = mssql ] && [ "$(uname -m)" != x86_64 ] && continue
    state="off"
    enabled "$id" && state="on ✓"
    rows+=("$glyph"$'\t'"$label"$'\t'"$id · $state")
  done
  choice=$(omarchy-menu-select "Docker databases" "${rows[@]}") || exit 0
  [ -z "$choice" ] && exit 0
  db="${choice##*$'\t'}"
  db="${db%% *}"
fi

case "$db" in
  postgres | mysql | mariadb | redis | mongodb | mssql) ;;
  *) echo "Usage: omarchy-install-docker-dbs [postgres|mysql|mariadb|redis|mongodb|mssql]" >&2; exit 1 ;;
esac

tmp=$(mktemp)
if enabled "$db"; then
  jq --arg d "$db" '.enabled -= [$d]' "$dbs_json" >"$tmp"
  msg="Disabling $db (its data volume is kept)"
else
  for other in mysql mariadb; do
    if [ "$db" != "$other" ] && { [ "$db" = mysql ] || [ "$db" = mariadb ]; } && enabled "$other"; then
      rm -f "$tmp"
      omarchy-notification-send -g 󰆼 "Docker DB" "$other already uses port 3306; disable it first"
      exit 1
    fi
  done
  jq --arg d "$db" '.enabled = (.enabled + [$d] | unique)' "$dbs_json" >"$tmp"
  msg="Enabling $db on localhost"
fi
mv "$tmp" "$dbs_json"

exec omarchy-launch-floating-terminal-with-presentation "echo ':: $msg'; omarchy-nixos-rebuild"
