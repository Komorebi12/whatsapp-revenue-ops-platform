#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_NAME="${PROJECT_NAME:-revenueops-load}"

pwsh -NoLogo -File "$ROOT_DIR/scripts/run-load-tests.ps1" -ProjectName "$PROJECT_NAME" "$@"
