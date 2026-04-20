#!/bin/bash
set -euo pipefail
if [[ "${1:-}" == "deps" ]]; then
  echo "mock_trans_tools_deps_fail: forcing deps failure" >&2
  exit 77
fi
echo "mock_trans_tools_deps_fail: unexpected argv: $*" >&2
exit 2
