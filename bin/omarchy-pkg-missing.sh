# True when any named package is not installed (see omarchy-pkg-present).
for pkg in "$@"; do
  omarchy-pkg-present "$pkg" || exit 0
done
exit 1
