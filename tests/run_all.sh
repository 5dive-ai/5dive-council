#!/usr/bin/env bash
# DIVE-4891 — run every carried council harness against the plugin + a core CLI.
# Usage: bash tests/run_all.sh [pattern]   (FIVEDIVE_CORE_DIR = a built core checkout)
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"
. tests/lib/core.sh
council_write_shim || exit 1
pat="${1:-}"
# The harnesses that seal (gate-proof) or init an isolated task store need root. In
# core they re-exec themselves under `sudo -n`; the env isolation they source turns
# `sudo` into a refusing function first, so each would SKIP. Run exactly those as
# root from here, and everything else as the invoking user, as each was written.
ROOT_HARNESSES=" council_plugin_unit.sh council_amend_e2e.sh council_ballot_e2e.sh council_gate_e2e.sh council_notify_e2e.sh council_record_e2e.sh council_roster_lineage_e2e.sh council_veto_e2e.sh "
as_root() {
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then "$@"
  else command sudo -n env PATH="$PATH" FIVEDIVE_CORE_DIR="$FIVEDIVE_CORE_DIR" FIVEDIVE_CORE_COUNCIL_DIR="${FIVEDIVE_CORE_COUNCIL_DIR:-}" HOME="${HOME:-/root}" "$@"; fi
}
pass=0; failn=0; failed=()
for t in tests/council_*; do
  [[ -z "$pat" || "$t" == *"$pat"* ]] || continue
  [[ "$t" == tests/council_mutants.sh ]] && continue   # the controls run on their own (CI step)
  case "$t" in
    *.mjs) out="$(timeout 900 node "$t" 2>&1)"; rc=$? ;;
    *.sh)  if [[ "$ROOT_HARNESSES" == *" $(basename "$t") "* ]]; then out="$(as_root timeout 900 bash "$t" 2>&1)"; rc=$?
           else out="$(timeout 900 bash "$t" 2>&1)"; rc=$?; fi ;;
    *) continue ;;
  esac
  if [[ $rc -eq 0 ]] && ! grep -q '^SKIP:' <<<"$out"; then pass=$((pass+1)); printf 'PASS %s  %s\n' "$t" "$(grep -E 'passed|[0-9]+ pass|ok ' <<<"$out" | tail -1 | cut -c1-120)"
  elif [[ $rc -eq 0 ]]; then printf 'SKIP %s  %s\n' "$t" "$(grep '^SKIP:' <<<"$out" | head -1 | cut -c1-140)"; failed+=("$t(skip)"); failn=$((failn+1))
  else failn=$((failn+1)); failed+=("$t"); printf 'FAIL %s rc=%s\n%s\n' "$t" "$rc" "$(tail -15 <<<"$out")"; fi
done
printf '\ncouncil plugin harnesses: %d passed, %d not passed %s\n' "$pass" "$failn" "${failed[*]:-}"
[[ $failn -eq 0 ]]
