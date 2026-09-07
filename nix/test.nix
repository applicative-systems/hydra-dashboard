{ lib, ... }:
{
  name = "hydra-dashboard";

  nodes = {
    hydra = ./nodes/hydra.nix;
    builder1 = ./nodes/builder.nix;
    builder2 = ./nodes/builder.nix;
    monitor = ./nodes/monitor.nix;
  };

  testScript = ''
    start_all()

    builder1.wait_for_unit("sshd.service")
    builder2.wait_for_unit("sshd.service")

    hydra.wait_for_unit("hydra-init.service")
    hydra.wait_for_unit("hydra-server.service")
    hydra.wait_for_unit("hydra-queue-runner.service")
    hydra.wait_for_unit("hydra-demo-setup.service")

    with subtest("first build turns green, built on a remote builder"):
        hydra.wait_until_succeeds(
            "curl -sfL -H 'Accept: application/json' http://localhost:3000/build/1"
            " | jq -e '.buildstatus == 0'",
            timeout=600,
        )
        hydra.succeed(
            "curl -sf -H 'Accept: application/json' http://localhost:3000/queue-runner-status"
            " | jq -e '[.machines[].nrStepsDone] | add >= 1'"
        )

    with subtest("json_exporter maps the status JSON to hydra_* metrics"):
        monitor.wait_for_unit("prometheus-json-exporter.service")
        probe = (
            "curl -sf 'http://localhost:7979/probe?module=hydra"
            "&target=http%3A%2F%2Fhydra%3A3000%2Fqueue-runner-status'"
        )
        # always-present gauge, native name
        monitor.wait_until_succeeds(f"{probe} | grep -E '^hydraqueuerunner_builds_unfinished '")
        # counter that must have moved
        monitor.wait_until_succeeds(f"{probe} | grep -E '^hydraqueuerunner_builds_finished [1-9]'")
        # conditional field, present once a step finished
        monitor.wait_until_succeeds(f"{probe} | grep -E '^hydra_avg_step_time_seconds '")
        # per-machine series with static hostname labels
        monitor.succeed(f"{probe} | grep -E '^hydraqueuerunner_machine_current_jobs.hostname=.builder1'")
        monitor.succeed(f"{probe} | grep -E '^hydraqueuerunner_machine_current_jobs.hostname=.builder2'")

    with subtest("prometheus ingests the metrics"):
        monitor.wait_for_unit("prometheus.service")
        monitor.wait_until_succeeds(
            "curl -sf 'http://localhost:9090/api/v1/query?query=hydraqueuerunner_builds_finished'"
            " | jq -e '.data.result | length > 0'"
        )
        # the ms series only exists via the recording rule
        monitor.wait_until_succeeds(
            "curl -sf 'http://localhost:9090/api/v1/query?query=hydraqueuerunner_steps_avg_total_time_ms'"
            " | jq -e '.data.result | length > 0'"
        )

    with subtest("the alerting rules are loaded and alertmanager is wired up"):
        monitor.wait_for_unit("alertmanager.service")
        monitor.wait_until_succeeds(
            "curl -sf http://localhost:9090/api/v1/alertmanagers"
            " | jq -e '.data.activeAlertmanagers | length > 0'"
        )
        monitor.wait_until_succeeds(
            "curl -sf 'http://localhost:9090/api/v1/rules?type=alert'"
            " | jq -e '[.data.groups[].rules[] | select(.name | startswith(\"Hydra\"))]"
            " | length == 6 and all(.[]; .health == \"ok\")'"
        )

    with subtest("a healthy fleet fires nothing"):
        monitor.succeed(
            "curl -sfG --data-urlencode 'query=ALERTS' http://localhost:9090/api/v1/query"
            " | jq -e '.data.result | length == 0'"
        )

    with subtest("grafana serves the provisioned dashboard"):
        monitor.wait_for_unit("grafana.service")
        monitor.wait_for_open_port(3001)
        monitor.wait_until_succeeds(
            "curl -sf http://localhost:3001/api/health | jq -e '.database == \"ok\"'"
        )
        monitor.wait_until_succeeds(
            "curl -sf http://localhost:3001/api/datasources/uid/prometheus/health"
            " | jq -e '.status == \"OK\"'"
        )
        monitor.succeed(
            "curl -sf 'http://localhost:3001/api/search?query=Hydra'"
            " | jq -e 'map(select(.uid == \"hydra\")) | length == 1'"
        )

    with subtest("every panel query in the dashboard runs against prometheus"):
        monitor.succeed(
            "curl -sf http://localhost:3001/api/dashboards/uid/hydra"
            " | jq -r '[.dashboard.panels[], (.dashboard.panels[].panels // [])[]]"
            " | .[].targets[]?.expr'"
            " | sed -e 's/\\$__rate_interval/1m/g'"
            " -e 's/\\$machine/.*/g' -e 's/\\$platform/.*/g'"
            " > /tmp/exprs"
        )
        monitor.succeed("test $(wc -l < /tmp/exprs) -ge 40")
        monitor.succeed(
            "while read -r q; do"
            " curl -sfG --data-urlencode \"query=$q\" http://localhost:9090/api/v1/query"
            " > /dev/null || { echo \"bad query: $q\"; exit 1; };"
            " done < /tmp/exprs"
        )
  '';

  # interactive only: ports for the host browser, and more headroom
  interactive.nodes = {
    hydra = {
      virtualisation.memorySize = lib.mkForce 3072;
      virtualisation.forwardPorts = [
        {
          from = "host";
          host.port = 3000;
          guest.port = 3000;
        }
      ];
    };
    monitor = {
      virtualisation.memorySize = lib.mkForce 2048;
      virtualisation.forwardPorts = [
        {
          from = "host";
          host.port = 3001;
          guest.port = 3001;
        }
        {
          from = "host";
          host.port = 9090;
          guest.port = 9090;
        }
        {
          from = "host";
          host.port = 9093;
          guest.port = 9093;
        }
      ];
    };
  };
}
