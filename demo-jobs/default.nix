{
  runCommand,
  bash,
  coreutils,
}:
runCommand "demo-jobs" { } ''
  mkdir $out
  substitute ${./trivial.nix.in} $out/trivial.nix --subst-var-by BASH ${bash}
  substitute ${./wave.nix.in} $out/wave.nix \
    --subst-var-by BASH ${bash} \
    --subst-var-by COREUTILS ${coreutils}
''
