import { expect, mock, test } from 'claude-code/testing'

const errorRow = (text: string) => ({
  message: { type: 'assistant' as const, role: 'assistant' as const, content: [{ type: 'text' as const, text }] },
  door: 'response' as const,
  origin: { kind: 'model' as const },
  uuid: crypto.randomUUID(),
})

const turnEnd = (reason: 'error' | 'answer') => ({
  answer: '',
  durationMs: 10,
  isAborted: false,
  turnId: crypto.randomUUID(),
  reason,
})

test('a network error ends the turn: continue is sent after the backoff', async ($, on) => {
  const clock = mock.clock(on)
  const sent: string[] = []
  on('prompt.submit', (_, e) => {
    sent.push(e.text)
    return { text: e.text }
  })
  on('turn.complete', (_, e) => ({ text: e.answer }))

  await $.session.append(errorRow('API Error: EPROTO: The TLS handshake failed. Does the server speak TLS on this port?'))
  await $.turn.complete(turnEnd('error'))

  await clock.advance(4_000)
  expect(sent.length).toBe(0)
  await clock.advance(1_500)
  expect(sent.length).toBe(1)
  expect(sent[0]?.startsWith('continue')).toBe(true)
})

test('other API errors are left alone', async ($, on) => {
  const clock = mock.clock(on)
  const sent: string[] = []
  on('prompt.submit', (_, e) => {
    sent.push(e.text)
    return { text: e.text }
  })
  on('turn.complete', (_, e) => ({ text: e.answer }))

  await $.session.append(errorRow('API Error: Login expired · Please run /login'))
  await $.turn.complete(turnEnd('error'))
  await clock.advance(120_000)
  expect(sent.length).toBe(0)
})

test('the streak stops at three tries', async ($, on) => {
  const clock = mock.clock(on)
  const sent: string[] = []
  on('prompt.submit', (_, e) => {
    sent.push(e.text)
    return { text: e.text }
  })
  on('turn.complete', (_, e) => ({ text: e.answer }))

  for (let i = 0; i < 4; i++) {
    await $.session.append(errorRow('API Error: Connection lost mid-response. The response above may be incomplete.'))
    await $.turn.complete(turnEnd('error'))
    await clock.advance(100_000)
  }
  expect(sent.length).toBe(3)
})
