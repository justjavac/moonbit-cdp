///|
pub(all) struct ProtocolVersion {
  major : String
  minor : String
} derive(Eq, ToJson, Debug)

///|
pub(all) struct ProtocolDomainSummary {
  protocol : String
  domain : String
  command_count : Int
  event_count : Int
  type_count : Int
  experimental : Bool
  deprecated : Bool
} derive(Eq, ToJson, Debug)

///|
pub(all) struct ProtocolSchemaSource {
  protocol : String
  path : String
  sha256 : String
  byte_count : Int
  domain_count : Int
  command_count : Int
  event_count : Int
  type_count : Int
} derive(Eq, ToJson, Debug)

///|
pub(all) struct ProtocolFieldSummary {
  name : String
  kind : String
  optional : Bool
  experimental : Bool
  deprecated : Bool
} derive(Eq, ToJson, Debug)

///|
pub(all) struct ProtocolCommand {
  protocol : String
  domain : String
  name : String
  cdp_method : String
  parameter_count : Int
  return_count : Int
  parameters : Array[String]
  returns : Array[String]
  parameter_details : Array[ProtocolFieldSummary]
  return_details : Array[ProtocolFieldSummary]
  experimental : Bool
  deprecated : Bool
} derive(Eq, ToJson, Debug)

///|
pub(all) struct ProtocolEvent {
  protocol : String
  domain : String
  name : String
  cdp_method : String
  parameter_count : Int
  parameters : Array[String]
  parameter_details : Array[ProtocolFieldSummary]
  experimental : Bool
  deprecated : Bool
} derive(Eq, ToJson, Debug)

///|
pub(all) struct ProtocolType {
  protocol : String
  domain : String
  name : String
  kind : String
  property_count : Int
  enum_count : Int
  properties : Array[String]
  property_details : Array[ProtocolFieldSummary]
  enum_values : Array[String]
  experimental : Bool
  deprecated : Bool
} derive(Eq, ToJson, Debug)

///|
pub(all) struct ProtocolManifest {
  version : ProtocolVersion
  sources : Array[ProtocolSchemaSource]
  domains : Array[ProtocolDomainSummary]
} derive(Eq, ToJson, Debug)

///|
pub fn ProtocolManifest::domain_count(self : ProtocolManifest) -> Int {
  self.domains.length()
}

///|
pub fn ProtocolManifest::command_count(self : ProtocolManifest) -> Int {
  self.domains.fold(init=0, (sum, item) => sum + item.command_count)
}

///|
pub fn ProtocolManifest::event_count(self : ProtocolManifest) -> Int {
  self.domains.fold(init=0, (sum, item) => sum + item.event_count)
}

///|
pub fn ProtocolManifest::type_count(self : ProtocolManifest) -> Int {
  self.domains.fold(init=0, (sum, item) => sum + item.type_count)
}

///|
pub fn ProtocolManifest::find_domain(
  self : ProtocolManifest,
  domain : String,
) -> ProtocolDomainSummary? {
  for item in self.domains {
    if item.domain == domain {
      return Some(item)
    }
  }
  None
}

///|
pub fn protocol_commands_for_domain(domain : String) -> Array[ProtocolCommand] {
  protocol_commands().filter(item => item.domain == domain)
}

///|
pub fn protocol_command(method_name : String) -> ProtocolCommand? {
  for command in protocol_commands() {
    if command.cdp_method == method_name {
      return Some(command)
    }
  }
  None
}

///|
pub fn protocol_commands_matching(query : String) -> Array[ProtocolCommand] {
  let needle = query.to_lower()
  protocol_commands().filter(command => command.matches_query(needle))
}

///|
pub fn protocol_events_for_domain(domain : String) -> Array[ProtocolEvent] {
  protocol_events().filter(item => item.domain == domain)
}

///|
pub fn protocol_event(method_name : String) -> ProtocolEvent? {
  for event in protocol_events() {
    if event.cdp_method == method_name {
      return Some(event)
    }
  }
  None
}

///|
pub fn protocol_events_matching(query : String) -> Array[ProtocolEvent] {
  let needle = query.to_lower()
  protocol_events().filter(event => event.matches_query(needle))
}

///|
pub fn protocol_types_for_domain(domain : String) -> Array[ProtocolType] {
  protocol_types().filter(item => item.domain == domain)
}

///|
pub fn protocol_type(type_name : String) -> ProtocolType? {
  for type_ in protocol_types() {
    let full_name = "\{type_.domain}.\{type_.name}"
    if full_name == type_name {
      return Some(type_)
    }
  }
  None
}

///|
pub fn protocol_types_matching(query : String) -> Array[ProtocolType] {
  let needle = query.to_lower()
  protocol_types().filter(type_ => type_.matches_query(needle))
}

///|
fn ProtocolCommand::matches_query(
  self : ProtocolCommand,
  needle : String,
) -> Bool {
  contains_protocol_query(self.cdp_method, needle) ||
  contains_protocol_query(self.protocol, needle) ||
  contains_protocol_query(self.domain, needle) ||
  contains_protocol_query(self.name, needle) ||
  protocol_items_match(self.parameters, needle) ||
  protocol_items_match(self.returns, needle)
}

///|
fn ProtocolEvent::matches_query(self : ProtocolEvent, needle : String) -> Bool {
  contains_protocol_query(self.cdp_method, needle) ||
  contains_protocol_query(self.protocol, needle) ||
  contains_protocol_query(self.domain, needle) ||
  contains_protocol_query(self.name, needle) ||
  protocol_items_match(self.parameters, needle)
}

///|
fn ProtocolType::matches_query(self : ProtocolType, needle : String) -> Bool {
  contains_protocol_query("\{self.domain}.\{self.name}", needle) ||
  contains_protocol_query(self.protocol, needle) ||
  contains_protocol_query(self.kind, needle) ||
  protocol_items_match(self.properties, needle) ||
  protocol_items_match(self.enum_values, needle)
}

///|
fn protocol_items_match(items : Array[String], needle : String) -> Bool {
  for item in items {
    if contains_protocol_query(item, needle) {
      return true
    }
  }
  false
}

///|
fn contains_protocol_query(value : String, needle : String) -> Bool {
  needle != "" && value.to_lower().contains(needle)
}
