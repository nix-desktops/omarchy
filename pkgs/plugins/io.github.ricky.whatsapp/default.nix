# WhatsApp: a Node daemon (daemon/, Baileys) is the connection; its scripts
# run `npm ci` into daemon/node_modules on first start unless
# daemon/node_modules/baileys is there. Built here from daemon's lock file,
# and the scripts pointed at the built daemon. Pattern: an install step
# patched to a store path.
{ lib, fetchFromGitHub, buildNpmPackage, nodejs }:
let
  src = fetchFromGitHub {
    owner = "srineshr1";
    repo = "omarchy-whatsapp";
    rev = "0a9b19cbc7c6e376ecf4dc3d3229543620caecca";
    hash = "sha256-7PguOAI2nSfXFpDwKsyZOy8OiloqSlyoSp8na7Ps0lM=";
  };

  daemon = buildNpmPackage {
    pname = "omarchy-whatsapp-daemon";
    version = "1.1.0-unstable-0a9b19c";
    inherit src nodejs;
    sourceRoot = "${src.name}/daemon";
    npmDepsHash = "sha256-qtouyYOxJOKmZkU/chNmM9d5X4zGSJNFUrlZJ4Fa53I=";
    # libsignal comes from git, without a lock file of its own.
    forceGitDeps = true;
    makeCacheWritable = true;
    dontNpmBuild = true;
    npmFlags = [ "--omit=dev" "--no-bin-links" ];
  };
in
{
  inherit src;
  # The daemon's files with their node_modules.
  postPatch = ''
    substituteInPlace bin/_common.sh \
      --replace-fail 'WA_DAEMON_DIR="$WA_ROOT/daemon"' \
                     'WA_DAEMON_DIR="${daemon}/lib/node_modules/omarchy-whatsapp-daemon"'
  '';
  packages = [ nodejs ]; # the daemon's node
  meta.description = "WhatsApp (its Node daemon's dependencies built from daemon/)";
}
