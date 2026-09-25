# 5dive council

**Governance for AI agents, with a human veto.** What a council is and how it
decides — quorum, a vote bar that scales with the stakes, sealed receipts, the
final human veto: **[5dive.ai/council](https://5dive.ai/council)**.

A sealed deliberation council for your 5dive agents, as a plugin: convene a panel
of seats on a question, run seat motions and constitutional amendments, give a
founder a veto, and keep every verdict in a tamper-evident lineage.

```bash
sudo 5dive plugin add 5dive-ai/5dive-council
5dive council --help
```

## What moved, and what did not

Council used to be built into the core CLI. It is now opt-in: a box that never
convenes a council no longer parses ~12k lines of it on every `5dive` call.

**What stays in core** is everything a box needs whether or not it runs a council:
the constitution file, its one parser, the tier-2 human-gate floor `5dive task need`
enforces, and the *reader* of the seal. Core decides whether to trust
`constitution.yaml` by reading the newest `constitutionDigest` in
`/var/lib/5dive/council/lineage.jsonl` as data. Installing or removing this plugin
changes nothing about how gates are enforced.

**What this plugin is** is the deliberation that *writes* that lineage:
`convene`, `bench`, `schedule`, `roster`, `promote|demote|expel`, `amend`, `veto`,
`gate-clear`, `rot-triage`, `record`, `verify`, `sign-vote`, `ballot-tap`.

**Your existing council keeps working.** The state lives where it always did
(`/var/lib/5dive/council/`: genesis, lineage, receipts, benches, schedules). A
lineage sealed by the built-in council verifies under this plugin, and records this
plugin seals verify under core — `tests/council_plugin_unit.sh` P5 proves both
directions against the last core release that carried council.

## Which core you need

On a core that still has the built-in `council` verb, this install is **refused**
(`council` is already a 5dive command) — that is correct, the two cannot both claim
the verb. Install it once your core is on the release that removed the built-in; that
release's `5dive council` prints the install line above instead of `unknown command`.

## How it talks to core

The plugin is an executable core runs, not code core loads, so it reaches core only
through core's CLI: `5dive gate-proof sign` (the root seal — the key never leaves
core), `5dive task show|ls --json`, `5dive task answer`, `5dive agent ask|send|list`,
`5dive agent telegram-access get`, and `5dive _audit_append`. The single remaining
data seam — the founder-veto offer reads the calling agent's bot token from core's
connector file, because core has no CLI verb that sends a message with a button — is
documented at the top of `council/bin/council`.

## Layout

| path | what it is |
|---|---|
| `council/bin/council` | the verb. **Generated** — edit `council/src/`, then `node council/src/gen.mjs` |
| `council/src/council/` | the engine, its CLI and the bash body, carried from core (`PLUGIN DIVERGENCE` marks each change) |
| `council/src/constitution/constitution.mjs` | core's constitution parser, vendored byte-identical (the ONE parser) |
| `council/src/prelude.sh` | what a plugin cannot inherit from core: `fail`/`ok`, error codes, the node locator, the CLI seams |
| `tests/council_*` | 29 harnesses carried from core, plus this repo's own `council_plugin_unit.sh` and `council_mutants.sh` |

## Tests

The harnesses need a built core checkout (the plugin reaches core over its CLI):

```bash
git clone https://github.com/5dive-ai/5dive.git .core && (cd .core && ./build.sh)
bash tests/run_all.sh          # every harness; the sealing ones run under sudo
bash tests/council_mutants.sh  # the controls: each mutant must turn a harness red
```

## License

Apache-2.0.
