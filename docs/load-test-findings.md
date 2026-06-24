# Load Test Findings

## Scope

This document is the M2.4 load-test worksheet for the WhatsApp Revenue Ops Platform public reference implementation.

It characterizes:

- mock-only Compose queue-mode worker scaling on one local machine,
- direct mock backend floor tests for `rag-api` and `sales-agent`, and
- a single-node kind deployment-under-load pass/fail check.

It does not claim production high availability, multi-node Kubernetes performance, real Gemini latency, real GoHighLevel throughput, or Compose-vs-Kubernetes performance parity.

## Environment

| Item | Value |
|---|---|
| Host CPU / memory | AMD Ryzen 7 7800X3D, 8 cores / 16 logical processors, 31.2 GiB RAM |
| Docker / Compose | Docker Desktop 4.73.0, Engine 29.4.3, Compose v5.1.3 |
| k6 | `k6.exe v2.0.0` |
| kind / kubectl | kind 0.32.0, kubectl client v1.34.1 |
| n8n | `n8nio/n8n:2.17.6` |
| Redis | `redis:7.2-alpine` |
| Qdrant | `qdrant/qdrant:v1.18.0` |
| Environment | `deploy/.env.mock` |
| Gemini path | Empty `GEMINI_API_KEY`, pure mock RAG |
| GHL path | `ghl-mock` only |

## Method

Compose queue-mode is the only horizontal comparison surface:

- A: direct `rag-api /chat` floor test.
- B: direct `sales-agent /agent/respond` floor test.
- C: n8n inbound webhook through the dedicated queue-mode webhook processor on `5680`, measured with `n8n-worker=1`, `2`, and `4`.

The Compose run used a 10 second warm-up, then three measured runs per scenario. Results below are medians from `scripts/run-load-tests.ps1` with `Vus=1` and `Duration=5s`. This is a conservative single-machine control run, intended to verify the measurement harness and worker participation rather than advertise a production ceiling.

kind is only a deployment-under-load validation:

- fixed worker scale,
- fixed VU/duration,
- no Pod restart increase,
- k6 error-rate threshold must pass,
- no RPS comparison against Compose.

## Compose Results

| Scenario | Worker scale | Median RPS | Median p50 ms | Median p95 ms | Median p99 ms | Median error rate | Notes |
|---|---:|---:|---:|---:|---:|---:|---|
| `rag-api /chat` | N/A | 732.38 | 1.06 | 1.59 | 2.09 | 0 | Pure mock RAG floor |
| `sales-agent /agent/respond` | N/A | 1.91 | 18.48 | 1381.12 | 7541.07 | 0 | FastAPI + Postgres + `ghl-mock` floor; local tail latency reflects sequential mock conversation work |
| n8n inbound | 1 | 35.08 | 27.90 | 33.00 | 37.93 | 0 | Queue-mode headline; `execution_entity` delta 505 |
| n8n inbound | 2 | 32.96 | 28.92 | 38.00 | 44.38 | 0 | Queue-mode headline; `execution_entity` delta 484 |
| n8n inbound | 4 | 25.74 | 33.40 | 45.83 | 54.80 | 0 | Queue-mode headline; `execution_entity` delta 408 |

## Queue Evidence

Redis / BullMQ keys are discovered dynamically with `redis-cli --scan`. Do not hard-code a public key pattern. In this run, queue-like keys included `bull:jobs:*`, while webhook cache keys used `n8n:cache:webhook:*`; both are n8n implementation details.

Durable completion evidence was the primary proof:

- n8n `execution_entity` count increased in every n8n inbound worker tier,
- Redis queue/cache keys were recorded as best-effort context,
- instantaneous `wait` depth was not required because mock jobs drain quickly,
- worker participation evidence increased from `1/1` to `2/2` to `4/4` containers with execution/workflow/job log evidence after the measured runs.

## Console Reply Smoke

`console/reply` is not a load scenario. It is a functional queue-mode debt retirement check. The M2.4 run created a unique ticket seed, posted `/webhook/console/reply` through host `5680`, and verified an outbound staff message in Postgres by `idempotency_key`.

## kind Under-Load Results

| Gate | Result | Evidence |
|---|---|---|
| Worker rollout completed before load | Pass | `deployment/n8n-worker` rolled out at 2 replicas |
| No Pod restart increase | Pass | restart counts before and after were identical |
| k6 error rate within threshold | Pass | 153 requests, error rate 0, checks rate 1 |
| RAG mock answer returned through webhook | Pass | k6 body checks passed through `n8n-webhook` port-forward |

Recorded kind validation: worker scale 2, `Vus=1`, `Duration=5s`, median-equivalent summary p50 32.26 ms, p95 36.73 ms, p99 44.98 ms, max 52.92 ms, RPS 30.45. This is a single-node deployment validation, not a throughput benchmark.

## Findings

1. The queue-mode path was stable across `1 / 2 / 4` workers with zero k6 errors and zero check failures.
2. On this one-VU local run, adding workers did not improve throughput. The likely ceiling is the single sequential webhook round trip plus n8n orchestration overhead, not worker capacity. A true horizontal-scaling benchmark should raise concurrency on a dedicated host.
3. Worker evidence still matters: even without a throughput gain at this load tier, execution deltas and worker logs proved that the queue-mode topology actually used the worker tier.
4. The direct `sales-agent` floor path has visible local tail latency because each request performs conversation state, scoring, audit writes, and mock GHL synchronization. This is useful as a bottleneck marker, not a blocker for M2.4.
5. Single-node kind stayed stable under the fixed validation load, with no Pod restart increase. Multi-node RWX storage and production HA remain outside this local baseline.

## Reproduction

```powershell
./scripts/run-load-tests.ps1 -WorkerScales 1,2,4 -RunsPerScenario 3 -WarmupSeconds 10 -Vus 1 -Duration 5s
./scripts/smoke-load-k8s.ps1 -WorkerScale 2 -Vus 1 -Duration 5s -WarmupSeconds 3
```

If host port `5432` is already occupied by a local PostgreSQL instance, pass a temporary Compose override that maps the container database to another host port. Do not commit that local override.

Raw summaries are written under `load/results/` for the local operator and are intentionally ignored by Git. The public repository commits this curated findings document, not raw time-series artifacts.

## Limitations

- Single-machine results are sensitive to host CPU, memory, disk, and Docker Desktop scheduling.
- Mock-only RAG does not measure real Gemini latency or quota behavior.
- `ghl-mock` is a single local mock service and may itself become a ceiling in sales-heavy load.
- Redis / BullMQ key names are n8n implementation details and should be treated as diagnostic context.
- The kind validation uses a single-node local cluster with the M2.3 storage compromise; it does not represent multi-node RWX storage or production HA.
- DB pool starvation, if observed at higher concurrency, should be recorded as a bottleneck finding rather than silently tuned away in `services/*`.

## Future Notes

- KEDA / HPA can be evaluated after these local data points exist.
- Production multi-node Kubernetes requires a real RWX storage class or a licensed external binary-data storage path supported by n8n.
- A future CI performance regression suite should use dedicated runners, not shared GitHub free runners.
