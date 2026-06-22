#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-revenue-ops}"
WORKER_SCALE="${WORKER_SCALE:-2}"
PORT_FORWARD_PORT="${PORT_FORWARD_PORT:-5680}"
READY_TIMEOUT_SECONDS="${READY_TIMEOUT_SECONDS:-600}"

cleanup() {
  if [[ -n "${PORT_FORWARD_PID:-}" ]]; then
    kill "$PORT_FORWARD_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

wait_port() {
  local deadline=$((SECONDS + 60))
  until (echo >"/dev/tcp/127.0.0.1/${PORT_FORWARD_PORT}") >/dev/null 2>&1; do
    if (( SECONDS >= deadline )); then
      echo "port ${PORT_FORWARD_PORT} did not become ready" >&2
      exit 1
    fi
    sleep 1
  done
}

echo "==> Wait for core deployments"
for deployment in postgres redis qdrant ghl-mock sales-agent ghl-sync rag-api n8n n8n-webhook n8n-worker; do
  kubectl -n "$NAMESPACE" rollout status "deployment/${deployment}" --timeout="${READY_TIMEOUT_SECONDS}s"
done

echo "==> Start port-forward to n8n-webhook"
kubectl -n "$NAMESPACE" port-forward svc/n8n-webhook "${PORT_FORWARD_PORT}:5678" >/tmp/revenueops-k8s-port-forward.log 2>&1 &
PORT_FORWARD_PID=$!
wait_port

post_webhook() {
  local ticket="$1"
  local intent="$2"
  local text="$3"
  curl -fsS \
    -H 'Content-Type: application/json' \
    -d "{\"customer_id\":\"11111111-1111-4111-8111-111111111111\",\"customer_phone\":\"+15551234567\",\"customer_display_name\":\"Demo Buyer\",\"message_id\":\"$(uuidgen)\",\"inbound_text\":\"${text}\",\"intent\":\"${intent}\",\"intent_confidence\":0.9,\"ticket_id\":\"${ticket}\"}" \
    "http://localhost:${PORT_FORWARD_PORT}/webhook/twilio/whatsapp/inbound"
}

echo "==> Assert sales path"
sales_response="$(post_webhook TICKET-K8S-SALES-SH-001 purchase 'I want pricing for your CRM automation product')"
echo "$sales_response" | grep -q 'qualification_tier'

echo "==> Assert RAG mock path"
rag_response="$(post_webhook TICKET-K8S-RAG-SH-001 information_query 'What is your return policy?')"
echo "$rag_response" | grep -q 'Mock RAG answer'
if echo "$rag_response" | grep -q '"fallback":true'; then
  echo "RAG path returned fallback=true" >&2
  exit 1
fi

echo "==> Scale n8n-worker"
kubectl -n "$NAMESPACE" scale deployment/n8n-worker --replicas="$WORKER_SCALE"
kubectl -n "$NAMESPACE" rollout status deployment/n8n-worker --timeout="${READY_TIMEOUT_SECONDS}s"

echo "==> Assert sales path after worker scale"
sales_scaled_response="$(post_webhook TICKET-K8S-SALES-SH-002 purchase 'I want pricing for your CRM automation product')"
echo "$sales_scaled_response" | grep -q 'qualification_tier'

echo "==> K8s smoke passed"
