{
  # align with the scrape interval
  interval ? "15s",
}:
let
  # json_exporter cannot multiply
  ms = record: raw: {
    inherit record;
    expr = "${raw} * 1000";
  };
in
{
  groups = [
    {
      name = "hydra-metrics-classic-native-units";
      inherit interval;
      rules = [
        (ms "hydraqueuerunner_steps_total_time_ms" "hydra_step_time_total")
        (ms "hydraqueuerunner_steps_total_build_time_ms" "hydra_step_build_time_total")
        (ms "hydraqueuerunner_steps_avg_total_time_ms" "hydra_avg_step_time_seconds")
        (ms "hydraqueuerunner_steps_avg_build_time_ms" "hydra_avg_step_build_time_seconds")
        (ms "hydraqueuerunner_machine_total_step_time_ms" "hydra_machine_step_time_total")
        (ms "hydraqueuerunner_machine_total_step_build_time_ms" "hydra_machine_step_build_time_total")
        (ms "hydraqueuerunner_machine_type_wait_time" "hydra_machine_type_wait_time_seconds")
      ];
    }
  ];
}
