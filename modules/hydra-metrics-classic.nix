{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.hydra-metrics-classic;
  exporterConfig = import ../lib/json-exporter-config.nix { inherit lib; } {
    inherit (cfg) machines systemTypes jobsets;
  };
in
{
  options.services.hydra-metrics-classic = {
    # the new rust queue runner serves these natively and needs no module
    enable = lib.mkEnableOption (
      "Prometheus metrics for the classic Hydra queue runner, mapped out of its "
      + "/queue-runner-status JSON with the stock json_exporter"
    );

    hydraStatusUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://localhost:3000/queue-runner-status";
      example = "https://hydra.example.com/queue-runner-status";
      description = ''
        URL of Hydra's queue-runner-status endpoint (served by the Hydra web
        frontend, no authentication required on a default setup).
      '';
    };

    machines = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "ssh://root@builder1" ];
      description = ''
        Build machine URIs, exactly as they appear as keys in the
        `machines` object of the status JSON (i.e. the URI column of
        your /etc/nix/machines). One set of machine metrics with a
        `hostname` label is generated per entry.
      '';
    };

    systemTypes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "x86_64-linux" ];
      example = [
        "x86_64-linux"
        "x86_64-linux:big-parallel"
      ];
      description = ''
        System types as they appear as keys in the `machineTypes` object
        (`system` or `system:feature,...`). One set of machine_type metrics
        with a `machine_type` label is generated per entry.
      '';
    };

    jobsets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "nixos:trunk-combined" ];
      description = ''
        Jobsets ("project:jobset") to export jobset metrics for (label
        `jobset_name`). Only jobsets that consumed build time appear in the
        status JSON.
      '';
    };

    scrapeInterval = lib.mkOption {
      type = lib.types.str;
      default = "15s";
      description = ''
        Prometheus scrape interval. Every scrape makes Hydra's web frontend
        run `hydra-queue-runner --status`, so don't go overboard.
      '';
    };

    exporterPort = lib.mkOption {
      type = lib.types.port;
      default = 7979;
      description = "Listen port of the json_exporter (localhost only).";
    };

    alertRules = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Install alerting rules for failing, disabled and unusable build
        machines (see lib/alert-rules.nix). Needs
        {option}`configurePrometheus`; point Prometheus at your Alertmanager
        with {option}`services.prometheus.alertmanagers` as usual.
      '';
    };

    alertDelay = lib.mkOption {
      type = lib.types.str;
      default = "5m";
      example = "30s";
      description = ''
        How long a builder has to keep failing before its alert fires
        (Prometheus `for:`). The alert for a machine Hydra has already
        disabled fires immediately regardless.
      '';
    };

    configurePrometheus = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Add the scrape job to {option}`services.prometheus.scrapeConfigs` on
        this host, plus the recording rules that derive the native
        millisecond series and the alerting rules (as
        {option}`services.prometheus.ruleFiles`). Disable to only run the
        exporter (e.g. when Prometheus lives elsewhere), then point your
        scraper at /probe?module=hydra&target=<hydraStatusUrl> and install
        the rules from lib/recording-rules.nix and lib/alert-rules.nix
        yourself.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.prometheus.exporters.json = {
      enable = true;
      port = cfg.exporterPort;
      listenAddress = "127.0.0.1";
      configFile = pkgs.writeText "hydra-json-exporter-config.json" (builtins.toJSON exporterConfig);
    };

    # one file each: services.prometheus.rules concatenates into a multi-document
    # YAML of which prometheus reads only the first. JSON is valid YAML
    services.prometheus.ruleFiles = lib.mkIf cfg.configurePrometheus (
      [
        (pkgs.writeText "hydra-recording-rules.yml" (
          builtins.toJSON (import ../lib/recording-rules.nix { interval = cfg.scrapeInterval; })
        ))
      ]
      ++ lib.optional cfg.alertRules (
        pkgs.writeText "hydra-alert-rules.yml" (
          builtins.toJSON (
            import ../lib/alert-rules.nix {
              interval = cfg.scrapeInterval;
              pendingFor = cfg.alertDelay;
            }
          )
        )
      )
    );

    services.prometheus.scrapeConfigs = lib.mkIf cfg.configurePrometheus [
      {
        job_name = "hydra";
        metrics_path = "/probe";
        params.module = [ "hydra" ];
        scrape_interval = cfg.scrapeInterval;
        static_configs = [ { targets = [ cfg.hydraStatusUrl ]; } ];
        relabel_configs = [
          {
            source_labels = [ "__address__" ];
            target_label = "__param_target";
          }
          {
            source_labels = [ "__param_target" ];
            target_label = "instance";
          }
          {
            target_label = "__address__";
            replacement = "127.0.0.1:${toString cfg.exporterPort}";
          }
        ];
      }
    ];
  };
}
