import type { Register } from 'claude-code'

// Turn-ending API errors that come from the network path, not from the request
// itself. Anything else (login, limits, prompt too long, refusals) is left alone.
const NETWORK_ERROR =
  /^API Error: (EPROTO|ECONNRESET|ETIMEDOUT|EPIPE|socket hang up|Connection lost mid-response|The response stopped arriving|No response from API|Unable to connect to API|Connection error)/i

// Wait before each automatic continue in one streak; its length is the cap.
const BACKOFF_MS = [5_000, 30_000, 90_000]

const CONTINUE_TEXT =
  'continue (the previous response was cut off by a network error; pick up where it stopped, without repeating finished work)'

export const register: Register = on => {
  // Module state: a reload starts these over, which is fine for a retry streak.
  let isEnabled = true
  let streak = 0
  let lastError: string | undefined
  let pending: { cancel: () => void } | undefined

  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'auto-continue',
      description: 'Auto-continue after network API errors: on, off, or status',
    })
    return next(e)
  })

  on('command.run', { command: 'auto-continue' }, async ($, e) => {
    const arg = e.args.trim().toLowerCase()
    if (arg === 'off') {
      isEnabled = false
      pending?.cancel()
      pending = undefined
      $.ui.status(undefined)
    } else if (arg === 'on') {
      isEnabled = true
      streak = 0
    }
    const state = isEnabled ? 'on' : 'off'
    return {
      text: `auto-continue is ${state}; streak ${streak}/${BACKOFF_MS.length}${lastError ? `; last error: ${lastError}` : ''}`,
    }
  })

  // Note the error text as the engine records it on the main conversation.
  on('session.append', async ($, e, next) => {
    if (e.agentId === undefined && e.message.type === 'assistant') {
      const text = e.message.content
        .map(block => (block.type === 'text' ? block.text : ''))
        .join('')
        .trim()
      if (NETWORK_ERROR.test(text)) lastError = text.slice(0, 80)
    }
    return next(e)
  })

  // Anything the person sends cancels a pending automatic continue.
  on('prompt.submit', async ($, e, next) => {
    if (e.origin.kind !== 'plugin' && pending !== undefined) {
      pending.cancel()
      pending = undefined
      $.ui.status(undefined)
    }
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    const done = await next(e)
    if (e.agentId !== undefined) return done

    if (e.reason !== 'error') {
      // A finished (or interrupted) turn ends the streak.
      if (e.reason === 'answer') streak = 0
      lastError = undefined
      return done
    }

    const error = lastError
    lastError = undefined
    if (!isEnabled || error === undefined) return done

    if (streak >= BACKOFF_MS.length) {
      $.ui.toast(`auto-continue: gave up after ${streak} tries (${error})`, { timeoutMs: 10_000 })
      $.ui.status(undefined)
      streak = 0
      return done
    }

    const waitMs = BACKOFF_MS[streak] ?? 90_000
    streak += 1
    const attempt = streak
    pending?.cancel()
    $.ui.status(`auto-continue ${attempt}/${BACKOFF_MS.length} in ${waitMs / 1000}s (network error)`)
    pending = $.clock.after(waitMs, () => {
      pending = undefined
      $.ui.status(undefined)
      $.ui.toast(`auto-continue ${attempt}/${BACKOFF_MS.length}: ${error}`)
      void $.prompt.submit({ text: CONTINUE_TEXT })
    })
    return done
  })
}
