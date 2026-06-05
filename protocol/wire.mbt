///|
pub(all) suberror ProtocolDecodeError {
  ExpectedObject
  MissingField(String)
  InvalidField(String)
} derive(Eq, ToJson, Debug)

///|
pub(all) struct CdpCommandMessage {
  id : Int
  method_name : String
  params : Json?
  session_id : String?
} derive(Eq, ToJson, Debug)

///|
pub(all) struct CdpError {
  code : Int
  message : String
  data : Json?
} derive(Eq, ToJson, Debug)

///|
pub(all) struct CdpResponseMessage {
  id : Int
  result : Json?
  error : CdpError?
  session_id : String?
} derive(Eq, ToJson, Debug)

///|
pub(all) struct CdpEventMessage {
  method_name : String
  params : Json?
  session_id : String?
} derive(Eq, ToJson, Debug)

///|
pub(all) enum CdpIncomingMessage {
  Response(CdpResponseMessage)
  Event(CdpEventMessage)
} derive(Eq, ToJson, Debug)

///|
pub fn cdp_command(
  id~ : Int,
  method_name~ : String,
  params? : Json,
  session_id? : String,
) -> CdpCommandMessage {
  { id, method_name, params, session_id }
}

///|
pub fn CdpCommandMessage::to_wire_json(self : CdpCommandMessage) -> Json {
  let fields : Map[String, Json] = {
    "id": Json::number(self.id.to_double()),
    "method": Json::string(self.method_name),
  }
  if self.params is Some(params) {
    fields["params"] = params
  }
  if self.session_id is Some(session_id) {
    fields["sessionId"] = Json::string(session_id)
  }
  Json::object(fields)
}

///|
pub fn CdpCommandMessage::stringify(self : CdpCommandMessage) -> String {
  self.to_wire_json().stringify()
}

///|
pub fn parse_cdp_incoming(
  json : Json,
) -> CdpIncomingMessage raise ProtocolDecodeError {
  guard json is Object(fields) else {
    raise ProtocolDecodeError::ExpectedObject
  }
  match fields.get("id") {
    Some(id_json) => Response(parse_response(fields, id_json))
    None => Event(parse_event(fields))
  }
}

///|
fn parse_response(
  fields : Map[String, Json],
  id_json : Json,
) -> CdpResponseMessage raise ProtocolDecodeError {
  let id = json_int(id_json, "id")
  let result = fields.get("result")
  let error = match fields.get("error") {
    Some(error_json) => Some(parse_error(error_json))
    None => None
  }
  let session_id = optional_string(fields, "sessionId")
  { id, result, error, session_id }
}

///|
fn parse_event(
  fields : Map[String, Json],
) -> CdpEventMessage raise ProtocolDecodeError {
  let method_name = required_string(fields, "method")
  let params = fields.get("params")
  let session_id = optional_string(fields, "sessionId")
  { method_name, params, session_id }
}

///|
fn parse_error(json : Json) -> CdpError raise ProtocolDecodeError {
  guard json is Object(fields) else {
    raise ProtocolDecodeError::InvalidField("error")
  }
  let code = match fields.get("code") {
    Some(value) => json_int(value, "error.code")
    None => raise ProtocolDecodeError::MissingField("error.code")
  }
  let message = required_string(fields, "message")
  let data = fields.get("data")
  { code, message, data }
}

///|
fn required_string(
  fields : Map[String, Json],
  name : String,
) -> String raise ProtocolDecodeError {
  match fields.get(name) {
    Some(String(value)) => value
    Some(_) => raise ProtocolDecodeError::InvalidField(name)
    None => raise ProtocolDecodeError::MissingField(name)
  }
}

///|
fn optional_string(
  fields : Map[String, Json],
  name : String,
) -> String? raise ProtocolDecodeError {
  match fields.get(name) {
    Some(String(value)) => Some(value)
    Some(_) => raise ProtocolDecodeError::InvalidField(name)
    None => None
  }
}

///|
fn json_int(json : Json, name : String) -> Int raise ProtocolDecodeError {
  match json {
    Number(value, ..) => {
      let int = value.to_int()
      if int.to_double() == value {
        int
      } else {
        raise ProtocolDecodeError::InvalidField(name)
      }
    }
    _ => raise ProtocolDecodeError::InvalidField(name)
  }
}
