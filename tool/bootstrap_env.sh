#!/usr/bin/env bash

set -euo pipefail

_saki_resolve_repo_root() {
  local from="${1:-}"
  if [ -n "$from" ]; then
    (cd "$from" && pwd)
    return
  fi
  (cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
}

_saki_ensure_node_bin() {
  local repo_root="$1"
  if command -v node >/dev/null 2>&1; then
    command -v node
    return
  fi
  "$repo_root/tool/ensure_node.sh" "$repo_root"
}

saki_setup_toolchain() {
  local repo_root
  repo_root="$(_saki_resolve_repo_root "${1:-}")"
  local node_bin
  node_bin="$(_saki_ensure_node_bin "$repo_root")"

  local exports_text
  exports_text="$("$node_bin" "$repo_root/tool/bootstrap_env.js" --repo-root "$repo_root" --format shell)"
  eval "$exports_text"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  saki_setup_toolchain "$(_saki_resolve_repo_root "${1:-}")"
  printf '%s\n' "Flutter: $SAKI_FLUTTER_BIN"
  printf '%s\n' "Node:    $SAKI_NODE_BIN"
fi
