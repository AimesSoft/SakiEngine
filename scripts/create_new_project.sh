#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NODE_BIN="$("$REPO_ROOT/tool/ensure_node.sh" "$REPO_ROOT")"

exec "$NODE_BIN" "$REPO_ROOT/tool/saki_cli.js" create "$@"
