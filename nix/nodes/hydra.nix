{
  config,
  lib,
  pkgs,
  ...
}:
let
  keys = import ../snakeoil-keys.nix;
  demoJobs = import ../demo-jobs.nix { inherit pkgs; };
  triggerWave = import ../trigger-wave.nix { inherit pkgs demoJobs; };

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
      url="http://localhost:3000"
      until curl -fsS "$url" > /dev/null; do sleep 1; done

      hydra-create-user admin --role admin --password admin

      cookies="$(mktemp)"
      trap 'rm -f "$cookies"' EXIT
      hcurl() {
        curl -fsS --referer "$url" \
          -H "Accept: application/json" -H "Content-Type: application/json" \
          -b "$cookies" -c "$cookies" "$@"
      }

      hcurl -d '{"username": "admin", "password": "admin"}' "$url/login" > /dev/null

      hcurl -X PUT "$url/project/demo" \
        -d '{"displayname": "Demo", "enabled": "1", "visible": "1"}' > /dev/null

      hcurl -X PUT "$url/jobset/demo/trivial" -d @- > /dev/null <<EOF
      {
        "description": "One instant build (integration test)",
        "checkinterval": "300",
        "enabled": "1",
        "visible": "1",
        "keepnr": "1",
        "nixexprinput": "jobs",
        "nixexprpath": "trivial.nix",
        "inputs": {
          "jobs": { "value": "${demoJobs}", "type": "path" }
        }
      }
      EOF

      hcurl -X POST "$url/api/push?jobsets=demo:trivial" > /dev/null
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
