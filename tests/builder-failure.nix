{ lib, ... }:
{
  name = "hydra-dashboard-builder-failure";

  nodes = {
    hydra = ./nodes/hydra.nix;
    builder1 = ./nodes/builder.nix;
    builder2 = ./nodes/builder.nix;
    monitor = ./nodes/monitor.nix;
  };

  testScript = ''
    status = (
        "curl -sf -H 'Accept: application/json' http://localhost:3000/queue-runner-status"
    )

    start_all()

    builder1.wait_for_unit("sshd.service")
    builder2.wait_for_unit("sshd.service")
    hydra.wait_for_unit("hydra-demo-setup.service")
    monitor.wait_for_unit("prometheus-json-exporter.service")

    with subtest("a wave of builds spreads over both builders"):
        hydra.succeed("demo-trigger-wave failure-demo")
        hydra.wait_until_succeeds(
            f"{status} | jq -e '.nrStepsBuilding >= 2'",
            timeout=600,
        )

    with subtest("a dying builder shows up as consecutive failures"):
        builder2.block()
        hydra.wait_until_succeeds(
            f"{status} | jq -e '.machines[\"ssh://root@builder2\"].consecutiveFailures >= 1'",
            timeout=600,
        )

    with subtest("the failure reaches the metrics pipeline"):
        probe = (
            "curl -sf 'http://localhost:7979/probe?module=hydra"
            "&target=http%3A%2F%2Fhydra%3A3000%2Fqueue-runner-status'"
        )
        monitor.wait_until_succeeds(
            f"{probe} | grep -E '^hydraqueuerunner_machine_consecutive_failures.hostname=.builder2.. [1-9]'"
        )

    with subtest("prometheus raises the alert for builder2"):
        monitor.wait_until_succeeds(
            "curl -sfG --data-urlencode"
            " 'query=ALERTS{alertname=\"HydraBuilderFailing\",hostname=\"builder2\",alertstate=\"firing\"}'"
            " http://localhost:9090/api/v1/query | jq -e '.data.result | length > 0'",
            timeout=300,
        )

    with subtest("the alert reaches alertmanager"):
        alerts = "curl -sf http://localhost:9093/api/v2/alerts"
        monitor.wait_until_succeeds(
            f"{alerts} | jq -e 'map(select(.labels.alertname == \"HydraBuilderFailing\""
            " and .labels.hostname == \"builder2\")) | length > 0'",
            timeout=300,
        )
        # hydra benches the machine, which is the critical alert
        monitor.wait_until_succeeds(
            f"{alerts} | jq -e 'map(select(.labels.alertname == \"HydraBuilderDisabled\""
            " and .labels.hostname == \"builder2\")) | length > 0'",
            timeout=300,
        )
        monitor.succeed(
            f"{alerts} | jq -e 'map(select(.labels.hostname == \"builder1\")) | length == 0'"
        )

    with subtest("the surviving builder keeps building"):
        hydra.wait_until_succeeds(
            f"{status} | jq -e '.machines[\"ssh://root@builder1\"].currentJobs >= 1'",
            timeout=300,
        )
  '';
}
