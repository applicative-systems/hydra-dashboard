# Official-grade observability for your private Hydra

Hydra measures queue depth, per-builder health and step timings, then hides
all of it in one JSON blob at `/queue-runner-status`; its built-in Prometheus
endpoint exports six metrics. The NixOS project bridged that gap with a
596-line custom Python re-exporter (2018–2026, [now retired](https://github.com/NixOS/infra/pull/1083/)). This repo bridges
it with the stock [prometheus json_exporter](https://github.com/prometheus-community/json_exporter)
and a generated mapping: 76 metrics, no Hydra patches, no exporter daemon to maintain.
The metrics carry the same names as the new Rust queue runner's native `/metrics` (`hydraqueuerunner_*`), i.e. the names the current
grafana.nixos.org dashboards query.

Included: a reusable NixOS module, a Grafana dashboard that plots every
exported metric, a full NixOS VM integration test, and an interactive
demo.

## Quickstart

```console
$ nix flake check                 # fixture + alert-rule + dashboard checks, then the 4-VM test
$ nix run .#demo                  # interactive demo
```

The demo boots four VMs: `hydra` (web + evaluator + queue runner + postgres),
`builder1`/`builder2` (plain sshd build machines), and `monitor`
(json_exporter + Prometheus + Alertmanager + Grafana). Hydra: `localhost:3000`,
Grafana: `localhost:3001` (anonymous), Prometheus: `localhost:9090`,
Alertmanager: `localhost:9093`.

## Take home

On the host that already runs your Prometheus (Hydra stays untouched):

```nix
{
  imports = [ hydra-dashboard.nixosModules.default ];

  services.hydra-metrics-classic = {
    enable = true;
    hydraStatusUrl = "https://hydra.example.com/queue-runner-status";
    machines = [ "ssh://root@builder1" "ssh://root@builder2" ];
    systemTypes = [ "x86_64-linux" ];
    jobsets = [ "myproject:main" ];
  };
}
```

| Option | Default | Notes |
|---|---|---|
| `hydraStatusUrl` | `http://localhost:3000/queue-runner-status` | served by the Hydra *web* port, unauthenticated |
| `machines` | `[ ]` | URIs as in `/etc/nix/machines` |
| `systemTypes` | `[ "x86_64-linux" ]` | keys of `.machineTypes`, e.g. `"x86_64-linux:big-parallel"` |
| `jobsets` | `[ ]` | `"project:jobset"` names to export share/time metrics for |
| `scrapeInterval` | `15s` | each scrape runs `hydra-queue-runner --status` on the Hydra host |
| `exporterPort` | `7979` | json_exporter, bound to localhost |
| `configurePrometheus` | `true` | set `false` if Prometheus lives on another host |
| `alertRules` | `true` | install the alerting rules from `lib/alert-rules.nix` |
| `alertDelay` | `5m` | how long a builder must keep failing before its alert fires |

### Why the machine lists are explicit

json_exporter's JSONPath engine cannot turn JSON map *keys* into Prometheus
labels.

## The dashboard

`dashboards/hydra.json` (uid `hydra`) is a drop-in for any Grafana: import it,
or provision the directory as the demo does. Nothing in it is demo-specific.

| Section | | |
|---|---|---|
| **Queue** | open | ETA and backlog, burndown, step pipeline, retries, step-time breakdown, queue read latency |
| **Machines** | open | per-builder jobs, throughput, consecutive failures, disabled builders, busy time, idle time |
| **Platforms** | collapsed | runnable vs running and wait pressure per system type |
| **Jobsets** | collapsed | fair-share accounting: `shareUsed` and consumed build time |
| **Local store and binary cache** | collapsed | narinfo cache hit rate, NAR throughput, compression |
| **Queue runner internals** | collapsed | dispatcher, database, data transfer, uptime, scrape freshness |

Every panel names the `/queue-runner-status` field it came from in its
description, and every metric the exporter emits is plotted somewhere. Four
rows ship collapsed: Grafana does not query a collapsed row, so the default
view stays cheap on a large instance — open them as needed.

Built for portability: the datasource is a `$datasource` variable rather than
a hardcoded uid, per-machine and per-platform panels filter through `$machine`
and `$platform` (both default to All), and rate windows use
`$__rate_interval`, so the panels follow your scrape interval instead of
assuming this repo's.

Queries use the native `hydraqueuerunner_*` names throughout, so the dashboard
keeps working against a real new-runner `/metrics` after you migrate off the
classic runner. The panels fed by classic-only fields say so in their
description; they go empty rather than break.

## Alerts

`lib/alert-rules.nix` ships six rules, installed by default alongside the
recording rules. Point Prometheus at your Alertmanager the usual way
(`services.prometheus.alertmanagers`) and they route like anything else.

| Alert | Fires when | Severity |
|---|---|---|
| `HydraBuilderFailing` | a builder has failed steps back to back for `alertDelay` | warning |
| `HydraBuilderDisabled` | Hydra itself put a builder on the bench (`disabledUntil` in the future) — immediately, no pending period | critical |
| `HydraBuilderNotEnabled` | a machine is in the list but Hydra will not schedule on it | warning |
| `HydraNoBuildersLeft` | every machine is disabled, so nothing can build | critical |
| `HydraStepsUnsupported` | steps have waited 15m with no machine offering their system type or features | warning |
| `HydraQueueRunnerStatusDown` | the scrape of `/queue-runner-status` itself is failing | critical |

Each alert carries the `hostname` label straight through, so a notification
names the builder. `tests/alert-rules.yml` is a `promtool test rules` suite
that feeds synthetic series to the rules and asserts which ones fire, with
which labels and which rendered text — run it VM-free with
`nix build .#checks.x86_64-linux.alert-rules`. The VM test in turn kills a
builder for real and waits for the alert to show up in Alertmanager
(`nix build .#test-builder-failure`).

## What you get

- 46 scalar metrics: queue gauges (`hydraqueuerunner_builds_unfinished`,
  `hydraqueuerunner_steps_unfinished`, `hydraqueuerunner_steps_building`, ...),
  throughput counters (`hydraqueuerunner_builds_finished`,
  `hydraqueuerunner_steps_finished`, ...), dispatcher internals, nar/store
  stats (`hydraqueuerunner_store_nar_*`).
- 11 per machine (`hostname` label): `hydraqueuerunner_machine_current_jobs`,
  `hydraqueuerunner_machine_consecutive_failures`,
  `hydraqueuerunner_machine_steps_done`, step-time aggregates, ...
- 4 per system type (`machine_type`), 2 per jobset (`jobset_name`).

Wherever a field has a unit-faithful counterpart on the new queue runner it
gets the native name, so dashboard queries written against a real new-runner
`/metrics` work unchanged here. Where the classic JSON reports seconds and the
native metric is milliseconds, the raw seconds value is exported as-is
(`hydra_avg_step_time_seconds` & friends) and a bundled Prometheus recording rule derives
`hydraqueuerunner_steps_avg_total_time_ms`. Classic-only
fields with no new queue-runner counterpart keep legacy `hydra_*` names
(`hydra_machine_enabled`, `hydra_machine_disabled_until`,
`hydra_db_connections`, byte counters, ...), with native-style labels so they
join cleanly.

Fields Hydra emits conditionally (`avgStepTime` & friends only after the
first step finishes, `idleSince` only while idle, the whole `s3` block only
for S3 stores) each live in their own config entry.
