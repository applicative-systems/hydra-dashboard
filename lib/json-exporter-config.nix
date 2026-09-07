{ lib }:
{
  machines ? [ ],
  systemTypes ? [ ],
  jobsets ? [ ],
}:
let
  hostLabel =
    uri:
    lib.pipe uri [
      (lib.removePrefix "ssh://")
      (lib.removePrefix "ssh-ng://")
      (lib.splitString "@")
      lib.last
    ];

  gauge = name: path: help: {
    inherit name path help;
    type = "value";
    valuetype = "gauge";
  };
  counter = name: path: help: {
    inherit name path help;
    type = "value";
    valuetype = "counter";
  };
  withLabels = labels: metric: metric // { inherit labels; };

  # k8s JSONPath needs bracket quoting for ':', '/', '@', '-' in keys, and
  # '@' (the current object) escaped even inside quotes
  sub =
    obj: key: field:
    "{ .${obj}['${lib.replaceStrings [ "@" ] [ "\\@" ] key}'].${field} }";

  topLevel =
    # hydraqueuerunner_* are the new rust runner's names, hydra_* has no
    # counterpart there
    [
      (gauge "hydraqueuerunner_uptime_seconds" "{ .uptime }"
        "uptime: seconds since the queue runner started"
      )
      (gauge "hydraqueuerunner_current_time_seconds" "{ .time }" "time: unix time of this status dump")
      (gauge "hydraqueuerunner_builds_unfinished" "{ .nrQueuedBuilds }"
        "nrQueuedBuilds: builds currently in the queue"
      )
      (counter "hydraqueuerunner_builds_read" "{ .nrBuildsRead }"
        "nrBuildsRead: builds read from the queue"
      )
      (counter "hydraqueuerunner_builds_read_time_ms" "{ .buildReadTimeMs }"
        "buildReadTimeMs: total time spent reading builds from the queue"
      )
      (counter "hydraqueuerunner_builds_finished" "{ .nrBuildsDone }"
        "nrBuildsDone: builds finished since start"
      )
      (gauge "hydraqueuerunner_steps_unfinished" "{ .nrUnfinishedSteps }"
        "nrUnfinishedSteps: build steps not yet finished"
      )
      (gauge "hydraqueuerunner_steps_runnable" "{ .nrRunnableSteps }"
        "nrRunnableSteps: steps ready to be dispatched"
      )
      (gauge "hydraqueuerunner_steps_building" "{ .nrStepsBuilding }"
        "nrStepsBuilding: steps currently building on a machine"
      )
      (gauge "hydraqueuerunner_steps_copying_to" "{ .nrStepsCopyingTo }"
        "nrStepsCopyingTo: steps copying inputs to a builder"
      )
      (gauge "hydraqueuerunner_steps_copying_from" "{ .nrStepsCopyingFrom }"
        "nrStepsCopyingFrom: steps copying outputs from a builder"
      )
      (gauge "hydraqueuerunner_steps_waiting" "{ .nrStepsWaiting }"
        "nrStepsWaiting: steps waiting on a machine slot"
      )
      (gauge "hydraqueuerunner_steps_unsupported" "{ .nrUnsupportedSteps }"
        "nrUnsupportedSteps: steps with no machine supporting their system type"
      )
      (counter "hydraqueuerunner_steps_started" "{ .nrStepsStarted }"
        "nrStepsStarted: build steps started since start"
      )
      (counter "hydraqueuerunner_steps_finished" "{ .nrStepsDone }"
        "nrStepsDone: build steps finished since start"
      )
      (counter "hydraqueuerunner_steps_retries" "{ .nrRetries }"
        "nrRetries: build step retries since start"
      )
      (gauge "hydraqueuerunner_steps_max_retries" "{ .maxNrRetries }"
        "maxNrRetries: highest retry count of any step"
      )
      (counter "hydraqueuerunner_dispatch_time_ms" "{ .dispatchTimeMs }"
        "dispatchTimeMs: total time spent dispatching"
      )
      (counter "hydraqueuerunner_dispatch_wakeup" "{ .nrDispatcherWakeups }"
        "nrDispatcherWakeups: dispatcher wakeups"
      )
    ]
    ++ [
      (gauge "hydra_steps_active" "{ .nrActiveSteps }"
        "nrActiveSteps: steps currently active (classic only)"
      )
      (counter "hydra_build_inputs_sent_bytes_total" "{ .bytesSent }"
        "bytesSent: bytes of build inputs sent to builders (classic only)"
      )
      (counter "hydra_build_outputs_received_bytes_total" "{ .bytesReceived }"
        "bytesReceived: bytes of build outputs received from builders (classic only)"
      )
      (gauge "hydra_builds_read_time_avg_ms" "{ .buildReadTimeAvgMs }"
        "buildReadTimeAvgMs: average time to read a build from the queue (classic only)"
      )
      (gauge "hydra_dispatch_time_avg_ms" "{ .dispatchTimeAvgMs }"
        "dispatchTimeAvgMs: average dispatch time (classic only)"
      )
      (counter "hydra_queue_wakeup_total" "{ .nrQueueWakeups }"
        "nrQueueWakeups: queue monitor wakeups (classic only)"
      )
      (gauge "hydra_db_connections" "{ .nrDbConnections }"
        "nrDbConnections: open database connections (classic only)"
      )
      (gauge "hydra_db_updates" "{ .nrActiveDbUpdates }"
        "nrActiveDbUpdates: active database updates (classic only)"
      )
    ]
    ++ [
      (counter "hydra_step_time_total" "{ .totalStepTime }"
        "totalStepTime: total time spent on steps, seconds (native ms series via recording rule)"
      )
      (counter "hydra_step_build_time_total" "{ .totalStepBuildTime }"
        "totalStepBuildTime: total time spent building, seconds (native ms series via recording rule)"
      )
      (gauge "hydra_avg_step_time_seconds" "{ .avgStepTime }"
        "avgStepTime: average step time, seconds (native ms series via recording rule)"
      )
      (gauge "hydra_avg_step_build_time_seconds" "{ .avgStepBuildTime }"
        "avgStepBuildTime: average step build time, seconds (native ms series via recording rule)"
      )
    ]
    ++ [
      (gauge "hydraqueuerunner_store_nar_info_read" "{ .store.narInfoRead }"
        "store.narInfoRead: narinfo files read"
      )
      (gauge "hydraqueuerunner_store_nar_info_read_averted" "{ .store.narInfoReadAverted }"
        "store.narInfoReadAverted: narinfo reads served from cache"
      )
      (gauge "hydraqueuerunner_store_nar_info_missing" "{ .store.narInfoMissing }"
        "store.narInfoMissing: narinfo lookups that found nothing"
      )
      (gauge "hydraqueuerunner_store_nar_info_write" "{ .store.narInfoWrite }"
        "store.narInfoWrite: narinfo files written"
      )
      (gauge "hydraqueuerunner_store_path_info_cache_size" "{ .store.narInfoCacheSize }"
        "store.narInfoCacheSize: entries in the narinfo cache"
      )
      (gauge "hydraqueuerunner_store_nar_read" "{ .store.narRead }" "store.narRead: NARs read")
      (gauge "hydraqueuerunner_store_nar_read_bytes" "{ .store.narReadBytes }"
        "store.narReadBytes: bytes of NARs read"
      )
      (gauge "hydraqueuerunner_store_nar_read_compressed_bytes" "{ .store.narReadCompressedBytes }"
        "store.narReadCompressedBytes: compressed bytes of NARs read"
      )
      (gauge "hydraqueuerunner_store_nar_write" "{ .store.narWrite }" "store.narWrite: NARs written")
      (gauge "hydraqueuerunner_store_nar_write_averted" "{ .store.narWriteAverted }"
        "store.narWriteAverted: NAR writes averted"
      )
      (gauge "hydraqueuerunner_store_nar_write_bytes" "{ .store.narWriteBytes }"
        "store.narWriteBytes: bytes of NARs written"
      )
      (gauge "hydraqueuerunner_store_nar_write_compressed_bytes" "{ .store.narWriteCompressedBytes }"
        "store.narWriteCompressedBytes: compressed bytes of NARs written"
      )
      (gauge "hydraqueuerunner_store_nar_write_compression_time_ms" "{ .store.narWriteCompressionTimeMs }"
        "store.narWriteCompressionTimeMs: time spent compressing NARs"
      )
      (gauge "hydraqueuerunner_store_nar_compression_savings" "{ .store.narCompressionSavings }"
        "store.narCompressionSavings: compression savings ratio"
      )
      (gauge "hydraqueuerunner_store_nar_compression_speed" "{ .store.narCompressionSpeed }"
        "store.narCompressionSpeed: compression speed, MiB/s"
      )
    ];

  perMachine = lib.concatMap (
    uri:
    let
      l = {
        hostname = hostLabel uri;
      };
      m = sub "machines" uri;
    in
    map (withLabels l) (
      [
        (gauge "hydraqueuerunner_machine_current_jobs" (m "currentJobs")
          "machines.*.currentJobs: steps currently running on this machine"
        )
        (gauge "hydraqueuerunner_machine_steps_done" (m "nrStepsDone")
          "machines.*.nrStepsDone: steps finished on this machine"
        )
        (gauge "hydraqueuerunner_machine_consecutive_failures" (m "consecutiveFailures")
          "machines.*.consecutiveFailures: consecutive failed steps"
        )
      ]
      ++ [
        (gauge "hydraqueuerunner_machine_idle_since_timestamp" (m "idleSince")
          "machines.*.idleSince: unix time since which the machine has been idle"
        )
      ]
      ++ [
        (gauge "hydra_machine_enabled" (m "enabled")
          "machines.*.enabled: 1 if the machine is enabled (classic only)"
        )
        (gauge "hydra_machine_disabled_until" (m "disabledUntil")
          "machines.*.disabledUntil: unix time until which the machine is disabled after failures (classic only)"
        )
        (gauge "hydra_machine_last_failure" (m "lastFailure")
          "machines.*.lastFailure: unix time of the last failure (classic only)"
        )
      ]
      ++ [
        (counter "hydra_machine_step_time_total" (m "totalStepTime")
          "machines.*.totalStepTime: total step time on this machine, seconds (native ms series via recording rule)"
        )
        (counter "hydra_machine_step_build_time_total" (m "totalStepBuildTime")
          "machines.*.totalStepBuildTime: total build time on this machine, seconds (native ms series via recording rule)"
        )
        (gauge "hydra_machine_avg_step_time_seconds" (m "avgStepTime")
          "machines.*.avgStepTime: average step time on this machine, seconds (classic only)"
        )
        (gauge "hydra_machine_avg_step_build_time_seconds" (m "avgStepBuildTime")
          "machines.*.avgStepBuildTime: average build time on this machine, seconds (classic only)"
        )
      ]
    )
  ) machines;

  perMachineType = lib.concatMap (
    t:
    let
      l = {
        machine_type = t;
      };
      m = sub "machineTypes" t;
    in
    map (withLabels l) [
      (gauge "hydraqueuerunner_machine_type_runnable" (m "runnable")
        "machineTypes.*.runnable: steps runnable for this system type"
      )
      (gauge "hydraqueuerunner_machine_type_running" (m "running")
        "machineTypes.*.running: steps running for this system type"
      )
      (counter "hydra_machine_type_wait_time_seconds" (m "waitTime")
        "machineTypes.*.waitTime: cumulative wait time of runnable steps, seconds (native ms series via recording rule)"
      )
      (gauge "hydra_machine_type_last_active" (m "lastActive")
        "machineTypes.*.lastActive: unix time this system type was last active (classic only)"
      )
    ]
  ) systemTypes;

  perJobset = lib.concatMap (
    js:
    let
      l = {
        jobset_name = js;
      };
      m = sub "jobsets" js;
    in
    map (withLabels l) [
      (gauge "hydraqueuerunner_jobset_seconds" (m "seconds")
        "jobsets.*.seconds: build time consumed by this jobset"
      )
      (gauge "hydraqueuerunner_jobset_share_used" (m "shareUsed")
        "jobsets.*.shareUsed: scheduling shares consumed by this jobset"
      )
    ]
  ) jobsets;
in
{
  modules.hydra = {
    # hydra's /queue-runner-status does content negotiation
    headers.Accept = "application/json";
    metrics = topLevel ++ perMachine ++ perMachineType ++ perJobset;
  };
}
