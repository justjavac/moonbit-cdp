# CDP 协议优先实施计划

## 目标

当前阶段重新聚焦为先完成 CDP 协议层，而不是继续扩展 agent-browser 的全部上层功能。

目标定义：

- 完整覆盖 Chrome DevTools Protocol 的 browser/js 协议定义。
- 可以直接连接已有 Chrome/Chromium 远程调试端口，例如 `127.0.0.1:9222`。
- 可以通过 browser target 和 page target 发送 CDP command、接收 response/event。
- 可以作为本项目和下游项目的 E2E 测试基础，稳定启动/连接浏览器、创建页面、导航、断言页面状态、收集调试输出。

非目标：

- 本阶段不优先做 dashboard、chat、provider、iOS、recording、完整 daemon UX。
- 本阶段不把所有 agent-browser 风格别名补齐；高层 CLI 只作为协议层验收入口。
- 不为了覆盖协议而手写大量重复 API；优先修复生成器和协议 runtime。

## 来源和当前基线

参考来源：

- 官方 CDP 文档：<https://chromedevtools.github.io/devtools-protocol/>
- 官方说明中，Chrome 使用 `--remote-debugging-port=9222` 时，当前浏览器实际支持的完整协议可从 `http://localhost:9222/json/protocol` 获取。
- 官方说明中，browser target 的 WebSocket endpoint 来自 `/json/version` 的 `webSocketDebuggerUrl`；page targets 来自 `/json` 或 `/json/list`。
- DevTools Protocol Monitor 可作为行为核对工具：<https://developer.chrome.com/docs/devtools/protocol-monitor>
- 本地 schema：`protocol/data/browser_protocol.json`、`protocol/data/js_protocol.json`

当前本地 schema 统计：

- `browser_protocol.json`：48 个 domain、583 个 command、214 个 event、584 个 type。
- `js_protocol.json`：6 个 domain、81 个 command、22 个 event、48 个 type。
- 合计：54 个 domain、664 个 command、236 个 event、632 个 type。

当前已有能力：

- `protocol` 包已有生成的 manifest、typed command/event/type surface。
- `protocol` 包已有覆盖统计测试，当前断言 54/664/236/632。
- `tools/gen_protocol_manifest.mjs --check` 已可校验 browser/js schema 固定计数、输出 schema hash，并比较当前生成文件与重新生成后经 `moon fmt` 的稳定输出。
- `protocol_coverage_report()` 已提供结构化覆盖报告，覆盖 registry、typed builder、params/result/event decoder 和 domain type 的缺失计数。
- `protocol_manifest()` 已记录两份本地 schema 的 path、sha256、字节数和 domain/command/event/type 计数。
- `connection` 包已有 `parse_cdp_target`、`discover_web_socket_url`、`discover_browser_web_socket_url`、`discover_page_web_socket_url`、`connect_cdp_target`、`connect_cdp_browser_target`、`connect_cdp_page_target`、`CdpClient::connect`、`send_command`、`send_schema_command`、`send_cdp_message`、`attach_to_target` 等基础能力。
- `connection` 包已新增 `discover_version`、`discover_targets`、`discover_protocol`，覆盖远程调试端口的 `/json/version`、`/json/list`、`/json/protocol` 读取。
- `protocol` 包已新增 `protocol_remote_summary()` 和 `protocol_schema_diff()`，可将远程 `/json/protocol` 与 bundled schema 按 domain/command/event/type 对比，并标出 remote-only、local-only、field changed。
- `CdpClient` 已新增低层 in-flight API：`send_cdp_command`、`recv_cdp_response`、`recv_cdp_event`、`cdp_events`、`on_cdp_event`、`remove_cdp_event_handler`。
- `recv_cdp_response(id, timeout_ms?)` 已支持超时；超时会清理对应 command context/pending response 并关闭 WebSocket，调用方应重连。
- `CdpClient` 已维护 attached target 状态：`Target.attachedToTarget` 记录 session -> target，`Target.detachedFromTarget` / `Inspector.detached` 清理。
- CLI 已有大量高层命令可通过现有 connection/runtime 调用 CDP。

主要风险：

- 协议代码虽然已经生成，但生成器、schema 版本来源、远程 `/json/protocol` 对比、结果/event typed decode 覆盖、真实浏览器 E2E 验收还没有形成闭环。
- 部分 CDP 方法只有 wire builder，没有足够的 runtime convenience API；本阶段应接受低层 `send_command` 作为完整协议覆盖入口，避免为 664 个 command 手写 wrapper。
- 本地 schema 与用户运行的 Chrome 版本可能不同；必须支持按远程端口获取实际 schema 并做兼容性报告。

## 成功标准

- [x] `protocol` 包可以从本地 schema 生成所有 manifest、typed params/result/event/type、builder、decoder 和覆盖统计。
- [x] 生成器可重复运行，生成结果稳定；`moon info` 后 `.mbti` 变化可解释。
- [x] 协议层覆盖检查能明确报告：domain、command、event、type、command params、command result、event params 的覆盖差异。
- [x] connection 层可以稳定解析并连接 `9222`、`127.0.0.1:9222`、`http://127.0.0.1:9222`、`ws://.../devtools/browser/...`、`ws://.../devtools/page/...`。
- [x] 支持读取远程 `GET /json/version`、`GET /json/list`、`GET /json/protocol`，并把 browser/page WebSocket URL 正规化为可连接地址。
- [x] 支持 browser target command、flatten session 下的 page target command、response/error/event dispatch。
- [x] 提供 E2E 测试工具入口：启动或连接 Chrome，创建 page，导航到测试页，执行 `Runtime.evaluate` / `Page.navigate` / `DOM` / `Network` / `Page.captureScreenshot` 等基本断言。
- [x] 在没有本机 Chrome 或端口不可用时，E2E 测试可跳过并给出明确原因；CI 可通过环境变量开启真实浏览器 E2E。

## P0：协议完整性和远程端口基础

- [x] 固定协议生成入口：补充 `tools/gen_protocol_manifest.mjs` 的 README 或脚本命令，明确输入、输出、稳定排序规则。
- [x] 增加生成器自检：读取 `browser_protocol.json` 和 `js_protocol.json` 后，输出并校验 domain/command/event/type 数量。
- [x] 增加 schema provenance：在生成文件或 manifest 中记录 schema 来源、version major/minor、输入文件 hash。
- [x] 增加 `protocol_coverage_report()`，返回结构化差异，而不仅是 boolean `complete`。
- [x] 覆盖 command params/result 的可解码性：每个 command 至少能从 schema 得到 builder，带 returns 的 command 必须有 result decoder 或明确标为 raw JSON fallback。
- [x] 覆盖 event params 的可解码性：每个 event 至少能得到 typed event decoder 或 raw JSON fallback。
- [x] 保留 `send_command(method, params, session_id?)` 作为完整 CDP 覆盖的低层 escape hatch。
- [x] 增加 typed `send` 辅助设计，不手写 664 个 runtime wrapper：优先让 generated command builder + generated result decoder 能组合使用。
- [x] 为 experimental/deprecated 字段保留 manifest 信息，E2E 和文档中不隐藏这些协议项。
- [x] review 一次 `ProtocolSchemaError` 粒度，确保错误能指出 domain/method/field/path，而不是只返回笼统解析失败。

## P0：远程调试端口 discovery 和连接

- [x] 扩展并测试 `parse_cdp_target`：支持裸端口、host:port、HTTP URL、WebSocket browser URL、WebSocket page URL。
- [x] 增加远程端口 metadata API：`discover_version(target)` 对应 `/json/version`。
- [x] 增加 target list API：`discover_targets(target)` 对应 `/json` 或 `/json/list`。
- [x] 增加 remote protocol API：`discover_protocol(target)` 对应 `/json/protocol`。
- [x] 正规化 `localhost` / `127.0.0.1` / IPv4 行为；优先避免 Chrome 只监听 IPv4 时把 `localhost` 解析成不可连的 `::1`。
- [x] 支持 browser target 与 page target 的连接差异：browser endpoint 用于 Target/Browser 域，page endpoint 用于页面域。
- [x] 支持从 browser target 创建 page：`Target.createTarget` + `Target.attachToTarget(flatten=true)`。
- [x] 支持从 `/json/list` 选择第一个 page target，并可按 target id/url/title/type 选择。
- [x] 增加连接超时、握手失败、HTTP 状态码、缺少 `webSocketDebuggerUrl` 的结构化错误。
- [x] 增加连接 close/reconnect 基础行为：不要求 daemon，但 CdpClient close 后不能留下未完成 pending response。

## P0：CDP wire runtime

- [x] audit WebSocket message loop：确保 response 按 `id` 唤醒，event 按 `method` 分发，session event 保留 `sessionId`。
- [x] 支持 CDP error response：解析 `error.code`、`error.message`、`error.data`，并带上 request method/session。
- [x] 支持 concurrent commands：多个 in-flight command 不串包。
- [x] 为 in-flight command 增加 timeout，并在超时后清理 pending response/context。
- [x] 支持 browser-level 和 session-level command 共用一个 WebSocket。
- [x] 支持 `Target.attachedToTarget`、`Target.detachedFromTarget`、`Inspector.detached` 的基础状态维护。
- [x] 增加 event subscription API：按 method 订阅、按 session 过滤、可取消订阅。
- [x] 增加 raw event drain API，便于 E2E 测试等待 `Page.loadEventFired`、`Network.loadingFinished` 等事件。
- [x] 明确线程/async 模型：优先使用 `moonbitlang/async`，不要引入自定义 event loop abstraction。

## P1：E2E 测试能力

- [x] 新增 `connection` 下的真实浏览器测试说明，默认跳过，环境变量开启，例如 `MBT_CDP_E2E=1`。
- [x] E2E 支持连接外部 `MBT_CDP_TARGET=127.0.0.1:9222`。
- [x] E2E 支持自动启动 Chrome；当前实现传入 `--remote-debugging-port=0`，并通过 `DevToolsActivePort` 发现实际端口。
- [x] 如需严格使用 `--remote-debugging-port=0`，补充 `DevToolsActivePort` 文件发现流程。
- [x] 自动启动模式必须使用独立 `user-data-dir`，避免 Chrome 136+ 默认 profile remote debugging 限制。
- [x] 增加 data URL 测试页，避免网络不稳定。
- [x] E2E case 1：连接 `/json/version`，校验 Browser、Protocol-Version、browser WebSocket URL。
- [x] E2E case 2：`Target.createTarget` 创建页面，attach flatten session。
- [x] E2E case 3：`Page.navigate` 到测试页，等待 load event，读取 `Runtime.evaluate("document.title")`。
- [x] E2E case 4：启用 DOM/Runtime/Page，查询元素文本、点击按钮、断言 DOM 变化。
- [x] E2E case 5：启用 Network，导航后收集 request/response event。
- [x] E2E case 6：`Page.captureScreenshot` 返回 base64，并验证非空。
- [x] E2E case 7：关闭 target，确认 `/json/list` 中 target 消失。
- [x] E2E 失败输出必须包含：Chrome 路径、target、version metadata、最后一个 CDP request/response/event 摘要。

## P1：远程 schema 兼容性

- [x] 增加本地 schema 与远程 `/json/protocol` 的差异报告。
- [x] 差异报告按 domain/command/event/type 分组，标明 remote-only、local-only、field changed。
- [x] 对 remote-only command/event/type 允许 raw JSON fallback，不阻断连接。
- [x] 对 local typed API 在远程不存在的 command，调用时返回明确 unsupported error。
- [x] 增加 CLI 入口，例如 `protocol version <target>`、`protocol list <target>`、`protocol diff <target>`。
- [x] 生成 `docs/CDP_PROTOCOL_STATUS.md` 或更新本文件，记录当前本地 schema 与某个 Chrome 版本的对比结果。

## P1：低层 CLI 验收入口

- [x] 增加或整理 `cdp send <target> <method> [json] [--session <id>]`，直接发送任意 CDP command。
- [x] 增加 `cdp targets <target>`，输出 `/json/list` 和 `Target.getTargets` 两类视角。
- [x] 增加 `cdp attach <target> <target-id>`，输出 flatten session id。
- [x] 增加 `cdp events <target> --method Page.loadEventFired --timeout 5000`，用于手动验证 event stream。
- [x] 增加 `cdp schema <target>`，输出远程 `/json/protocol` 摘要。
- [x] CLI 输出默认 JSON，便于下游 E2E 工具消费。

## P2：协议层文档和维护流程

- [x] 写 `docs/CDP_PROTOCOL.md`，说明协议包公开 API、raw/typed 两种使用方式、browser/page/session target 模型。
- [x] 写 schema 更新流程：下载/替换 JSON、运行生成器、运行 `moon fmt && moon check && moon test protocol && moon info`、review `.mbti`。
- [x] 增加生成器变更 review checklist：排序稳定、命名稳定、nullable/optional/ref/array/enum/object 处理、deprecated/experimental 保留。
- [x] 增加兼容性策略：本地 schema 追随 bundled version，远程 schema 用 diff 报告，不强行阻断 raw CDP。
- [x] 增加 E2E troubleshooting：端口占用、Chrome 未启动、默认 profile remote debugging 被拒、IPv4/IPv6 localhost、证书/代理。

## MoonBit 和依赖约束

- 优先使用 `moonbitlang/core`、`moonbitlang/x`、`moonbitlang/async`。
- 新增依赖前必须先查 Mooncakes；如果已有稳定包，优先使用；没有再写子包。
- 生成器当前是 Node 脚本，短期可以保留为开发工具；协议 runtime 和公开 API 必须在 MoonBit 包内。
- 不新增通用大型框架；只为 CDP schema、WebSocket/HTTP discovery、E2E harness 引入必要代码。

## 每个功能完成后的 review 清单

- [x] 是否只是完成当前功能，没有顺手重构无关 CLI 或高层 agent-browser 功能。
- [x] 是否保留 raw CDP escape hatch，没有为了“强类型”牺牲完整协议覆盖。
- [x] 是否有针对 schema 边界的测试：optional、array、ref、enum、object、any/raw JSON。
- [x] 是否有针对远程端口的失败测试：HTTP 状态码、缺字段、无 page target、WebSocket 关闭。
- [x] 是否在真实 Chrome E2E 中至少覆盖一个 browser-level command 和一个 session-level page command。
- [x] 是否运行 `moon fmt`、`moon check`、相关 `moon test`；公开 API 变化后运行 `moon info` 并 review `.mbti`。
- [x] 文档是否更新了当前完成状态和剩余限制。

## 建议执行顺序

1. 先补协议覆盖报告和生成器自检，确保“完整覆盖”有可量化依据。
2. 再补远程端口 discovery API，打通 `/json/version`、`/json/list`、`/json/protocol`。
3. 然后审计 WebSocket runtime 的 response/event/session dispatch。
4. 接着加可跳过的真实 Chrome E2E harness，形成回归测试闭环。
5. 最后补低层 `cdp` CLI 入口和协议文档。

## 当前决策

- `send_command` 是完整 CDP 覆盖的底线能力。
- generated typed builders/decoders 是主要开发体验，不把 664 个 command 全部手写成 `CdpClient` 方法。
- E2E 先以 Chrome/Chromium 本地或远程调试端口为准，不先抽象 provider。
- daemon/session UX 以后再接入 CDP core；当前先让无 daemon 的协议层足够可靠。
