# CDP Protocol Status

生成日期：2026-06-05

本文件记录一次本地 bundled schema 与真实远程调试端口 `/json/protocol` 的对比结果。该状态用于维护判断，不作为运行时兼容性的硬门槛。

## 测试环境

- Browser: `Edg/148.0.3967.96`
- Protocol-Version: `1.3`
- User-Agent: `HeadlessChrome/148.0.0.0 ... Edg/148.0.0.0`
- Browser path: `C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe`
- Launch mode: `--remote-debugging-port=0` with a temporary user-data-dir

## Bundled Schema

- `browser_protocol.json`
  - sha256: `bb10379f95d76f9c423f68039df3bc996b8ae26563434a4d66e1bb0ae90300c8`
- `js_protocol.json`
  - sha256: `5a54a335617a0ff088c22f8d7a39ee7616ebdba3eb982ebf4e6b1869239e60f5`

| Source | Domains | Commands | Events | Types |
| --- | ---: | ---: | ---: | ---: |
| Bundled browser+js | 54 | 664 | 236 | 632 |
| Edge `/json/protocol` | 59 | 676 | 238 | 621 |

## Diff Summary

| Kind | Remote-only | Local-only |
| --- | ---: | ---: |
| Domain | 5 | 0 |
| Command | 17 | 5 |
| Event | 6 | 4 |
| Type | 21 | 32 |

Remote-only domains are Edge-specific or browser-vendor extensions:

- `CrashReportContext`
- `EdgeDOMMemory`
- `EdgeDevToolsSnapshot`
- `EdgeTesting`
- `WebMCP`

Selected remote-only commands:

- `CSS.setNavigationText`
- `Emulation.updateScreen`
- `CrashReportContext.getEntries`
- `EdgeDOMMemory.enable`
- `EdgeDOMMemory.disable`
- `EdgeDevToolsSnapshot.createSessionLog`
- `EdgeTesting.enableCopilotBrowserActions`
- `WebMCP.enable`
- `WebMCP.disable`

Selected local-only commands:

- `Audits.checkContrast`
- `Storage.getAffectedUrlsForThirdPartyCookieMetadata`
- `Storage.sendPendingAttributionReports`
- `Storage.setAttributionReportingLocalTestingMode`
- `Storage.setAttributionReportingTracking`

Selected event differences:

- Remote-only: `Animation.svgAnimationRegistered`, `Emulation.screenOrientationLockChanged`, `WebMCP.toolInvoked`, `WebMCP.toolsAdded`
- Local-only: `Storage.attributionReportingReportSent`, `Storage.attributionReportingSourceRegistered`, `Storage.attributionReportingTriggerRegistered`

## Maintenance Notes

- Raw CDP remains usable for remote-only commands and events.
- Bundled typed API should not block connection when remote schema differs.
- Local-only typed commands need a runtime unsupported diagnostic when the active remote schema proves the command is absent.
- Edge vendor domains should stay remote-only unless this project intentionally decides to vendor Edge-specific protocol extensions.
