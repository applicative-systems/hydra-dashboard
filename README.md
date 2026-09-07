# Official-grade observability for your private Hydra

Hydra measures queue depth, per-builder health and step timings, then hides
all of it in one JSON blob at `/queue-runner-status`; its built-in Prometheus
endpoint exports six metrics. The NixOS project bridged that gap with a
596-line custom Python re-exporter (2018–2026, [now retired](https://github.com/NixOS/infra/pull/1083/)).
This repo bridges it with the stock
[prometheus json_exporter](https://github.com/prometheus-community/json_exporter)
and a generated mapping: no Hydra patches, no exporter daemon to maintain.

## Design notes

- Metrics carry the names of the new Rust queue runner's native `/metrics`
  (`hydraqueuerunner_*`), which are the names the grafana.nixos.org dashboards
  query, so dashboard and rules keep working after a migration off the classic
  runner. Classic-only fields keep `hydra_*` names with the same labels and
  simply go empty then.
- The machine, system type and jobset lists are explicit options because
  json_exporter's JSONPath engine cannot turn JSON map keys into labels.
- Hydra omits some fields until they have a value (`avgStepTime` before the
  first finished step, `idleSince` while busy), so each field is its own
  exporter entry and goes missing on its own.
- Four dashboard rows ship collapsed: Grafana does not query a collapsed row,
  so the default view stays cheap on a large instance.
