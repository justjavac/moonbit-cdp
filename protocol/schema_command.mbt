///|
pub(all) suberror ProtocolSchemaError {
  UnknownCommand(String)
  UnsupportedRemoteCommand(String)
  UnknownEvent(String)
  ExpectedParamsObject(String)
  MissingParameter(String, String)
  UnknownParameter(String, String)
  InvalidParameterType(String, String, String)
  ExpectedResultObject(String)
  MissingReturn(String, String)
  UnknownReturn(String, String)
  InvalidReturnType(String, String, String)
} derive(Eq, ToJson, Debug)

///|
pub(all) struct ProtocolSchemaErrorDiagnostic {
  kind : String
  method_name : String?
  field_name : String?
  path : String
  expected_type : String?
} derive(Eq, ToJson, Debug)

///|
pub fn ProtocolSchemaError::diagnostic(
  self : ProtocolSchemaError,
) -> ProtocolSchemaErrorDiagnostic {
  {
    kind: self.kind(),
    method_name: self.method_name(),
    field_name: self.field_name(),
    path: self.path(),
    expected_type: self.expected_type(),
  }
}

///|
pub fn ProtocolSchemaError::kind(self : ProtocolSchemaError) -> String {
  match self {
    UnknownCommand(_) => "unknown_command"
    UnsupportedRemoteCommand(_) => "unsupported_remote_command"
    UnknownEvent(_) => "unknown_event"
    ExpectedParamsObject(_) => "expected_params_object"
    MissingParameter(_, _) => "missing_parameter"
    UnknownParameter(_, _) => "unknown_parameter"
    InvalidParameterType(_, _, _) => "invalid_parameter_type"
    ExpectedResultObject(_) => "expected_result_object"
    MissingReturn(_, _) => "missing_return"
    UnknownReturn(_, _) => "unknown_return"
    InvalidReturnType(_, _, _) => "invalid_return_type"
  }
}

///|
pub fn ProtocolSchemaError::method_name(self : ProtocolSchemaError) -> String? {
  match self {
    UnknownCommand(method_name)
    | UnsupportedRemoteCommand(method_name)
    | UnknownEvent(method_name)
    | ExpectedParamsObject(method_name)
    | MissingParameter(method_name, _)
    | UnknownParameter(method_name, _)
    | InvalidParameterType(method_name, _, _)
    | ExpectedResultObject(method_name)
    | MissingReturn(method_name, _)
    | UnknownReturn(method_name, _)
    | InvalidReturnType(method_name, _, _) => Some(method_name)
  }
}

///|
pub fn ProtocolSchemaError::field_name(self : ProtocolSchemaError) -> String? {
  match self {
    MissingParameter(_, field_name)
    | UnknownParameter(_, field_name)
    | InvalidParameterType(_, field_name, _)
    | MissingReturn(_, field_name)
    | UnknownReturn(_, field_name)
    | InvalidReturnType(_, field_name, _) => Some(field_name)
    UnknownCommand(_)
    | UnsupportedRemoteCommand(_)
    | UnknownEvent(_)
    | ExpectedParamsObject(_)
    | ExpectedResultObject(_) => None
  }
}

///|
pub fn ProtocolSchemaError::path(self : ProtocolSchemaError) -> String {
  match self {
    UnknownCommand(method_name)
    | UnsupportedRemoteCommand(method_name)
    | UnknownEvent(method_name) => method_name
    ExpectedParamsObject(method_name) => "\{method_name}.params"
    MissingParameter(method_name, field_name)
    | UnknownParameter(method_name, field_name)
    | InvalidParameterType(method_name, field_name, _) =>
      "\{method_name}.params.\{field_name}"
    ExpectedResultObject(method_name) => "\{method_name}.result"
    MissingReturn(method_name, field_name)
    | UnknownReturn(method_name, field_name)
    | InvalidReturnType(method_name, field_name, _) =>
      "\{method_name}.result.\{field_name}"
  }
}

///|
pub fn ProtocolSchemaError::expected_type(
  self : ProtocolSchemaError,
) -> String? {
  match self {
    InvalidParameterType(_, _, expected) | InvalidReturnType(_, _, expected) =>
      Some(expected)
    UnknownCommand(_)
    | UnsupportedRemoteCommand(_)
    | UnknownEvent(_)
    | ExpectedParamsObject(_)
    | MissingParameter(_, _)
    | UnknownParameter(_, _)
    | ExpectedResultObject(_)
    | MissingReturn(_, _)
    | UnknownReturn(_, _) => None
  }
}

///|
pub(all) struct ProtocolCoverage {
  domain_count : Int
  command_count : Int
  event_count : Int
  type_count : Int
  command_registry_count : Int
  event_registry_count : Int
  type_registry_count : Int
  complete : Bool
} derive(Eq, ToJson, Debug)

///|
pub(all) struct ProtocolCoverageReport {
  domain_count : Int
  source_count : Int
  command_count : Int
  command_registry_count : Int
  command_registry_missing_count : Int
  event_count : Int
  event_registry_count : Int
  event_registry_missing_count : Int
  type_count : Int
  type_registry_count : Int
  type_registry_missing_count : Int
  command_with_params_count : Int
  typed_command_params_count : Int
  typed_command_params_missing_count : Int
  command_with_returns_count : Int
  typed_command_result_count : Int
  typed_command_result_missing_count : Int
  typed_command_result_decoder_count : Int
  typed_command_result_decoder_missing_count : Int
  event_with_params_count : Int
  typed_event_params_count : Int
  typed_event_params_missing_count : Int
  typed_event_decoder_count : Int
  typed_event_decoder_missing_count : Int
  typed_command_builder_count : Int
  typed_command_builder_missing_count : Int
  typed_event_builder_count : Int
  typed_event_builder_missing_count : Int
  typed_domain_type_count : Int
  typed_domain_type_missing_count : Int
  complete : Bool
} derive(Eq, ToJson, Debug)

///|
pub fn protocol_coverage() -> ProtocolCoverage {
  let manifest = protocol_manifest()
  let command_count = manifest.command_count()
  let event_count = manifest.event_count()
  let type_count = manifest.type_count()
  let command_registry_count = protocol_commands().length()
  let event_registry_count = protocol_events().length()
  let type_registry_count = protocol_types().length()
  {
    domain_count: manifest.domain_count(),
    command_count,
    event_count,
    type_count,
    command_registry_count,
    event_registry_count,
    type_registry_count,
    complete: command_count == command_registry_count &&
    event_count == event_registry_count &&
    type_count == type_registry_count,
  }
}

///|
pub fn protocol_coverage_report() -> ProtocolCoverageReport {
  let manifest = protocol_manifest()
  let command_count = manifest.command_count()
  let event_count = manifest.event_count()
  let type_count = manifest.type_count()
  let command_registry_count = protocol_commands().length()
  let event_registry_count = protocol_events().length()
  let type_registry_count = protocol_types().length()
  let command_with_params_count = protocol_commands()
    .filter(command => command.parameter_count > 0)
    .length()
  let command_with_returns_count = protocol_commands()
    .filter(command => command.return_count > 0)
    .length()
  let event_with_params_count = protocol_events()
    .filter(event => event.parameter_count > 0)
    .length()
  let typed_command_builder_count = protocol_typed_command_builder_count()
  let typed_command_params_count = protocol_typed_command_params_count()
  let typed_command_result_count = protocol_typed_command_result_count()
  let typed_command_result_decoder_count = protocol_typed_command_result_decoder_count()
  let typed_event_builder_count = protocol_typed_event_builder_count()
  let typed_event_params_count = protocol_typed_event_params_count()
  let typed_event_decoder_count = protocol_typed_event_decoder_count()
  let typed_domain_type_count = protocol_typed_domain_type_count()
  let command_registry_missing_count = missing_count(
    command_count, command_registry_count,
  )
  let event_registry_missing_count = missing_count(
    event_count, event_registry_count,
  )
  let type_registry_missing_count = missing_count(
    type_count, type_registry_count,
  )
  let typed_command_builder_missing_count = missing_count(
    command_count, typed_command_builder_count,
  )
  let typed_command_params_missing_count = missing_count(
    command_with_params_count, typed_command_params_count,
  )
  let typed_command_result_missing_count = missing_count(
    command_with_returns_count, typed_command_result_count,
  )
  let typed_command_result_decoder_missing_count = missing_count(
    command_with_returns_count, typed_command_result_decoder_count,
  )
  let typed_event_builder_missing_count = missing_count(
    event_count, typed_event_builder_count,
  )
  let typed_event_params_missing_count = missing_count(
    event_with_params_count, typed_event_params_count,
  )
  let typed_event_decoder_missing_count = missing_count(
    event_with_params_count, typed_event_decoder_count,
  )
  let typed_domain_type_missing_count = missing_count(
    type_count, typed_domain_type_count,
  )
  {
    domain_count: manifest.domain_count(),
    source_count: manifest.sources.length(),
    command_count,
    command_registry_count,
    command_registry_missing_count,
    event_count,
    event_registry_count,
    event_registry_missing_count,
    type_count,
    type_registry_count,
    type_registry_missing_count,
    command_with_params_count,
    typed_command_params_count,
    typed_command_params_missing_count,
    command_with_returns_count,
    typed_command_result_count,
    typed_command_result_missing_count,
    typed_command_result_decoder_count,
    typed_command_result_decoder_missing_count,
    event_with_params_count,
    typed_event_params_count,
    typed_event_params_missing_count,
    typed_event_decoder_count,
    typed_event_decoder_missing_count,
    typed_command_builder_count,
    typed_command_builder_missing_count,
    typed_event_builder_count,
    typed_event_builder_missing_count,
    typed_domain_type_count,
    typed_domain_type_missing_count,
    complete: command_registry_missing_count == 0 &&
    event_registry_missing_count == 0 &&
    type_registry_missing_count == 0 &&
    typed_command_builder_missing_count == 0 &&
    typed_command_params_missing_count == 0 &&
    typed_command_result_missing_count == 0 &&
    typed_command_result_decoder_missing_count == 0 &&
    typed_event_builder_missing_count == 0 &&
    typed_event_params_missing_count == 0 &&
    typed_event_decoder_missing_count == 0 &&
    typed_domain_type_missing_count == 0,
  }
}

///|
fn missing_count(expected : Int, actual : Int) -> Int {
  if actual >= expected {
    0
  } else {
    expected - actual
  }
}

///|
pub fn cdp_schema_command(
  id~ : Int,
  method_name~ : String,
  params? : Json,
  session_id? : String,
) -> CdpCommandMessage raise ProtocolSchemaError {
  match protocol_command(method_name) {
    Some(command) => command.build_command(id~, params?, session_id?)
    None => raise ProtocolSchemaError::UnknownCommand(method_name)
  }
}

///|
pub fn cdp_remote_schema_command(
  id~ : Int,
  method_name~ : String,
  remote_schema~ : Json,
  params? : Json,
  session_id? : String,
) -> CdpCommandMessage raise ProtocolSchemaError {
  let command = cdp_schema_command(id~, method_name~, params?, session_id?)
  if protocol_remote_has_command(remote_schema, method_name) {
    command
  } else {
    raise ProtocolSchemaError::UnsupportedRemoteCommand(method_name)
  }
}

///|
pub fn protocol_remote_has_command(
  remote_schema : Json,
  method_name : String,
) -> Bool {
  let (domain_name, command_name) = split_cdp_method(method_name)
  match remote_schema {
    Object(schema_fields) =>
      match schema_fields.get("domains") {
        Some(Array(domains)) =>
          domains.any(domain => {
            match domain {
              Object(domain_fields) =>
                match domain_fields.get("domain") {
                  Some(String(name)) if name == domain_name =>
                    remote_domain_has_command(domain_fields, command_name)
                  _ => false
                }
              _ => false
            }
          })
        _ => false
      }
    _ => false
  }
}

///|
pub fn cdp_schema_event(
  method_name~ : String,
  params? : Json,
  session_id? : String,
) -> CdpEventMessage raise ProtocolSchemaError {
  match protocol_event(method_name) {
    Some(event) => event.build_event(params?, session_id?)
    None => raise ProtocolSchemaError::UnknownEvent(method_name)
  }
}

///|
fn remote_domain_has_command(
  domain_fields : Map[String, Json],
  command_name : String,
) -> Bool {
  match domain_fields.get("commands") {
    Some(Array(commands)) =>
      commands.any(command => {
        match command {
          Object(command_fields) =>
            match command_fields.get("name") {
              Some(String(name)) => name == command_name
              _ => false
            }
          _ => false
        }
      })
    _ => false
  }
}

///|
fn split_cdp_method(method_name : String) -> (String, String) {
  match method_name.find(".") {
    Some(index) =>
      (method_name[:index].to_owned(), method_name[index + 1:].to_owned())
    None => ("", method_name)
  }
}

///|
pub fn ProtocolCommand::build_command(
  self : ProtocolCommand,
  id~ : Int,
  params? : Json,
  session_id? : String,
) -> CdpCommandMessage raise ProtocolSchemaError {
  self.validate_params(params?)
  cdp_command(id~, method_name=self.cdp_method, params?, session_id?)
}

///|
pub fn cdp_schema_response(
  method_name~ : String,
  response : CdpResponseMessage,
) -> CdpResponseMessage raise ProtocolSchemaError {
  match protocol_command(method_name) {
    Some(command) => {
      command.validate_response(response)
      response
    }
    None => raise ProtocolSchemaError::UnknownCommand(method_name)
  }
}

///|
pub fn ProtocolCommand::validate_response(
  self : ProtocolCommand,
  response : CdpResponseMessage,
) -> Unit raise ProtocolSchemaError {
  if response.error is Some(_) {
    return
  }
  validate_protocol_result(
    self.cdp_method,
    self.domain,
    self.returns,
    response.result,
  )
}

///|
pub fn ProtocolEvent::build_event(
  self : ProtocolEvent,
  params? : Json,
  session_id? : String,
) -> CdpEventMessage raise ProtocolSchemaError {
  validate_protocol_params(
    self.cdp_method,
    self.domain,
    self.parameters,
    params?,
  )
  { method_name: self.cdp_method, params, session_id }
}

///|
pub fn ProtocolCommand::required_parameters(
  self : ProtocolCommand,
) -> Array[String] {
  self.parameters
  .filter(item => !protocol_item_optional(item))
  .map(protocol_item_name)
}

///|
pub fn ProtocolCommand::required_returns(
  self : ProtocolCommand,
) -> Array[String] {
  self.returns
  .filter(item => !protocol_item_optional(item))
  .map(protocol_item_name)
}

///|
pub fn ProtocolEvent::required_parameters(
  self : ProtocolEvent,
) -> Array[String] {
  self.parameters
  .filter(item => !protocol_item_optional(item))
  .map(protocol_item_name)
}

///|
pub fn ProtocolCommand::parameter_names(
  self : ProtocolCommand,
) -> Array[String] {
  self.parameters.map(protocol_item_name)
}

///|
pub fn ProtocolCommand::return_names(self : ProtocolCommand) -> Array[String] {
  self.returns.map(protocol_item_name)
}

///|
pub fn ProtocolEvent::parameter_names(self : ProtocolEvent) -> Array[String] {
  self.parameters.map(protocol_item_name)
}

///|
fn ProtocolCommand::validate_params(
  self : ProtocolCommand,
  params? : Json,
) -> Unit raise ProtocolSchemaError {
  validate_protocol_params(
    self.cdp_method,
    self.domain,
    self.parameters,
    params?,
  )
}

///|
fn validate_protocol_params(
  method_name : String,
  domain : String,
  parameters : Array[String],
  params? : Json,
) -> Unit raise ProtocolSchemaError {
  let required = parameters
    .filter(item => !protocol_item_optional(item))
    .map(protocol_item_name)
  match params {
    Some(Object(fields)) => {
      for name in required {
        if fields.get(name) is None {
          raise ProtocolSchemaError::MissingParameter(method_name, name)
        }
      }
      let allowed = parameters.map(protocol_item_name)
      for name, _ in fields {
        if !allowed.contains(name) {
          raise ProtocolSchemaError::UnknownParameter(method_name, name)
        }
      }
      validate_protocol_param_types(method_name, domain, parameters, fields)
    }
    Some(_) => raise ProtocolSchemaError::ExpectedParamsObject(method_name)
    None =>
      match required {
        [first, ..] =>
          raise ProtocolSchemaError::MissingParameter(method_name, first)
        [] => ()
      }
  }
}

///|
fn validate_protocol_param_types(
  method_name : String,
  domain : String,
  parameters : Array[String],
  fields : Map[String, Json],
) -> Unit raise ProtocolSchemaError {
  for item in parameters {
    let name = protocol_item_name(item)
    match fields.get(name) {
      Some(Null) if protocol_item_optional(item) => ()
      Some(value) => {
        let expected = protocol_item_type(item)
        if !json_matches_protocol_type(value, domain, expected) {
          raise ProtocolSchemaError::InvalidParameterType(
            method_name, name, expected,
          )
        }
      }
      None => ()
    }
  }
}

///|
fn validate_protocol_result(
  method_name : String,
  domain : String,
  returns : Array[String],
  result : Json?,
) -> Unit raise ProtocolSchemaError {
  let required = returns
    .filter(item => !protocol_item_optional(item))
    .map(protocol_item_name)
  match result {
    Some(Object(fields)) => {
      for name in required {
        if fields.get(name) is None {
          raise ProtocolSchemaError::MissingReturn(method_name, name)
        }
      }
      let allowed = returns.map(protocol_item_name)
      for name, _ in fields {
        if !allowed.contains(name) {
          raise ProtocolSchemaError::UnknownReturn(method_name, name)
        }
      }
      validate_protocol_return_types(method_name, domain, returns, fields)
    }
    Some(_) => raise ProtocolSchemaError::ExpectedResultObject(method_name)
    None =>
      match required {
        [first, ..] =>
          raise ProtocolSchemaError::MissingReturn(method_name, first)
        [] => ()
      }
  }
}

///|
fn validate_protocol_return_types(
  method_name : String,
  domain : String,
  returns : Array[String],
  fields : Map[String, Json],
) -> Unit raise ProtocolSchemaError {
  for item in returns {
    let name = protocol_item_name(item)
    match fields.get(name) {
      Some(Null) if protocol_item_optional(item) => ()
      Some(value) => {
        let expected = protocol_item_type(item)
        if !json_matches_protocol_type(value, domain, expected) {
          raise ProtocolSchemaError::InvalidReturnType(
            method_name, name, expected,
          )
        }
      }
      None => ()
    }
  }
}

///|
fn protocol_item_name(item : String) -> String {
  let head = item.split(":").to_array()[0].to_owned()
  if head.has_suffix("?") {
    head[:head.length() - 1].to_owned()
  } else {
    head
  }
}

///|
fn protocol_item_optional(item : String) -> Bool {
  item.split(":").to_array()[0].has_suffix("?")
}

///|
fn protocol_item_type(item : String) -> String {
  let parts = item.split(":").to_array()
  match parts {
    [_, type_name] => type_name.to_owned()
    _ => "any"
  }
}

///|
fn json_matches_protocol_type(
  value : Json,
  domain : String,
  expected : String,
) -> Bool {
  if expected.has_prefix("array<") {
    return value is Array(_)
  }
  match protocol_type_kind(domain, expected) {
    "any" => true
    "string" | "binary" => value is String(_)
    "integer" => json_is_integer(value)
    "number" => value is Number(_)
    "boolean" => value is True || value is False
    "object" => value is Object(_)
    "array" => value is Array(_)
    _ => true
  }
}

///|
fn protocol_type_kind(domain : String, expected : String) -> String {
  match expected {
    "any" | "string" | "binary" | "integer" | "number" | "boolean" | "object" =>
      expected
    _ =>
      match resolve_protocol_type(domain, expected) {
        Some(type_) => type_.kind
        None => "any"
      }
  }
}

///|
fn resolve_protocol_type(domain : String, expected : String) -> ProtocolType? {
  if expected.contains(".") {
    protocol_type(expected)
  } else {
    protocol_type("\{domain}.\{expected}")
  }
}

///|
fn json_is_integer(value : Json) -> Bool {
  match value {
    Number(number, ..) => number.to_int().to_double() == number
    _ => false
  }
}
