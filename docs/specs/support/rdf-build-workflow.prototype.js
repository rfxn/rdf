export const meta = {
  name: 'rdf-build-loop',
  description: 'RDF /r-build phase loop: engineer -> QA || sentinel -> bounded retry -> verdict (option B prototype)',
  whenToUse: 'Only when the /r-build skill invokes it after plan validation, the consistency gate, and tier/session resolution. Never run directly.',
  phases: [
    { title: 'Parse', detail: 'plan text -> phase list (args.planText preferred; schema agent fallback)' },
    { title: 'Build', detail: 'per phase: engineer -> Gate 1 -> QA || sentinel -> retry <=3 -> commit' },
    { title: 'End-of-plan', detail: 'cumulative 3-pass sentinel, <=2 fix cycles (plans >=3 phases, tier full or floor)' },
  ],
}

// Design artifact for docs/specs/2026-09-02-platform-alignment-spike-design.md (D1, option B).
// Not wired into any adapter. Mirrors canonical/agents/dispatcher.md; cites are dispatcher.md
// line numbers at 3.6.5 unless stated.
//
// args (all supplied by the /r-build skill — the script has no filesystem, shell, or env access):
//   planPath        absolute plan path (agents read it)
//   planText        plan contents; when present, parsed here deterministically
//   phases          optional [n, ...] subset; default: every phase whose status is not complete
//   tier            'full' | 'quick-plan' | 'bugfix'   (rdf_active_tier, state/rdf-bus.sh:201)
//   sessionId       RDF_SESSION_ID (rdf-bus.sh:38) — scoped result-file names, dispatcher.md:22-26
//   projectRoot     absolute project root
//   baseCommit      HEAD before phase 1 (end-of-plan diff base, dispatcher.md:409)
//   governance      { files: [...], sensitivePaths: [...], crossCuttingPaths: [...] }  (/r-build §4)
//   timestamp       ISO string — Date.now() throws inside scripts
//   commit          default true; false leaves commits to the skill

const MAX_PHASE_RETRIES = 3        // dispatcher.md:400-401
const MAX_FIX_CYCLES = 3           // dispatcher.md:498
const MAX_END_OF_PLAN_CYCLES = 2   // dispatcher.md:413-414
const ZERO_FINDING_MIN_LINES = 50  // dispatcher.md:432-439
// reviewer.md:183-187 — the single source; tiers.md:62-63 and dispatcher.md:294-295 restate it
const SECURITY_INDICATORS = ['auth', 'cred', 'secret', 'token', 'key', 'passwd', 'encrypt', 'hash', 'sign', 'cert', 'session', 'permission']

const FINDING = {
  type: 'object',
  required: ['severity', 'qualifier', 'file', 'line', 'description'],
  properties: {
    severity: { type: 'string', enum: ['MUST-FIX', 'SHOULD-FIX', 'INFORMATIONAL'] },
    qualifier: { type: 'string' },
    file: { type: 'string' },
    line: { type: 'integer' },
    description: { type: 'string' },
    suggestedFix: { type: 'string' },
  },
}
const PLAN_SCHEMA = {
  type: 'object', required: ['phases'],
  properties: { phases: { type: 'array', items: { type: 'object', required: ['n', 'title', 'files', 'status'], properties: {
    n: { type: 'integer' }, title: { type: 'string' }, mode: { type: 'string' }, status: { type: 'string' },
    accept: { type: 'string' }, test: { type: 'string' }, regressionCase: { type: 'string' },
    files: { type: 'array', items: { type: 'object', required: ['action', 'path'], properties: { action: { type: 'string' }, path: { type: 'string' } } } },
    hasTrailingRule: { type: 'boolean' },
  } } } },
}
const ENGINEER_SCHEMA = {
  type: 'object', required: ['status', 'tddEvidence', 'evidence', 'changedFiles'],
  properties: {
    status: { type: 'string', enum: ['DONE', 'DONE_WITH_CONCERNS', 'BLOCKED', 'NEEDS_CONTEXT'] },
    tddEvidence: { type: 'string' },
    evidence: { type: 'array', items: { type: 'string' } },
    changedFiles: { type: 'array', items: { type: 'string' } },
    notes: { type: 'string' },
  },
}
const QA_SCHEMA = {
  type: 'object', required: ['result', 'checks', 'findings', 'resultFile'],
  properties: {
    result: { type: 'string', enum: ['PASS', 'FAIL'] },
    checks: { type: 'array', items: { type: 'object', required: ['name', 'result'], properties: { name: { type: 'string' }, result: { type: 'string' }, detail: { type: 'string' } } } },
    findings: { type: 'array', items: FINDING },
    resultFile: { type: 'string' },
  },
}
const SENTINEL_SCHEMA = {
  type: 'object', required: ['findings', 'reported', 'discarded', 'changedLines'],
  properties: {
    findings: { type: 'array', items: FINDING },
    reported: { type: 'integer' }, discarded: { type: 'integer' }, changedLines: { type: 'integer' },
    passes: { type: 'array', items: { type: 'string' } },
  },
}
const FIX_SCHEMA = {
  type: 'object', required: ['action'],
  properties: {
    action: { type: 'string', enum: ['FIXED', 'REFUTED'] },
    diffSummary: { type: 'string' }, refutation: { type: 'string' },
    changedFiles: { type: 'array', items: { type: 'string' } },
  },
}
const REFUTATION_SCHEMA = {
  type: 'object', required: ['citesFileLine', 'explainsWhy', 'addressesConcern'],
  properties: { citesFileLine: { type: 'boolean' }, explainsWhy: { type: 'boolean' }, addressesConcern: { type: 'boolean' } },
}
const COMMIT_SCHEMA = { type: 'object', required: ['sha', 'message'], properties: { sha: { type: 'string' }, message: { type: 'string' } } }

// ── Pure functions: the deterministic core the prose dispatcher carries today ──

// plan-schema.md Rules 1-3 + Files field shape (r-build.md:117-119)
function parsePlan(text) {
  const lines = text.split('\n')
  const phases = []
  let cur = null
  const field = (name, line) => {
    const m = line.match(new RegExp('^-?\\s*\\*\\*' + name + '\\*\\*:?\\s*(.*)$'))
    return m ? m[1].trim() : null
  }
  for (const line of lines) {
    const h = line.match(/^### Phase (\d+): (.+)$/)
    if (h) { cur = { n: Number(h[1]), title: h[2].trim(), mode: '', status: 'pending', accept: '', test: '', regressionCase: '', files: [], hasTrailingRule: false }; phases.push(cur); continue }
    if (!cur) continue
    const f = line.match(/^\s*-\s*(Create|Modify|Delete):\s*`([^`]+)`/)
    if (f) { cur.files.push({ action: f[1].toLowerCase(), path: f[2] }); continue }
    let v
    if ((v = field('Mode', line)) !== null) cur.mode = v
    else if ((v = field('Status', line)) !== null) cur.status = v.toLowerCase()
    else if ((v = field('Accept', line)) !== null) cur.accept = v
    else if ((v = field('Test', line)) !== null) cur.test = v
    else if ((v = field('Regression-case', line)) !== null) cur.regressionCase = v
    else if (/^---\s*$/.test(line)) cur.hasTrailingRule = true
  }
  return { phases }
}

const base = p => p.split('/').pop().toLowerCase()
const matchesAny = (path, prefixes) => (prefixes || []).some(x => path === x || path.startsWith(x.replace(/\*+$/, '')))
const isProse = p => /\.md$/i.test(p) || /(^|\/)(CHANGELOG|README|LICENSE)/i.test(p)

// dispatcher.md:216-261 — highest matching level wins: sensitive > cross-cutting > multi-file > focused > docs
function classifyScope(phase, gov) {
  const paths = phase.files.map(f => f.path)
  if (paths.length === 0) return 'multi-file'
  if (paths.some(p => matchesAny(p, gov.sensitivePaths))) return 'sensitive'
  if (paths.some(p => matchesAny(p, gov.crossCuttingPaths) || /(^|\/)(install\.sh|uninstall\.sh|bin\/)/.test(p))) return 'cross-cutting'
  if (paths.every(isProse)) return 'docs'
  if (paths.length === 1) return 'focused'
  return 'multi-file'
}

// tiers.md:51-65 / dispatcher.md:290-301
function securityFloor(phase, scope, gov) {
  if (scope === 'sensitive') return true
  return phase.files.some(f => matchesAny(f.path, gov.sensitivePaths) || SECURITY_INDICATORS.some(i => base(f.path).includes(i)))
}

// dispatcher.md:250-259 (scope map), 303-315 (tier cap), 290-301 (floor): max(floor, min(scope, cap))
function deriveGates(scope, tier, floor, files) {
  const g = { gate2: false, gate3: 'none', gate4: false }
  if (scope === 'focused') g.gate2 = true
  if (scope === 'multi-file') { g.gate2 = true; g.gate3 = 'lite' }
  if (scope === 'cross-cutting' || scope === 'sensitive') { g.gate2 = true; g.gate3 = 'full' }
  if (files.some(f => /(^|\/)(bin\/|man\/)|\.[1-8]$|usage/i.test(f.path))) g.gate4 = true
  if (tier === 'quick-plan' && g.gate3 === 'full') g.gate3 = 'lite'
  if (tier === 'bugfix') { g.gate2 = g.gate2 && 'regression-only'; g.gate3 = g.gate3 === 'none' ? 'none' : 'regression-lite'; g.gate4 = false }
  if (floor) { g.gate2 = true; g.gate3 = 'full' }
  return g
}

// dispatcher.md:326-356
function targetClass(files) {
  if (files.length === 0) return 'code'
  const ext = p => (p.match(/\.([a-z0-9]+)$/i) || ['', ''])[1].toLowerCase()
  const prose = new Set(['md']), schema = new Set(['json', 'yaml', 'yml', 'proto', 'toml'])
  let hasProse = false, hasSchema = false, hasCode = false
  for (const f of files) { const e = ext(f.path); if (prose.has(e)) hasProse = true; else if (schema.has(e)) hasSchema = true; else hasCode = true }
  const active = [hasProse, hasSchema, hasCode].filter(Boolean).length
  if (active > 1) return 'mixed'
  return hasCode ? 'code' : hasSchema ? 'schema' : 'prose'
}

// dispatcher.md:191-200 — Gate 1 structural evidence check
const EVIDENCE_LINE = /^.+: (.+:\d+|.+ (→|->) .+|[0-9a-f]{7,40} .+)$/
function gate1(r) {
  if (!r) return { ok: false, verdict: 'NEEDS_CONTEXT', feedback: 'engineer returned no result (skipped or terminal error)' }
  if (r.status === 'BLOCKED') return { ok: false, verdict: 'BLOCKED', feedback: r.notes || 'engineer BLOCKED' }
  if (r.status === 'NEEDS_CONTEXT') return { ok: false, verdict: 'NEEDS_CONTEXT', feedback: r.notes || 'engineer NEEDS_CONTEXT' }
  if (!r.evidence.some(l => EVIDENCE_LINE.test(l))) return { ok: false, verdict: 'NEEDS_CONTEXT', feedback: 'EVIDENCE block missing required citation' }
  return { ok: true }
}

// dispatcher.md:383-395 — dedupe by file + line proximity, higher severity wins
const RANK = { 'MUST-FIX': 3, 'SHOULD-FIX': 2, 'INFORMATIONAL': 1 }
function mergeFindings(qa, sentinel) {
  const out = []
  for (const f of [...qa.map(x => ({ ...x, from: ['qa'] })), ...sentinel.map(x => ({ ...x, from: ['sentinel'] }))]) {
    const dup = out.find(o => o.file === f.file && Math.abs(o.line - f.line) <= 5)
    if (!dup) { out.push(f); continue }
    dup.from = [...new Set([...dup.from, ...f.from])]
    if (RANK[f.severity] > RANK[dup.severity]) { dup.severity = f.severity; dup.qualifier = f.qualifier }
  }
  return out
}

// ── Prompt builders (agents own all file/shell I/O) ─────────────────────────

const govBlock = () => `GOVERNANCE:\n${(args.governance.files || []).map(f => '  ' + f).join('\n')}\nPROJECT_ROOT: ${args.projectRoot}\nRDF_SESSION_ID: ${args.sessionId}`

function engineerPrompt(ph, feedback) {
  return `TASK: implement Phase ${ph.n} of the active plan.\nPLAN: ${args.planPath}\nPHASE: ${ph.n}\nDESCRIPTION: ${ph.title}\nMODE: ${ph.mode || 'serial-agent'}\nTIER: ${args.tier}\nFILES:\n${ph.files.map(f => `  ${f.action}: ${f.path}`).join('\n')}\nACCEPT: ${ph.accept}\nTEST: ${ph.test}\nREGRESSION_CASE: ${ph.regressionCase}\n${govBlock()}\n` +
    (feedback ? `\nPRIOR_ATTEMPT_FEEDBACK:\n${feedback}\n` : '') +
    `\nFollow TDD (red -> green -> refactor). Do NOT commit. Return STATUS, TDD_EVIDENCE, and an EVIDENCE list where every line is "<claim>: <path>:<line>" or "<claim>: <cmd> -> <output>" or "<claim>: <sha> <message>".`
}
function qaPrompt(ph, gates) {
  return `TASK: verify Phase ${ph.n} (${ph.title}) against .rdf/governance/verification.md.\nPLAN: ${args.planPath}\nPHASE: ${ph.n}\nRDF_SESSION_ID: ${args.sessionId}\nRESULT_FILE: .rdf/work-output/phase-${ph.n}-result-${args.sessionId}.md\nMODE: ${gates.gate2 === 'regression-only' ? 'run ONLY the phase regression test: ' + ph.regressionCase : 'full verification matrix'}\n${govBlock()}\nWrite the structured report to RESULT_FILE and return its path plus findings.`
}
function sentinelPrompt(ph, depth, scope, diffRange) {
  return `TASK: sentinel-review\nDEPTH: ${depth}\nDIFF: ${diffRange}\nPHASE_SCOPE: scope:${scope}\ntarget_class: ${targetClass(ph.files)}\nPLAN: ${args.planPath}\nPHASE: ${ph.n}\n${govBlock()}\nReturn findings with severity + qualifier, REPORTED/DISCARDED counts, and the changed-line count of the diff.`
}
function fixPrompt(finding) {
  return `TASK: fix-finding\nFINDING: ${finding.file}:${finding.line} — ${finding.description}\nSEVERITY: MUST-FIX (${finding.qualifier})\nCONTEXT: ${finding.suggestedFix || ''}\nINSTRUCTION: Fix this issue, or refute with counter-evidence. If fixing: make the minimal change, run existing tests, report diff. If refuting: cite specific code, explain why it is correct. Do NOT commit.\n${govBlock()}`
}

// ── Gate execution ────────────────────────────────────────────────────────────

async function runGates(ph, gates, scope, diffRange, tag) {
  const jobs = []
  if (gates.gate2) jobs.push(() => agent(qaPrompt(ph, gates), { agentType: 'rdf-qa', schema: QA_SCHEMA, phase: 'Build', label: `${tag} QA` }))
  if (gates.gate3 !== 'none') jobs.push(() => agent(sentinelPrompt(ph, gates.gate3 === 'full' ? 'full' : 'lite', scope, diffRange), { agentType: 'rdf-reviewer', schema: SENTINEL_SCHEMA, phase: 'Build', label: `${tag} sentinel-${gates.gate3}` }))
  if (gates.gate4) jobs.push(() => agent(`TASK: UAT for Phase ${ph.n} (${ph.title}). Exercise CLI entry points / help text end-to-end.\n${govBlock()}`, { agentType: 'rdf-uat', schema: QA_SCHEMA, phase: 'Build', label: `${tag} UAT` }))
  const results = await parallel(jobs)            // barrier is correct: dedupe needs both reports (dispatcher.md:377-395)
  const dead = results.filter(r => r === null).length
  if (dead) log(`${tag}: ${dead} gate agent(s) returned null — treated as gate failure, not as PASS`)
  let qa = null, sentinel = null, uat = null, i = 0
  if (gates.gate2) qa = results[i++]
  if (gates.gate3 !== 'none') sentinel = results[i++]
  if (gates.gate4) uat = results[i++]
  // FP calibration 1 (dispatcher.md:432-439): zero findings on a big diff at lite depth -> re-run full
  if (sentinel && gates.gate3 === 'lite' && sentinel.reported === 0 && sentinel.discarded === 0 && sentinel.changedLines >= ZERO_FINDING_MIN_LINES) {
    log(`${tag}: zero-finding anomaly on ${sentinel.changedLines} lines — re-dispatching sentinel at full depth`)
    sentinel = (await agent(sentinelPrompt(ph, 'full', scope, diffRange), { agentType: 'rdf-reviewer', schema: SENTINEL_SCHEMA, phase: 'Build', label: `${tag} sentinel-full (calibration)` })) || sentinel
  }
  const findings = mergeFindings([...(qa ? qa.findings : []), ...(uat ? uat.findings : [])], sentinel ? sentinel.findings : [])
  const failed = dead > 0 || (qa && qa.result !== 'PASS') || (uat && uat.result !== 'PASS')
  const discardAnomaly = sentinel && sentinel.discarded > 4 && sentinel.discarded > 2 * sentinel.reported
  return { failed, findings, resultFile: qa ? qa.resultFile : null, discardAnomaly, sentinel }
}

// dispatcher.md:486-517 — MUST-FIX resolution with 3-check refutation review
async function resolveMustFix(finding, tag) {
  for (let cycle = 1; cycle <= MAX_FIX_CYCLES; cycle++) {
    const r = await agent(fixPrompt(finding), { agentType: 'rdf-engineer', schema: FIX_SCHEMA, phase: 'Build', label: `${tag} fix ${finding.file}:${finding.line} (${cycle}/${MAX_FIX_CYCLES})` })
    if (!r) continue
    if (r.action === 'FIXED') return { resolved: true, how: 'FIXED', cycles: cycle }
    const j = await agent(`Judge this refutation of a MUST-FIX finding. Finding: ${finding.file}:${finding.line} — ${finding.description}. Refutation: ${r.refutation}. Answer the three checks strictly.`, { agentType: 'rdf-reviewer', schema: REFUTATION_SCHEMA, effort: 'low', phase: 'Build', label: `${tag} refutation check` })
    if (j && j.citesFileLine && j.explainsWhy && j.addressesConcern) return { resolved: true, how: 'REFUTED', cycles: cycle }
    finding = { ...finding, suggestedFix: `Refutation rejected (cites:${j && j.citesFileLine} why:${j && j.explainsWhy} addresses:${j && j.addressesConcern}). ${finding.suggestedFix || ''}` }
  }
  return { resolved: false, how: 'EXHAUSTED', cycles: MAX_FIX_CYCLES }
}

async function buildPhase(ph) {
  const tag = `P${ph.n}`
  const scope = classifyScope(ph, args.governance)
  const floor = securityFloor(ph, scope, args.governance)
  const gates = deriveGates(scope, args.tier, floor, ph.files)
  const verdict = { phase: ph.n, title: ph.title, scope, floor, gates, attempts: 0, status: 'FAIL', resolved: [], advisory: [], unresolved: [], escalations: [], resultFile: null, commit: null }
  log(`${tag}: scope:${scope} floor:${floor} tier:${args.tier} -> gate2:${gates.gate2} gate3:${gates.gate3} gate4:${gates.gate4}`)
  let feedback = ''
  for (let attempt = 1; attempt <= MAX_PHASE_RETRIES; attempt++) {
    verdict.attempts = attempt
    const eng = await agent(engineerPrompt(ph, feedback), { agentType: 'rdf-engineer', schema: ENGINEER_SCHEMA, phase: 'Build', label: `${tag} engineer (${attempt}/${MAX_PHASE_RETRIES})`, ...(scope === 'docs' || scope === 'focused' ? { model: 'sonnet' } : {}) })
    const g1 = gate1(eng)
    if (!g1.ok) {
      if (g1.verdict === 'BLOCKED') { verdict.status = 'NEEDS_USER'; verdict.escalations.push(g1.feedback); return verdict }
      feedback = `Gate 1 ${g1.verdict}: ${g1.feedback}`; log(`${tag}: ${feedback}`); continue
    }
    const gr = await runGates(ph, gates, scope, 'working tree vs HEAD', tag)
    verdict.resultFile = gr.resultFile
    if (gr.discardAnomaly) verdict.escalations.push(`sentinel discard ratio anomaly: ${gr.sentinel.discarded} discarded vs ${gr.sentinel.reported} reported`)
    const must = gr.findings.filter(f => f.severity === 'MUST-FIX')
    verdict.advisory.push(...gr.findings.filter(f => f.severity === 'SHOULD-FIX'))
    const blocking = must.filter(f => /blocking-concern/.test(f.qualifier))
    if (blocking.length) { verdict.status = 'NEEDS_USER'; verdict.unresolved.push(...blocking); verdict.escalations.push('MUST-FIX(blocking-concern) needs a human decision — no mid-run user input in a workflow'); return verdict }
    let allResolved = true
    for (const f of must) {
      const r = await resolveMustFix(f, tag)
      if (r.resolved) verdict.resolved.push({ ...f, how: r.how, cycles: r.cycles }); else { allResolved = false; verdict.unresolved.push(f) }
    }
    if (!allResolved) { verdict.status = 'NEEDS_USER'; verdict.escalations.push('MUST-FIX unresolved after fix/refute cycles'); return verdict }
    if (gr.failed) { feedback = `Gates failed on attempt ${attempt}: ${JSON.stringify(gr.findings.slice(0, 5))}`; log(`${tag}: ${feedback.slice(0, 160)}`); continue }
    if (must.length) {                                // fixes changed code -> re-run gates once before commit (dispatcher.md:489)
      const re = await runGates(ph, gates, scope, 'working tree vs HEAD', `${tag} re-gate`)
      if (re.failed || re.findings.some(f => f.severity === 'MUST-FIX')) { feedback = 'post-fix re-gate failed'; continue }
    }
    if (args.commit !== false) {
      verdict.commit = await agent(`Commit Phase ${ph.n} of ${args.planPath} on ${args.projectRoot}: stage exactly the phase's changed files by name (never git add -A), one commit, message derived from the phase description "${ph.title}" per .rdf/governance/conventions.md. Return the sha.`, { schema: COMMIT_SCHEMA, effort: 'low', phase: 'Build', label: `${tag} commit` })
    }
    verdict.status = 'PASS'
    return verdict
  }
  verdict.escalations.push(`retry budget exhausted (${MAX_PHASE_RETRIES}); last feedback: ${feedback.slice(0, 200)}`)
  return verdict
}

// ── Main ─────────────────────────────────────────────────────────────────────

phase('Parse')
let plan
if (args.planText) { plan = parsePlan(args.planText); log(`Parsed ${plan.phases.length} phases in-script (deterministic)`) }
else {
  plan = await agent(`Read ${args.planPath} and return every "### Phase N:" block as structured data (files from the **Files:** list, status, mode, accept, test, regression-case, trailing --- present).`, { schema: PLAN_SCHEMA, effort: 'low', phase: 'Parse', label: 'plan parse (agent fallback)' })
  if (!plan) return { error: 'plan parse agent returned null', phases: [] }
  log(`Parsed ${plan.phases.length} phases via agent (skill supplied no planText)`)
}
const truncated = plan.phases.filter(p => !p.hasTrailingRule).map(p => p.n)
if (truncated.length) log(`Warning: phases without trailing --- (plan-schema Rule 3): ${truncated.join(', ')}`)

const wanted = Array.isArray(args.phases) && args.phases.length ? plan.phases.filter(p => args.phases.includes(p.n)) : plan.phases.filter(p => p.status !== 'complete')
log(`Building ${wanted.map(p => p.n).join(', ') || '(nothing pending)'} of ${plan.phases.length} phases; tier ${args.tier}`)

phase('Build')
const verdicts = []
for (const ph of wanted) {                             // serial: plan phases are dependency-ordered; batching stays in the skill
  const v = await buildPhase(ph)
  verdicts.push(v)
  log(`P${ph.n}: ${v.status}${v.resolved.length ? ` (${v.resolved.length} findings resolved)` : ''}${v.advisory.length ? ` — ${v.advisory.length} advisory` : ''}`)
  if (v.status !== 'PASS') { log(`Stopping after P${ph.n}: ${v.status} — remaining phases not attempted: ${wanted.filter(p => p.n > ph.n).map(p => p.n).join(', ') || 'none'}`); break }
}

phase('End-of-plan')
const allPass = verdicts.length === wanted.length && verdicts.every(v => v.status === 'PASS')
const floorAny = verdicts.some(v => v.floor)
const eligible = allPass && plan.phases.length >= 3 && (args.tier === 'full' || floorAny)   // dispatcher.md:403-420
let endOfPlan = { ran: false, reason: eligible ? 'ran' : (allPass ? `skipped: ${plan.phases.length} phases / tier ${args.tier}` : 'skipped: not all phases passed') }
if (eligible) {
  const range = `${args.baseCommit}..HEAD`
  const last = plan.phases[plan.phases.length - 1]
  let unresolved = []
  for (let cycle = 1; cycle <= MAX_END_OF_PLAN_CYCLES; cycle++) {
    const s = await agent(sentinelPrompt({ ...last, files: plan.phases.flatMap(p => p.files) }, 'full', 'cross-cutting', range) + `\nWrite the report to .rdf/work-output/sentinel-plan-final.md.`, { agentType: 'rdf-reviewer', schema: SENTINEL_SCHEMA, phase: 'End-of-plan', label: `end-of-plan sentinel (${cycle}/${MAX_END_OF_PLAN_CYCLES})` })
    if (!s) { unresolved = [{ severity: 'MUST-FIX', qualifier: 'workflow-breaking', file: '-', line: 0, description: 'end-of-plan sentinel returned null' }]; break }
    const must = s.findings.filter(f => f.severity === 'MUST-FIX')
    unresolved = []
    for (const f of must) { const r = await resolveMustFix(f, 'EOP'); if (!r.resolved) unresolved.push(f) }
    endOfPlan = { ran: true, cycle, reported: s.reported, discarded: s.discarded, mustFix: must.length, unresolved }
    if (must.length === 0 || unresolved.length) break
  }
}

return {
  timestamp: args.timestamp, tier: args.tier, plan: args.planPath,
  phases: verdicts, endOfPlan,
  overall: allPass && (!endOfPlan.ran || endOfPlan.unresolved.length === 0) ? 'PASS' : 'ATTENTION',
  // Boundary: the skill owns these after the run (no filesystem/env/user input inside a workflow).
  skillMustDo: ['write phase Status in the plan', 'update the task list', 'present escalations to the user', 'clear/advance active-plan pointers'],
}
