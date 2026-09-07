{
  description = "Official-grade observability for your private Hydra — queue-runner-status JSON mapped to 50+ Prometheus metrics via json_exporter, pure configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    {
      self,
      nixpkgs,
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      demoExporterSettings = {
        machines = [
          "ssh://root@builder1"
          "ssh://root@builder2"
        ];
        systemTypes = [ "x86_64-linux" ];
        jobsets = [
          "demo:trivial"
          "demo:wave"
        ];
      };
    in
    {
      nixosModules.hydra-metrics-classic = ./modules/hydra-metrics-classic.nix;
      nixosModules.default = self.nixosModules.hydra-metrics-classic;

      # for non-flake / non-NixOS reuse
      lib.mkJsonExporterConfig = import ./lib/json-exporter-config.nix;

      checks.${system} = {
        integration = pkgs.testers.runNixOSTest ./nix/test.nix;

        exporter-fixture =
          pkgs.runCommand "exporter-fixture-check"
            {
              nativeBuildInputs = [
                pkgs.prometheus-json-exporter
                pkgs.python3
                pkgs.curl
                pkgs.gnugrep
              ];
              config = builtins.toJSON (
                import ./lib/json-exporter-config.nix { lib = pkgs.lib; } demoExporterSettings
              );
              passAsFile = [ "config" ];
            }
            ''
              cp ${./fixtures/queue-runner-status.json} fixture.json
              python3 -m http.server 18888 --bind 127.0.0.1 &
              json_exporter --config.file "$configPath" --web.listen-address 127.0.0.1:17979 &
              sleep 2
              curl -sf --retry 5 --retry-connrefused \
                'http://127.0.0.1:17979/probe?module=hydra&target=http%3A%2F%2F127.0.0.1%3A18888%2Ffixture.json' \
                > probe.out
              grep -q '^hydraqueuerunner_builds_unfinished 42' probe.out
              grep -q '^hydraqueuerunner_machine_current_jobs{hostname="builder1"} 4' probe.out
              grep -q '^hydra_machine_enabled{hostname="builder2"} 0' probe.out
              grep -q '^hydra_avg_step_time_seconds 199.1' probe.out
              [ "$(grep -c '^hydra' probe.out)" -ge 50 ]
              mv probe.out $out
            '';

        alert-rules =
          pkgs.runCommand "alert-rules-check"
            {
              nativeBuildInputs = [ pkgs.prometheus.cli ];
              rules = builtins.toJSON (
                import ./lib/alert-rules.nix {
                  interval = "1m";
                  pendingFor = "5m";
                }
              );
              passAsFile = [ "rules" ];
            }
            ''
              cp "$rulesPath" rules.yml
              cp ${./tests/alert-rules.yml} tests.yml
              promtool check rules rules.yml
              promtool test rules tests.yml | tee $out
            '';

        dashboard-queries =
          let
            dashboard = builtins.fromJSON (builtins.readFile ./dashboards/hydra.json);
            panels = dashboard.panels ++ builtins.concatMap (p: p.panels or [ ]) dashboard.panels;
            exprs = builtins.concatMap (p: map (t: t.expr) (p.targets or [ ])) panels;
            # grafana variables mean nothing to promtool
            resolve =
              builtins.replaceStrings
                [ "$__rate_interval" "$machine" "$platform" ]
                [
                  "1m"
                  ".*"
                  ".*"
                ];
            rules = {
              groups = [
                {
                  name = "dashboard-panels";
                  rules = pkgs.lib.imap0 (i: e: {
                    record = "panel_${toString i}";
                    expr = resolve e;
                  }) exprs;
                }
              ];
            };
          in
          pkgs.runCommand "dashboard-queries-check"
            {
              nativeBuildInputs = [ pkgs.prometheus.cli ];
              panelRules = builtins.toJSON rules;
              recordingRules = builtins.toJSON (import ./lib/recording-rules.nix { });
              passAsFile = [
                "panelRules"
                "recordingRules"
              ];
            }
            ''
              [ ${toString (builtins.length exprs)} -ge 40 ]
              promtool check rules "$panelRulesPath" "$recordingRulesPath" | tee $out
            '';
      };

      packages.${system} = {
        demo = self.checks.${system}.integration.driverInteractive;

        exporter-config = pkgs.writeText "hydra-json-exporter.yml" (
          builtins.toJSON (import ./lib/json-exporter-config.nix { lib = pkgs.lib; } demoExporterSettings)
        );

        recording-rules = pkgs.writeText "hydra-recording-rules.yml" (
          builtins.toJSON (import ./lib/recording-rules.nix { })
        );

        alert-rules = pkgs.writeText "hydra-alert-rules.yml" (
          builtins.toJSON (import ./lib/alert-rules.nix { })
        );

        dashboards = pkgs.runCommand "hydra-dashboards" { } ''
          mkdir -p $out
          cp ${./dashboards}/*.json $out/
        '';

        # too slow and timing-dependent for checks
        test-builder-failure = pkgs.testers.runNixOSTest ./nix/test-builder-failure.nix;
      };

      apps.${system} = {
        demo = {
          type = "app";
          program = "${self.packages.${system}.demo}/bin/nixos-test-driver";
        };
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          jq
          curl
          prometheus-json-exporter
        ];
      };

      formatter.${system} = pkgs.nixfmt;
    };
}
