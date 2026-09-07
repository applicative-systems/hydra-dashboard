{
  # align with the scrape interval
  interval ? "15s",
  pendingFor ? "5m",
}:
{
  groups = [
    {
      name = "hydra-metrics-classic-builders";
      inherit interval;
      rules = [
        {
          alert = "HydraBuilderFailing";
          expr = "hydraqueuerunner_machine_consecutive_failures > 0";
          for = pendingFor;
          labels.severity = "warning";
          annotations = {
            summary = "Hydra builder {{ $labels.hostname }} is failing steps";
            description =
              "{{ $value }} step(s) in a row failed on {{ $labels.hostname }}. "
              + "Hydra drops a builder out of rotation once these pile up.";
          };
        }
        {
          # hydra already made the call, so no pending period
          alert = "HydraBuilderDisabled";
          expr = "hydra_machine_disabled_until > time()";
          labels.severity = "critical";
          annotations = {
            summary = "Hydra took builder {{ $labels.hostname }} out of rotation";
            description =
              "Too many failures in a row; {{ $labels.hostname }} is disabled until "
              + "{{ $value | humanizeTimestamp }}.";
          };
        }
        {
          alert = "HydraBuilderNotEnabled";
          expr = "hydra_machine_enabled == 0";
          for = pendingFor;
          labels.severity = "warning";
          annotations = {
            summary = "Hydra builder {{ $labels.hostname }} is not enabled";
            description =
              "{{ $labels.hostname }} is still in the machine list but Hydra is not " + "scheduling on it.";
          };
        }
        {
          alert = "HydraNoBuildersLeft";
          expr = "sum(hydra_machine_enabled) == 0";
          for = pendingFor;
          labels.severity = "critical";
          annotations = {
            summary = "Hydra has no usable build machines";
            description = "Every machine in the status JSON is disabled. Nothing can build.";
          };
        }
        {
          alert = "HydraStepsUnsupported";
          expr = "hydraqueuerunner_steps_unsupported > 0";
          for = "15m";
          labels.severity = "warning";
          annotations = {
            summary = "{{ $value }} queued step(s) have no machine that can build them";
            description =
              "No enabled builder offers the system type or features these steps need. "
              + "They stay queued until one shows up.";
          };
        }
        {
          alert = "HydraQueueRunnerStatusDown";
          expr = "up{job=\"hydra\"} == 0";
          for = pendingFor;
          labels.severity = "critical";
          annotations = {
            summary = "Hydra's queue-runner-status is unreachable";
            description =
              "The json_exporter could not scrape {{ $labels.instance }}, so none of "
              + "these alerts can fire on real data.";
          };
        }
      ];
    }
  ];
}
