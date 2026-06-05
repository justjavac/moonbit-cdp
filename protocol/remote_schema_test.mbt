///|
test "remote protocol summary parses json protocol shape" {
  let summary = @protocol.protocol_remote_summary(sample_remote_schema())
  inspect(summary.version.major, content="1")
  inspect(summary.version.minor, content="3")
  inspect(summary.domain_count, content="2")
  inspect(summary.command_count, content="2")
  inspect(summary.event_count, content="1")
  inspect(summary.type_count, content="1")
  assert_true(summary.domains.any(domain => domain.domain == "Page"))
  assert_true(summary.domains.any(domain => domain.domain == "TestOnly"))
}

///|
test "remote protocol diff reports local remote and field changes" {
  let report = @protocol.protocol_schema_diff(sample_remote_schema())
  assert_true(report.remote_only_domains.contains("TestOnly"))
  assert_true(report.local_only_domains.contains("Runtime"))
  assert_true(report.remote_only_commands.contains("TestOnly.doThing"))
  assert_true(report.local_only_commands.contains("Runtime.evaluate"))
  assert_true(
    report.changed_commands.any(item => {
      item.name == "Page.navigate" &&
      item.details.any(detail => detail.contains("parameters")) &&
      item.details.any(detail => detail.contains("returns"))
    }),
  )
  assert_true(report.changed_types.any(item => item.name == "Page.FrameId"))
  assert_true(!report.compatible)
}

///|
fn sample_remote_schema() -> Json raise {
  @json.parse(
    (
      #|{
      #|  "version": { "major": "1", "minor": "3" },
      #|  "domains": [
      #|    {
      #|      "domain": "Page",
      #|      "commands": [
      #|        {
      #|          "name": "navigate",
      #|          "parameters": [{ "name": "url", "type": "string" }],
      #|          "returns": [{ "name": "frameId", "$ref": "FrameId" }]
      #|        }
      #|      ],
      #|      "events": [
      #|        {
      #|          "name": "loadEventFired",
      #|          "parameters": [{ "name": "timestamp", "$ref": "Network.MonotonicTime" }]
      #|        }
      #|      ],
      #|      "types": [{ "id": "FrameId", "type": "string", "experimental": true }]
      #|    },
      #|    {
      #|      "domain": "TestOnly",
      #|      "commands": [{ "name": "doThing" }]
      #|    }
      #|  ]
      #|}
    ),
  )
}
