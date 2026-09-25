# tobi/try, as its own flake packages it (Ruby, no gems). Named tobi-try as
# in Omarchy: nixpkgs' `try` is a different tool.
{ lib, stdenvNoCC, inputs, ruby_3_3, makeBinaryWrapper }:

stdenvNoCC.mkDerivation {
  pname = "tobi-try";
  version = lib.trim (builtins.readFile "${inputs.tobi-try}/VERSION");
  src = inputs.tobi-try;

  nativeBuildInputs = [ makeBinaryWrapper ];
  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp try.rb $out/bin/try
    cp -r lib $out/bin/
    chmod +x $out/bin/try
    wrapProgram $out/bin/try --prefix PATH : ${ruby_3_3}/bin
    runHook postInstall
  '';

  meta = {
    description = "Fresh directories for every vibe";
    homepage = "https://github.com/tobi/try";
    license = lib.licenses.mit;
    mainProgram = "try";
  };
}
