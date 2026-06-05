///|
pub(all) suberror BrowserLaunchError {
  BrowserNotFound
  BrowserNotReady(Int)
} derive(Eq, ToJson, Debug)

///|
pub(all) struct CdpLaunchOptions {
  browser_path : String?
  port : Int
  user_data_dir : String
  headless : Bool
  url : String?
  timeout_ms : Int
  extra_args : Array[String]
  extensions : Array[String]
  proxy_server : String?
  proxy_bypass : String?
  ignore_https_errors : Bool
  allow_file_access : Bool
  hide_scrollbars : Bool
} derive(Eq, ToJson, Debug)

///|
pub(all) struct CdpLaunchInfo {
  pid : Int
  port : Int
  endpoint : String
  web_socket_url : String
  user_data_dir : String
} derive(Eq, ToJson, Debug)

///|
priv struct DevToolsActivePort {
  port : Int
  web_socket_path : String
}

///|
pub fn default_launch_options() -> CdpLaunchOptions {
  {
    browser_path: None,
    port: 9222,
    user_data_dir: "_build/mbt-cdp-profile-9222",
    headless: false,
    url: Some("about:blank"),
    timeout_ms: 5000,
    extra_args: [],
    extensions: [],
    proxy_server: None,
    proxy_bypass: None,
    ignore_https_errors: false,
    allow_file_access: false,
    hide_scrollbars: false,
  }
}

///|
pub async fn launch_browser(options : CdpLaunchOptions) -> CdpLaunchInfo {
  let browser_path = match options.browser_path {
    Some(path) => path
    None => resolve_chrome_executable()
  }
  if !@fs.exists(options.user_data_dir) {
    @fs.mkdir(options.user_data_dir, recursive=true)
  }
  let user_data_dir = @fs.realpath(options.user_data_dir)
  let launch_options = { ..options, user_data_dir, }
  if launch_options.port == 0 {
    remove_devtools_active_port_file(launch_options.user_data_dir)
  }
  let args = chrome_launch_args(launch_options)
  let pid = @process.spawn_orphan(browser_path, args)
  let (actual_port, web_socket_url) = if launch_options.port == 0 {
    let active_port = wait_for_devtools_active_port(
      launch_options.user_data_dir,
      timeout_ms=launch_options.timeout_ms,
    )
    (
      active_port.port,
      "ws://127.0.0.1:\{active_port.port}\{active_port.web_socket_path}",
    )
  } else {
    let endpoint = "http://127.0.0.1:\{launch_options.port}"
    (
      launch_options.port,
      wait_for_browser_endpoint(endpoint, timeout_ms=launch_options.timeout_ms),
    )
  }
  let endpoint = "http://127.0.0.1:\{actual_port}"
  {
    pid,
    port: actual_port,
    endpoint,
    web_socket_url,
    user_data_dir: launch_options.user_data_dir,
  }
}

///|
pub fn chrome_launch_args(options : CdpLaunchOptions) -> Array[String] {
  let args : Array[String] = [
    "--remote-debugging-port=\{options.port}",
    "--user-data-dir=\{options.user_data_dir}",
    "--no-first-run",
    "--no-default-browser-check",
  ]
  if options.headless {
    args.push("--headless=new")
  }
  if options.proxy_server is Some(proxy_server) {
    args.push("--proxy-server=\{proxy_server}")
  }
  if options.proxy_bypass is Some(proxy_bypass) {
    args.push("--proxy-bypass-list=\{proxy_bypass}")
  }
  if options.ignore_https_errors {
    args.push("--ignore-certificate-errors")
  }
  if options.allow_file_access {
    args.push("--allow-file-access-from-files")
  }
  if options.hide_scrollbars {
    args.push("--hide-scrollbars")
  }
  if options.extensions.length() > 0 {
    args.push("--load-extension=\{options.extensions.join(",")}")
  }
  for arg in options.extra_args {
    args.push(arg)
  }
  if options.url is Some(url) {
    args.push(url)
  }
  args
}

///|
async fn remove_devtools_active_port_file(user_data_dir : String) -> Unit {
  let path = devtools_active_port_path(user_data_dir)
  if @fs.exists(path) {
    @fs.remove(path) catch {
      _ => ()
    }
  }
}

///|
fn devtools_active_port_path(user_data_dir : String) -> String {
  "\{strip_trailing_path_separator(user_data_dir)}/DevToolsActivePort"
}

///|
fn strip_trailing_path_separator(path : String) -> String {
  match path.strip_suffix("/") {
    Some(path) => path.to_owned()
    None =>
      match path.strip_suffix("\\") {
        Some(path) => path.to_owned()
        None => path
      }
  }
}

///|
async fn wait_for_devtools_active_port(
  user_data_dir : String,
  timeout_ms~ : Int,
) -> DevToolsActivePort {
  let path = devtools_active_port_path(user_data_dir)
  let deadline = @async.now() + timeout_ms.to_int64()
  for ;; {
    try parse_devtools_active_port(@fs.read_file(path).text()) catch {
      _ => {
        if @async.now() >= deadline {
          raise BrowserLaunchError::BrowserNotReady(timeout_ms)
        }
        @async.sleep(100)
        continue
      }
    } noraise {
      Some(info) => return info
      None => {
        if @async.now() >= deadline {
          raise BrowserLaunchError::BrowserNotReady(timeout_ms)
        }
        @async.sleep(100)
        continue
      }
    }
  }
}

///|
fn parse_devtools_active_port(raw : String) -> DevToolsActivePort? {
  match raw.split("\n").to_array() {
    [port_line, path_line, ..] =>
      match parse_debugging_port(port_line.trim().to_owned()) {
        Some(port) => {
          let path = path_line.trim().to_owned()
          if path == "" {
            None
          } else if path.has_prefix("/") {
            Some({ port, web_socket_path: path })
          } else {
            Some({ port, web_socket_path: "/\{path}" })
          }
        }
        None => None
      }
    _ => None
  }
}

///|
fn parse_debugging_port(value : String) -> Int? {
  if value == "" {
    return None
  }
  let mut port = 0
  for char in value {
    if !char.is_ascii_digit() {
      return None
    }
    port = port * 10 + (char.to_int() - '0'.to_int())
  }
  if port > 0 && port < 65536 {
    Some(port)
  } else {
    None
  }
}

///|
pub async fn resolve_chrome_executable() -> String {
  for candidate in chrome_executable_candidates() {
    if @fs.exists(candidate) {
      return candidate
    }
  }
  raise BrowserLaunchError::BrowserNotFound
}

///|
pub fn chrome_executable_candidates() -> Array[String] {
  [
    "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe", "C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe",
    "C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe", "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
    "/usr/bin/google-chrome", "/usr/bin/google-chrome-stable", "/usr/bin/chromium",
    "/usr/bin/chromium-browser", "/snap/bin/chromium",
  ]
}

///|
pub async fn wait_for_browser_endpoint(
  endpoint : String,
  timeout_ms~ : Int,
) -> String {
  let deadline = @async.now() + timeout_ms.to_int64()
  for ;; {
    try discover_web_socket_url(Http(endpoint)) catch {
      _ => {
        if @async.now() >= deadline {
          raise BrowserLaunchError::BrowserNotReady(timeout_ms)
        }
        @async.sleep(100)
        continue
      }
    } noraise {
      url => return url
    }
  }
}
