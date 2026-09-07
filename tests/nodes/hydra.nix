{
  config,
  lib,
  pkgs,
  ...
}:
let
  keys = import ../snakeoil-keys.nix;
  demoJobs = pkgs.callPackage ../../demo-jobs { };
  triggerWave = pkgs.callPackage ../../pkgs/demo-trigger-wave { demo-jobs = demoJobs; };

  machinesFile = pkgs.writeText "hydra-machines" ''
    ssh://root@builder1 x86_64-linux /etc/keys/snakeoil 4 1 - - -
    ssh://root@builder2 x86_64-linux /etc/keys/snakeoil 4 1 - - -
  '';

  demoSetup = pkgs.writeShellApplication {
    name = "hydra-demo-setup";
    runtimeInputs = [
      pkgs.curl
      pkgs.coreutils
    ];
    text = ''
      export DEMO_JOBS=${demoJobs}
      ${builtins.readFile ./hydra-demo-setup.sh}
    '';
  };
in
{
  services.hydra = {
    enable = true;
    hydraURL = "http://hydra:3000";
    notificationSender = "hydra@example.com";
    useSubstitutes = false;
    buildMachinesFiles = [ "${machinesFile}" ];
  };

  systemd.services.hydra-demo-setup = {
    description = "Create Hydra admin user and demo jobset";
    wantedBy = [ "multi-user.target" ];
    wants = [ "hydra-server.service" ];
    after = [
      "hydra-server.service"
      "hydra-queue-runner.service"
      "hydra-evaluator.service"
    ];
    environment = {
      HYDRA_DBI = config.services.hydra.dbi;
      HYDRA_CONFIG = "/var/lib/hydra/hydra.conf";
      HYDRA_DATA = "/var/lib/hydra";
    };
    path = [ config.services.hydra.package ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = "exec ${demoSetup}/bin/hydra-demo-setup";
  };

  # ssh insists on 0400 owner-only private keys
  environment.etc."keys/snakeoil" = {
    text = keys.private;
    mode = "0400";
    user = "hydra-queue-runner";
  };
  # ConnectTimeout/ServerAlive keep failure detection snappy when a builder
  # dies mid-build, a highlight of the live demo
  programs.ssh.extraConfig = ''
    Host builder1 builder2
      StrictHostKeyChecking no
      UserKnownHostsFile /dev/null
      LogLevel ERROR
      ConnectTimeout 5
      ServerAliveInterval 5
      ServerAliveCountMax 2
  '';

  nix.settings.substituters = lib.mkForce [ ];
  networking.firewall.allowedTCPPorts = [ 3000 ];
  environment.systemPackages = [
    triggerWave
    pkgs.jq
  ];

  virtualisation.cores = 2;
  virtualisation.memorySize = 2048;
}
