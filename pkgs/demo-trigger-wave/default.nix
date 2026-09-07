{
  writeShellApplication,
  curl,
  coreutils,
  demo-jobs,
}:
writeShellApplication {
  name = "demo-trigger-wave";
  runtimeInputs = [
    curl
    coreutils
  ];
  text = ''
    export DEMO_JOBS=${demo-jobs}
    ${builtins.readFile ./demo-trigger-wave.sh}
  '';
}
