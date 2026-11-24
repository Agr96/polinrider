#!/usr/bin/env bash
# Legacy shim — all logic lives in bin/polinrider (see docs/PRD.md).
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$here/lib/legacy.sh"
legacy_exec "$here" sentinel "$@"
