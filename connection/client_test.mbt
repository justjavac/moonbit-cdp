///|
async test "cdp client sends command and waits for matching response" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let addr = server.addr
    group.spawn_bg() <| () => {
      defer server.close()
      let (conn, _) = server.accept()
      defer conn.close()
      let request = conn.read_request()
      let ws = @websocket.from_http_server(request, conn)
      defer ws.close()
      let text = ws.recv().read_all().text()
      assert_true(text.contains("\"method\":\"Runtime.evaluate\""))
      assert_true(text.contains("\"id\":1"))
      ws.send_text(
        "{\"method\":\"Runtime.executionContextCreated\",\"params\":{}}",
      )
      ws.send_text("{\"id\":1,\"result\":{\"ok\":true}}")
    }
    let client = @connection.CdpClient::connect("ws://localhost:\{addr.port()}")
    defer client.close()
    let response = client.send_command("Runtime.evaluate", params={
      "expression": "1+1",
    })
    inspect(response.id, content="1")
    guard client.last_cdp_request() is Some(request) else {
      fail("expected last CDP request")
    }
    inspect(request.method_name, content="Runtime.evaluate")
    guard client.last_cdp_response() is Some(last_response) else {
      fail("expected last CDP response")
    }
    inspect(last_response.id, content="1")
    guard client.last_cdp_event() is Some(event) else {
      fail("expected last CDP event")
    }
    inspect(event.method_name, content="Runtime.executionContextCreated")
    guard response.result is Some({ "ok": true, .. }) else {
      fail("expected result")
    }
  }
}

///|
async test "cdp client sends generated command messages and decodes typed results" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let addr = server.addr
    group.spawn_bg() <| () => {
      defer server.close()
      let (conn, _) = server.accept()
      defer conn.close()
      let request = conn.read_request()
      let ws = @websocket.from_http_server(request, conn)
      defer ws.close()
      let first = ws.recv().read_all().text()
      assert_true(first.contains("\"id\":7"))
      assert_true(first.contains("\"method\":\"Runtime.evaluate\""))
      assert_true(first.contains("\"sessionId\":\"session-1\""))
      ws.send_text(
        "{\"id\":7,\"result\":{\"result\":{\"type\":\"number\",\"value\":2},\"exceptionDetails\":null},\"sessionId\":\"session-1\"}",
      )
      let second = ws.recv().read_all().text()
      assert_true(second.contains("\"id\":8"))
      assert_true(second.contains("\"method\":\"Runtime.enable\""))
      ws.send_text("{\"id\":8,\"result\":{}}")
    }
    let client = @connection.CdpClient::connect("ws://localhost:\{addr.port()}")
    defer client.close()
    let params : @protocol.RuntimeEvaluateParams = {
      expression: "1 + 1",
      object_group: None,
      include_command_line_api: None,
      silent: None,
      context_id: None,
      return_by_value: Some(true),
      generate_preview: None,
      user_gesture: None,
      await_promise: None,
      throw_on_side_effect: None,
      timeout: None,
      disable_breaks: None,
      repl_mode: None,
      allow_unsafe_eval_blocked_by_csp: None,
      unique_context_id: None,
      serialization_options: None,
    }
    let command = @protocol.runtime_evaluate_command(
      id=7,
      params,
      session_id="session-1",
    )
    let response = client.send_cdp_message(command)
    let result = @protocol.RuntimeEvaluateResult::from_json(
      @connection.cdp_response_result_json(response),
    )
    inspect(result.result.type_, content="number")
    let next = client.send_command("Runtime.enable")
    inspect(next.id, content="8")
  }
}

///|
async test "cdp client sends schema commands and validates schema responses" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let addr = server.addr
    group.spawn_bg() <| () => {
      defer server.close()
      let (conn, _) = server.accept()
      defer conn.close()
      let request = conn.read_request()
      let ws = @websocket.from_http_server(request, conn)
      defer ws.close()
      let first = ws.recv().read_all().text()
      assert_true(first.contains("\"id\":1"))
      assert_true(first.contains("\"method\":\"Page.navigate\""))
      ws.send_text(
        "{\"id\":1,\"result\":{\"frameId\":\"frame-1\",\"loaderId\":null,\"isDownload\":false},\"sessionId\":\"session-1\"}",
      )
      let second = ws.recv().read_all().text()
      assert_true(second.contains("\"id\":2"))
      assert_true(second.contains("\"method\":\"Page.navigate\""))
      ws.send_text("{\"id\":2,\"result\":{},\"sessionId\":\"session-1\"}")
    }
    let client = @connection.CdpClient::connect("ws://localhost:\{addr.port()}")
    defer client.close()
    let response = client.send_schema_command(
      "Page.navigate",
      params={ "url": "https://example.com/" },
      session_id="session-1",
    )
    let result = @protocol.PageNavigateResult::from_json(
      @connection.cdp_response_result_json(response),
    )
    inspect(result.frame_id.value, content="frame-1")
    let invalid : Result[@protocol.CdpResponseMessage, Error] = try? client.send_schema_command(
      "Page.navigate",
      params={ "url": "https://example.com/" },
      session_id="session-1",
    )
    guard invalid
      is Err(
        @protocol.ProtocolSchemaError::MissingReturn("Page.navigate", "frameId")
      ) else {
      fail("expected missing frameId")
    }
  }
}

///|
async test "cdp client exposes raw event buffer subscriptions and drain" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let addr = server.addr
    group.spawn_bg() <| () => {
      defer server.close()
      let (conn, _) = server.accept()
      defer conn.close()
      let request = conn.read_request()
      let ws = @websocket.from_http_server(request, conn)
      defer ws.close()
      ws.send_text(
        "{\"method\":\"Runtime.consoleAPICalled\",\"sessionId\":\"session-1\",\"params\":{\"type\":\"log\",\"args\":[{\"type\":\"string\",\"value\":\"hello\"}]}}",
      )
      ws.send_text(
        "{\"method\":\"Page.loadEventFired\",\"sessionId\":\"session-2\",\"params\":{\"timestamp\":1}}",
      )
    }
    let client = @connection.CdpClient::connect("ws://localhost:\{addr.port()}")
    defer client.close()
    let seen : Array[String] = []
    let handler_id = client.on_cdp_event(
      method_name="Runtime.consoleAPICalled",
      session_id="session-1",
      fn(event) { seen.push(event.method_name) },
    )
    let event = client.recv_cdp_event(
      method_name="Runtime.consoleAPICalled",
      session_id="session-1",
    )
    inspect(event.method_name, content="Runtime.consoleAPICalled")
    json_inspect(seen, content=["Runtime.consoleAPICalled"])
    assert_true(client.remove_cdp_event_handler(handler_id))
    let load = client.recv_cdp_event(method_name="Page.loadEventFired")
    assert_true(load.session_id == Some("session-2"))
    client.clear_cdp_events()
    inspect(client.cdp_events().length(), content="0")
  }
}

///|
async test "cdp client tracks target attached and detached events" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let addr = server.addr
    group.spawn_bg() <| () => {
      defer server.close()
      let (conn, _) = server.accept()
      defer conn.close()
      let request = conn.read_request()
      let ws = @websocket.from_http_server(request, conn)
      defer ws.close()
      ignore(ws.recv().read_all())
      ws.send_text(
        "{\"method\":\"Target.attachedToTarget\",\"params\":{\"sessionId\":\"session-1\",\"targetInfo\":{\"targetId\":\"target-1\",\"type\":\"page\",\"title\":\"Example\",\"url\":\"https://example.com/\",\"attached\":true,\"browserContextId\":\"context-1\"},\"waitingForDebugger\":true}}",
      )
      ws.send_text("{\"id\":1,\"result\":{\"sessionId\":\"session-1\"}}")
      ignore(ws.recv().read_all())
      ws.send_text(
        "{\"method\":\"Target.detachedFromTarget\",\"params\":{\"sessionId\":\"session-1\",\"targetId\":\"target-1\"}}",
      )
      ws.send_text("{\"id\":2,\"result\":{}}")
    }
    let client = @connection.CdpClient::connect("ws://localhost:\{addr.port()}")
    defer client.close()
    let session_id = client.attach_to_target("target-1")
    inspect(session_id, content="session-1")
    guard client.attached_target("session-1") is Some(attached) else {
      fail("expected attached target")
    }
    inspect(attached.target_id, content="target-1")
    ignore(client.send_command("Runtime.enable", session_id="session-1"))
    assert_true(client.attached_target("session-1") is None)
  }
}
