# DNS is part of the NixOS config (networking.nameservers / NetworkManager),
# not something to rewrite in /etc at runtime. Reports the resolver mode for
# the network panel; refuses changes.
if [ $# -eq 0 ]; then
  echo "DHCP"
  exit 0
fi
notify-send -a Omarchy "󰇖  DNS" "DNS is set in the NixOS config (networking.nameservers)."
exit 1
