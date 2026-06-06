# justjavac/cdp/protocol

Core Chrome DevTools Protocol wire types and schema helpers.

This package provides raw CDP command, response, and event message types,
bundled protocol manifest lookup, schema-aware command builders, response
validation, incoming-message decoding, and remote schema comparison helpers.

## Use

```mbt nocheck
let command = @protocol.cdp_schema_command(
  id=1,
  method_name="Browser.getVersion",
)

println(command.stringify())
```

Protocol metadata can be inspected from the bundled manifest:

```mbt nocheck
let manifest = @protocol.protocol_manifest()
println(manifest.command_count())

let runtime_commands = @protocol.protocol_commands_for_domain("Runtime")
println(runtime_commands.length())
```
