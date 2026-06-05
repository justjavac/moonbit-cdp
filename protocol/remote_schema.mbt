///|
pub(all) suberror ProtocolSchemaDiffError {
  ExpectedObject(String)
  MissingField(String)
  InvalidField(String)
} derive(Eq, ToJson, Debug)

///|
pub(all) struct ProtocolSchemaDiffItem {
  name : String
  details : Array[String]
} derive(Eq, ToJson, Debug)

///|
pub(all) struct ProtocolRemoteSummary {
  version : ProtocolVersion
  domain_count : Int
  command_count : Int
  event_count : Int
  type_count : Int
  domains : Array[ProtocolDomainSummary]
} derive(Eq, ToJson, Debug)

///|
pub(all) struct ProtocolSchemaDiffReport {
  local_version : ProtocolVersion
  remote_version : ProtocolVersion
  local_domain_count : Int
  remote_domain_count : Int
  local_command_count : Int
  remote_command_count : Int
  local_event_count : Int
  remote_event_count : Int
  local_type_count : Int
  remote_type_count : Int
  remote_only_domains : Array[String]
  local_only_domains : Array[String]
  remote_only_commands : Array[String]
  local_only_commands : Array[String]
  changed_commands : Array[ProtocolSchemaDiffItem]
  remote_only_events : Array[String]
  local_only_events : Array[String]
  changed_events : Array[ProtocolSchemaDiffItem]
  remote_only_types : Array[String]
  local_only_types : Array[String]
  changed_types : Array[ProtocolSchemaDiffItem]
  compatible : Bool
} derive(Eq, ToJson, Debug)

///|
priv struct RemoteProtocolSchema {
  version : ProtocolVersion
  domains : Array[ProtocolDomainSummary]
  commands : Array[ProtocolCommand]
  events : Array[ProtocolEvent]
  types : Array[ProtocolType]
}

///|
pub fn protocol_remote_summary(
  schema : Json,
) -> ProtocolRemoteSummary raise ProtocolSchemaDiffError {
  let remote = parse_remote_protocol_schema(schema)
  {
    version: remote.version,
    domain_count: remote.domains.length(),
    command_count: remote.commands.length(),
    event_count: remote.events.length(),
    type_count: remote.types.length(),
    domains: remote.domains,
  }
}

///|
pub fn protocol_schema_diff(
  remote_schema : Json,
) -> ProtocolSchemaDiffReport raise ProtocolSchemaDiffError {
  let local_manifest = protocol_manifest()
  let remote = parse_remote_protocol_schema(remote_schema)
  let local_command_index = protocol_command_index()
  let remote_command_index = remote_command_index(remote.commands)
  let local_event_index = protocol_event_index()
  let remote_event_index = remote_event_index(remote.events)
  let local_type_index = protocol_type_index()
  let remote_type_index = remote_type_index(remote.types)
  let local_only_domains = missing_domains(
    local_manifest.domains,
    remote.domains,
  )
  let remote_only_domains = missing_domains(
    remote.domains,
    local_manifest.domains,
  )
  let local_only_commands : Array[String] = []
  let remote_only_commands : Array[String] = []
  let changed_commands : Array[ProtocolSchemaDiffItem] = []
  for command in protocol_commands() {
    match remote_command_index.get(command.cdp_method) {
      Some(remote_command) => {
        let details = command_diff_details(command, remote_command)
        if details.length() > 0 {
          changed_commands.push({ name: command.cdp_method, details })
        }
      }
      None => local_only_commands.push(command.cdp_method)
    }
  }
  for command in remote.commands {
    if local_command_index.get(command.cdp_method) is None {
      remote_only_commands.push(command.cdp_method)
    }
  }
  let local_only_events : Array[String] = []
  let remote_only_events : Array[String] = []
  let changed_events : Array[ProtocolSchemaDiffItem] = []
  for event in protocol_events() {
    match remote_event_index.get(event.cdp_method) {
      Some(remote_event) => {
        let details = event_diff_details(event, remote_event)
        if details.length() > 0 {
          changed_events.push({ name: event.cdp_method, details })
        }
      }
      None => local_only_events.push(event.cdp_method)
    }
  }
  for event in remote.events {
    if local_event_index.get(event.cdp_method) is None {
      remote_only_events.push(event.cdp_method)
    }
  }
  let local_only_types : Array[String] = []
  let remote_only_types : Array[String] = []
  let changed_types : Array[ProtocolSchemaDiffItem] = []
  for type_ in protocol_types() {
    let name = protocol_type_name(type_)
    match remote_type_index.get(name) {
      Some(remote_type) => {
        let details = type_diff_details(type_, remote_type)
        if details.length() > 0 {
          changed_types.push({ name, details })
        }
      }
      None => local_only_types.push(name)
    }
  }
  for type_ in remote.types {
    let name = protocol_type_name(type_)
    if local_type_index.get(name) is None {
      remote_only_types.push(name)
    }
  }
  {
    local_version: local_manifest.version,
    remote_version: remote.version,
    local_domain_count: local_manifest.domain_count(),
    remote_domain_count: remote.domains.length(),
    local_command_count: protocol_commands().length(),
    remote_command_count: remote.commands.length(),
    local_event_count: protocol_events().length(),
    remote_event_count: remote.events.length(),
    local_type_count: protocol_types().length(),
    remote_type_count: remote.types.length(),
    remote_only_domains,
    local_only_domains,
    remote_only_commands,
    local_only_commands,
    changed_commands,
    remote_only_events,
    local_only_events,
    changed_events,
    remote_only_types,
    local_only_types,
    changed_types,
    compatible: local_only_domains.length() == 0 &&
    local_only_commands.length() == 0 &&
    changed_commands.length() == 0 &&
    local_only_events.length() == 0 &&
    changed_events.length() == 0 &&
    local_only_types.length() == 0 &&
    changed_types.length() == 0,
  }
}

///|
fn parse_remote_protocol_schema(
  schema : Json,
) -> RemoteProtocolSchema raise ProtocolSchemaDiffError {
  let fields = json_object_fields(schema, "protocol")
  let version = parse_protocol_version(required_json(fields, "version"))
  let domain_items = json_array(required_json(fields, "domains"), "domains")
  let domains : Array[ProtocolDomainSummary] = []
  let commands : Array[ProtocolCommand] = []
  let events : Array[ProtocolEvent] = []
  let types : Array[ProtocolType] = []
  for domain_json in domain_items {
    let domain_fields = json_object_fields(domain_json, "domains[]")
    let domain_name = schema_required_string(domain_fields, "domain")
    let protocol = remote_domain_protocol(domain_name)
    let domain_experimental = optional_bool(domain_fields, "experimental")
    let domain_deprecated = optional_bool(domain_fields, "deprecated")
    let domain_commands = optional_json_array(domain_fields, "commands")
    let domain_events = optional_json_array(domain_fields, "events")
    let domain_types = optional_json_array(domain_fields, "types")
    domains.push({
      protocol,
      domain: domain_name,
      command_count: domain_commands.length(),
      event_count: domain_events.length(),
      type_count: domain_types.length(),
      experimental: domain_experimental,
      deprecated: domain_deprecated,
    })
    for command_json in domain_commands {
      commands.push(
        parse_remote_command(
          protocol, domain_name, domain_experimental, domain_deprecated, command_json,
        ),
      )
    }
    for event_json in domain_events {
      events.push(
        parse_remote_event(
          protocol, domain_name, domain_experimental, domain_deprecated, event_json,
        ),
      )
    }
    for type_json in domain_types {
      types.push(
        parse_remote_type(
          protocol, domain_name, domain_experimental, domain_deprecated, type_json,
        ),
      )
    }
  }
  { version, domains, commands, events, types }
}

///|
fn parse_remote_command(
  protocol : String,
  domain : String,
  domain_experimental : Bool,
  domain_deprecated : Bool,
  json : Json,
) -> ProtocolCommand raise ProtocolSchemaDiffError {
  let fields = json_object_fields(json, "\{domain}.commands[]")
  let name = schema_required_string(fields, "name")
  let parameters = field_summaries(optional_json_array(fields, "parameters"))
  let returns = field_summaries(optional_json_array(fields, "returns"))
  let experimental = domain_experimental ||
    optional_bool(fields, "experimental")
  let deprecated = domain_deprecated || optional_bool(fields, "deprecated")
  {
    protocol,
    domain,
    name,
    cdp_method: "\{domain}.\{name}",
    parameter_count: parameters.length(),
    return_count: returns.length(),
    parameters,
    returns,
    parameter_details: field_detail_summaries(
      optional_json_array(fields, "parameters"),
      inherited_experimental=experimental,
      inherited_deprecated=deprecated,
    ),
    return_details: field_detail_summaries(
      optional_json_array(fields, "returns"),
      inherited_experimental=experimental,
      inherited_deprecated=deprecated,
    ),
    experimental,
    deprecated,
  }
}

///|
fn parse_remote_event(
  protocol : String,
  domain : String,
  domain_experimental : Bool,
  domain_deprecated : Bool,
  json : Json,
) -> ProtocolEvent raise ProtocolSchemaDiffError {
  let fields = json_object_fields(json, "\{domain}.events[]")
  let name = schema_required_string(fields, "name")
  let parameters = field_summaries(optional_json_array(fields, "parameters"))
  let experimental = domain_experimental ||
    optional_bool(fields, "experimental")
  let deprecated = domain_deprecated || optional_bool(fields, "deprecated")
  {
    protocol,
    domain,
    name,
    cdp_method: "\{domain}.\{name}",
    parameter_count: parameters.length(),
    parameters,
    parameter_details: field_detail_summaries(
      optional_json_array(fields, "parameters"),
      inherited_experimental=experimental,
      inherited_deprecated=deprecated,
    ),
    experimental,
    deprecated,
  }
}

///|
fn parse_remote_type(
  protocol : String,
  domain : String,
  domain_experimental : Bool,
  domain_deprecated : Bool,
  json : Json,
) -> ProtocolType raise ProtocolSchemaDiffError {
  let fields = json_object_fields(json, "\{domain}.types[]")
  let name = schema_required_string(fields, "id")
  let properties = field_summaries(optional_json_array(fields, "properties"))
  let enum_values = string_values(optional_json_array(fields, "enum"))
  let experimental = domain_experimental ||
    optional_bool(fields, "experimental")
  let deprecated = domain_deprecated || optional_bool(fields, "deprecated")
  {
    protocol,
    domain,
    name,
    kind: type_kind(fields),
    property_count: properties.length(),
    enum_count: enum_values.length(),
    properties,
    property_details: field_detail_summaries(
      optional_json_array(fields, "properties"),
      inherited_experimental=experimental,
      inherited_deprecated=deprecated,
    ),
    enum_values,
    experimental,
    deprecated,
  }
}

///|
fn parse_protocol_version(
  json : Json,
) -> ProtocolVersion raise ProtocolSchemaDiffError {
  let fields = json_object_fields(json, "version")
  {
    major: schema_required_string(fields, "major"),
    minor: schema_required_string(fields, "minor"),
  }
}

///|
fn remote_domain_protocol(domain : String) -> String {
  match protocol_manifest().find_domain(domain) {
    Some(local_domain) => local_domain.protocol
    None => "remote"
  }
}

///|
fn field_summaries(
  items : Array[Json],
) -> Array[String] raise ProtocolSchemaDiffError {
  items.map(item => field_summary(item))
}

///|
fn field_summary(item : Json) -> String raise ProtocolSchemaDiffError {
  let fields = json_object_fields(item, "field")
  let name = schema_required_string(fields, "name")
  let optional = if optional_bool(fields, "optional") { "?" } else { "" }
  "\{name}\{optional}:\{value_kind(fields)}"
}

///|
fn field_detail_summaries(
  items : Array[Json],
  inherited_experimental~ : Bool,
  inherited_deprecated~ : Bool,
) -> Array[ProtocolFieldSummary] raise ProtocolSchemaDiffError {
  items.map(item => {
    field_detail_summary(item, inherited_experimental~, inherited_deprecated~)
  })
}

///|
fn field_detail_summary(
  item : Json,
  inherited_experimental~ : Bool,
  inherited_deprecated~ : Bool,
) -> ProtocolFieldSummary raise ProtocolSchemaDiffError {
  let fields = json_object_fields(item, "field")
  {
    name: schema_required_string(fields, "name"),
    kind: value_kind(fields),
    optional: optional_bool(fields, "optional"),
    experimental: inherited_experimental ||
    optional_bool(fields, "experimental"),
    deprecated: inherited_deprecated || optional_bool(fields, "deprecated"),
  }
}

///|
fn value_kind(
  fields : Map[String, Json],
) -> String raise ProtocolSchemaDiffError {
  match schema_optional_string(fields, "$ref") {
    Some(ref_) => ref_
    None =>
      match schema_optional_string(fields, "type") {
        Some("array") => "array<\{array_item_kind(fields)}>"
        Some(kind) => kind
        None => "any"
      }
  }
}

///|
fn array_item_kind(
  fields : Map[String, Json],
) -> String raise ProtocolSchemaDiffError {
  match fields.get("items") {
    Some(Object(item_fields)) => value_kind(item_fields)
    Some(_) => raise InvalidField("items")
    None => "any"
  }
}

///|
fn type_kind(
  fields : Map[String, Json],
) -> String raise ProtocolSchemaDiffError {
  match schema_optional_string(fields, "type") {
    Some(kind) => kind
    None =>
      match schema_optional_string(fields, "$ref") {
        Some(_) => "ref"
        None => "any"
      }
  }
}

///|
fn string_values(
  items : Array[Json],
) -> Array[String] raise ProtocolSchemaDiffError {
  let values : Array[String] = []
  for item in items {
    match item {
      String(value) => values.push(value)
      _ => raise InvalidField("enum")
    }
  }
  values
}

///|
fn missing_domains(
  left : Array[ProtocolDomainSummary],
  right : Array[ProtocolDomainSummary],
) -> Array[String] {
  let names : Array[String] = []
  for item in left {
    if !right.any(other => other.domain == item.domain) {
      names.push(item.domain)
    }
  }
  names
}

///|
fn protocol_command_index() -> Map[String, ProtocolCommand] {
  let index : Map[String, ProtocolCommand] = {}
  for command in protocol_commands() {
    index[command.cdp_method] = command
  }
  index
}

///|
fn remote_command_index(
  commands : Array[ProtocolCommand],
) -> Map[String, ProtocolCommand] {
  let index : Map[String, ProtocolCommand] = {}
  for command in commands {
    index[command.cdp_method] = command
  }
  index
}

///|
fn protocol_event_index() -> Map[String, ProtocolEvent] {
  let index : Map[String, ProtocolEvent] = {}
  for event in protocol_events() {
    index[event.cdp_method] = event
  }
  index
}

///|
fn remote_event_index(
  events : Array[ProtocolEvent],
) -> Map[String, ProtocolEvent] {
  let index : Map[String, ProtocolEvent] = {}
  for event in events {
    index[event.cdp_method] = event
  }
  index
}

///|
fn protocol_type_index() -> Map[String, ProtocolType] {
  let index : Map[String, ProtocolType] = {}
  for type_ in protocol_types() {
    index[protocol_type_name(type_)] = type_
  }
  index
}

///|
fn remote_type_index(types : Array[ProtocolType]) -> Map[String, ProtocolType] {
  let index : Map[String, ProtocolType] = {}
  for type_ in types {
    index[protocol_type_name(type_)] = type_
  }
  index
}

///|
fn command_diff_details(
  bundled : ProtocolCommand,
  remote : ProtocolCommand,
) -> Array[String] {
  let details : Array[String] = []
  push_flag_diff(
    details,
    "experimental",
    bundled.experimental,
    remote.experimental,
  )
  push_flag_diff(details, "deprecated", bundled.deprecated, remote.deprecated)
  push_array_diff(details, "parameters", bundled.parameters, remote.parameters)
  push_array_diff(details, "returns", bundled.returns, remote.returns)
  details
}

///|
fn event_diff_details(
  bundled : ProtocolEvent,
  remote : ProtocolEvent,
) -> Array[String] {
  let details : Array[String] = []
  push_flag_diff(
    details,
    "experimental",
    bundled.experimental,
    remote.experimental,
  )
  push_flag_diff(details, "deprecated", bundled.deprecated, remote.deprecated)
  push_array_diff(details, "parameters", bundled.parameters, remote.parameters)
  details
}

///|
fn type_diff_details(
  bundled : ProtocolType,
  remote : ProtocolType,
) -> Array[String] {
  let details : Array[String] = []
  if bundled.kind != remote.kind {
    details.push("kind local=\{bundled.kind} remote=\{remote.kind}")
  }
  push_flag_diff(
    details,
    "experimental",
    bundled.experimental,
    remote.experimental,
  )
  push_flag_diff(details, "deprecated", bundled.deprecated, remote.deprecated)
  push_array_diff(details, "properties", bundled.properties, remote.properties)
  push_array_diff(details, "enum", bundled.enum_values, remote.enum_values)
  details
}

///|
fn push_flag_diff(
  details : Array[String],
  name : String,
  bundled : Bool,
  remote : Bool,
) -> Unit {
  if bundled != remote {
    details.push("\{name} local=\{bundled} remote=\{remote}")
  }
}

///|
fn push_array_diff(
  details : Array[String],
  name : String,
  bundled : Array[String],
  remote : Array[String],
) -> Unit {
  if !string_arrays_equal(bundled, remote) {
    details.push(
      "\{name} local=[\{bundled.join(", ")}] remote=[\{remote.join(", ")}]",
    )
  }
}

///|
fn string_arrays_equal(left : Array[String], right : Array[String]) -> Bool {
  if left.length() != right.length() {
    return false
  }
  for index in 0..<left.length() {
    if left[index] != right[index] {
      return false
    }
  }
  true
}

///|
fn protocol_type_name(type_ : ProtocolType) -> String {
  "\{type_.domain}.\{type_.name}"
}

///|
fn json_object_fields(
  value : Json,
  name : String,
) -> Map[String, Json] raise ProtocolSchemaDiffError {
  match value {
    Object(fields) => fields
    _ => raise ExpectedObject(name)
  }
}

///|
fn required_json(
  fields : Map[String, Json],
  name : String,
) -> Json raise ProtocolSchemaDiffError {
  match fields.get(name) {
    Some(value) => value
    None => raise MissingField(name)
  }
}

///|
fn json_array(
  value : Json,
  name : String,
) -> Array[Json] raise ProtocolSchemaDiffError {
  match value {
    Array(items) => items
    _ => raise InvalidField(name)
  }
}

///|
fn optional_json_array(
  fields : Map[String, Json],
  name : String,
) -> Array[Json] raise ProtocolSchemaDiffError {
  match fields.get(name) {
    Some(value) => json_array(value, name)
    None => []
  }
}

///|
fn schema_required_string(
  fields : Map[String, Json],
  name : String,
) -> String raise ProtocolSchemaDiffError {
  match fields.get(name) {
    Some(String(value)) => value
    Some(_) => raise InvalidField(name)
    None => raise MissingField(name)
  }
}

///|
fn schema_optional_string(
  fields : Map[String, Json],
  name : String,
) -> String? raise ProtocolSchemaDiffError {
  match fields.get(name) {
    Some(String(value)) => Some(value)
    Some(Null) | None => None
    Some(_) => raise InvalidField(name)
  }
}

///|
fn optional_bool(
  fields : Map[String, Json],
  name : String,
) -> Bool raise ProtocolSchemaDiffError {
  match fields.get(name) {
    Some(True) => true
    Some(False) | Some(Null) | None => false
    Some(_) => raise InvalidField(name)
  }
}
