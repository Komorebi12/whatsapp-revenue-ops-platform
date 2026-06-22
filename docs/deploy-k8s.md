# Deploy on Kubernetes (kind)

This guide runs the mock-first queue-mode topology on a local `kind` cluster. It is a Kubernetes translation of the Compose queue-mode stack in `docs/queue-mode.md`, not a production HA chart.

The baseline deploys:

- Postgres, Redis, Qdrant, n8n main, n8n webhook, n8n worker
- `sales-agent`, `ghl-sync`, `ghl-mock`, and `rag-api`
- optional ingress routing for `/webhook`
- optional `operator-console` overlay, kept out of the default base because it needs Clerk keys

## Prerequisites

- Docker Desktop or another Docker engine
- `kind`
- `kubectl` with built-in kustomize support
- PowerShell 7+ for the bundled smoke scripts on Windows

Check local tooling:

```powershell
docker version
kind version
kubectl version --client
```

## Create a cluster

For the port-forward smoke path, a default cluster is enough:

```powershell
kind create cluster --name revenue-ops
```

If you also want to test ingress on host ports `80` and `443`, create the cluster with the provided config:

```powershell
kind create cluster --name revenue-ops --config .\deploy\k8s\kind\kind-config.yaml
```

Ingress is optional for M2.3. The acceptance smoke uses `kubectl port-forward` so local ingress-nginx mapping issues do not block the baseline.

## Build and load local images

The public images (`postgres:16`, `redis:7.2-alpine`, `qdrant/qdrant:v1.18.0`, `n8nio/n8n:2.17.6`) are pulled normally. The custom services use local `:local-dev` tags and `imagePullPolicy: IfNotPresent`.

```powershell
docker build -t sales-agent:local-dev -f .\deploy\docker\sales-agent.Dockerfile .
docker build -t ghl-sync:local-dev -f .\deploy\docker\ghl-sync.Dockerfile .
docker build -t rag-api:local-dev -f .\deploy\docker\rag-api.Dockerfile .
docker build -t ghl-mock:local-dev .\mock\ghl-mock-server

kind load docker-image `
  sales-agent:local-dev `
  ghl-sync:local-dev `
  rag-api:local-dev `
  ghl-mock:local-dev `
  --name revenue-ops
```

For the optional console overlay:

```powershell
docker build -t operator-console:local-dev -f .\deploy\docker\operator-console.Dockerfile .
kind load docker-image operator-console:local-dev --name revenue-ops
```

Avoid `:latest` for local kind images. Kubernetes defaults `:latest` to `imagePullPolicy: Always`, which bypasses the kind image cache.

## Verify manifests

Run the static gate before applying:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\verify-k8s-manifests.ps1
```

This renders `deploy/k8s/base`, checks the webhook/worker `args` translation, enforces the Redis `7.2-alpine` tag, checks Recreate strategy placement, and verifies that K8s asset mirrors match the source SQL/workflow/bootstrap files.

## Apply the base

```powershell
kubectl apply -k .\deploy\k8s\base
```

Wait for rollouts:

```powershell
kubectl -n revenue-ops get pods
kubectl -n revenue-ops rollout status deployment/postgres --timeout=600s
kubectl -n revenue-ops rollout status deployment/n8n --timeout=600s
kubectl -n revenue-ops rollout status deployment/n8n-webhook --timeout=600s
kubectl -n revenue-ops rollout status deployment/n8n-worker --timeout=600s
```

The n8n main pod has the widest startup probe because it runs Postgres metadata migration, imports credentials/workflows, publishes workflows, and only then starts `n8n`.

## Smoke test

Run the bundled smoke:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\smoke-k8s.ps1 -WorkerScale 2
```

The smoke:

- waits for core deployments,
- checks `rag-api /health` reports `mock_mode=true`,
- port-forwards `svc/n8n-webhook` to local `5680`,
- sends one sales webhook and one RAG mock webhook,
- scales `n8n-worker` to two replicas,
- sends another webhook after scaling, and
- checks Redis for queue-like keys.

You can run the core port-forward manually:

```powershell
kubectl -n revenue-ops port-forward svc/n8n-webhook 5680:5678
```

Then POST to:

```text
http://localhost:5680/webhook/twilio/whatsapp/inbound
```

## Optional console overlay

The console mirrors the Compose `console` profile and is not part of the default base.

```powershell
kubectl apply -k .\deploy\k8s\overlays\console
```

For non-mock usage, provide Clerk values through a real Secret outside git. The committed base intentionally keeps `operator-console` opt-in so the default K8s path remains mock-first.

## Optional ingress route

If your kind cluster was created with `deploy/k8s/kind/kind-config.yaml`, install ingress-nginx for kind, then route `/webhook` to `n8n-webhook`.

The ingress path is a production-style routing demonstration. It is intentionally not the M2.3 acceptance gate because host port conflicts and ingress controller startup can vary across local machines.

## Scale workers

```powershell
kubectl -n revenue-ops scale deployment/n8n-worker --replicas=2
kubectl -n revenue-ops rollout status deployment/n8n-worker --timeout=600s
```

`n8n-worker` intentionally keeps the default RollingUpdate strategy. Worker replicas are queue consumers, and concurrent access to the shared `n8n-data` volume is the steady-state design.

Postgres, Qdrant, n8n main, and n8n webhook use `strategy: Recreate` to avoid two writers touching the same backing directory during a rollout window. This is about write overlap and data safety, not Multi-Attach: kind's default local-path storage is hostPath-style and does not use CSI attach/detach.

## Storage tradeoff (read before production)

This kind baseline mounts a single `ReadWriteOnce` PVC (`n8n-data`) into the n8n main, webhook, and worker Deployments at the same time. This works **only because kind runs a single node**: in Kubernetes, `ReadWriteOnce` means the volume is mountable read-write by one *node*, and multiple pods on that one node may share it. kind's default local-path provisioner is a hostPath-style local directory and does not perform volume attach/detach, so no Multi-Attach error occurs here.

This is a **local reference compromise, not a production pattern**. If you scale this to a multi-node cluster:

- pin all n8n pods to the same node with a `nodeSelector` or pod affinity (degrades availability), **or**
- switch `n8n-data` to a real `ReadWriteMany` storage class (e.g. NFS, CephFS, EFS, Azure Files), **or**
- use an n8n-supported external binary-data storage option.

**On object storage:** n8n's S3 external binary-data mode is a paid / Enterprise-plan feature depending on n8n version and is intentionally **not** implemented in this public baseline. This repo does not add MinIO or any S3 service. Treat S3/RWX as the production route, documented here as a note only.

The same full-`.n8n` sharing tradeoff documented in `docs/queue-mode.md` applies: runtime config and the append-only event log are also shared across the three processes. On a single-node local demo this is benign (no shared mutable database file; all relational state lives in Postgres).

## ConfigMap size note

`deploy/k8s/base` mirrors the three SQL init files into a ConfigMap. Kubernetes ConfigMaps are backed by etcd and have an effective object size ceiling around 1 MiB. The current mock seed files are far below that limit, and `scripts/verify-k8s-manifests.ps1` checks the size explicitly.

If future sample data grows near the limit, do not keep expanding the ConfigMap. Move init data to a PVC-mounted file set or a dedicated migration/init image.

## Local reset

The cleanest reset is to delete the local kind cluster:

```powershell
kind delete cluster --name revenue-ops
```

This does not delete unrelated Docker volumes outside the cluster.

## Troubleshooting

`ImagePullBackOff`

: Rebuild and reload the `:local-dev` images into kind. Check for accidental `:latest` tags.

`n8n-webhook` or `n8n-worker` stuck in init

: Check `deployment/n8n` first. Webhook and worker wait for `http://n8n:5678/healthz`, which only succeeds after main imports and activates workflows.

Webhook returns `404`

: Confirm the n8n main logs show workflow import and publish before the webhook process starts. The committed `bootstrap-entrypoint.sh` imports credentials/workflows and publishes workflows before `exec n8n start`.

PVC pending

: Confirm the cluster has a default StorageClass. kind normally provides local-path storage.

Port `5680` busy

: Use `-PortForwardPort` with `scripts/smoke-k8s.ps1`, for example `-PortForwardPort 5681`.

## Non-goals

M2.3 does not add k6 benchmarks, HPA/KEDA, Helm, Terraform, MinIO/S3, service mesh, multi-tenant SaaS controls, or production HA claims. Load testing and K8s deployment validation under load belong to M2.4.

