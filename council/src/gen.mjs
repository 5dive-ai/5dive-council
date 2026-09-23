#!/usr/bin/env node
// DIVE-4891 — generate council/bin/council, the plugin's one executable.
//
// Same shape as core's src/council/gen_cmd.mjs (which this replaces): the node
// modules are embedded as heredocs into the bash body so the verb ships as ONE
// file, materialised to a temp dir at call time. What is new is the frame
// around it: the prelude (what a plugin cannot inherit from core) goes on top
// and a trailer that strips `--json` the way core's main() did goes on the end.
//
//     node council/src/gen.mjs            # write council/bin/council
//     node council/src/gen.mjs --check    # exit 1 if the committed bin is stale
//
// council/src/council/* and council/src/constitution/constitution.mjs are kept
// byte-identical to core's files of the same path, apart from the template's
// PLUGIN DIVERGENCE sites; tests/council_plugin_unit.sh holds both to that.
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const here = path.dirname(fileURLToPath(import.meta.url))
const read = (p) => fs.readFileSync(path.join(here, p), 'utf-8')

// engine.mjs imports the constitution kernel by its source-tree path; the
// embedded runtime is one flat temp dir, so the specifier becomes a sibling.
const KERNEL_SPEC = "from '../constitution/constitution.mjs'"
const rawEngine = read('council/engine.mjs')
if (!rawEngine.includes(KERNEL_SPEC)) { console.error(`engine.mjs no longer imports ${KERNEL_SPEC} — update gen.mjs`); process.exit(1) }
const engine = rawEngine.split(KERNEL_SPEC).join("from './constitution.mjs'")
const kernel = read('constitution/constitution.mjs')
const cli = read('council/cli.mjs')
let body = read('council/cmd_council.template.sh')

for (const [tok, src, delim] of [['__CONSTITUTION_MJS__', kernel, 'COUNCIL_CONSTITUTION_MJS'], ['__ENGINE_MJS__', engine, 'COUNCIL_ENGINE_MJS'], ['__CLI_MJS__', cli, 'COUNCIL_CLI_MJS']]) {
  if (src.split('\n').some(l => l === delim)) { console.error(`refuse: ${delim} appears on its own line inside the embedded module`); process.exit(1) }
  const line = new RegExp(`^${tok}$`, 'm')
  if (!line.test(body)) { console.error(`marker ${tok} not found in template`); process.exit(1) }
  body = body.replace(line, () => src.replace(/\n$/, ''))
}

let prelude = read('prelude.sh')
const HELPERS = /^__INIT_HELPERS__$/m
if (!HELPERS.test(prelude)) { console.error('marker __INIT_HELPERS__ not found in prelude.sh'); process.exit(1) }
prelude = prelude.replace(HELPERS, () => read('init_helpers.part.sh').replace(/\n$/, ''))

const trailer = `
# ==================== entry ====================
# Core's main() stripped every \`--json\` out of argv and set JSON_MODE before it
# dispatched to cmd_council. Core now execs this file instead, so do the same
# strip here: the carried body keeps receiving exactly the argv it was written for.
# Sourced (by a harness, for the function bodies) it defines and returns.
if [[ "\${BASH_SOURCE[0]}" == "\$0" ]]; then
  set -euo pipefail
  _council_argv=()
  for _council_a in "$@"; do
    if [[ "$_council_a" == "--json" ]]; then JSON_MODE=1; else _council_argv+=("$_council_a"); fi
  done
  unset _council_a
  cmd_council "\${_council_argv[@]+"\${_council_argv[@]}"}"
fi
`
const out = prelude.replace(/\n*$/, '\n') + '\n' + body.replace(/\n*$/, '\n') + trailer

const dest = path.join(here, '..', 'bin', 'council')
if (process.argv.includes('--check')) {
  const cur = fs.existsSync(dest) ? fs.readFileSync(dest, 'utf-8') : ''
  if (cur !== out) { console.error(`${dest} is stale — run: node council/src/gen.mjs`); process.exit(1) }
  console.error(`${dest} is current`)
  process.exit(0)
}
fs.writeFileSync(dest, out, { mode: 0o755 })
fs.chmodSync(dest, 0o755)
console.error(`wrote ${dest} (${out.length} bytes; constitution ${kernel.length} + engine ${engine.length} + cli ${cli.length} embedded)`)
