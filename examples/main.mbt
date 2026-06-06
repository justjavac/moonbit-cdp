///|
// Return the remote debugging target configured for examples.
fn example_target() -> String {
  match @env.get_env_var("MBT_CDP_TARGET") {
    Some(value) if value != "" => value
    _ => "9222"
  }
}

///|
// Return the selected example name.
fn example_name() -> String {
  match @env.get_env_var("MBT_CDP_EXAMPLE") {
    Some(value) if value != "" => value
    _ => "discover_version"
  }
}

///|
// Build a small Runtime.evaluate request for the current page.
fn evaluate_params() -> @typed.RuntimeEvaluateParams {
  {
    expression: "1 + 1",
    object_group: None,
    include_command_line_api: None,
    silent: None,
    context_id: None,
    return_by_value: Some(true),
    generate_preview: None,
    user_gesture: None,
    await_promise: None,
    throw_on_side_effect: None,
    timeout: None,
    disable_breaks: None,
    repl_mode: None,
    allow_unsafe_eval_blocked_by_csp: None,
    unique_context_id: None,
    serialization_options: None,
  }
}

///|
// Print browser metadata from `/json/version`.
async fn run_discover_version() -> Unit {
  let target = @client.parse_cdp_target(example_target())
  let version = @client.discover_version(target)
  println("browser: \{version.browser}")
  println("protocol: \{version.protocol_version}")
  println("websocket: \{version.web_socket_debugger_url}")
}

///|
// Evaluate a JavaScript expression on the first page target.
async fn run_runtime_evaluate() -> Unit {
  let target = @client.parse_cdp_target(example_target())
  let client = @client.connect_cdp_page_target(target)
  defer client.close()
  let command = @typed.runtime_evaluate_command(id=1, evaluate_params())
  let response = client.send_cdp_message(command)
  let result = @typed.RuntimeEvaluateResult::from_json(
    @client.cdp_response_result_json(response),
  )
  println("Runtime.evaluate result type: \{result.result.type_}")
}

///|
async fn main {
  match example_name() {
    "discover_version" => run_discover_version()
    "runtime_evaluate" => run_runtime_evaluate()
    other =>
      fail(
        "unknown example \{other}; set MBT_CDP_EXAMPLE=discover_version or runtime_evaluate",
      )
  }
}
