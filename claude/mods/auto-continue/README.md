# auto-continue

A Claude Code mod that sends a `continue` prompt for you when a turn dies on a network error, so a session keeps going without you having to notice and type it.

It exists because sessions on the GlobalProtect / Prisma Access VPN periodically lose their connection to the API mid-response. Since Claude Code 2.1.303 (Bun 1.4.4) such a drop ends the turn with `API Error: EPROTO: The TLS handshake failed...` instead of being recovered (anthropics/claude-code#106197).

## What it reacts to

Only turn-ending API errors that come from the network path:

- `EPROTO`, `ECONNRESET`, `ETIMEDOUT`, `EPIPE`, `socket hang up`
- "Connection lost mid-response"
- "The response stopped arriving"
- "No response from API"
- "Unable to connect to API", "Connection error"

Login, usage-limit, prompt-too-long, refusal and every other error are left alone. Only the main conversation is watched, not subagents.

## Behaviour

| | |
|---|---|
| Backoff | 5 s, then 30 s, then 90 s before each automatic continue in a streak |
| Cap | 3 tries in a row; then it stops and shows a toast |
| Reset | A turn that ends with a normal answer resets the streak |
| Cancel | Anything you send yourself cancels a pending continue |
| Feedback | Status-line countdown while waiting; a toast when it sends |

The prompt it sends tells the model the previous response was cut off by a network error and to pick up without repeating finished work.

## Commands

```
/auto-continue        status: on or off, current streak, last error seen
/auto-continue on     turn it on (default) and reset the streak
/auto-continue off    turn it off and cancel anything pending
```

The on/off setting lasts until the mod reloads or the session restarts.

## Install

```
/plugin install auto-continue@dev-setup
```

## Tests

`claude plugin test claude/mods/auto-continue` runs `tests/auto-continue.test.ts`: a network error sends the continue after the backoff, other errors are ignored, and a streak stops at three tries.

It was also checked end to end on Claude Code 2.1.319 against a local fake Vertex endpoint that breaks the TLS stream mid-response (the repro from anthropics/claude-code#106197): the turn ended with the EPROTO error, the mod showed its 5 s countdown, sent the continue, and the next request completed.
