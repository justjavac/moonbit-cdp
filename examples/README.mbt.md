# justjavac/cdp examples

Runnable examples for the `justjavac/cdp` MoonBit Chrome DevTools Protocol
library.

## Run

Start Chrome with remote debugging:

```powershell
& "C:\Program Files\Google\Chrome\Application\chrome.exe" `
  --remote-debugging-port=9222 `
  --user-data-dir="$env:TEMP\mbt-cdp-profile"
```

Then run an example:

```powershell
$env:MBT_CDP_TARGET = "9222"
$env:MBT_CDP_EXAMPLE = "discover_version"
moon run cmd

$env:MBT_CDP_EXAMPLE = "runtime_evaluate"
moon run cmd
```

From the repository root, prefix the command with `-C examples`:

```powershell
moon -C examples run cmd
```
