// Literal {{TOKEN}} replacement driven by a JSON map, standing in for the token-filling the
// /bootstrap command does by editing files. Substitution is literal so values containing regex
// metacharacters (| \ . /) survive intact, and an unknown token is an error rather than a silent
// pass-through: an unfilled placeholder reaching a real project is exactly what these tests exist to
// catch.
import { readFileSync, writeFileSync } from 'node:fs'

const [mapPath, ...files] = process.argv.slice(2)
if (!mapPath || files.length === 0) {
  console.error('usage: fill.mjs <values.json> <file> [file...]')
  process.exit(2)
}

const map = JSON.parse(readFileSync(mapPath, 'utf8'))
const missing = new Set()

for (const file of files) {
  const before = readFileSync(file, 'utf8')
  const after = before.replace(/\{\{[A-Z_]+\}\}/g, (match) => {
    const key = match.slice(2, -2)
    if (!(key in map)) {
      missing.add(`${key} (${file})`)
      return match
    }
    return map[key]
  })
  if (after !== before) writeFileSync(file, after)
}

if (missing.size > 0) {
  console.error('✗ tokens with no value in the scenario file:')
  for (const m of missing) console.error(`      ${m}`)
  process.exit(1)
}
console.log('  ✓ every token substituted')
