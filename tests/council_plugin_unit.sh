#!/usr/bin/env bash
# DIVE-4891 — `council` as a standalone plugin: the arms that say whether this repo
# owns what it is supposed to own, and reaches core only through core's CLI.
#
# The 29 carried harnesses (tests/council_*) grade council's BEHAVIOUR; they came
# from core and pass here with core's counts. What they cannot grade is the move
# itself, so this file does:
#
#   P1  the install shape    — manifest name = folder = marketplace source, and the
#                              verb resolves to an executable council/bin/council.
#   P2  generated, not edited — council/bin/council is exactly what gen.mjs makes.
#   P3  no in-process core   — the bin calls none of core's internal functions, and
#                              the CLI seams it uses instead are really wired.
#   P4  carried verbatim     — engine/cli/constitution are byte-identical to core's,
#                              and the template differs from core's ONLY at the
#                              marked PLUGIN DIVERGENCE sites, while core main still
#                              carries a copy; the parser stays held to core forever.
#   P5  the store survives   — a lineage sealed by core's BUILT-IN council verifies
#                              under this plugin, and a plugin-sealed record verifies
#                              under core's reader. Needs root and a core that still
#                              has council (FIVEDIVE_CORE_COUNCIL_DIR, pinned in CI).
#   P6  the --json shape     — core stripped `--json` before cmd_council; so does the
#                              entry trailer, wherever the flag sits.
#   P7  the dry-run guard    — _mirror_send can never reach a human under
#                              FIVEDIVE_NOTIFY_DRYRUN (DIVE-1500), carried verbatim.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib/grading_tree.sh" \
  || printf 'grading tree: UNRESOLVED (tests/lib/grading_tree.sh not reachable; no tree named)\n' >&2
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"
BIN="${COUNCIL_BIN:-$ROOT/council/bin/council}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/council-plugin-unit.XXXXXX")"
trap 'rc=$?; rm -rf "$TMP"; echo "HARNESS-RC=$rc"' EXIT
PASS=0; FAIL=0; SKIP=0
t() { if [[ "$2" == "$3" ]]; then PASS=$((PASS+1)); printf 'ok   %s\n' "$1"; else FAIL=$((FAIL+1)); printf 'FAIL %s\n       want: %s\n       got : %s\n' "$1" "$2" "${3:0:400}"; fi; }
skip() { SKIP=$((SKIP+1)); printf 'SKIP %s — %s\n' "$1" "$2"; }

# ---- P1 install shape ------------------------------------------------------------------------
t "P1 manifest name is its folder name (contract §1)" council "$(jq -r .name council/.claude-plugin/plugin.json)"
t "P1 marketplace source names that folder (trap D)" ./council "$(jq -r '.plugins[]|select(.name=="council")|.source' .claude-plugin/marketplace.json)"
t "P1 the repo offers exactly one plugin (one-command install)" 1 "$(jq '.plugins|length' .claude-plugin/marketplace.json)"
t "P1 the verb is declared with the verb capability" "council verb" \
  "$(jq -r '[.fivedive.verbs[0].name, (.fivedive.capabilities|index("verb")|if .==null then "none" else "verb" end)]|join(" ")' council/.claude-plugin/plugin.json)"
t "P1 council/bin/council is executable in the tree" 0 "$([[ -x council/bin/council ]]; echo $?)"

# ---- P2 generated ----------------------------------------------------------------------------
t "P2 council/bin/council is what gen.mjs produces" 0 "$(node council/src/gen.mjs --check >/dev/null 2>&1; echo $?)"
t "P2 the bin parses" 0 "$(bash -n "$BIN" 2>/dev/null; echo $?)"

# ---- P3 no in-process core -------------------------------------------------------------------
# Every core internal the carried body used to call in-process. A CALL is the name followed by a
# space, `(`, `"`, `$` or end-of-line outside a comment; the names also appear in comments
# explaining the divergence, which is why comments are stripped first.
CORE_INTERNALS='db|sqlq|_task_agent_channel|_task_owner_channel|cmd_gate_proof|registry_read|with_registry_lock|actor_routing_agent|_gate_caller_uid|_tg_access_state_dir|cmd_task_[a-z_]+|audit_init|_emit_audit_line|ensure_state'
calls="$(sed -e 's/^[[:space:]]*#.*$//' "$BIN" | grep -nE "(^|[;&|({[:space:]]|\\\$\\()(${CORE_INTERNALS})([[:space:]]|\"|\\(|\$)" | grep -vE '^[0-9]+:\s*(//|\*)' | head -5)"
t "P3 the bin makes no in-process call to a core internal" "" "$calls"
# The functions the carried body calls that core USED to supply must now be defined here.
for f in fail ok warn audit_log require_node ensure_node_on_path _mirror_send cmd_gate_proof_sign_stdin \
         _init_pick _init_text _init_section _init_ok _init_note _init_warn _init_review_row _init_color_enabled; do
  got="$(bash -c 'source "$1" >/dev/null 2>&1; declare -F "$2" >/dev/null && echo defined || echo missing' _ "$BIN" "$f")"
  t "P3 $f is defined by the plugin itself" defined "$got"
done
# The seams are REAL: drive them against a stub core and read what it was asked.
STUB="$TMP/stub5dive"; LOG="$TMP/stub.log"
cat > "$STUB" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG"
case "$1 $2" in
  "gate-proof sign") cat >/dev/null; echo stubseal ;;
  "task show") printf '{"ok":true,"data":{"task":{"ident":"%s","status":"done","need_type":"decision","tier":2,"recommend":"ship","need_options":"ship|hold","ask":"Ship it?","need_answered_at":null}}}\n' "$3" ;;
  "agent telegram-access") printf '{"ok":true,"data":{"access":{"allowFrom":["4242"]}}}\n' ;;
  "_audit_append ") cat >> "$STUB_LOG" ;;
esac
EOF
chmod +x "$STUB"
seam() { STUB_LOG="$LOG" COUNCIL_5DIVE_BIN="$STUB" bash -c 'source "$1"; shift; "$@"' _ "$BIN" "$@" 2>/dev/null; }
: > "$LOG"
# `id` is shadowed to report root so the arm drives the in-process branch core used to take
# (`cmd_gate_proof sign`) without needing root: that branch must now be the CLI verb.
t "P3 the root seal goes through 'gate-proof sign'" stubseal "$(printf x | seam bash -c 'id() { echo 0; }; source "$0"; cmd_gate_proof_sign_stdin' "$BIN")"
t "P3 ...and the stub core was asked for exactly that verb" "gate-proof sign" "$(tail -1 "$LOG")"
t "P3 a task row is read through 'task show --json'" '"done"' "$(seam _council_task_json DIVE-7 | jq -c .status)"
t "P3 the gate json keeps core's live predicate (done row -> live 0)" 0 "$(seam _council_gate_json /tmp DIVE-7 | jq -r .live)"
t "P3 human:<agent> resolves through 'agent telegram-access get'" 4242 "$(seam _council_resolve_principal human:main)"
t "P3 tg:<id> resolves with no core call at all" 99 "$(: > "$LOG"; seam _council_resolve_principal tg:99; )"
t "P3 ...and really made none" 0 "$(grep -c . "$LOG")"
if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
  seam audit_log "council convene" error 7 -- "refused=x" >/dev/null
  t "P3 audit rows go to core's append-only primitive (as root)" '"council convene"' "$(grep -F '"via":"council-plugin"' "$LOG" | jq -c .cmd)"
else
  AS="$TMP/audit.ndjson"
  COUNCIL_AUDIT_SINK="$AS" seam audit_log "council convene" error 7 -- "refused=x" >/dev/null
  t "P3 audit_log renders core's row shape (cmd/result/code/args)" '"council convene" "error" 7 ["refused=x"]' \
    "$(jq -r '[(.cmd|tojson),(.result|tojson),(.code|tostring),(.args|tojson)]|join(" ")' "$AS")"
fi

# ---- P4 carried verbatim ---------------------------------------------------------------------
# Against core MAIN (FIVEDIVE_CORE_DIR), not a pinned ref: while core still carries a copy the two
# must not drift, and once core deletes src/council this repo owns it and only the parser — which
# core keeps — is still held to byte-identity.
CORE="${FIVEDIVE_CORE_DIR:-}"
if [[ -n "$CORE" && -f "$CORE/src/council/engine.mjs" ]]; then
  for f in council/engine.mjs council/cli.mjs constitution/constitution.mjs; do
    t "P4 $f is byte-identical to core's src/$f" 0 "$(cmp -s "council/src/$f" "$CORE/src/$f"; echo $?)"
  done
  # Every hunk of the template diff must touch a PLUGIN DIVERGENCE site. Count hunks, and count
  # hunks that carry the marker; they must be equal and non-zero.
  d="$(diff -U0 "$CORE/src/council/cmd_council.template.sh" council/src/council/cmd_council.template.sh)"
  hunks="$(grep -c '^@@' <<<"$d")"; marked="$(awk '/^@@/{if(h)n+=m; h=1; m=0} /PLUGIN DIVERGENCE/{m=1} END{if(h)n+=m; print n+0}' <<<"$d")"
  t "P4 the template differs from core's only at marked PLUGIN DIVERGENCE sites ($hunks hunks)" "$hunks" "$marked"
  t "P4 ...and there are exactly the 7 divergences the prelude documents" 7 "$hunks"
elif [[ -n "$CORE" && -f "$CORE/src/constitution/constitution.mjs" ]]; then
  t "P4 constitution.mjs is byte-identical to core's kernel (the ONE parser)" 0 "$(cmp -s council/src/constitution/constitution.mjs "$CORE/src/constitution/constitution.mjs"; echo $?)"
  skip "P4 engine/cli/template parity" "core at $CORE no longer carries src/council (post-unwire): this repo is now the only copy"
else
  skip "P4 parity with core" "no core checkout (set FIVEDIVE_CORE_DIR)"
fi

# ---- P5 the store survives the move ----------------------------------------------------------
CC="${FIVEDIVE_CORE_COUNCIL_DIR:-${FIVEDIVE_CORE_DIR:-}}"
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  skip "P5 cross-writer lineage" "needs root (the gate-proof seal); tests/run_all.sh runs it as root"
elif [[ -z "$CC" || ! -x "$CC/5dive" ]] || ! "$CC/5dive" council --help >/dev/null 2>&1; then
  skip "P5 cross-writer lineage" "no built core with a built-in council (set FIVEDIVE_CORE_COUNCIL_DIR to a core checkout at or before the unwire)"
else
  S="$TMP/state"; mkdir -p "$S"
  (
    export STATE_DIR="$S" COUNCIL_MOCK=1 COUNCIL_5DIVE_BIN="$CC/5dive"
    "$CC/5dive" council init --seats="main:chair,theo,olivia" --threshold=majority --veto="tg:1234567890" >/dev/null 2>&1
    echo "core-init=$?"
    "$CC/5dive" council promote --subject=codex --lens="codex — rigor." --mode=quick --json >/dev/null 2>&1
    echo "core-promote=$?"
    "$BIN" verify >/dev/null 2>&1; echo "plugin-verify-core-chain=$?"
    "$BIN" roster --json 2>/dev/null | jq -r '"plugin-roster-seats=\(.data.seatCount)"'
    "$BIN" demote --subject=theo --mode=quick --json >/dev/null 2>&1; echo "plugin-demote=$?"
    "$CC/5dive" council verify >/dev/null 2>&1; echo "core-verify-mixed-chain=$?"
    "$BIN" verify >/dev/null 2>&1; echo "plugin-verify-mixed-chain=$?"
    echo "records=$(grep -c . "$S/council/lineage.jsonl")"
  ) > "$TMP/p5.out" 2>&1
  for want in core-init=0 core-promote=0 plugin-verify-core-chain=0 plugin-roster-seats=4 plugin-demote=0 core-verify-mixed-chain=0 plugin-verify-mixed-chain=0 records=3; do
    t "P5 ${want%%=*}" "$want" "$(grep -E "^${want%%=*}=" "$TMP/p5.out")"
  done
  # And the tamper control, so a verify that always says yes cannot pass the arms above.
  sed -i '2s/"seq":1/"seq":9/' "$S/council/lineage.jsonl"
  t "P5 control: the plugin's verify goes RED on a tampered core-written record" 1 \
    "$(STATE_DIR="$S" COUNCIL_5DIVE_BIN="$CC/5dive" "$BIN" verify >/dev/null 2>&1 && echo 0 || echo 1)"
fi

# ---- P6 --json ---------------------------------------------------------------------------------
J="$TMP/json"; mkdir -p "$J"
t "P6 'council bench ls --json' emits the JSON envelope" true "$(STATE_DIR="$J" COUNCIL_MOCK=1 "$BIN" bench ls --json 2>/dev/null | jq -r .ok 2>/dev/null)"
t "P6 'council --json bench ls' (flag first) emits the same" true "$(STATE_DIR="$J" COUNCIL_MOCK=1 "$BIN" --json bench ls 2>/dev/null | jq -r .ok 2>/dev/null)"
t "P6 FIVEDIVE_JSON_MODE=1 (a core that forwards the mode) emits it too" true "$(STATE_DIR="$J" COUNCIL_MOCK=1 FIVEDIVE_JSON_MODE=1 "$BIN" bench ls 2>/dev/null | jq -r .ok 2>/dev/null)"
jr=0; jout="$(STATE_DIR="$J" "$BIN" nonsense --json 2>/dev/null)" || jr=$?
t "P6 a usage refusal is a JSON error envelope in JSON mode (rc 2)" "false 2" "$(jq -r .ok <<<"$jout" 2>/dev/null) $jr"

# ---- P7 dry-run guard --------------------------------------------------------------------------
DL="$TMP/dry.log"
out="$(FIVEDIVE_NOTIFY_DRYRUN=1 FIVEDIVE_NOTIFY_DRYRUN_LOG="$DL" bash -c 'source "$1"; _mirror_send tok 42 "" "hello" "{}"' _ "$BIN" 2>/dev/null)"
t "P7 a dry-run send returns the synthetic ok" true "$(jq -r .dry_run <<<"$out" 2>/dev/null)"
t "P7 ...logs the would-be payload, never the token" "1 0" "$(grep -c 'notify-dryrun chat=42' "$DL") $(grep -c tok "$DL")"

printf '\ncouncil_plugin_unit: %d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
[[ "$FAIL" -eq 0 ]]
