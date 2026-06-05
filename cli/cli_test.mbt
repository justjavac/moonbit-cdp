///|
test "parse cdp-only commands" {
  inspect(
    @cli.render_command(@cli.parse_cli(["version"])),
    content="mbt-cdp 0.1.0",
  )
  inspect(
    @cli.render_command(@cli.parse_cli(["connect", "9222"])),
    content="connect 9222",
  )
  inspect(
    @cli.render_command(
      @cli.parse_cli(["cdp", "send", "9222", "Runtime.evaluate"]),
    ),
    content="cdp send Runtime.evaluate to 9222",
  )
  inspect(
    @cli.render_command(
      @cli.parse_cli([
        "cdp", "send", "9222", "Runtime.evaluate", "{\"expression\":\"1\"}", "--session",
        "s1",
      ]),
    ),
    content="cdp send Runtime.evaluate to 9222 session s1",
  )
  inspect(
    @cli.render_command(@cli.parse_cli(["cdp", "targets", "9222"])),
    content="cdp targets 9222",
  )
  inspect(
    @cli.render_command(@cli.parse_cli(["cdp", "attach", "9222", "page-1"])),
    content="cdp attach page-1 via 9222",
  )
  inspect(
    @cli.render_command(
      @cli.parse_cli([
        "cdp", "events", "9222", "--method=Page.loadEventFired", "--timeout", "50",
      ]),
    ),
    content="cdp events 9222 timeout 50",
  )
  inspect(
    @cli.render_command(@cli.parse_cli(["cdp", "schema", "9222"])),
    content="cdp schema 9222",
  )
}

///|
test "reject removed non-cdp commands" {
  try @cli.parse_cli(["snapshot"]) catch {
    err => assert_true("\{err}".contains("unsupported command"))
  } noraise {
    _ => fail("expected snapshot to be removed")
  }
  try @cli.parse_cli(["chat"]) catch {
    err => assert_true("\{err}".contains("unsupported command"))
  } noraise {
    _ => fail("expected chat to be removed")
  }
}
