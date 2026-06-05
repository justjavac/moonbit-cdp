///|
test "parse DevToolsActivePort file" {
  guard parse_devtools_active_port(
      (
        #|45555
        #|/devtools/browser/browser-id
        #|
      ),
    )
    is Some(info) else {
    fail("expected DevToolsActivePort info")
  }
  inspect(info.port, content="45555")
  inspect(info.web_socket_path, content="/devtools/browser/browser-id")
  guard parse_devtools_active_port("0\n/devtools/browser/id\n") is None else {
    fail("port 0 should be rejected")
  }
  guard parse_devtools_active_port("bad\n/devtools/browser/id\n") is None else {
    fail("invalid port should be rejected")
  }
  guard parse_devtools_active_port("45555\n\n") is None else {
    fail("empty websocket path should be rejected")
  }
}

///|
test "parse DevToolsActivePort normalizes relative websocket path" {
  guard parse_devtools_active_port("45555\ndevtools/browser/browser-id\n")
    is Some(info) else {
    fail("expected DevToolsActivePort info")
  }
  inspect(info.web_socket_path, content="/devtools/browser/browser-id")
}

///|
async test "wait for DevToolsActivePort file" {
  let dir = @fs.tmpdir(prefix="mbt-cdp-devtools-")
  @async.with_task_group() <| group => {
    group.spawn_bg() <| () => {
      @async.sleep(100)
      @fs.write_file(
        devtools_active_port_path(dir),
        (
          #|46666
          #|/devtools/browser/waited
          #|
        ),
        create_mode=CreateOrTruncate,
      )
    }
    let info = wait_for_devtools_active_port(dir, timeout_ms=1000)
    inspect(info.port, content="46666")
    inspect(info.web_socket_path, content="/devtools/browser/waited")
  }
  @fs.rmdir(dir, recursive=true) catch {
    _ => ()
  }
}
