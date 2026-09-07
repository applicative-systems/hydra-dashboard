{ pkgs, config, ... }:
{
  imports = [ ../../modules/hydra-metrics-classic.nix ];

  environment.systemPackages = [ pkgs.jq ];

  services.hydra-metrics-classic = {
    enable = true;
    hydraStatusUrl = "http://hydra:3000/queue-runner-status";
    machines = [
      "ssh://root@builder1"
      "ssh://root@builder2"
    ];
    systemTypes = [ "x86_64-linux" ];
    jobsets = [
      "demo:trivial"
      "demo:wave"
    ];
    scrapeInterval = "5s";
    # a demo cannot wait five minutes for a builder to be declared bad
    alertDelay = "15s";
  };

  services.prometheus = {
    enable = true;

    alertmanagers = [
      {
        static_configs = [
          { targets = [ "localhost:${toString config.services.prometheus.alertmanager.port}" ]; }
        ];
      }
    ];

    alertmanager = {
      enable = true;
      configuration = {
        route = {
          receiver = "blackhole";
          group_wait = "1s";
          group_interval = "1s";
          repeat_interval = "1h";
        };
        receivers = [
          { name = "blackhole"; }
        ];
      };
    };
  };

  services.grafana = {
    enable = true;
    settings = {
      server = {
        # hydra owns 3000 in this demo, grafana evades to 3001
        http_addr = "0.0.0.0";
        http_port = 3001;
      };
      "auth.anonymous" = {
        enabled = true;
        org_role = "Admin";
      };
      security.secret_key = "demo-only-not-a-secret";
      analytics.reporting_enabled = false;
    };
    provision = {
      enable = true;
      datasources.settings = {
        apiVersion = 1;
        datasources = [
          {
            name = "Prometheus";
            uid = "prometheus";
            type = "prometheus";
            access = "proxy";
            url = "http://localhost:${toString config.services.prometheus.port}";
            isDefault = true;
          }
        ];
      };
      dashboards.settings = {
        apiVersion = 1;
        providers = [
          {
            name = "hydra-demo";
            options.path = ../../dashboards;
            allowUiUpdates = true;
          }
        ];
      };
    };
  };

  networking.firewall.allowedTCPPorts = [
    config.services.grafana.settings.server.http_port
    config.services.prometheus.port
    config.services.prometheus.alertmanager.port
  ];

  virtualisation.memorySize = 1536;
}
