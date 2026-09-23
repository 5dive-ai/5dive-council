#!/usr/bin/env bash
# DIVE-4891 — the controls. A port's suite is the easiest place to write arms that
# cannot fail, so each mutant below re-opens one decision this move made and names
# the harness that must go RED on it. A mutant that stays green is a FAIL here.
#
#   M1 the seal goes back in-process    (cmd_gate_proof sign)  -> council_plugin_unit P3
#   M2 the trailer stops stripping --json                       -> council_plugin_unit P6
#   M3 rot-triage loses the gate-file time (task ls has none)   -> council_gate_e2e leg C
#   M4 an UNMARKED divergence from core's template              -> council_plugin_unit P4
#   M5 a task row read by SQL again (db/sqlq)                   -> council_plugin_unit P3
#
# Each runs in a throwaway copy of the tree, so the checkout is never touched.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"
. tests/lib/core.sh
TMP="$(mktemp -d "${TMPDIR:-/tmp}/council-mutants.XXXXXX")"
trap 'rc=$?; rm -rf "$TMP"; echo "HARNESS-RC=$rc"' EXIT
PASS=0; FAIL=0

mutant() { # <id> <file> <python-replace-old> <python-replace-new> <harness>
  local id="$1" file="$2" old="$3" new="$4" harness="$5" w="$TMP/$1"
  mkdir -p "$w"
  (cd "$ROOT" && tar --exclude=./.git --exclude=./.core --exclude=./.core-council --exclude=./5dive -cf - .) | (cd "$w" && tar -xf -)
  if ! python3 - "$w/$file" "$old" "$new" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p).read()
if s.count(old) != 1: sys.exit(f"anchor matched {s.count(old)} times")
open(p, 'w').write(s.replace(old, new))
PY
  then FAIL=$((FAIL+1)); echo "FAIL $id: the mutant's anchor no longer matches $file — re-anchor it"; return; fi
  (cd "$w" && node council/src/gen.mjs >/dev/null 2>&1)
  local rc=0
  (cd "$w" && FIVEDIVE_CORE_DIR="$FIVEDIVE_CORE_DIR" bash tests/run_all.sh "$harness" >"$w.log" 2>&1) || rc=$?
  if (( rc != 0 )); then PASS=$((PASS+1)); echo "ok   $id: $harness went RED ($(grep -m1 -E '^FAIL [PM][0-9]|^  FAIL: ' "$w.log" | sed 's/^ *//' | cut -c1-110))"
  else FAIL=$((FAIL+1)); echo "FAIL $id: $harness stayed GREEN on the mutant"; fi
}

mutant M1 council/src/prelude.sh \
  'if [[ "$(id -u)" -eq 0 ]]; then _council_core gate-proof sign' \
  'if [[ "$(id -u)" -eq 0 ]]; then cmd_gate_proof sign' \
  council_plugin_unit
mutant M2 council/src/gen.mjs \
  'if [[ "$_council_a" == "--json" ]]; then JSON_MODE=1; else' \
  'if false; then JSON_MODE=1; else' \
  council_plugin_unit
mutant M3 council/src/council/cmd_council.template.sh \
  "_asked=\"\$(_council_task_json \"\$_cand\" | jq -r '.need_asked_at // empty' 2>/dev/null)\" || _asked=\"\"" \
  '_asked=""' \
  council_gate_e2e
mutant M4 council/src/council/cmd_council.template.sh \
  'COUNCIL_DIR="${STATE_DIR}/council"' \
  'COUNCIL_DIR="${STATE_DIR}/council"  # a quiet local edit' \
  council_plugin_unit
mutant M5 council/src/council/cmd_council.template.sh \
  "    st=\"\$(_council_task_json \"\$subj\" | jq -r '.status // empty' 2>/dev/null)\" || st=\"\"" \
  "    st=\"\$(db \"SELECT status FROM tasks WHERE ident=\$(sqlq \"\$subj\") LIMIT 1;\" 2>/dev/null)\"" \
  council_plugin_unit

printf '\ncouncil_mutants: %d red as required, %d not\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
