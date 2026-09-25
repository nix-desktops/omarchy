An Omarchy desktop on NixOS. Next:

1. Set `user` (and the time zone) in configuration.nix.
2. Generate this machine's hardware config here:
     nixos-generate-config --show-hardware-config > hardware-configuration.nix
3. Track the files (flakes only see what git tracks):
     git init && git add -A
4. Build and switch:
     sudo nixos-rebuild switch --flake .#omarchy

Afterwards the Omarchy menu (SUPER+SPACE) installs apps, switches
themes and updates the system by editing ./omarchy and rebuilding.
