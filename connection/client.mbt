///|
pub struct CdpClient {
  priv ws : @websocket.Conn
  priv mut next_id : Int
  priv mut next_event_handler_id : Int
  priv pending_responses : Map[Int, @protocol.CdpResponseMessage]
  priv command_contexts : Map[Int, CdpCommandContext]
  priv mut last_command_failure : CdpCommandFailure?
  priv cdp_events : Array[@protocol.CdpEventMessage]
  priv cdp_event_handlers : Array[CdpEventHandler]
  priv mut last_cdp_request : @protocol.CdpCommandMessage?
  priv mut last_cdp_response : @protocol.CdpResponseMessage?
  priv mut last_cdp_event : @protocol.CdpEventMessage?
  priv attached_targets : Map[String, CdpAttachedTarget]
}

///|
struct CdpCommandContext {
  method_name : String
  session_id : String?
}

///|
struct CdpEventHandler {
  id : Int
  method_name : String?
  session_id : String?
  handler : (@protocol.CdpEventMessage) -> Unit
}

///|
pub(all) struct CdpCommandFailure {
  id : Int
  method_name : String
  session_id : String?
  code : Int
  message : String
  data : Json?
} derive(Eq, ToJson, Debug)

///|
pub(all) struct CdpAttachedTarget {
  session_id : String
  target_id : String
  target_type : String
  title : String
  url : String
  attached : Bool
  browser_context_id : String?
  waiting_for_debugger : Bool
} derive(Eq, ToJson, Debug)

///|
pub(all) suberror CdpConnectionError {
  ConnectionTimeout(String, Int)
  WebSocketHandshakeFailed(String, String)
} derive(Eq, ToJson, Debug)

///|
pub(all) struct CdpConnectionErrorDiagnostic {
  kind : String
  web_socket_url : String
  timeout_ms : Int?
  reason : String?
  path : String
  message : String
} derive(Eq, ToJson, Debug)

///|
pub fn CdpConnectionError::diagnostic(
  self : CdpConnectionError,
) -> CdpConnectionErrorDiagnostic {
  {
    kind: self.kind(),
    web_socket_url: self.web_socket_url(),
    timeout_ms: self.timeout_ms(),
    reason: self.reason(),
    path: self.path(),
    message: self.message(),
  }
}

///|
pub fn CdpConnectionError::kind(self : CdpConnectionError) -> String {
  match self {
    ConnectionTimeout(_, _) => "connection_timeout"
    WebSocketHandshakeFailed(_, _) => "websocket_handshake_failed"
  }
}

///|
pub fn CdpConnectionError::web_socket_url(self : CdpConnectionError) -> String {
  match self {
    ConnectionTimeout(web_socket_url, _)
    | WebSocketHandshakeFailed(web_socket_url, _) => web_socket_url
  }
}

///|
pub fn CdpConnectionError::timeout_ms(self : CdpConnectionError) -> Int? {
  match self {
    ConnectionTimeout(_, timeout_ms) => Some(timeout_ms)
    WebSocketHandshakeFailed(_, _) => None
  }
}

///|
pub fn CdpConnectionError::reason(self : CdpConnectionError) -> String? {
  match self {
    WebSocketHandshakeFailed(_, reason) => Some(reason)
    ConnectionTimeout(_, _) => None
  }
}

///|
pub fn CdpConnectionError::path(self : CdpConnectionError) -> String {
  match self {
    ConnectionTimeout(_, _) => "connection.websocket.timeout"
    WebSocketHandshakeFailed(_, _) => "connection.websocket.handshake"
  }
}

///|
pub fn CdpConnectionError::message(self : CdpConnectionError) -> String {
  match self {
    ConnectionTimeout(web_socket_url, timeout_ms) =>
      "timed out after \{timeout_ms}ms connecting to \{web_socket_url}"
    WebSocketHandshakeFailed(web_socket_url, reason) =>
      "websocket handshake failed for \{web_socket_url}: \{reason}"
  }
}

///|
pub async fn CdpClient::connect(web_socket_url : String) -> CdpClient {
  CdpClient::from_websocket(@websocket.connect(web_socket_url))
}

///|
pub async fn CdpClient::connect_with_timeout(
  web_socket_url : String,
  timeout_ms? : Int = 25000,
) -> CdpClient {
  let timeout_ms = checked_duration(timeout_ms, "timeout")
  let result : Result[@websocket.Conn?, Error] = try? @async.with_timeout_opt(
    timeout_ms,
    () => @websocket.connect(web_socket_url),
  )
  match result {
    Ok(Some(ws)) => CdpClient::from_websocket(ws)
    Ok(None) =>
      raise CdpConnectionError::ConnectionTimeout(web_socket_url, timeout_ms)
    Err(_) =>
      raise CdpConnectionError::WebSocketHandshakeFailed(
        web_socket_url, "websocket connect failed",
      )
  }
}

///|
fn CdpClient::from_websocket(ws : @websocket.Conn) -> CdpClient {
  {
    ws,
    next_id: 1,
    next_event_handler_id: 1,
    pending_responses: {},
    command_contexts: {},
    last_command_failure: None,
    cdp_events: [],
    cdp_event_handlers: [],
    last_cdp_request: None,
    last_cdp_response: None,
    last_cdp_event: None,
    attached_targets: {},
  }
}

///|
pub async fn connect_cdp_target(target : CdpTarget) -> CdpClient {
  let web_socket_url = discover_web_socket_url(target)
  CdpClient::connect(web_socket_url)
}

///|
pub async fn connect_cdp_target_with_timeout(
  target : CdpTarget,
  timeout_ms? : Int = 25000,
) -> CdpClient {
  let web_socket_url = discover_web_socket_url(target)
  CdpClient::connect_with_timeout(web_socket_url, timeout_ms~)
}

///|
pub async fn connect_cdp_browser_target(target : CdpTarget) -> CdpClient {
  let web_socket_url = discover_browser_web_socket_url(target)
  CdpClient::connect(web_socket_url)
}

///|
pub async fn connect_cdp_browser_target_with_timeout(
  target : CdpTarget,
  timeout_ms? : Int = 25000,
) -> CdpClient {
  let web_socket_url = discover_browser_web_socket_url(target)
  CdpClient::connect_with_timeout(web_socket_url, timeout_ms~)
}

///|
pub async fn connect_cdp_page_target(
  target : CdpTarget,
  target_id? : String,
  url? : String,
  title? : String,
) -> CdpClient {
  let web_socket_url = discover_page_web_socket_url(
    target,
    target_id?,
    url?,
    title?,
  )
  CdpClient::connect(web_socket_url)
}

///|
pub async fn connect_cdp_page_target_with_timeout(
  target : CdpTarget,
  target_id? : String,
  url? : String,
  title? : String,
  timeout_ms? : Int = 25000,
) -> CdpClient {
  let web_socket_url = discover_page_web_socket_url(
    target,
    target_id?,
    url?,
    title?,
  )
  CdpClient::connect_with_timeout(web_socket_url, timeout_ms~)
}

///|
pub fn CdpClient::close(self : CdpClient) -> Unit {
  self.clear_connection_state()
  self.ws.close()
}

///|
pub async fn CdpClient::send_command(
  self : CdpClient,
  method_name : String,
  params? : Json,
  session_id? : String,
) -> @protocol.CdpResponseMessage {
  let id = self.send_cdp_command(method_name, params?, session_id?)
  self.recv_cdp_response(id)
}

///|
pub async fn CdpClient::send_schema_command(
  self : CdpClient,
  method_name : String,
  params? : Json,
  session_id? : String,
  timeout_ms? : Int = 25000,
) -> @protocol.CdpResponseMessage {
  let command = @protocol.cdp_schema_command(
    id=self.next_id,
    method_name~,
    params?,
    session_id?,
  )
  self.send_cdp_message(command, timeout_ms~)
}

///|
pub async fn CdpClient::send_remote_schema_command(
  self : CdpClient,
  remote_schema : Json,
  method_name : String,
  params? : Json,
  session_id? : String,
  timeout_ms? : Int = 25000,
) -> @protocol.CdpResponseMessage {
  let command = @protocol.cdp_remote_schema_command(
    id=self.next_id,
    method_name~,
    remote_schema~,
    params?,
    session_id?,
  )
  self.send_cdp_message(command, timeout_ms~)
}

///|
pub async fn CdpClient::send_cdp_message(
  self : CdpClient,
  command : @protocol.CdpCommandMessage,
  timeout_ms? : Int = 25000,
) -> @protocol.CdpResponseMessage {
  self.send_cdp_message_no_wait(command)
  let response = self.recv_cdp_response(command.id, timeout_ms~)
  @protocol.cdp_schema_response(method_name=command.method_name, response)
}

///|
pub async fn CdpClient::send_cdp_command(
  self : CdpClient,
  method_name : String,
  params? : Json,
  session_id? : String,
) -> Int {
  let id = self.next_id
  self.next_id = self.next_id + 1
  let command = @protocol.cdp_command(id~, method_name~, params?, session_id?)
  self.last_cdp_request = Some(command)
  self.command_contexts[id] = { method_name, session_id }
  self.ws.send_text(command.stringify())
  id
}

///|
pub async fn CdpClient::recv_cdp_response(
  self : CdpClient,
  id : Int,
  timeout_ms? : Int = 25000,
) -> @protocol.CdpResponseMessage {
  let timeout_ms = checked_duration(timeout_ms, "timeout")
  match @async.with_timeout_opt(timeout_ms, () => self.recv_response(id)) {
    Some(response) => response
    None => {
      self.clear_inflight_command(id)
      self.ws.close()
      raise BrowserError::WaitTimeout("cdp response \{id}")
    }
  }
}

///|
async fn CdpClient::send_cdp_message_no_wait(
  self : CdpClient,
  command : @protocol.CdpCommandMessage,
) -> Unit {
  self.reserve_cdp_command_id(command.id)
  self.last_cdp_request = Some(command)
  self.command_contexts[command.id] = {
    method_name: command.method_name,
    session_id: command.session_id,
  }
  self.ws.send_text(command.stringify())
}

///|
fn CdpClient::reserve_cdp_command_id(
  self : CdpClient,
  id : Int,
) -> Unit raise BrowserError {
  if id <= 0 || self.command_contexts.contains(id) {
    raise InvalidField("id")
  }
  if id >= self.next_id {
    self.next_id = id + 1
  }
}

///|
async fn CdpClient::recv_response(
  self : CdpClient,
  id : Int,
) -> @protocol.CdpResponseMessage {
  match self.take_pending_response(id) {
    Some(response) => return self.finish_response(response)
    None => ()
  }
  for ;; {
    let message = self.ws.recv()
    let text = message.read_all().text()
    let incoming = @protocol.parse_cdp_incoming(@json.parse(text))
    match incoming {
      Response(response) =>
        if response.id == id {
          return self.finish_response(response)
        } else if self.command_contexts.contains(response.id) {
          self.pending_responses[response.id] = response
        }
      Event(event) => self.record_cdp_event(event)
    }
  }
}

///|
pub fn CdpClient::last_command_failure(self : CdpClient) -> CdpCommandFailure? {
  self.last_command_failure
}

///|
pub fn CdpClient::last_cdp_request(
  self : CdpClient,
) -> @protocol.CdpCommandMessage? {
  self.last_cdp_request
}

///|
pub fn CdpClient::last_cdp_response(
  self : CdpClient,
) -> @protocol.CdpResponseMessage? {
  self.last_cdp_response
}

///|
pub fn CdpClient::last_cdp_event(
  self : CdpClient,
) -> @protocol.CdpEventMessage? {
  self.last_cdp_event
}

///|
pub fn CdpClient::attached_targets(
  self : CdpClient,
) -> Array[CdpAttachedTarget] {
  let targets : Array[CdpAttachedTarget] = []
  for _, target in self.attached_targets {
    targets.push(target)
  }
  targets
}

///|
pub fn CdpClient::attached_target(
  self : CdpClient,
  session_id : String,
) -> CdpAttachedTarget? {
  self.attached_targets.get(session_id)
}

///|
pub fn CdpClient::cdp_events(
  self : CdpClient,
  method_name? : String,
  session_id? : String,
) -> Array[@protocol.CdpEventMessage] {
  self.cdp_events.filter(event => {
    cdp_event_matches(event, method_name?, session_id?)
  })
}

///|
pub fn CdpClient::clear_cdp_events(self : CdpClient) -> Unit {
  self.cdp_events.clear()
}

///|
pub fn CdpClient::on_cdp_event(
  self : CdpClient,
  method_name? : String,
  session_id? : String,
  handler : (@protocol.CdpEventMessage) -> Unit,
) -> Int {
  let id = self.next_event_handler_id
  self.next_event_handler_id = id + 1
  self.cdp_event_handlers.push({ id, method_name, session_id, handler })
  id
}

///|
pub fn CdpClient::remove_cdp_event_handler(self : CdpClient, id : Int) -> Bool {
  let kept : Array[CdpEventHandler] = []
  let mut removed = false
  for handler in self.cdp_event_handlers {
    if handler.id == id {
      removed = true
    } else {
      kept.push(handler)
    }
  }
  self.cdp_event_handlers.clear()
  for handler in kept {
    self.cdp_event_handlers.push(handler)
  }
  removed
}

///|
pub async fn CdpClient::recv_cdp_event(
  self : CdpClient,
  method_name? : String,
  session_id? : String,
) -> @protocol.CdpEventMessage {
  for event in self.cdp_events {
    if cdp_event_matches(event, method_name?, session_id?) {
      return event
    }
  }
  for ;; {
    let message = self.ws.recv()
    let text = message.read_all().text()
    let incoming = @protocol.parse_cdp_incoming(@json.parse(text))
    match incoming {
      Response(response) =>
        if self.command_contexts.contains(response.id) {
          self.pending_responses[response.id] = response
        }
      Event(event) => {
        self.record_cdp_event(event)
        if cdp_event_matches(event, method_name?, session_id?) {
          return event
        }
      }
    }
  }
}

///|
fn CdpClient::record_cdp_event(
  self : CdpClient,
  event : @protocol.CdpEventMessage,
) -> Unit {
  self.last_cdp_event = Some(event)
  match event.method_name {
    "Target.attachedToTarget" => self.record_target_attached(event.params)
    "Target.detachedFromTarget" => self.record_target_detached(event.params)
    "Inspector.detached" => self.record_inspector_detached(event)
    _ => ()
  }
  self.cdp_events.push(event)
  for handler in self.cdp_event_handlers {
    if cdp_event_matches(
        event,
        method_name?=handler.method_name,
        session_id?=handler.session_id,
      ) {
      (handler.handler)(event)
    }
  }
}

///|
fn CdpClient::record_target_attached(self : CdpClient, params : Json?) -> Unit {
  guard params is Some(Object(fields)) else { return }
  guard fields.get("targetInfo") is Some(Object(target)) else { return }
  let session_id = optional_json_string(fields, "sessionId").unwrap_or("")
  if session_id == "" {
    return
  }
  self.attached_targets[session_id] = {
    session_id,
    target_id: optional_json_string(target, "targetId").unwrap_or(""),
    target_type: optional_json_string(target, "type").unwrap_or(""),
    title: optional_json_string(target, "title").unwrap_or(""),
    url: optional_json_string(target, "url").unwrap_or(""),
    attached: optional_json_bool(target, "attached").unwrap_or(false),
    browser_context_id: optional_json_string(target, "browserContextId"),
    waiting_for_debugger: optional_json_bool(fields, "waitingForDebugger").unwrap_or(
      false,
    ),
  }
}

///|
fn CdpClient::record_target_detached(self : CdpClient, params : Json?) -> Unit {
  guard params is Some(Object(fields)) else { return }
  match optional_json_string(fields, "sessionId") {
    Some(session_id) => self.attached_targets.remove(session_id)
    None => ()
  }
}

///|
fn CdpClient::record_inspector_detached(
  self : CdpClient,
  event : @protocol.CdpEventMessage,
) -> Unit {
  match event.session_id {
    Some(session_id) => self.attached_targets.remove(session_id)
    None => ()
  }
}

///|
fn CdpClient::take_pending_response(
  self : CdpClient,
  id : Int,
) -> @protocol.CdpResponseMessage? {
  match self.pending_responses.get(id) {
    Some(response) => {
      self.pending_responses.remove(id)
      Some(response)
    }
    None => None
  }
}

///|
fn CdpClient::finish_response(
  self : CdpClient,
  response : @protocol.CdpResponseMessage,
) -> @protocol.CdpResponseMessage {
  self.last_cdp_response = Some(response)
  if response.error is Some(error) {
    let context = self.command_contexts.get(response.id)
    self.last_command_failure = Some({
      id: response.id,
      method_name: match context {
        Some(context) => context.method_name
        None => ""
      },
      session_id: match context {
        Some(context) => context.session_id
        None => response.session_id
      },
      code: error.code,
      message: error.message,
      data: error.data,
    })
  }
  self.command_contexts.remove(response.id)
  response
}

///|
fn CdpClient::clear_inflight_command(self : CdpClient, id : Int) -> Unit {
  self.command_contexts.remove(id)
  self.pending_responses.remove(id)
}

///|
fn CdpClient::clear_connection_state(self : CdpClient) -> Unit {
  self.command_contexts.clear()
  self.pending_responses.clear()
}

///|
fn cdp_event_matches(
  event : @protocol.CdpEventMessage,
  method_name? : String,
  session_id? : String,
) -> Bool {
  let method_matches = match method_name {
    Some(method_name) => event.method_name == method_name
    None => true
  }
  let session_matches = match session_id {
    Some(session_id) => event.session_id == Some(session_id)
    None => true
  }
  method_matches && session_matches
}

///|
fn optional_json_string(fields : Map[String, Json], name : String) -> String? {
  match fields.get(name) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
fn optional_json_bool(fields : Map[String, Json], name : String) -> Bool? {
  match fields.get(name) {
    Some(True) => Some(true)
    Some(False) => Some(false)
    _ => None
  }
}
