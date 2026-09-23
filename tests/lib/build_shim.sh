#!/usr/bin/env bash
# tests/lib/build_shim.sh <out> — DIVE-4891. Stands in for core's `BUILD_OUT=<out> ./build.sh`.
# The carried harnesses built a throwaway core bundle to drive `council`; here the
# "build" is the same shim tests/lib/core.sh writes, at the path the harness asked for.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/core.sh"
out="${1:?usage: build_shim.sh <out>}"
council_write_shim || exit 1
[[ "$out" -ef "$ROOT/5dive" ]] || install -m 0755 "$ROOT/5dive" "$out"
