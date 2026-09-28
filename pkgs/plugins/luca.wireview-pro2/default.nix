# WireView Pro II: the bar widget runs <plugin>/omarchy/bin/wireview-pro2-qs
# (Rust: reads the power meter), committed as a static musl build. Pattern:
# a helper inside the plugin's tree, built from source instead.
{ lib, fetchFromGitHub, omarchyUnstable }:
let
  src = fetchFromGitHub {
    owner = "LucaNerlich";
    repo = "wireview-pro2-qs";
    rev = "97d43d925a397e92e55a9a6189fd4a4f9677e0ae";
    hash = "sha256-5mpuWglyA2J73phauTE1qrwnJ892Rycb5Uf1OxItBPI=";
  };

  # Cargo.toml asks for rustc 1.97.1; 26.05 has 1.95.
  wireview = omarchyUnstable.rustPlatform.buildRustPackage {
    pname = "wireview-pro2-qs";
    version = "1.3.1-unstable-97d43d9";
    inherit src;
    cargoHash = "sha256-QXxQWVCUW4Xu+4Nc0TTvt9F8eOtexx/plpCGFD1qLBE=";
    # Its doc examples don't compile (private functions): tests only.
    cargoTestFlags = [ "--all-targets" ];
    # Its tests spawn /bin/sleep, which the sandbox lacks.
    postPatch = "substituteInPlace src/app.rs --replace-fail 'Command::new(\"/bin/sleep\")' 'Command::new(\"sleep\")'";
    meta.mainProgram = "wireview-pro2-qs";
  };
in
{
  inherit src;
  helpers."omarchy/bin/wireview-pro2-qs" = lib.getExe wireview;
  meta.description = "WireView Pro II power meter (wireview-pro2-qs built from the repo)";
}
