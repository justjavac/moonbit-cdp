# CDP E2E 测试说明

`connection/e2e_test.mbt` 提供真实 Chrome/Chromium 的 CDP smoke test。默认情况下测试只输出 skip 原因并通过，不会启动浏览器。

## 开启方式

默认只跑跳过分支：

```powershell
moon test connection
```

连接已有远程调试端口：

```powershell
$env:MBT_CDP_E2E = "1"
$env:MBT_CDP_TARGET = "127.0.0.1:9222"
moon test connection
```

自动启动 Chrome：

```powershell
$env:MBT_CDP_E2E = "1"
$env:MBT_CDP_BROWSER = "C:\Program Files\Google\Chrome\Application\chrome.exe"
moon test connection
```

如果未设置 `MBT_CDP_BROWSER`，测试会尝试 `AGENT_BROWSER_EXECUTABLE_PATH`，再尝试项目已有的 Chrome 可执行文件发现逻辑。未找到 Chrome 时会跳过并输出明确原因。仅通过自动发现得到的浏览器如果没有在等待窗口内开放 CDP endpoint，也会跳过；显式指定浏览器路径时会保留失败，便于 CI 暴露环境问题。

## 环境变量

- `MBT_CDP_E2E=1`：开启真实浏览器 E2E。
- `MBT_CDP_TARGET`：连接外部调试端口，支持 `9222`、`127.0.0.1:9222`、HTTP URL、browser/page WebSocket URL。
- `MBT_CDP_BROWSER`：自动启动模式使用的 Chrome/Chromium 路径。
- `AGENT_BROWSER_EXECUTABLE_PATH`：`MBT_CDP_BROWSER` 未设置时的兼容路径来源。
- `MBT_CDP_E2E_PROFILE`：自动启动模式使用的独立 user-data-dir；默认是 `_build/mbt-cdp-e2e-profile-auto`。
- `MBT_CDP_E2E_HEADLESS=0`：自动启动模式使用 headed Chrome；默认 headless。

## 当前覆盖

测试会连接 `/json/version` 和 `/json/list`，通过 browser target 执行 `Target.createTarget`，attach flatten session，然后在 data URL 测试页上覆盖 `Page.navigate`、`Page.loadEventFired`、`Runtime.evaluate`、`DOM.getDocument`、`DOM.querySelector`、`Network.requestWillBeSent`、`Network.responseReceived`、`Page.captureScreenshot` 和 `Target.closeTarget`。

自动启动模式使用 `--remote-debugging-port=0`，然后从独立 user-data-dir 下的 `DevToolsActivePort` 文件发现 Chrome 实际绑定端口和 browser WebSocket path。

## 失败诊断

真实浏览器 E2E 失败时会统一补充诊断字段：

- `browser_path`：自动启动模式使用的 Chrome/Edge/Chromium 路径；外部 `MBT_CDP_TARGET` 模式可能为 `unavailable`。
- `target`：测试实际连接的 CDP target。
- `version_metadata`：`/json/version` 中的 Browser、Protocol-Version 和 browser WebSocket URL。
- `last_request`：最后发送的 CDP request id、method、session。
- `last_response`：最后收到的 CDP response id、session、error 摘要。
- `last_event`：最后收到的 CDP event method、session。
