{ lib, rustPlatform, installShellFiles, stdenv, inputs }:

rustPlatform.buildRustPackage {
  pname = "ttfx";
  version = "0.3.3";
  src = inputs.ttfx;
  cargoLock.lockFile = "${inputs.ttfx}/Cargo.lock";

  nativeBuildInputs = [ installShellFiles ];
  postInstall = lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
    installShellCompletion --cmd ttfx \
      --bash <($out/bin/ttfx --print-completion bash) \
      --zsh <($out/bin/ttfx --print-completion zsh)
  '';

  meta = {
    description = "Terminal text effects as a single static binary (a Rust port of terminaltexteffects)";
    homepage = "https://github.com/omacom/ttfx";
    license = lib.licenses.mit;
    mainProgram = "ttfx";
  };
}
