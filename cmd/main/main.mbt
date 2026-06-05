///|
async fn main {
  let args = @env.args()
  let argv = if args.length() > 1 { args[1:].to_owned() } else { [] }
  let output = try {
    let command = @cli.parse_cli(argv)
    render_command(command)
  } catch {
    err => "error: \{err}"
  }
  println(output)
}

///|
async fn render_command(command : @cli.CliCommand) -> String {
  match command {
    Version => @cli.render_command(command)
    Connect(target) => {
      let cdp_target = @connection.parse_cdp_target(target)
      let ws_url = @connection.discover_web_socket_url(cdp_target)
      ({ "webSocketDebuggerUrl": ws_url } : Json).stringify()
    }
    CdpSend(target, method_name, params_json, session_id) =>
      cdp_send_result(target, method_name, params_json, session_id).stringify()
    CdpTargets(target) => cdp_targets_result(target).stringify()
    CdpAttach(target, target_id) =>
      cdp_attach_result(target, target_id).stringify()
    CdpEvents(target, options) => cdp_events_result(target, options).stringify()
    CdpSchema(target) => {
      let cdp_target = @connection.parse_cdp_target(target)
      @connection.discover_protocol(cdp_target).stringify()
    }
  }
}

///|
async fn connect_client(target : String) -> @connection.CdpClient {
  let cdp_target = @connection.parse_cdp_target(target)
  @connection.connect_cdp_browser_target(cdp_target)
}

///|
async fn cdp_send_result(
  target : String,
  method_name : String,
  params_json : String?,
  session_id : String?,
) -> Json {
  let client = connect_client(target)
  defer client.close()
  let response = match params_json {
    Some(raw) => {
      let params = @json.parse(raw)
      client.send_command(method_name, params~, session_id?)
    }
    None => client.send_command(method_name, session_id?)
  }
  response.to_json()
}

///|
async fn cdp_targets_result(target : String) -> Json {
  let cdp_target = @connection.parse_cdp_target(target)
  let discovery_targets = @connection.discover_targets(cdp_target)
  let client = @connection.connect_cdp_browser_target(cdp_target)
  defer client.close()
  { "discovery": discovery_targets, "targetGetTargets": client.get_targets() }
}

///|
async fn cdp_attach_result(target : String, target_id : String) -> Json {
  let client = connect_client(target)
  defer client.close()
  let session_id = client.attach_to_target(target_id, flatten=true)
  { "targetId": target_id, "sessionId": session_id }
}

///|
async fn cdp_events_result(
  target : String,
  options : @cli.CdpEventsOptions,
) -> Json {
  let client = connect_client(target)
  defer client.close()
  match
    @async.with_timeout_opt(options.timeout_ms, () => {
      client.recv_cdp_event(
        method_name?=options.method_name,
        session_id?=options.session_id,
      )
    }) {
    Some(event) => { "timedOut": false, "event": event }
    None => cdp_event_timeout_json(options)
  }
}

///|
fn cdp_event_timeout_json(options : @cli.CdpEventsOptions) -> Json {
  let result : Map[String, Json] = {
    "timedOut": Json::boolean(true),
    "timeoutMs": Json::number(options.timeout_ms.to_double()),
  }
  if options.method_name is Some(method_name) {
    result["method"] = Json::string(method_name)
  }
  if options.session_id is Some(session_id) {
    result["sessionId"] = Json::string(session_id)
  }
  Json::object(result)
}
