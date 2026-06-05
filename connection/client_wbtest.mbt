///|
async test "close clears in-flight command state" {
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
      ignore(ws.recv())
      ignore(ws.recv())
      ws.send_text("{\"id\":1,\"result\":{\"ok\":true}}")
      ws.send_text("{\"id\":2,\"result\":{\"ok\":true}}")
      try ws.recv() catch {
        _ => ()
      } noraise {
        _ => ()
      }
    }
    let client = CdpClient::connect("ws://127.0.0.1:\{addr.port()}")
    let first = client.send_cdp_command("Runtime.evaluate")
    let second = client.send_cdp_command("Page.enable")
    inspect(first, content="1")
    inspect(second, content="2")
    ignore(client.recv_cdp_response(second))
    inspect(client.pending_responses.length(), content="1")
    inspect(client.command_contexts.length(), content="1")
    client.close()
    inspect(client.pending_responses.length(), content="0")
    inspect(client.command_contexts.length(), content="0")
  }
}
