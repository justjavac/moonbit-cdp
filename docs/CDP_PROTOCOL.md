# CDP 协议层使用说明

本文记录当前 CDP core 的公开模型。协议层目标是完整覆盖 Chrome DevTools Protocol，并提供低层 escape hatch；不会为所有 CDP command 手写一层重复 wrapper。

## Target 模型

- `parse_cdp_target(raw)` 接受 `9222`、`127.0.0.1:9222`、HTTP discovery URL、browser WebSocket URL 和 page WebSocket URL。
- `discover_version(target)` 读取 `/json/version`，返回 Browser、Protocol-Version、User-Agent 和 browser `webSocketDebuggerUrl`。
- `discover_targets(target)` 读取 `/json/list`，返回远程调试端口暴露的 target 列表。
- `discover_protocol(target)` 读取 `/json/protocol`，用于和 bundled schema 做兼容性对比。
- `connect_cdp_browser_target(target)` 连接 browser endpoint，适合 `Browser.*` 和 `Target.*` command。
- `connect_cdp_page_target(target, ...)` 选择 page endpoint，适合直接操作 page target。
- `connect_cdp_*_with_timeout(target, timeout_ms?)` 先 discovery 再连接，并把 WebSocket 连接超时/握手失败包装为结构化错误。

Browser target 是推荐的 E2E 基础入口：先用 `Target.createTarget` 创建页面，再用 `Target.attachToTarget(flatten=true)` 得到 session id，后续 page command 都带上该 session id。

## 连接错误

Discovery 阶段抛出的 `DiscoveryError` 提供 `diagnostic()`、`kind()` 和 `path()`：

- HTTP 非 2xx 返回 `HttpStatus(code, reason)`，diagnostic 中保留 `http_status` 和 `reason`。
- `/json/version` 缺少 browser endpoint 返回 `MissingWebSocketDebuggerUrl`。
- `/json/list` 中选中的 target 缺少 endpoint 返回 `MissingTargetWebSocketDebuggerUrl(target_id)`。

WebSocket 连接阶段可使用 `CdpClient::connect_with_timeout(web_socket_url, timeout_ms?)` 或 `connect_cdp_*_with_timeout(...)`。它们保留原有 raw CDP 能力，同时把连接失败归类为：

- `ConnectionTimeout(web_socket_url, timeout_ms)`。
- `WebSocketHandshakeFailed(web_socket_url, reason)`。

## Raw CDP

`CdpClient::send_command(method, params?, session_id?)` 是完整协议覆盖的底线能力。只要远程 Chrome 支持某个 CDP method，即使本地 schema 没有 convenience wrapper，也可以通过 raw JSON 发送。

CLI 低层入口使用 `cdp` 命名空间，默认输出 JSON：

- `cdp send <target> <method> [json] [--session <id>]` 发送任意 CDP command。
- `cdp targets <target>` 同时输出 `/json/list` 和 `Target.getTargets` 视角。
- `cdp attach <target> <target-id>` 使用 `Target.attachToTarget(flatten=true)` 并输出 session id。
- `cdp events <target> --method <method> --timeout <ms>` 等待一个 event。
- `cdp schema <target>` 输出远程 `/json/protocol`。

低层 in-flight API 可用于更细的控制：

- `send_cdp_command(method, params?, session_id?)`：只发送 command，返回 request id。
- `recv_cdp_response(id, timeout_ms?)`：等待指定 id 的 response。
- `recv_cdp_event(method_name?, session_id?)`：从事件缓冲或 WebSocket 中等待匹配 event。
- `cdp_events(method_name?, session_id?)`：读取已记录 event。
- `on_cdp_event(...)` / `remove_cdp_event_handler(...)`：订阅和取消订阅 event。

## Typed CDP

`protocol` 包从 bundled `browser_protocol.json` 和 `js_protocol.json` 生成 typed params/result/event/type surface。`CdpClient::send_schema_command(method, params?, session_id?)` 会先按 schema 校验 method/params，收到 response 后按 generated result decoder 校验结果。

当远程 `/json/protocol` 与 bundled schema 不一致时，`protocol_schema_diff(remote_schema)` 用于报告 remote-only、local-only 和 field changed。raw CDP 不会因为 schema diff 被阻断。

如果调用方已经读取了远程 `/json/protocol`，可以使用 `CdpClient::send_remote_schema_command(remote_schema, method, ...)`。它会先按 bundled schema 构建 typed command；如果本地支持但远程 schema 不含该 method，会返回 `ProtocolSchemaError::UnsupportedRemoteCommand(method)`，避免把 local-only typed API 发送到不支持它的浏览器。

## Manifest Flags

`protocol_manifest()` 和 registry API 保留 `experimental` / `deprecated` 标记：

- `ProtocolDomainSummary` 记录 domain-level flags。
- `ProtocolCommand` 记录 command flags，并通过 `parameter_details` / `return_details` 保留参数和返回值 flags。
- `ProtocolEvent` 通过 `parameter_details` 保留事件参数 flags。
- `ProtocolType` 记录 type flags，并通过 `property_details` 保留属性 flags。

旧的 `parameters`、`returns`、`properties` 字符串摘要保持原格式，用于 schema validator 和兼容现有调用；新增 details 字段用于需要完整 manifest 元数据的工具。

## Async 模型

协议 runtime 使用 `moonbitlang/async`，不引入自定义 event loop abstraction。

- 一个 `CdpClient` 包装一个 WebSocket 连接。
- 多个 in-flight command 可以共用同一个连接；response 按 CDP `id` 归还给对应请求。
- Browser-level command 和 flatten session 下的 page-level command 共用同一个 browser WebSocket。
- Event 按 `method` 和 `sessionId` 记录、过滤和订阅。
- `recv_cdp_response(id, timeout_ms?)` 超时后会清理该 request 的 pending context 并关闭 WebSocket；调用方应重连。
- `recv_cdp_event(...)` 当前用于测试和低层等待；需要业务级 timeout 时，调用方应使用 `@async.with_timeout_opt` 包裹。
- `CdpClient::close()` 会清理当前连接的 in-flight command context 和 pending response，然后关闭 WebSocket；如果需要关闭浏览器进程，使用 `Browser.close` 对应的 `close_browser()`。

## E2E 启动

`launch_browser(options)` 支持固定端口和 `port=0`。当 `port=0` 时，会传入 `--remote-debugging-port=0`，然后从独立 user-data-dir 下的 `DevToolsActivePort` 文件读取实际端口和 browser WebSocket path。

真实浏览器 smoke test 见 `docs/CDP_E2E.md`。

## Schema 更新流程

更新 bundled CDP schema 时按固定流程做，避免生成结果漂移：

1. 替换 `protocol/data/browser_protocol.json` 和 `protocol/data/js_protocol.json`。
2. 运行 `node tools/gen_protocol_manifest.mjs --check`，确认 domain/command/event/type 计数和 sha256。
3. 如果 check 提示生成文件变化，运行 `node tools/gen_protocol_manifest.mjs` 重新生成。
4. 运行 `moon fmt && moon check && moon test protocol && moon info`。
5. Review `protocol/pkg.generated.mbti` 和根/下游 `.mbti`，确认公开 API 变化来自 schema 更新本身。
6. 最后运行全量 `moon test`，真实浏览器相关测试仍保持默认跳过，按 `docs/CDP_E2E.md` 手动打开。

生成器变更 review checklist：

- 输出排序稳定：domain、command、event、type、字段顺序不依赖输入对象遍历偶然性。
- 命名稳定：同一 CDP 名称反复生成相同 MoonBit 标识符。
- `optional`、`nullable`、`$ref`、`array`、`enum`、`object`、`any/raw JSON` 都有明确处理。
- `deprecated` / `experimental` 在 domain、command、event、type、参数、返回值、属性层级保留。
- raw CDP escape hatch 不能被 typed schema 校验阻断。

## 兼容策略

Bundled schema 用于提供稳定 typed builder/decoder 和本地文档；远程 Chrome/Chromium 的真实能力以 `/json/protocol` 为准。

- 本地 schema 随项目版本更新，不在运行时强制要求远程版本完全一致。
- `protocol_schema_diff(remote_schema)` 报告 remote-only、local-only 和 field changed。
- remote-only command/event/type 继续允许通过 raw JSON fallback 使用。
- local-only typed API 可通过 `send_remote_schema_command` 结合远程 schema 做兼容判断；不能把 schema diff 作为连接失败处理。

## E2E Troubleshooting

- 端口占用：换固定端口，或使用 `launch_browser` 的 `port=0` 让浏览器分配端口。
- Chrome 未启动：检查 `browser_path`，或通过 `MBT_CDP_BROWSER` 指定 Chrome/Edge/Chromium 可执行文件。
- 默认 profile remote debugging 被拒：Chrome 136+ 对默认 profile 有限制；E2E 必须使用独立 `user-data-dir`。
- IPv4/IPv6 localhost：优先使用 `127.0.0.1:<port>`，避免浏览器只监听 IPv4 时 `localhost` 解析到 `::1`。
- 证书/代理：测试页面优先使用 data URL；需要代理时用 launch options 的 `proxy_server` / `proxy_bypass`。
