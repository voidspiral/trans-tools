#!/bin/bash
# Build baseline vs staged libwr_fixture.so and a small ELF linked against /vol8/.../libwr_fixture.so.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VOL8_LIB_DIR="${WRAPPERSRUN_FIXTURE_VOL8_LIB:-/vol8/wr_run_fixture/lib}"
BUILD_DIR="${PROJECT_DIR}/build/wr_fixture"
CC="${CC:-gcc}"

mkdir -p "${BUILD_DIR}" "${VOL8_LIB_DIR}"

"${CC}" -shared -fPIC -fvisibility=hidden \
  -DWR_FIXTURE_MARKER=\"WR_FIXTURE_MARKER_VOL8_RAW\" \
  -o "${BUILD_DIR}/libwr_fixture_baseline.so" \
  "${PROJECT_DIR}/scripts/wrappersrun_fixture/libwr_fixture.c"

"${CC}" -shared -fPIC -fvisibility=hidden \
  -DWR_FIXTURE_MARKER=\"WR_FIXTURE_MARKER_FAKEFS_STAGED\" \
  -o "${BUILD_DIR}/libwr_fixture_staged.so" \
  "${PROJECT_DIR}/scripts/wrappersrun_fixture/libwr_fixture.c"

# Simulated Lustre path keeps the baseline fingerprint; staged copy is injected into deps tar via POST_DEPS_HOOK.
cp -f "${BUILD_DIR}/libwr_fixture_baseline.so" "${VOL8_LIB_DIR}/libwr_fixture.so"

"${CC}" -O0 -g \
  -o "${PROJECT_DIR}/bin/wrappersrun_fixture_prog" \
  "${PROJECT_DIR}/scripts/wrappersrun_fixture/wrappersrun_fixture_prog.c" \
  -L"${VOL8_LIB_DIR}" -lwr_fixture \
  -Wl,-rpath,"${VOL8_LIB_DIR}"

chmod a+rx "${PROJECT_DIR}/bin/wrappersrun_fixture_prog" || true
