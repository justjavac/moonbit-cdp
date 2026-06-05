///|
pub(all) suberror DiscoveryError {
  InvalidTarget(String)
  HttpStatus(Int, String)
  MissingWebSocketDebuggerUrl
  MissingTargetWebSocketDebuggerUrl(String)
  NoMatchingTarget(String)
  InvalidVersionResponse
} derive(Eq, ToJson, Debug)

///|
pub(all) struct DiscoveryErrorDiagnostic {
  kind : String
  target : String?
  http_status : Int?
  reason : String?
  target_id : String?
  selector : String?
  path : String
  message : String
} derive(Eq, ToJson, Debug)

///|
pub fn DiscoveryError::diagnostic(
  self : DiscoveryError,
) -> DiscoveryErrorDiagnostic {
  {
    kind: self.kind(),
    target: self.target(),
    http_status: self.http_status(),
    reason: self.reason(),
    target_id: self.target_id(),
    selector: self.selector(),
    path: self.path(),
    message: self.message(),
  }
}

///|
pub fn DiscoveryError::kind(self : DiscoveryError) -> String {
  match self {
    InvalidTarget(_) => "invalid_target"
    HttpStatus(_, _) => "http_status"
    MissingWebSocketDebuggerUrl => "missing_websocket_debugger_url"
    MissingTargetWebSocketDebuggerUrl(_) =>
      "missing_target_websocket_debugger_url"
    NoMatchingTarget(_) => "no_matching_target"
    InvalidVersionResponse => "invalid_version_response"
  }
}

///|
pub fn DiscoveryError::path(self : DiscoveryError) -> String {
  match self {
    InvalidTarget(_) => "target"
    HttpStatus(_, _) => "discovery.http"
    MissingWebSocketDebuggerUrl => "json.version.webSocketDebuggerUrl"
    MissingTargetWebSocketDebuggerUrl(target_id) =>
      "json.list[\{target_id}].webSocketDebuggerUrl"
    NoMatchingTarget(_) => "json.list"
    InvalidVersionResponse => "json.version"
  }
}

///|
pub fn DiscoveryError::message(self : DiscoveryError) -> String {
  match self {
    InvalidTarget(target) => "invalid CDP target: \{target}"
    HttpStatus(code, reason) =>
      "remote debugging endpoint returned HTTP \{code} \{reason}"
    MissingWebSocketDebuggerUrl =>
      "remote debugging /json/version response is missing webSocketDebuggerUrl"
    MissingTargetWebSocketDebuggerUrl(target_id) =>
      "target \{target_id} is missing webSocketDebuggerUrl"
    NoMatchingTarget(selector) =>
      "no remote debugging target matched \{selector}"
    InvalidVersionResponse =>
      "remote debugging /json/version response has invalid shape"
  }
}

///|
pub fn DiscoveryError::target(self : DiscoveryError) -> String? {
  match self {
    InvalidTarget(target) => Some(target)
    _ => None
  }
}

///|
pub fn DiscoveryError::http_status(self : DiscoveryError) -> Int? {
  match self {
    HttpStatus(code, _) => Some(code)
    _ => None
  }
}

///|
pub fn DiscoveryError::reason(self : DiscoveryError) -> String? {
  match self {
    HttpStatus(_, reason) => Some(reason)
    _ => None
  }
}

///|
pub fn DiscoveryError::target_id(self : DiscoveryError) -> String? {
  match self {
    MissingTargetWebSocketDebuggerUrl(target_id) => Some(target_id)
    _ => None
  }
}

///|
pub fn DiscoveryError::selector(self : DiscoveryError) -> String? {
  match self {
    NoMatchingTarget(selector) => Some(selector)
    _ => None
  }
}

///|
pub(all) enum CdpTarget {
  WebSocket(String)
  Http(String)
} derive(Eq, ToJson, Debug)

///|
pub(all) struct CdpVersionInfo {
  browser : String
  protocol_version : String
  user_agent : String?
  v8_version : String?
  webkit_version : String?
  web_socket_debugger_url : String
  raw : Json
} derive(Eq, ToJson, Debug)

///|
pub(all) struct CdpDiscoveredTarget {
  target_id : String
  target_type : String
  title : String
  url : String
  description : String
  devtools_frontend_url : String?
  web_socket_debugger_url : String?
  raw : Json
} derive(Eq, ToJson, Debug)

///|
pub fn parse_cdp_target(raw : String) -> CdpTarget raise DiscoveryError {
  let target = raw.trim().to_owned()
  if target == "" {
    raise DiscoveryError::InvalidTarget(raw)
  }
  if target.has_prefix("ws://") || target.has_prefix("wss://") {
    WebSocket(target)
  } else if target.has_prefix("http://") || target.has_prefix("https://") {
    Http(strip_trailing_slash(target))
  } else if target_is_port(target) {
    Http("http://127.0.0.1:\{target}")
  } else if target_is_host_port(target) {
    Http("http://\{target}")
  } else {
    raise DiscoveryError::InvalidTarget(raw)
  }
}

///|
pub async fn discover_web_socket_url(target : CdpTarget) -> String {
  if target is WebSocket(url) {
    return url
  }
  let base_url = discovery_base_url(target)
  normalize_discovered_web_socket_url(
    base_url,
    web_socket_url_from_version_json(
      fetch_discovery_json(base_url, "/json/version"),
    ),
  )
}

///|
pub async fn discover_browser_web_socket_url(target : CdpTarget) -> String {
  discover_web_socket_url(target)
}

///|
pub async fn discover_page_web_socket_url(
  target : CdpTarget,
  target_id? : String,
  url? : String,
  title? : String,
) -> String {
  match target {
    WebSocket(web_socket_url) =>
      if target_id is None &&
        url is None &&
        title is None &&
        is_page_web_socket_url(web_socket_url) {
        return web_socket_url
      }
    _ => ()
  }
  let selected = select_discovered_page_target(
    discover_targets(target),
    target_id?,
    url?,
    title?,
  )
  match selected.web_socket_debugger_url {
    Some(web_socket_url) => web_socket_url
    None =>
      raise DiscoveryError::MissingTargetWebSocketDebuggerUrl(
        selected.target_id,
      )
  }
}

///|
pub async fn discover_version(target : CdpTarget) -> CdpVersionInfo {
  let base_url = discovery_base_url(target)
  parse_version_info(fetch_discovery_json(base_url, "/json/version"), base_url)
}

///|
pub async fn discover_targets(target : CdpTarget) -> Array[CdpDiscoveredTarget] {
  let base_url = discovery_base_url(target)
  match fetch_discovery_json(base_url, "/json/list") {
    Array(items) => items.map(item => parse_discovered_target(item, base_url))
    _ => raise DiscoveryError::InvalidTarget("/json/list")
  }
}

///|
pub fn select_discovered_page_target(
  targets : Array[CdpDiscoveredTarget],
  target_id? : String,
  url? : String,
  title? : String,
) -> CdpDiscoveredTarget raise DiscoveryError {
  select_discovered_target(
    targets,
    target_id?,
    target_type="page",
    url?,
    title?,
  )
}

///|
pub fn select_discovered_target(
  targets : Array[CdpDiscoveredTarget],
  target_id? : String,
  target_type? : String,
  url? : String,
  title? : String,
) -> CdpDiscoveredTarget raise DiscoveryError {
  for target in targets {
    if discovered_target_matches(target, target_id?, target_type?, url?, title?) {
      return target
    }
  }
  raise DiscoveryError::NoMatchingTarget(
    target_selection_description(target_id?, target_type?, url?, title?),
  )
}

///|
pub async fn discover_protocol(target : CdpTarget) -> Json {
  fetch_discovery_json(discovery_base_url(target), "/json/protocol")
}

///|
pub fn web_socket_url_from_version_json(
  json : Json,
) -> String raise DiscoveryError {
  guard json is Object(fields) else {
    raise DiscoveryError::InvalidVersionResponse
  }
  match fields.get("webSocketDebuggerUrl") {
    Some(String(url)) => url
    Some(_) => raise DiscoveryError::InvalidVersionResponse
    None => raise DiscoveryError::MissingWebSocketDebuggerUrl
  }
}

///|
fn parse_version_info(
  json : Json,
  base_url : String,
) -> CdpVersionInfo raise DiscoveryError {
  guard json is Object(fields) else {
    raise DiscoveryError::InvalidVersionResponse
  }
  let web_socket_debugger_url = normalize_discovered_web_socket_url(
    base_url,
    web_socket_url_from_version_json(json),
  )
  {
    browser: discovery_required_string(fields, "Browser"),
    protocol_version: discovery_required_string(fields, "Protocol-Version"),
    user_agent: discovery_optional_string(fields, "User-Agent"),
    v8_version: discovery_optional_string(fields, "V8-Version"),
    webkit_version: discovery_optional_string(fields, "WebKit-Version"),
    web_socket_debugger_url,
    raw: json,
  }
}

///|
fn parse_discovered_target(
  json : Json,
  base_url : String,
) -> CdpDiscoveredTarget raise DiscoveryError {
  guard json is Object(fields) else {
    raise DiscoveryError::InvalidTarget("/json/list item")
  }
  let web_socket_debugger_url = match
    discovery_optional_string(fields, "webSocketDebuggerUrl") {
    Some(url) => Some(normalize_discovered_web_socket_url(base_url, url))
    None => None
  }
  {
    target_id: discovery_required_string(fields, "id"),
    target_type: discovery_required_string(fields, "type"),
    title: discovery_optional_string(fields, "title").unwrap_or(""),
    url: discovery_optional_string(fields, "url").unwrap_or(""),
    description: discovery_optional_string(fields, "description").unwrap_or(""),
    devtools_frontend_url: discovery_optional_string(
      fields, "devtoolsFrontendUrl",
    ),
    web_socket_debugger_url,
    raw: json,
  }
}

///|
async fn fetch_discovery_json(base_url : String, path : String) -> Json {
  let url = "\{strip_trailing_slash(base_url)}\{path}"
  let (response, body) = @http.get(url)
  if response.code < 200 || response.code >= 300 {
    raise DiscoveryError::HttpStatus(response.code, response.reason)
  }
  body.json()
}

///|
fn discovery_base_url(target : CdpTarget) -> String raise DiscoveryError {
  match target {
    Http(base_url) => strip_trailing_slash(base_url)
    WebSocket(url) => {
      let (scheme, rest) = web_socket_url_rest(url)
      let authority = web_socket_authority(rest)
      let http_scheme = if scheme == "wss" { "https" } else { "http" }
      "\{http_scheme}://\{authority}"
    }
  }
}

///|
fn normalize_discovered_web_socket_url(
  base_url : String,
  web_socket_url : String,
) -> String raise DiscoveryError {
  let (_, ws_rest) = web_socket_url_rest(web_socket_url)
  let (ws_authority, ws_path) = split_authority_and_path(ws_rest)
  let base_authority = http_url_authority(base_url)
  if authority_host(base_authority) == "127.0.0.1" &&
    authority_host(ws_authority) == "localhost" {
    replace_web_socket_authority(web_socket_url, base_authority, ws_path)
  } else {
    web_socket_url
  }
}

///|
pub fn devtools_frontend_url(
  browser_web_socket_url : String,
  target_id : String,
) -> String raise DiscoveryError {
  let (scheme, rest) = web_socket_url_rest(browser_web_socket_url)
  let authority = web_socket_authority(rest)
  let frontend_scheme = if scheme == "wss" { "https" } else { "http" }
  "\{frontend_scheme}://\{authority}/devtools/inspector.html?ws=\{authority}/devtools/page/\{target_id}"
}

///|
fn web_socket_url_rest(url : String) -> (String, String) raise DiscoveryError {
  match url.strip_prefix("ws://") {
    Some(rest) => ("ws", rest.to_owned())
    None =>
      match url.strip_prefix("wss://") {
        Some(rest) => ("wss", rest.to_owned())
        None => raise DiscoveryError::InvalidTarget(url)
      }
  }
}

///|
fn web_socket_authority(rest : String) -> String raise DiscoveryError {
  let (authority, _) = split_authority_and_path(rest)
  if authority == "" {
    raise DiscoveryError::InvalidTarget(rest)
  } else {
    authority
  }
}

///|
fn split_authority_and_path(rest : String) -> (String, String) {
  match rest.find("/") {
    Some(index) => (rest[:index].to_owned(), rest[index:].to_owned())
    None => (rest, "")
  }
}

///|
fn http_url_authority(url : String) -> String raise DiscoveryError {
  let rest = match url.strip_prefix("http://") {
    Some(rest) => rest
    None =>
      match url.strip_prefix("https://") {
        Some(rest) => rest
        None => raise DiscoveryError::InvalidTarget(url)
      }
  }
  let (authority, _) = split_authority_and_path(rest.to_owned())
  if authority == "" {
    raise DiscoveryError::InvalidTarget(url)
  } else {
    authority
  }
}

///|
fn authority_host(authority : String) -> String {
  let host = if authority.has_prefix("[") {
    match authority.find("]") {
      Some(end) => authority[:end + 1].to_owned()
      None => authority
    }
  } else {
    match authority.find(":") {
      Some(index) => authority[:index].to_owned()
      None => authority
    }
  }
  host.to_lower()
}

///|
fn replace_web_socket_authority(
  url : String,
  authority : String,
  path : String,
) -> String raise DiscoveryError {
  let (scheme, _) = web_socket_url_rest(url)
  "\{scheme}://\{authority}\{path}"
}

///|
fn is_page_web_socket_url(url : String) -> Bool {
  url.contains("/devtools/page/")
}

///|
fn discovered_target_matches(
  target : CdpDiscoveredTarget,
  target_id? : String,
  target_type? : String,
  url? : String,
  title? : String,
) -> Bool {
  optional_target_field_matches(target.target_id, target_id) &&
  optional_target_field_matches(target.target_type, target_type) &&
  optional_target_field_matches(target.url, url) &&
  optional_target_field_matches(target.title, title)
}

///|
fn optional_target_field_matches(value : String, expected : String?) -> Bool {
  match expected {
    Some(expected) => value == expected
    None => true
  }
}

///|
fn target_selection_description(
  target_id? : String,
  target_type? : String,
  url? : String,
  title? : String,
) -> String {
  let parts : Array[String] = []
  if target_id is Some(target_id) {
    parts.push("id=\{target_id}")
  }
  if target_type is Some(target_type) {
    parts.push("type=\{target_type}")
  }
  if url is Some(url) {
    parts.push("url=\{url}")
  }
  if title is Some(title) {
    parts.push("title=\{title}")
  }
  if parts.length() == 0 {
    "any target"
  } else {
    parts.join(" ")
  }
}

///|
fn discovery_required_string(
  fields : Map[String, Json],
  name : String,
) -> String raise DiscoveryError {
  match fields.get(name) {
    Some(String(value)) => value
    _ => raise DiscoveryError::InvalidVersionResponse
  }
}

///|
fn discovery_optional_string(
  fields : Map[String, Json],
  name : String,
) -> String? raise DiscoveryError {
  match fields.get(name) {
    Some(String(value)) => Some(value)
    Some(Null) | None => None
    Some(_) => raise DiscoveryError::InvalidVersionResponse
  }
}

///|
fn strip_trailing_slash(value : String) -> String {
  match value.strip_suffix("/") {
    Some(stripped) => stripped.to_owned()
    None => value
  }
}

///|
fn target_is_port(value : String) -> Bool {
  if value == "" {
    return false
  }
  let mut port = 0
  for char in value {
    if !char.is_ascii_digit() {
      return false
    }
    port = port * 10 + (char.to_int() - '0'.to_int())
  }
  port > 0 && port < 65536
}

///|
fn target_is_host_port(value : String) -> Bool {
  match value.rev_find(":") {
    Some(index) if index > 0 && index + 1 < value.length() =>
      !value.contains("/") && target_is_port(value[index + 1:].to_owned())
    _ => false
  }
}
