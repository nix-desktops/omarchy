# Omatop: a system monitor. Service.qml runs
# <plugin>/sampler/target/release/omatop-sampler (Rust, sampler/: reads
# /proc), and builds it with cargo when it's missing. Pattern: a helper
# inside the plugin's tree.
{ lib, fetchFromGitHub, rustPlatform }:
let
  src = fetchFromGitHub {
    owner = "ryanyogan";
    repo = "omarchy-omatop";
    rev = "d8c4bae56290d77355ac6588f35a4b09c18694cd";
    hash = "sha256-sai7RtSTm+rXbKtWqxXnG3kVe7hNZyLRjpkk9GmwihI=";
  };

  sampler = rustPlatform.buildRustPackage {
    pname = "omatop-sampler";
    version = "1.2.2-unstable-d8c4bae";
    inherit src;
    sourceRoot = "${src.name}/sampler";
    # Expects a kernel thread in /proc, which the sandbox's has none of.
    checkFlags = [ "--skip=apps_cover_every_bucket_and_carry_every_field" ];
    cargoHash = "sha256-8xjzkCTf3IjBH+QtJSq/FLsBgNupoz5l/+XVS4bn41A=";
    meta.mainProgram = "omatop-sampler";
  };
in
{
  inherit src;
  helpers."sampler/target/release/omatop-sampler" = lib.getExe sampler;
  meta.description = "System monitor (omatop-sampler built from sampler/)";
}
