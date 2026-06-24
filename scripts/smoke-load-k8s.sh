#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pwsh -NoLogo -File "$ROOT_DIR/scripts/smoke-load-k8s.ps1" "$@"
