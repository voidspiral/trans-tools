#!/bin/bash
# After trans-tools deps, replace libwr_fixture.so inside *_so.tar with staged fingerprint build.
set -euo pipefail

PROJECT_DIR="${WRAPPERSRUN_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DEST="${WRAPPERSRUN_DEPS_DEST:-/tmp/dependencies}"
STAGED="${WRAPPERSRUN_FIXTURE_STAGED_SO:-${PROJECT_DIR}/build/wr_fixture/libwr_fixture_staged.so}"

if [[ ! -f "${STAGED}" ]]; then
  echo "[fixture-patch] staged library missing: ${STAGED}" >&2
  exit 1
fi

shopt -s nullglob
patched=0
for t in "${DEST}"/*_so.tar; do
  [[ -f "${t}" ]] || continue
  if ! tar tf "${t}" | grep -q 'libwr_fixture\.so'; then
    continue
  fi
  echo "[fixture-patch] patching tar=$(basename "${t}")"
  work="$(mktemp -d)"
  tar xf "${t}" -C "${work}"
  tgt="$(find "${work}" -name libwr_fixture.so -type f | head -1)"
  if [[ -z "${tgt}" ]]; then
    echo "[fixture-patch] libwr_fixture.so not found inside ${t}" >&2
    rm -rf "${work}"
    exit 1
  fi
  cp -f "${STAGED}" "${tgt}"
  if ! ( cd "${work}" && tar cf "${t}.new" . ); then
    echo "[fixture-patch] repack failed for ${t}" >&2
    rm -rf "${work}"
    exit 1
  fi
  mv -f "${t}.new" "${t}"
  rm -rf "${work}"
  patched=$((patched + 1))
done

if [[ "${patched}" -eq 0 ]]; then
  echo "[fixture-patch] no matching *_so.tar under ${DEST} (expected libwr_fixture.so member)" >&2
  exit 1
fi
