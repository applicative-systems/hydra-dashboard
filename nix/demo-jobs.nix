{ pkgs }:
let
  trivial = pkgs.writeText "trivial.nix" ''
    { ... }:
    let
      bash = builtins.storePath ${pkgs.bash};
    in
    {
      trivial = derivation {
        name = "demo-trivial";
        system = "x86_64-linux";
        builder = "''${bash}/bin/bash";
        args = [
          "-c"
          "echo success > $out"
        ];
        allowSubstitutes = false;
      };
    }
  '';

  # sized to drain in ~4-5 minutes on 2 builders x 4 slots; the wave tag in
  # every derivation name makes each trigger produce genuinely new builds
  wave = pkgs.writeText "wave.nix" ''
    { wave ? "0", ... }:
    let
      bash = builtins.storePath ${pkgs.bash};
      coreutils = builtins.storePath ${pkgs.coreutils};
      mkJob = i: seconds: {
        name = "job''${toString i}";
        value = derivation {
          name = "wave-''${wave}-job''${toString i}";
          system = "x86_64-linux";
          builder = "''${bash}/bin/bash";
          args = [
            "-c"
            "''${coreutils}/bin/sleep ''${toString seconds}; echo done > $out"
          ];
          allowSubstitutes = false;
        };
      };
      mod = a: b: a - (a / b) * b;
      short = builtins.genList (i: mkJob i (10 + mod (i * 7) 41)) 55;
      long = builtins.genList (i: mkJob (55 + i) 90) 5;
    in
    builtins.listToAttrs (short ++ long)
  '';
in
pkgs.runCommand "demo-jobs" { } ''
  mkdir $out
  cp ${trivial} $out/trivial.nix
  cp ${wave} $out/wave.nix
''
