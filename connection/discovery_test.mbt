///|
test "parse cdp target accepts websocket urls" {
  guard @connection.parse_cdp_target("ws://localhost:9222/devtools/browser/id")
    is WebSocket("ws://localhost:9222/devtools/browser/id") else {
    fail("expected direct websocket target")
  }
  guard @connection.parse_cdp_target("wss://example.test/cdp")
    is WebSocket("wss://example.test/cdp") else {
    fail("expected secure websocket target")
  }
}

///|
test "parse cdp target converts debugging port to http discovery endpoint" {
  guard @connection.parse_cdp_target("9222") is Http("http://127.0.0.1:9222") else {
    fail("expected local http endpoint")
  }
  guard @connection.parse_cdp_target("localhost:9222")
    is Http("http://localhost:9222") else {
    fail("expected host port http endpoint")
  }
  guard @connection.parse_cdp_target("127.0.0.1:9222")
    is Http("http://127.0.0.1:9222") else {
    fail("expected IPv4 host port http endpoint")
  }
}

///|
test "parse cdp target accepts http discovery endpoints" {
  guard @connection.parse_cdp_target("http://localhost:9222/")
    is Http("http://localhost:9222") else {
    fail("expected http endpoint")
  }
}

///|
test "parse cdp target rejects invalid ports and unsupported values" {
  let zero : Result[@connection.CdpTarget, @connection.DiscoveryError] = try? @connection.parse_cdp_target(
    "0",
  )
  guard zero is Err(InvalidTarget(_)) else { fail("port 0 should be invalid") }
  let ftp : Result[@connection.CdpTarget, @connection.DiscoveryError] = try? @connection.parse_cdp_target(
    "ftp://localhost",
  )
  guard ftp is Err(InvalidTarget(_)) else { fail("ftp should be invalid") }
}

///|
test "extract websocket url from /json/version response" {
  let json : Json = {
    "Browser": "Chrome/144.0.0.0",
    "webSocketDebuggerUrl": "ws://127.0.0.1:9222/devtools/browser/id",
  }
  inspect(
    @connection.web_socket_url_from_version_json(json),
    content="ws://127.0.0.1:9222/devtools/browser/id",
  )
}

///|
async test "discover remote debugging version targets and protocol" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let addr = server.addr
    let paths = []
    group.spawn_bg() <| () => {
      defer server.close()
      for _ in 0..<4 {
        let (conn, _) = server.accept()
        defer conn.close()
        let request = conn.read_request()
        paths.push(request.path)
        conn.send_response(200, "OK", extra_headers={
          "Content-Type": "application/json",
        })
        match request.path {
          "/json/version" =>
            conn.write(
              (
                $|{
                $|  "Browser": "Chrome/144.0.0.0",
                $|  "Protocol-Version": "1.3",
                $|  "User-Agent": "Chrome Test",
                $|  "V8-Version": "14.4",
                $|  "WebKit-Version": "537.36",
                $|  "webSocketDebuggerUrl": "ws://localhost:\{addr.port()}/devtools/browser/browser-1"
                $|}
              ),
            )
          "/json/list" =>
            conn.write(
              (
                $|[
                $|  {
                $|    "id": "page-1",
                $|    "type": "page",
                $|    "title": "Example",
                $|    "url": "https://example.com/",
                $|    "description": "",
                $|    "devtoolsFrontendUrl": "/devtools/inspector.html?ws=localhost:\{addr.port()}/devtools/page/page-1",
                $|    "webSocketDebuggerUrl": "ws://localhost:\{addr.port()}/devtools/page/page-1"
                $|  }
                $|]
              ),
            )
          "/json/protocol" =>
            conn.write(
              (
                $|{
                $|  "version": { "major": "1", "minor": "3" },
                $|  "domains": [{ "domain": "Page", "commands": [], "events": [], "types": [] }]
                $|}
              ),
            )
          other => conn.write("{\"unexpected\":\"\{other}\"}")
        }
        conn.end_response()
      }
    }
    let http_target = @connection.parse_cdp_target("127.0.0.1:\{addr.port()}")
    let version = @connection.discover_version(http_target)
    inspect(version.browser, content="Chrome/144.0.0.0")
    inspect(version.protocol_version, content="1.3")
    inspect(
      version.web_socket_debugger_url,
      content="ws://127.0.0.1:\{addr.port()}/devtools/browser/browser-1",
    )
    let targets = @connection.discover_targets(http_target)
    inspect(targets.length(), content="1")
    inspect(targets[0].target_id, content="page-1")
    inspect(targets[0].target_type, content="page")
    guard targets[0].web_socket_debugger_url is Some(page_ws) else {
      fail("expected normalized page websocket url")
    }
    inspect(
      page_ws,
      content="ws://127.0.0.1:\{addr.port()}/devtools/page/page-1",
    )
    let selected_page_ws = @connection.discover_page_web_socket_url(
      http_target,
      target_id="page-1",
    )
    inspect(
      selected_page_ws,
      content="ws://127.0.0.1:\{addr.port()}/devtools/page/page-1",
    )
    let protocol = @connection.discover_protocol(
      WebSocket("ws://127.0.0.1:\{addr.port()}/devtools/browser/browser-1"),
    )
    assert_true(
      protocol is { "version": { "major": "1", "minor": "3", .. }, .. },
    )
    json_inspect(paths, content=[
      "/json/version", "/json/list", "/json/list", "/json/protocol",
    ])
  }
}

///|
test "select discovered targets by page defaults and filters" {
  let targets = sample_discovered_targets()
  let first_page = @connection.select_discovered_page_target(targets)
  inspect(first_page.target_id, content="page-1")
  let settings = @connection.select_discovered_page_target(
    targets,
    title="Settings",
  )
  inspect(settings.target_id, content="page-2")
  let by_url = @connection.select_discovered_page_target(
    targets,
    url="https://example.com/",
  )
  inspect(by_url.target_id, content="page-1")
  let service_worker = @connection.select_discovered_target(
    targets,
    target_type="service_worker",
  )
  inspect(service_worker.target_id, content="worker-1")
}

///|
test "select discovered target reports no match" {
  let result : Result[
    @connection.CdpDiscoveredTarget,
    @connection.DiscoveryError,
  ] = try? @connection.select_discovered_page_target(
    sample_discovered_targets(),
    target_id="missing",
  )
  guard result is Err(NoMatchingTarget("id=missing type=page")) else {
    fail("expected NoMatchingTarget")
  }
}

///|
async test "discover page websocket keeps direct page endpoint" {
  inspect(
    @connection.discover_page_web_socket_url(
      WebSocket("ws://localhost:9222/devtools/page/page-1"),
    ),
    content="ws://localhost:9222/devtools/page/page-1",
  )
}

///|
async test "discover page websocket reports target without endpoint" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let addr = server.addr
    group.spawn_bg() <| () => {
      defer server.close()
      let (conn, _) = server.accept()
      defer conn.close()
      let request = conn.read_request()
      guard request.path is "/json/list" else { fail("expected /json/list") }
      conn.send_response(200, "OK", extra_headers={
        "Content-Type": "application/json",
      })
      conn.write(
        (
          $|[
          $|  {
          $|    "id": "page-2",
          $|    "type": "page",
          $|    "title": "Settings",
          $|    "url": "chrome://settings/",
          $|    "description": ""
          $|  }
          $|]
        ),
      )
      conn.end_response()
    }
    try
      @connection.discover_page_web_socket_url(
        @connection.parse_cdp_target("127.0.0.1:\{addr.port()}"),
        title="Settings",
      )
    catch {
      @connection.DiscoveryError::MissingTargetWebSocketDebuggerUrl("page-2") =>
        ()
      _ => fail("expected MissingTargetWebSocketDebuggerUrl")
    } noraise {
      _ => fail("expected MissingTargetWebSocketDebuggerUrl")
    }
  }
}

///|
fn sample_discovered_targets() -> Array[@connection.CdpDiscoveredTarget] {
  [
    {
      target_id: "browser-1",
      target_type: "browser",
      title: "",
      url: "",
      description: "",
      devtools_frontend_url: None,
      web_socket_debugger_url: Some(
        "ws://127.0.0.1:9222/devtools/browser/browser-1",
      ),
      raw: {},
    },
    {
      target_id: "worker-1",
      target_type: "service_worker",
      title: "Worker",
      url: "https://example.com/sw.js",
      description: "",
      devtools_frontend_url: None,
      web_socket_debugger_url: Some(
        "ws://127.0.0.1:9222/devtools/page/worker-1",
      ),
      raw: {},
    },
    {
      target_id: "page-1",
      target_type: "page",
      title: "Example",
      url: "https://example.com/",
      description: "",
      devtools_frontend_url: Some(
        "/devtools/inspector.html?ws=127.0.0.1:9222/devtools/page/page-1",
      ),
      web_socket_debugger_url: Some("ws://127.0.0.1:9222/devtools/page/page-1"),
      raw: {},
    },
    {
      target_id: "page-2",
      target_type: "page",
      title: "Settings",
      url: "chrome://settings/",
      description: "",
      devtools_frontend_url: None,
      web_socket_debugger_url: None,
      raw: {},
    },
  ]
}

///|
test "build devtools frontend url from browser websocket endpoint" {
  inspect(
    @connection.devtools_frontend_url(
      "ws://127.0.0.1:9222/devtools/browser/browser-1", "target-1",
    ),
    content="http://127.0.0.1:9222/devtools/inspector.html?ws=127.0.0.1:9222/devtools/page/target-1",
  )
  inspect(
    @connection.devtools_frontend_url(
      "wss://chrome.example.test/devtools/browser/browser-1", "target-2",
    ),
    content="https://chrome.example.test/devtools/inspector.html?ws=chrome.example.test/devtools/page/target-2",
  )
}

///|
test "reject /json/version response without websocket url" {
  let result : Result[String, @connection.DiscoveryError] = try? @connection.web_socket_url_from_version_json({},
  )
  guard result is Err(MissingWebSocketDebuggerUrl) else {
    fail("expected MissingWebSocketDebuggerUrl")
  }
}

///|
test "discovery errors expose stable diagnostic paths" {
  let http = @connection.DiscoveryError::HttpStatus(404, "Not Found")
  inspect(http.kind(), content="http_status")
  inspect(http.path(), content="discovery.http")
  assert_true(http.http_status() == Some(404))
  assert_true(http.reason() == Some("Not Found"))
  json_inspect(http.diagnostic(), content={
    "kind": "http_status",
    "http_status": 404,
    "reason": "Not Found",
    "path": "discovery.http",
    "message": "remote debugging endpoint returned HTTP 404 Not Found",
  })

  let missing = @connection.DiscoveryError::MissingWebSocketDebuggerUrl
  inspect(missing.kind(), content="missing_websocket_debugger_url")
  inspect(missing.path(), content="json.version.webSocketDebuggerUrl")

  let target_missing = @connection.DiscoveryError::MissingTargetWebSocketDebuggerUrl(
    "page-2",
  )
  inspect(
    target_missing.kind(),
    content="missing_target_websocket_debugger_url",
  )
  inspect(
    target_missing.path(),
    content="json.list[page-2].webSocketDebuggerUrl",
  )
  assert_true(target_missing.target_id() == Some("page-2"))
}

///|
test "build chrome launch args from options" {
  let args = @connection.chrome_launch_args({
    ..@connection.default_launch_options(),
    browser_path: Some("chrome"),
    port: 9333,
    user_data_dir: "_build/profile",
    headless: true,
    url: Some("https://example.com"),
    timeout_ms: 1000,
  })
  json_inspect(args, content=[
    "--remote-debugging-port=9333", "--user-data-dir=_build/profile", "--no-first-run",
    "--no-default-browser-check", "--headless=new", "https://example.com",
  ])
}

///|
async test "wait for browser endpoint reads websocket debugger url" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let addr = server.addr
    let paths = []
    group.spawn_bg() <| () => {
      defer server.close()
      let (conn, _) = server.accept()
      defer conn.close()
      let request = conn.read_request()
      paths.push(request.path)
      conn.send_response(200, "OK", extra_headers={
        "Content-Type": "application/json",
      })
      conn.write(
        "{\"webSocketDebuggerUrl\":\"ws://127.0.0.1:\{addr.port()}/devtools/browser/id\"}",
      )
      conn.end_response()
    }
    let url = @connection.wait_for_browser_endpoint(
      "http://127.0.0.1:\{addr.port()}",
      timeout_ms=1000,
    )
    inspect(url, content="ws://127.0.0.1:\{addr.port()}/devtools/browser/id")
    json_inspect(paths, content=["/json/version"])
  }
}
