import type { Register } from 'claude-code'

// session-color: the session's /color follows its work stage.
// Spec: the transition table in the design notes (README).
//   Code decides: start (yellow), PR open (cyan), merge (purple), harness events (pink).
//   Haiku decides: yellow <-> green, closeout (orange), done (blue, gated), blocked (red).
//   Ben's manual /color always wins; anything backward from cyan is his alone.
// Off unless CC_SESSION_COLOR=on at launch or `/session-color on`. Off means every hook returns at once.

type Stage = 'unvetted' | 'building' | 'pr-ready' | 'merged' | 'closeout' | 'done'
type Pr = { url: string; state: 'OPEN' | 'MERGED' | 'CLOSED' }
type Event = { at: string; what: string }
type Move = { at: string; from: Stage; to: Stage; by: 'code' | 'haiku' | 'ben'; why: string }
type S = {
  enabled: boolean
  paused: boolean
  debug: boolean
  stage: Stage
  harness: Event[]
  blocked: Event | null
  applied: string | null
  prs: Pr[]
  branches: string[]
  suppressed: Stage[]
  last: Move | null
}

// guide.md ships with the mod (versioned); logs are per machine, outside any repo.
let GUIDE_PATH = ''
let LOG_DIR = ''
const POLL_MS = 5 * 60 * 1000
const MIN_CONFIDENCE = 0.7

const STAGE_COLOR: Record<Stage, string> = {
  unvetted: 'yellow',
  building: 'green',
  'pr-ready': 'cyan',
  merged: 'purple',
  closeout: 'orange',
  done: 'blue',
}
const COLOR_STAGE: Record<string, Stage> = {
  yellow: 'unvetted',
  green: 'building',
  cyan: 'pr-ready',
  purple: 'merged',
  orange: 'closeout',
  blue: 'done',
}
// What Haiku may propose from each stage (04-transition-audit: Y1, G1, G3, G4, Y3, C3, P2, P3, O2).
const HAIKU_MOVES: Record<Stage, Stage[]> = {
  unvetted: ['building', 'closeout', 'done'],
  building: ['unvetted', 'closeout', 'done'],
  'pr-ready': ['closeout', 'done'],
  merged: ['closeout', 'done'],
  closeout: ['done'],
  done: [],
}
const AUTH_STOP_ERRORS = ['authentication_failed', 'cloud_credential_error', 'oauth_org_not_allowed']
const AUTH_RE =
  /(gcloud auth login|reauthenticat|invalid_grant|token (has )?expired|expired token|HTTP 401|401 Unauthorized|op signin|not signed in|gh auth login|needs authentication|az login)/i
const PR_URL_RE = /https:\/\/github\.com\/[\w.-]+\/[\w.-]+\/pull\/\d+/g
const PR_ACTION_RE = /gh pr (create|ready|merge)|\/pulls\b|create_pull_request|pull_request_create/i

let sid = ''
let cwd = ''
let poll: { cancel: () => void } | null = null

function fresh(): S {
  return {
    enabled: true,
    paused: false,
    debug: false,
    stage: 'unvetted',
    harness: [],
    blocked: null,
    applied: null,
    prs: [],
    branches: [],
    suppressed: [],
    last: null,
  }
}

async function load($: any): Promise<S | undefined> {
  if (!sid) return undefined
  return (await $.store.get(`s:${sid}`)) as S | undefined
}

async function save($: any, s: S) {
  await $.store.set(`s:${sid}`, s)
}

async function stamp($: any): Promise<string> {
  return new Date(await $.clock.now()).toISOString()
}

async function appendLog($: any, name: string, record: object) {
  try {
    const day = (await stamp($)).slice(0, 10)
    const path = `${LOG_DIR}/${name}-${day}.jsonl`
    const prior = (await $.fs.exists(path)) ? String(await $.fs.read(path)) : ''
    await $.fs.write(path, prior + JSON.stringify({ at: await stamp($), session: sid, cwd, ...record }) + '\n')
  } catch (err) {
    $.ui.log(`session-color: log write failed: ${String(err)}`)
  }
}

function desiredColor(s: S): string {
  if (s.harness.length > 0) return 'pink'
  if (s.blocked) return 'red'
  return STAGE_COLOR[s.stage]
}

async function apply($: any, s: S) {
  if (!s.enabled || s.paused) return
  const color = desiredColor(s)
  if (color === s.applied) return
  try {
    await $.command.run({ command: 'color', args: color })
    s.applied = color
    await save($, s)
  } catch (err) {
    $.ui.log(`session-color: /color ${color} failed: ${String(err)}`)
  }
}

async function move($: any, s: S, to: Stage, by: Move['by'], why: string) {
  if (s.stage === to) return
  const m: Move = { at: await stamp($), from: s.stage, to, by, why }
  s.last = m
  s.stage = to
  await appendLog($, 'decisions', { kind: 'move', ...m })
  if (s.debug) $.ui.toast(`session-color: ${m.from} -> ${to} (${by}): ${why}`)
}

async function gh($: any, argv: string[]): Promise<any> {
  const r = await $.process.run(['gh', ...argv], { cwd: cwd || undefined, timeoutMs: 20000 })
  if (r.exitCode !== 0) {
    if (AUTH_RE.test(r.stderr)) throw new Error(`gh auth: ${r.stderr.slice(0, 200)}`)
    return undefined
  }
  return JSON.parse(r.stdout)
}

// T4/T5b: refresh tracked PR states, and find PRs opened from pushed branches.
async function refreshPrs($: any, s: S): Promise<boolean> {
  let isNew = false
  try {
    for (const b of s.branches) {
      const found = (await gh($, ['pr', 'list', '--head', b, '--state', 'all', '--json', 'url,state'])) ?? []
      for (const p of found) {
        if (!s.prs.some(x => x.url === p.url)) {
          s.prs.push({ url: p.url, state: p.state })
          isNew = true
        }
      }
    }
    for (const p of s.prs) {
      if (p.state !== 'OPEN') continue
      const v = await gh($, ['pr', 'view', p.url, '--json', 'state'])
      if (v?.state) p.state = v.state
    }
  } catch (err) {
    // T4a: gh itself needs a login: a harness problem for Ben.
    s.harness.push({ at: await stamp($), what: String(err) })
  }
  return isNew
}

// C0, P4, C2: the moves code decides from PR facts. Returns true when it moved.
async function codeMoves($: any, s: S): Promise<boolean> {
  const hasOpen = s.prs.some(p => p.state === 'OPEN')
  if (hasOpen && (s.stage === 'unvetted' || s.stage === 'building' || s.stage === 'merged')) {
    await move($, s, 'pr-ready', 'code', 'tracked PR open')
    return true
  }
  if (s.stage === 'pr-ready' && s.prs.length > 0 && !hasOpen && s.prs.some(p => p.state === 'MERGED')) {
    await move($, s, 'merged', 'code', 'every tracked PR merged')
    return true
  }
  return false
}

function startPoll($: any, s: S) {
  if (poll || !s.prs.some(p => p.state === 'OPEN')) return
  poll = $.clock.every(POLL_MS, () => void pollTick($))
}

async function pollTick($: any) {
  const s = await load($)
  if (!s?.enabled || s.paused || !s.prs.some(p => p.state === 'OPEN')) {
    poll?.cancel()
    poll = null
    return
  }
  await refreshPrs($, s)
  if (await codeMoves($, s)) s.suppressed = []
  await save($, s)
  await apply($, s)
}

// D1, D2, D4 (D3 is Haiku's evidence).
async function doneGate($: any, s: S): Promise<string | null> {
  if (s.prs.some(p => p.state === 'OPEN')) return 'a tracked PR is still open'
  try {
    const agents = await $.agent.list()
    if (agents.some((a: any) => ['pending', 'running', 'waiting'].includes(a.status))) return 'background agents still running'
  } catch {}
  for (const b of s.branches) {
    const wt = await $.process.run(['git', 'worktree', 'list', '--porcelain'], { cwd, timeoutMs: 10000 })
    if (wt.stdout.includes(`branch refs/heads/${b}\n`)) return `worktree still checked out for ${b}`
    const br = await $.process.run(['git', 'branch', '--list', b], { cwd, timeoutMs: 10000 })
    if (br.stdout.trim()) return `local branch ${b} still exists`
  }
  return null
}

async function readGuide($: any): Promise<string> {
  try {
    return String(await $.fs.read(GUIDE_PATH))
  } catch {
    return 'Decide whether the session stage should change. Default to stay. Reply with JSON only: {"next","confidence","evidence","blocked","blocked_what","harness","harness_what"}.'
  }
}

async function askHaiku($: any, s: S) {
  const moves = HAIKU_MOVES[s.stage].filter(m => !s.suppressed.includes(m))
  const msgs = await $.session.messages()
  const lastUser = [...msgs].reverse().find((m: any) => m.role === 'user' && m.text.trim())
  const recent = msgs.slice(-8).map((m: any) => {
    const tools = (m.toolUses ?? [])
      .map((t: any) => `${t.name}${t.isError ? ' (error)' : ''}: ${JSON.stringify(t.input ?? {}).slice(0, 100)}`)
      .join('; ')
    return `${m.role.toUpperCase()}: ${m.text.slice(0, 700)}${tools ? `\n  tools: ${tools}` : ''}`
  })
  const facts = {
    stage: s.stage,
    allowed_moves: ['stay', ...moves],
    blocked: s.blocked,
    harness_events: s.harness.slice(-3),
    tracked_prs: s.prs,
    last_move: s.last,
  }
  const prompt = `${await readGuide($)}

## This session now
${JSON.stringify(facts, null, 1)}

## Ben's latest message
${lastUser ? lastUser.text.slice(0, 1500) : '(none)'}

## Recent conversation (oldest first)
${recent.join('\n')}

Reply with the JSON object only.`

  const t0 = await $.clock.now()
  const r = await $.model.complete({ model: 'haiku', prompt, maxTokens: 200, effort: 'low', timeoutMs: 30000 })
  const ms = (await $.clock.now()) - t0
  if (!r.isAnswered) {
    await appendLog($, 'decisions', { kind: 'haiku-error', reason: r.reason, ms })
    return
  }
  let d: any = {}
  try {
    d = JSON.parse(r.text.replace(/```json|```/g, '').trim())
  } catch {
    await appendLog($, 'decisions', { kind: 'haiku-unparsed', text: r.text, ms })
    return
  }
  const confident = Number(d.confidence) >= MIN_CONFIDENCE && typeof d.evidence === 'string' && d.evidence.trim() !== ''
  let applied = 'stay'
  let gate: string | null = null

  if (confident && moves.includes(d.next)) {
    gate = d.next === 'done' ? await doneGate($, s) : null
    if (!gate) {
      await move($, s, d.next, 'haiku', d.evidence)
      applied = d.next
    }
  }
  if (confident && d.blocked === 'set' && !s.blocked) s.blocked = { at: await stamp($), what: d.blocked_what || d.evidence }
  if (confident && d.blocked === 'clear' && s.blocked) s.blocked = null
  if (confident && d.harness === 'set') s.harness.push({ at: await stamp($), what: d.harness_what || d.evidence })

  await appendLog($, 'decisions', {
    kind: 'haiku',
    ms,
    usage: r.usage,
    stage_before: facts.stage,
    allowed: facts.allowed_moves,
    answer: d,
    applied,
    gate,
    prompt_chars: prompt.length,
    prompt, // full input, so the tuning session can replay this case against a revised guide.md
  })
}

async function evaluate($: any, reason: string) {
  const s = await load($)
  if (!s?.enabled || s.paused) return
  const isNewPr = await refreshPrs($, s)
  const codeMoved = await codeMoves($, s)
  if (isNewPr || codeMoved) s.suppressed = []
  // T1/T2: Haiku only after a normal answer, and not when code already decided or nothing can move.
  if (reason === 'answer' && !codeMoved && s.stage !== 'done') await askHaiku($, s)
  await save($, s)
  await apply($, s)
  startPoll($, s)
}

function statusText(s: S | undefined): string {
  if (!s) return 'session-color: not enabled for this session (`/session-color on` to start)'
  const flags = [s.harness.length ? `harness: ${s.harness.at(-1)?.what}` : '', s.blocked ? `blocked: ${s.blocked.what}` : '']
    .filter(Boolean)
    .join('; ')
  return [
    `session-color: ${s.enabled ? (s.paused ? 'paused' : 'on') : 'off'}${s.debug ? ' (debug)' : ''}`,
    `stage: ${s.stage} (${STAGE_COLOR[s.stage]}), showing: ${s.applied ?? 'unknown'}`,
    flags ? `flags: ${flags}` : 'flags: none',
    `PRs: ${s.prs.map(p => `${p.url} ${p.state}`).join(', ') || 'none'}`,
    s.last ? `last move: ${s.last.from} -> ${s.last.to} by ${s.last.by} (${s.last.why})` : 'last move: none',
  ].join('\n')
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    // Headless runs (`claude -p`, including the cldp title probe) never get colors.
    if (!e.isInteractive) return next(e)
    sid = await $.session.id()
    cwd = e.cwd
    GUIDE_PATH = `${$.plugin.root}/guide.md`
    LOG_DIR =
      (await $.env.get('SESSION_COLOR_DATA_DIR')) || `${await $.env.get('HOME')}/.claude/plugins/data/session-color`
    await $.process.run(['mkdir', '-p', LOG_DIR], { timeoutMs: 5000 })
    await $.command.register({
      name: 'session-color',
      description: 'Stage-driven session color: status, on, off, ack, debug on|off, feedback <text>',
      argumentHint: '[on|off|ack|debug on|off|feedback <text>]',
    })
    let s = await load($)
    if (!s) {
      const flag = await $.env.get('CC_SESSION_COLOR')
      if (flag === 'on' || flag === '1') {
        s = fresh() // S1
        await save($, s)
        await appendLog($, 'decisions', { kind: 'start', stage: s.stage })
      }
    }
    if (s?.enabled && !s.paused) {
      const started = s
      $.clock.after(0, () => void apply($, started))
      startPoll($, started)
    }
    return next(e)
  })

  // Manual /color (M1 to M4). The mod's own runs come from timers, which skip this hook.
  on('command.run', { command: 'color' }, async ($, e, next) => {
    const result = await next(e)
    const origin: any = e.origin
    if (origin?.kind === 'plugin' && origin?.name === 'session-color') return result
    const s = await load($)
    if (!s?.enabled) return result
    const color = e.args.trim().toLowerCase()
    const before = { stage: s.stage, showing: s.applied }
    if (color === 'default') {
      s.paused = true // M2
      s.applied = null
    } else if (color === 'pink') {
      s.harness.push({ at: await stamp($), what: 'set by Ben' })
      s.applied = 'pink'
    } else if (color === 'red') {
      s.blocked = { at: await stamp($), what: 'set by Ben' }
      s.applied = 'red'
    } else if (COLOR_STAGE[color]) {
      const to = COLOR_STAGE[color]
      // M3: Ben reversed the mod's last automatic move.
      if (s.last && s.last.by !== 'ben' && s.last.to === s.stage && to === s.last.from) s.suppressed.push(s.last.to)
      s.harness = [] // F5
      s.blocked = null // F7
      s.paused = false
      await move($, s, to, 'ben', `/color ${color}`)
      s.applied = color
    } else {
      s.applied = null // a bare /color picks a random color
    }
    await save($, s)
    if (before.showing !== color) await appendLog($, 'feedback', { kind: 'override', color, before, after: s.stage }) // M4
    return result
  }).catch(($, e, next) => next(e))

  on('command.run', { command: 'session-color' }, async ($, e) => {
    const [sub = 'status', ...rest] = e.args.trim().split(/\s+/)
    let s = await load($)
    if (sub === 'status' || sub === '') return { text: statusText(s) }
    if (sub === 'on') {
      s = s ?? fresh() // S3
      s.enabled = true
      s.paused = false
      await save($, s)
      const started = s
      $.clock.after(0, () => void apply($, started))
      return { text: `session-color: on (stage ${s.stage})` }
    }
    if (!s) return { text: statusText(s) }
    if (sub === 'off') {
      s.enabled = false
      poll?.cancel()
      poll = null
    } else if (sub === 'ack') {
      s.harness = []
      const acked = s
      $.clock.after(0, () => void apply($, acked))
    } else if (sub === 'debug') {
      s.debug = rest[0] !== 'off'
    } else if (sub === 'feedback') {
      const text = rest.join(' ')
      if (!text) return { text: 'usage: /session-color feedback <what was wrong>' }
      await appendLog($, 'feedback', { kind: 'feedback', text, state: s })
      return { text: 'session-color: feedback logged' }
    } else {
      return { text: 'usage: /session-color [on|off|ack|debug on|off|feedback <text>]' }
    }
    await save($, s)
    return { text: statusText(s) }
  })

  // T5a/T5b: PRs and pushed branches; F3: auth failures.
  on('tool.call', async ($, e, next) => {
    const ran: any = await next(e)
    const isBash = e.tool === 'Bash'
    const input = JSON.stringify(e).slice(0, 4000)
    const isPrAction = PR_ACTION_RE.test(input)
    const isPush = isBash && /\bgit\b[^|;&]*\bpush\b/.test(String((e as any).command))
    if (!isPrAction && !isPush && !ran?.isError) return ran
    const s = await load($)
    if (!s?.enabled) return ran
    const text = typeof ran?.text === 'string' ? ran.text : JSON.stringify(ran?.result ?? '')
    let changed = false
    if (isPrAction && !ran?.isError) {
      for (const url of text.match(PR_URL_RE) ?? []) {
        if (!s.prs.some(p => p.url === url)) {
          s.prs.push({ url, state: 'OPEN' }) // refreshed from GitHub at the end of the turn
          changed = true
        }
      }
    }
    if (isPush && !ran?.isError) {
      for (const m of text.matchAll(/->\s+([\w./-]+)/g)) {
        if (!s.branches.includes(m[1]) && m[1] !== 'main' && m[1] !== 'master') {
          s.branches.push(m[1])
          changed = true
        }
      }
    }
    if (ran?.isError && AUTH_RE.test(text)) {
      s.harness.push({ at: await stamp($), what: `${e.tool}: ${text.match(AUTH_RE)?.[0]}` })
      changed = true
    }
    if (changed) await save($, s)
    return ran
  }).catch(($, e, next) => next(e))

  // F1
  on('classic.PermissionDenied', async ($, e, next) => {
    const s = await load($)
    if (s?.enabled) {
      s.harness.push({ at: await stamp($), what: `${(e as any).tool_name} denied: ${String((e as any).reason).slice(0, 160)}` })
      await save($, s)
    }
    return next(e)
  }).catch(($, e, next) => next(e))

  // F2
  on('classic.StopFailure', async ($, e, next) => {
    const s = await load($)
    const err = String((e as any).error)
    if (s?.enabled && AUTH_STOP_ERRORS.includes(err)) {
      s.harness.push({ at: await stamp($), what: `Claude Code: ${err}` })
      await save($, s)
    }
    return next(e)
  }).catch(($, e, next) => next(e))

  // T1: evaluate after each main-thread turn, off the turn's path.
  on('turn.complete', async ($, e, next) => {
    const result = await next(e)
    if (e.agentId !== undefined || !sid) return result
    const reason = String((e as any).reason)
    $.clock.after(0, () => void evaluate($, reason))
    return result
  })
}
