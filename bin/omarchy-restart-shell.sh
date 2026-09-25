# The shell runs as the omarchy-shell systemd user service (home-manager
# restarts it when the package or theme changes), so restarting goes
# through systemd instead of upstream's kill + hyprctl exec, which would
# start a second, unsupervised copy.
systemctl --user restart omarchy-shell.service
