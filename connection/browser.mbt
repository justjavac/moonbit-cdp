///|
pub(all) suberror BrowserError {
  CommandFailed(Int, String)
  MissingField(String)
  InvalidField(String)
  WaitTimeout(String)
} derive(Eq, ToJson, Debug)

///|
pub(all) struct CdpTargetInfo {
  target_id : String
  target_type : String
  title : String
  url : String
  attached : Bool
  browser_context_id : String?
} derive(Eq, ToJson, Debug)

///|
pub async fn CdpClient::get_targets(self : CdpClient) -> Array[CdpTargetInfo] {
  let response = self.send_schema_command("Target.getTargets")
  let result = response_result(response)
  guard required_json(result, "targetInfos") is Array(targets) else {
    raise BrowserError::InvalidField("targetInfos")
  }
  targets.map(parse_target_info)
}

///|
pub async fn CdpClient::create_target(
  self : CdpClient,
  url? : String = "about:blank",
  browser_context_id? : String,
  new_window? : Bool = false,
) -> String {
  let params : Map[String, Json] = { "url": Json::string(url) }
  if browser_context_id is Some(browser_context_id) {
    params["browserContextId"] = Json::string(browser_context_id)
  }
  if new_window {
    params["newWindow"] = Json::boolean(true)
  }
  let response = self.send_schema_command(
    "Target.createTarget",
    params=Json::object(params),
  )
  let result = response_result(response)
  required_string(result, "targetId")
}

///|
pub async fn CdpClient::attach_to_target(
  self : CdpClient,
  target_id : String,
  flatten? : Bool = true,
) -> String {
  let response = self.send_schema_command("Target.attachToTarget", params={
    "targetId": target_id,
    "flatten": flatten,
  })
  let result = response_result(response)
  required_string(result, "sessionId")
}

///|
fn parse_target_info(value : Json) -> CdpTargetInfo raise BrowserError {
  guard value is Object(fields) else {
    raise BrowserError::InvalidField("targetInfos[]")
  }
  {
    target_id: required_string(fields, "targetId"),
    target_type: required_string(fields, "type"),
    title: required_string(fields, "title"),
    url: required_string(fields, "url"),
    attached: optional_bool(fields, "attached").unwrap_or(false),
    browser_context_id: optional_string(fields, "browserContextId"),
  }
}

///|
fn response_result(
  response : @protocol.CdpResponseMessage,
) -> Map[String, Json] raise BrowserError {
  if response.error is Some(err) {
    raise BrowserError::CommandFailed(err.code, err.message)
  }
  match response.result {
    Some(Object(result)) => result
    Some(_) => raise BrowserError::InvalidField("result")
    None => raise BrowserError::MissingField("result")
  }
}

///|
pub fn cdp_response_result_json(
  response : @protocol.CdpResponseMessage,
) -> Json raise BrowserError {
  if response.error is Some(err) {
    raise CommandFailed(err.code, err.message)
  }
  match response.result {
    Some(result) => result
    None => Json::object({})
  }
}

///|
fn required_json(
  fields : Map[String, Json],
  name : String,
) -> Json raise BrowserError {
  match fields.get(name) {
    Some(value) => value
    None => raise BrowserError::MissingField(name)
  }
}

///|
fn required_string(
  fields : Map[String, Json],
  name : String,
) -> String raise BrowserError {
  match fields.get(name) {
    Some(String(value)) => value
    Some(_) => raise BrowserError::InvalidField(name)
    None => raise BrowserError::MissingField(name)
  }
}

///|
fn optional_string(
  fields : Map[String, Json],
  name : String,
) -> String? raise BrowserError {
  match fields.get(name) {
    Some(String(value)) => Some(value)
    Some(_) => raise BrowserError::InvalidField(name)
    None => None
  }
}

///|
fn optional_bool(
  fields : Map[String, Json],
  name : String,
) -> Bool? raise BrowserError {
  match fields.get(name) {
    Some(True) => Some(true)
    Some(False) => Some(false)
    Some(_) => raise BrowserError::InvalidField(name)
    None => None
  }
}

///|
fn checked_duration(value : Int, name : String) -> Int raise BrowserError {
  if value > 0 {
    value
  } else {
    raise BrowserError::InvalidField(name)
  }
}
