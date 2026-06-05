# justjavac/moonbit_cdp

MoonBit Chrome DevTools Protocol library and CLI.

This repository is now CDP-only. It keeps the generated protocol surface,
remote debugging discovery, WebSocket CDP client, low-level CLI commands, and
real-browser E2E tests. Agent-browser-style automation commands, daemon/session
runtime, providers, dashboard, chat, recording, screenshot diff, auth vault,
state, cookies, storage, and other high-level browser helpers have been removed.

## Packages

- `protocol`: bundled Chrome DevTools Protocol schema, generated command
  builders, event builders, result decoders, and generic schema validation.
- `connection`: remote debugging endpoint discovery, WebSocket CDP client,
  target attach/create helpers used by E2E, and optional Chrome launch helpers.
- `cli`: CDP-only command parser.
- `cmd/main`: native CLI entry point.

## CLI

Targets can be a remote debugging port, `host:port`, HTTP DevTools endpoint, or
direct browser/page WebSocket URL.

```bash
moon run cmd/main --target native -- version
moon run cmd/main --target native -- connect 9222
moon run cmd/main --target native -- cdp schema 9222
moon run cmd/main --target native -- cdp targets 9222
moon run cmd/main --target native -- cdp send 9222 Browser.getVersion
moon run cmd/main --target native -- cdp send 9222 Runtime.evaluate '{"expression":"1+1","returnByValue":true}' --session <session-id>
moon run cmd/main --target native -- cdp attach 9222 <target-id>
moon run cmd/main --target native -- cdp events 9222 --method Page.loadEventFired --timeout 5000
```

## E2E

Unit tests run without a browser:

```bash
moon test
```

Real browser E2E is opt-in:

```bash
MBT_CDP_E2E=1 moon test connection --filter "*real Chrome CDP E2E*"
```

Useful environment variables:

- `MBT_CDP_TARGET`: existing remote debugging endpoint, for example `9222` or
  `http://127.0.0.1:9222`.
- `MBT_CDP_BROWSER`: Chrome/Edge/Chromium executable path used when the test
  should launch a browser itself.
- `MBT_CDP_E2E_HEADLESS=0`: run launched browser headed.
- `MBT_CDP_E2E_PROFILE`: user data directory for launched browser E2E.

The E2E test checks `/json/version`, `/json/list`, target creation, attach,
Page/Runtime/DOM/Network schema commands, event buffering, and cleanup through
CDP commands.

## Protocol Coverage

The bundled protocol currently covers 54 domains, 664 commands, 236 events, and
632 types. See `docs/CDP_PROTOCOL.md`, `docs/CDP_PROTOCOL_STATUS.md`, and
`docs/CDP_E2E.md` for details.
