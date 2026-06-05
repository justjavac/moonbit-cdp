///|
pub(all) enum CliCommand {
  Version
  Connect(String)
  CdpSend(String, String, String?, String?)
  CdpTargets(String)
  CdpAttach(String, String)
  CdpEvents(String, CdpEventsOptions)
  CdpSchema(String)
}

///|
pub(all) struct CdpEventsOptions {
  method_name : String?
  session_id : String?
  timeout_ms : Int
} derive(Eq, Debug)

///|
pub fn default_cdp_events_options() -> CdpEventsOptions {
  { method_name: None, session_id: None, timeout_ms: 1000 }
}

///|
pub fn parse_cli(args : Array[String]) -> CliCommand raise {
  let view = args[:]
  if view.length() == 0 {
    fail(usage())
  }
  match view[0] {
    "version" | "--version" | "-V" => Version
    "connect" => Connect(required_arg(view, 1, "target"))
    "cdp" => parse_cdp(view[1:])
    "--help" | "-h" | "help" => fail(usage())
    other => fail("unsupported command: \{other}\n\{usage()}")
  }
}

///|
fn parse_cdp(args : ArrayView[String]) -> CliCommand raise {
  if args.length() == 0 {
    fail(cdp_usage())
  }
  match args[0] {
    "send" => {
      let target = required_arg(args, 1, "target")
      let method_name = required_arg(args, 2, "method")
      let (params, session_id) = parse_send_args(args[3:])
      CdpSend(target, method_name, params, session_id)
    }
    "targets" => CdpTargets(required_arg(args, 1, "target"))
    "attach" =>
      CdpAttach(
        required_arg(args, 1, "target"),
        required_arg(args, 2, "target-id"),
      )
    "events" =>
      CdpEvents(
        required_arg(args, 1, "target"),
        parse_cdp_events_options(args[2:]),
      )
    "schema" => CdpSchema(required_arg(args, 1, "target"))
    other => fail("unsupported cdp command: \{other}\n\{cdp_usage()}")
  }
}

///|
fn parse_send_args(args : ArrayView[String]) -> (String?, String?) raise {
  let mut params : String? = None
  let mut session_id : String? = None
  let mut index = 0
  while index < args.length() {
    let arg = args[index]
    if arg == "--session" || arg == "--session-id" {
      if session_id is Some(_) {
        fail("duplicate send session")
      }
      session_id = Some(required_arg(args, index + 1, arg))
      index += 2
    } else if arg.has_prefix("--session=") || arg.has_prefix("--session-id=") {
      if session_id is Some(_) {
        fail("duplicate send session")
      }
      session_id = Some(flag_value(arg))
      index += 1
    } else {
      if params is Some(_) {
        fail("unexpected send argument: \{arg}")
      }
      params = Some(arg)
      index += 1
    }
  }
  (params, session_id)
}

///|
fn parse_cdp_events_options(args : ArrayView[String]) -> CdpEventsOptions raise {
  let mut options = default_cdp_events_options()
  let mut index = 0
  while index < args.length() {
    let arg = args[index]
    if arg == "--method" {
      options = {
        ..options,
        method_name: Some(required_arg(args, index + 1, arg)),
      }
      index += 2
    } else if arg.has_prefix("--method=") {
      options = { ..options, method_name: Some(flag_value(arg)) }
      index += 1
    } else if arg == "--session" || arg == "--session-id" {
      options = {
        ..options,
        session_id: Some(required_arg(args, index + 1, arg)),
      }
      index += 2
    } else if arg.has_prefix("--session=") || arg.has_prefix("--session-id=") {
      options = { ..options, session_id: Some(flag_value(arg)) }
      index += 1
    } else if arg == "--timeout" || arg == "--timeout-ms" {
      options = {
        ..options,
        timeout_ms: parse_positive_int(required_arg(args, index + 1, arg)),
      }
      index += 2
    } else if arg.has_prefix("--timeout=") || arg.has_prefix("--timeout-ms=") {
      options = { ..options, timeout_ms: parse_positive_int(flag_value(arg)) }
      index += 1
    } else {
      fail("unsupported cdp events option: \{arg}")
    }
  }
  options
}

///|
fn required_arg(
  args : ArrayView[String],
  index : Int,
  name : String,
) -> String raise {
  if index < args.length() {
    args[index]
  } else {
    fail("missing \{name}")
  }
}

///|
fn flag_value(arg : String) -> String raise {
  match arg.split("=").to_array() {
    [_, value] => value.to_owned()
    _ => fail("missing value for \{arg}")
  }
}

///|
fn parse_positive_int(raw : String) -> Int raise {
  let mut valid = raw != ""
  let mut result = 0
  for char in raw {
    if char.is_ascii_digit() {
      result = result * 10 + (char.to_int() - '0'.to_int())
    } else {
      valid = false
    }
  }
  if valid && result > 0 {
    result
  } else {
    fail("expected positive integer: \{raw}")
  }
}

///|
pub fn render_command(command : CliCommand) -> String {
  match command {
    Version => "mbt-cdp 0.1.0"
    Connect(target) => "connect \{target}"
    CdpSend(target, method_name, _, session_id) =>
      match session_id {
        Some(session_id) =>
          "cdp send \{method_name} to \{target} session \{session_id}"
        None => "cdp send \{method_name} to \{target}"
      }
    CdpTargets(target) => "cdp targets \{target}"
    CdpAttach(target, target_id) => "cdp attach \{target_id} via \{target}"
    CdpEvents(target, options) =>
      "cdp events \{target} timeout \{options.timeout_ms}"
    CdpSchema(target) => "cdp schema \{target}"
  }
}

///|
pub fn usage() -> String {
  "usage: mbt-cdp <version|connect|cdp>\n\{cdp_usage()}"
}

///|
pub fn cdp_usage() -> String {
  "cdp commands: send <target> <method> [params-json] [--session <id>], targets <target>, attach <target> <target-id>, events <target> [--method <name>] [--session <id>] [--timeout <ms>], schema <target>"
}
