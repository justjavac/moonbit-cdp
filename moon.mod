name = "justjavac/cdp"

version = "0.1.6"

readme = "README.mbt.md"

import {
  "moonbitlang/async@0.19.2",
  "moonbitlang/x@0.4.45",
}

repository = "https://github.com/justjavac/moonbit-cdp"

license = "MIT"

keywords = [
  "cdp",
  "chrome-devtools-protocol",
  "chrome",
  "devtools",
  "browser-automation",
]

description = "MoonBit Chrome DevTools Protocol library"

preferred_target = "native"

options(
  source: "src",
)
