import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const args = new Set(process.argv.slice(2));
const checkMode = args.has("--check");
const helpMode = args.has("--help") || args.has("-h");
const sources = [
  ["browser", "protocol/data/browser_protocol.json"],
  ["js", "protocol/data/js_protocol.json"],
];
const expectedSources = new Map([
  ["browser", { domains: 48, commands: 583, events: 214, types: 584 }],
  ["js", { domains: 6, commands: 81, events: 22, types: 48 }],
]);

if (helpMode) {
  console.log([
    "Usage: node tools/gen_protocol_manifest.mjs [--check]",
    "",
    "Inputs:",
    "  protocol/data/browser_protocol.json",
    "  protocol/data/js_protocol.json",
    "",
    "Outputs:",
    "  protocol/manifest_generated.mbt",
    "  protocol/typed_generated_index.mbt",
    "  protocol/typed_generated_<domain>.mbt",
    "",
    "Default mode rewrites generated files. --check verifies schema counts and",
    "generated file stability without writing files.",
  ].join("\n"));
  process.exit(0);
}

for (const arg of args) {
  if (arg !== "--check") {
    console.error(`unknown option: ${arg}`);
    process.exit(2);
  }
}

function q(value) {
  return JSON.stringify(value);
}

function count(domain, key) {
  return Array.isArray(domain[key]) ? domain[key].length : 0;
}

function bool(value) {
  return value ? "true" : "false";
}

function typeKind(type) {
  if (typeof type.type === "string") return type.type;
  if (typeof type.$ref === "string") return "ref";
  return "any";
}

function valueKind(value) {
  if (!value) return "any";
  if (typeof value.$ref === "string") return value.$ref;
  if (value.type === "array") return `array<${valueKind(value.items)}>`;
  if (typeof value.type === "string") return value.type;
  return "any";
}

function fieldSummary(field) {
  const optional = field.optional ? "?" : "";
  return `${field.name}${optional}:${valueKind(field)}`;
}

function fieldSummaries(owner, key) {
  return (owner[key] ?? []).map(fieldSummary);
}

function fieldDetails(owner, key, inheritedExperimental = false, inheritedDeprecated = false) {
  return (owner[key] ?? []).map((field) => ({
    name: field.name,
    kind: valueKind(field),
    optional: Boolean(field.optional),
    experimental: Boolean(inheritedExperimental || field.experimental),
    deprecated: Boolean(inheritedDeprecated || field.deprecated),
  }));
}

function stringArray(values) {
  return `[${values.map(q).join(", ")}]`;
}

function fieldDetailsArray(values) {
  return `[${values.map((field) =>
    `{ name: ${q(field.name)}, kind: ${q(field.kind)}, optional: ${bool(field.optional)}, ` +
    `experimental: ${bool(field.experimental)}, deprecated: ${bool(field.deprecated)} }`
  ).join(", ")}]`;
}

function fail(message) {
  console.error(`protocol generator check failed: ${message}`);
  process.exitCode = 1;
}

const protocols = sources.map(([name, relative]) => {
  const path = join(root, relative);
  const text = readFileSync(path, "utf8");
  const data = JSON.parse(text);
  const source = {
    protocol: name,
    path: relative.replaceAll("\\", "/"),
    sha256: createHash("sha256").update(text).digest("hex"),
    byteCount: Buffer.byteLength(text, "utf8"),
    domainCount: data.domains.length,
    commandCount: data.domains.reduce((sum, domain) => sum + count(domain, "commands"), 0),
    eventCount: data.domains.reduce((sum, domain) => sum + count(domain, "events"), 0),
    typeCount: data.domains.reduce((sum, domain) => sum + count(domain, "types"), 0),
  };
  return [name, data, source];
});

const sourceSummaries = protocols.map(([, , source]) => source);
const outputFiles = new Map();

const version = protocols[0][1].version;
const domains = protocols.flatMap(([protocol, data]) =>
  data.domains.map((domain) => ({
    protocol,
    domain: domain.domain,
    commandCount: count(domain, "commands"),
    eventCount: count(domain, "events"),
    typeCount: count(domain, "types"),
    experimental: Boolean(domain.experimental),
    deprecated: Boolean(domain.deprecated),
  })),
);

domains.sort((a, b) =>
  a.domain === b.domain
    ? a.protocol.localeCompare(b.protocol)
    : a.domain.localeCompare(b.domain),
);

const commands = [];
const events = [];
const types = [];
const typeKinds = new Map();
const typeDefinitions = new Map();

for (const [protocol, data] of protocols) {
  for (const domain of data.domains) {
    const domainExperimental = Boolean(domain.experimental);
    const domainDeprecated = Boolean(domain.deprecated);
    for (const command of domain.commands ?? []) {
      const commandExperimental = Boolean(command.experimental || domainExperimental);
      const commandDeprecated = Boolean(command.deprecated || domainDeprecated);
      commands.push({
        protocol,
        domain: domain.domain,
        name: command.name,
        cdpMethod: `${domain.domain}.${command.name}`,
        parameterCount: count(command, "parameters"),
        returnCount: count(command, "returns"),
        parameters: fieldSummaries(command, "parameters"),
        returns: fieldSummaries(command, "returns"),
        parameterDetails: fieldDetails(command, "parameters", commandExperimental, commandDeprecated),
        returnDetails: fieldDetails(command, "returns", commandExperimental, commandDeprecated),
        experimental: commandExperimental,
        deprecated: commandDeprecated,
      });
    }
    for (const event of domain.events ?? []) {
      const eventExperimental = Boolean(event.experimental || domainExperimental);
      const eventDeprecated = Boolean(event.deprecated || domainDeprecated);
      events.push({
        protocol,
        domain: domain.domain,
        name: event.name,
        cdpMethod: `${domain.domain}.${event.name}`,
        parameterCount: count(event, "parameters"),
        parameters: fieldSummaries(event, "parameters"),
        parameterDetails: fieldDetails(event, "parameters", eventExperimental, eventDeprecated),
        experimental: eventExperimental,
        deprecated: eventDeprecated,
      });
    }
    for (const type of domain.types ?? []) {
      const typeExperimental = Boolean(type.experimental || domainExperimental);
      const typeDeprecated = Boolean(type.deprecated || domainDeprecated);
      const generatedType = {
        protocol,
        domain: domain.domain,
        name: type.id,
        kind: typeKind(type),
        propertyCount: count(type, "properties"),
        enumCount: count(type, "enum"),
        properties: fieldSummaries(type, "properties"),
        propertyDetails: fieldDetails(type, "properties", typeExperimental, typeDeprecated),
        enumValues: type.enum ?? [],
        experimental: typeExperimental,
        deprecated: typeDeprecated,
      };
      types.push(generatedType);
      typeKinds.set(`${domain.domain}.${type.id}`, generatedType.kind);
      typeDefinitions.set(`${domain.domain}.${type.id}`, {
        domain: domain.domain,
        ...type,
      });
    }
  }
}

function byDomainName(a, b) {
  return a.domain === b.domain
    ? a.name === b.name
      ? a.protocol.localeCompare(b.protocol)
      : a.name.localeCompare(b.name)
    : a.domain.localeCompare(b.domain);
}

commands.sort(byDomainName);
events.sort(byDomainName);
types.sort(byDomainName);

const lines = [
  "///|",
  "// Generated by tools/gen_protocol_manifest.mjs. Do not edit by hand.",
  "pub fn protocol_manifest() -> ProtocolManifest {",
  "  {",
  `    version: { major: ${q(version.major)}, minor: ${q(version.minor)} },`,
  "    sources: [",
];

for (const source of sourceSummaries) {
  lines.push(
    "      { " +
      `protocol: ${q(source.protocol)}, ` +
      `path: ${q(source.path)}, ` +
      `sha256: ${q(source.sha256)}, ` +
      `byte_count: ${source.byteCount}, ` +
      `domain_count: ${source.domainCount}, ` +
      `command_count: ${source.commandCount}, ` +
      `event_count: ${source.eventCount}, ` +
      `type_count: ${source.typeCount}` +
      " },",
  );
}

lines.push(
  "    ],",
  "    domains: [",
);

for (const domain of domains) {
  lines.push(
    "      { " +
      `protocol: ${q(domain.protocol)}, ` +
      `domain: ${q(domain.domain)}, ` +
      `command_count: ${domain.commandCount}, ` +
      `event_count: ${domain.eventCount}, ` +
      `type_count: ${domain.typeCount}, ` +
      `experimental: ${bool(domain.experimental)}, ` +
      `deprecated: ${bool(domain.deprecated)}` +
      " },",
  );
}

lines.push("    ],", "  }", "}", "");

lines.push(
  "///|",
  "pub fn protocol_commands() -> Array[ProtocolCommand] {",
  "  [",
);

for (const command of commands) {
  lines.push(
    "    { " +
      `protocol: ${q(command.protocol)}, ` +
      `domain: ${q(command.domain)}, ` +
      `name: ${q(command.name)}, ` +
      `cdp_method: ${q(command.cdpMethod)}, ` +
      `parameter_count: ${command.parameterCount}, ` +
      `return_count: ${command.returnCount}, ` +
      `parameters: ${stringArray(command.parameters)}, ` +
      `returns: ${stringArray(command.returns)}, ` +
      `parameter_details: ${fieldDetailsArray(command.parameterDetails)}, ` +
      `return_details: ${fieldDetailsArray(command.returnDetails)}, ` +
      `experimental: ${bool(command.experimental)}, ` +
      `deprecated: ${bool(command.deprecated)}` +
      " },",
  );
}

lines.push("  ]", "}", "");

lines.push(
  "///|",
  "pub fn protocol_events() -> Array[ProtocolEvent] {",
  "  [",
);

for (const event of events) {
  lines.push(
    "    { " +
      `protocol: ${q(event.protocol)}, ` +
      `domain: ${q(event.domain)}, ` +
      `name: ${q(event.name)}, ` +
      `cdp_method: ${q(event.cdpMethod)}, ` +
      `parameter_count: ${event.parameterCount}, ` +
      `parameters: ${stringArray(event.parameters)}, ` +
      `parameter_details: ${fieldDetailsArray(event.parameterDetails)}, ` +
      `experimental: ${bool(event.experimental)}, ` +
      `deprecated: ${bool(event.deprecated)}` +
      " },",
  );
}

lines.push("  ]", "}", "");

lines.push(
  "///|",
  "pub fn protocol_types() -> Array[ProtocolType] {",
  "  [",
);

for (const type of types) {
  lines.push(
    "    { " +
      `protocol: ${q(type.protocol)}, ` +
      `domain: ${q(type.domain)}, ` +
      `name: ${q(type.name)}, ` +
      `kind: ${q(type.kind)}, ` +
      `property_count: ${type.propertyCount}, ` +
      `enum_count: ${type.enumCount}, ` +
      `properties: ${stringArray(type.properties)}, ` +
      `property_details: ${fieldDetailsArray(type.propertyDetails)}, ` +
      `enum_values: ${stringArray(type.enumValues)}, ` +
      `experimental: ${bool(type.experimental)}, ` +
      `deprecated: ${bool(type.deprecated)}` +
      " },",
  );
}

lines.push("  ]", "}", "");

outputFiles.set("protocol/manifest_generated.mbt", lines.join("\n"));

const reserved = new Set([
  "as",
  "async",
  "break",
  "catch",
  "continue",
  "else",
  "enum",
  "false",
  "fn",
  "for",
  "if",
  "in",
  "is",
  "let",
  "loop",
  "match",
  "mut",
  "method",
  "override",
  "priv",
  "pub",
  "raise",
  "return",
  "self",
  "struct",
  "true",
  "try",
  "type",
  "while",
]);

function words(value) {
  return String(value)
    .replace(/([a-z0-9])([A-Z])/g, "$1_$2")
    .replace(/[^A-Za-z0-9]+/g, "_")
    .split("_")
    .filter(Boolean);
}

function pascal(value) {
  return words(value)
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join("");
}

function snake(value) {
  const name = words(value)
    .map((word) => word.toLowerCase())
    .join("_");
  if (!name) return "value";
  return reserved.has(name) ? `${name}_` : name;
}

function methodName(domain, name) {
  return `${domain}.${name}`;
}

function typeKeyForRef(domain, ref) {
  return ref.includes(".") ? ref : `${domain}.${ref}`;
}

function typeNameForRef(domain, ref) {
  const key = typeKeyForRef(domain, ref);
  const type = typeDefinitions.get(key);
  return type ? domainTypeName(type.domain, type.id) : undefined;
}

function typeNameForField(domain, field, useRefs = false) {
  if (useRefs && typeof field.$ref === "string") {
    return typeNameForRef(domain, field.$ref) ?? moonType(domain, valueKind(field));
  }
  if (useRefs && field.type === "array") {
    const itemType = arrayItemType(domain, field.items, useRefs, field);
    if (itemType) return `Array[${itemType}]`;
  }
  return moonType(domain, valueKind(field));
}

function arrayItemType(domain, item, useRefs, field = undefined) {
  if (!item) return undefined;
  if (useRefs && typeof item.$ref === "string") {
    return typeNameForRef(domain, item.$ref);
  }
  if (useRefs && item.type === "object" && field?.anonymous_item_name) {
    return field.anonymous_item_name;
  }
  switch (item.type) {
    case "string":
    case "binary":
      return "String";
    case "integer":
      return "Int";
    case "number":
      return "Double";
    case "boolean":
      return "Bool";
    default:
      return undefined;
  }
}

function moonType(domain, kind) {
  if (kind.startsWith("array<")) return "Json";
  switch (kind) {
    case "string":
    case "binary":
      return "String";
    case "integer":
      return "Int";
    case "number":
      return "Double";
    case "boolean":
      return "Bool";
    case "object":
    case "any":
      return "Json";
    default: {
      const resolved = resolveKind(domain, kind);
      if (resolved === kind) return "Json";
      return moonType(domain, resolved);
    }
  }
}

function resolveKind(domain, kind) {
  if (kind.includes(".")) return typeKinds.get(kind) ?? kind;
  return typeKinds.get(`${domain}.${kind}`) ?? kind;
}

function fieldType(domain, field, useRefs = false) {
  const base = typeNameForField(domain, field, useRefs);
  return field.optional ? `${base}?` : base;
}

function jsonExpr(type, value, useToJson = false) {
  if (useToJson) return `${value}.to_json()`;
  switch (type) {
    case "String":
      return `Json::string(${value})`;
    case "Int":
      return `Json::number(${value}.to_double())`;
    case "Double":
      return `Json::number(${value})`;
    case "Bool":
      return `Json::boolean(${value})`;
    default:
      return value;
  }
}

function fieldJsonExpr(field, value, useRefs = false) {
  if (useRefs && field.type === "array") {
    const itemType = arrayItemType(field.domain, field.items, useRefs, field);
    if (itemType) {
      const itemUseToJson = typeof field.items?.$ref === "string" ||
        Boolean(field.anonymous_item_name);
      return `Json::array(${value}.map(item => ${jsonExpr(
        itemType,
        "item",
        itemUseToJson,
      )}))`;
    }
  }
  const baseType = typeNameForField(field.domain, field, useRefs);
  const useToJson = useRefs && typeof field.$ref === "string";
  return jsonExpr(baseType, value, useToJson);
}

function structName(domain, name, suffix) {
  return `${pascal(domain)}${pascal(name)}${suffix}`;
}

function commandBuilderName(domain, name) {
  return `${snake(domain)}_${snake(name)}_command`;
}

function eventBuilderName(domain, name) {
  return `${snake(domain)}_${snake(name)}_event`;
}

function domainTypeName(domain, name) {
  return `${pascal(domain)}${pascal(name)}`;
}

function anonymousArrayItemName(domain, owner, field) {
  return `${pascal(domain)}${pascal(owner)}${pascal(field.name)}Item`;
}

function annotateAnonymousArrayItems(domain, owner, fields) {
  return fields.map(field => {
    if (
      field.type === "array" &&
      field.items?.type === "object" &&
      !field.items.properties
    ) {
      return {
        ...field,
        anonymous_item_name: anonymousArrayItemName(domain, owner, field),
      };
    }
    return field;
  });
}

function emitAnonymousArrayItem(out, name) {
  out.push(
    "///|",
    `pub(all) struct ${name} {`,
    "  value : Json",
    "} derive(Eq, Debug)",
    "",
    "///|",
    `pub fn ${name}::to_json(self : ${name}) -> Json {`,
    "  self.value",
    "}",
    "",
    "///|",
    `pub fn ${name}::from_json(value : Json) -> ${name} {`,
    "  { value, }",
    "}",
    "",
  );
}

function emitAnonymousArrayItems(out, fields) {
  const emitted = new Set();
  for (const field of fields) {
    if (field.anonymous_item_name && !emitted.has(field.anonymous_item_name)) {
      emitAnonymousArrayItem(out, field.anonymous_item_name);
      emitted.add(field.anonymous_item_name);
    }
  }
}

function emitStruct(out, name, fields, useRefs = false) {
  out.push("///|", `pub(all) struct ${name} {`);
  for (const field of fields) {
    out.push(
      `  ${snake(field.name)} : ${fieldType(field.domain, field, useRefs)}`,
    );
  }
  out.push("} derive(Eq, Debug)", "");
}

function emitToJson(out, structNameValue, fields, options = {}) {
  const { transparent = false, useRefs = false } = options;
  out.push(
    "///|",
    `pub fn ${structNameValue}::to_json(self : ${structNameValue}) -> Json {`,
  );
  if (transparent) {
    const field = fields[0];
    const name = snake(field.name);
    out.push(
      `  ${fieldJsonExpr(field, `self.${name}`, useRefs)}`,
      "}",
      "",
    );
    return;
  }
  out.push("  let fields : Map[String, Json] = {}");
  for (const field of fields) {
    const name = snake(field.name);
    if (field.optional) {
      out.push(
        `  if self.${name} is Some(value) {`,
        `    fields[${q(field.name)}] = ${fieldJsonExpr(field, "value", useRefs)}`,
        "  }",
      );
    } else {
      out.push(
        `  fields[${q(field.name)}] = ${fieldJsonExpr(
          field,
          `self.${name}`,
          useRefs,
        )}`,
      );
    }
  }
  out.push("  Json::object(fields)", "}", "");
}

function refDecodeExpr(field, valueExpr) {
  if (typeof field.$ref !== "string") return undefined;
  const typeName = typeNameForRef(field.domain, field.$ref);
  return typeName ? `${typeName}::from_json(${valueExpr})` : undefined;
}

function arrayItemDecodeExpr(domain, item, valueExpr, methodNameExpr, fieldName, expected, result = false) {
  if (typeof item?.$ref === "string") {
    const typeName = typeNameForRef(domain, item.$ref);
    if (typeName) return `${typeName}::from_json(${valueExpr})`;
  }
  if (item?.anonymous_item_name) {
    return `${item.anonymous_item_name}::from_json(${valueExpr})`;
  }
  const prefix = result ? "typed_result_array" : "typed_array";
  switch (item?.type) {
    case "string":
    case "binary":
      return `${prefix}_string(${methodNameExpr}, ${fieldName}, ${expected}, ${valueExpr})`;
    case "integer":
      return `${prefix}_int(${methodNameExpr}, ${fieldName}, ${expected}, ${valueExpr})`;
    case "number":
      return `${prefix}_double(${methodNameExpr}, ${fieldName}, ${expected}, ${valueExpr})`;
    case "boolean":
      return `${prefix}_bool(${methodNameExpr}, ${fieldName}, ${expected}, ${valueExpr})`;
    default:
      return valueExpr;
  }
}

function decodeArrayExpr(field, result = false, directValue = undefined) {
  const itemType = arrayItemType(field.domain, field.items, true, field);
  if (!itemType) return undefined;
  const name = q(field.name);
  const expected = q(valueKind(field));
  const requiredJson = directValue ?? (result
    ? `typed_required_result_json(method_name, fields, ${name})`
    : `typed_required_json(method_name, fields, ${name})`);
  const optionalJson = result
    ? `typed_optional_result_json(fields, ${name})`
    : `typed_optional_json(fields, ${name})`;
  const arrayHelper = result ? "typed_result_array" : "typed_param_array";
  const itemExpr = arrayItemDecodeExpr(
    field.domain,
    field.anonymous_item_name
      ? { ...field.items, anonymous_item_name: field.anonymous_item_name }
      : field.items,
    "item",
    "method_name",
    name,
    expected,
    result,
  );
  const decodeItems = value =>
    `${arrayHelper}(method_name, ${value}, ${name}, ${expected}).map(item => ${itemExpr})`;
  return !directValue && field.optional
    ? `match ${optionalJson} { Some(value) => Some(${decodeItems("value")}); None => None }`
    : decodeItems(requiredJson);
}

function decodeExpr(field, useRefs = false) {
  const name = q(field.name);
  const expected = q(valueKind(field));
  if (useRefs && field.type === "array") {
    const arrayExpr = decodeArrayExpr(field, false);
    if (arrayExpr) return arrayExpr;
  }
  if (useRefs && typeof field.$ref === "string") {
    const refExpr = refDecodeExpr(field, "value");
    if (refExpr) {
      return field.optional
        ? `match typed_optional_json(fields, ${name}) { Some(value) => Some(${refExpr}); None => None }`
        : refDecodeExpr(field, `typed_required_json(method_name, fields, ${name})`);
    }
  }
  const baseType = typeNameForField(field.domain, field, useRefs);
  const prefix = field.optional ? "typed_optional" : "typed_required";
  switch (baseType) {
    case "String":
      return `${prefix}_string(method_name, fields, ${name}, ${expected})`;
    case "Int":
      return `${prefix}_int(method_name, fields, ${name}, ${expected})`;
    case "Double":
      return `${prefix}_double(method_name, fields, ${name}, ${expected})`;
    case "Bool":
      return `${prefix}_bool(method_name, fields, ${name}, ${expected})`;
    default:
      return field.optional
        ? `typed_optional_json(fields, ${name})`
        : `typed_required_json(method_name, fields, ${name})`;
  }
}

function decodeResultExpr(field, useRefs = false) {
  const name = q(field.name);
  const expected = q(valueKind(field));
  if (useRefs && field.type === "array") {
    const arrayExpr = decodeArrayExpr(field, true);
    if (arrayExpr) return arrayExpr;
  }
  if (useRefs && typeof field.$ref === "string") {
    const refExpr = refDecodeExpr(field, "value");
    if (refExpr) {
      return field.optional
        ? `match typed_optional_result_json(fields, ${name}) { Some(value) => Some(${refExpr}); None => None }`
        : refDecodeExpr(
          field,
          `typed_required_result_json(method_name, fields, ${name})`,
        );
    }
  }
  const baseType = typeNameForField(field.domain, field, useRefs);
  const prefix = field.optional
    ? "typed_optional_result"
    : "typed_required_result";
  switch (baseType) {
    case "String":
      return `${prefix}_string(method_name, fields, ${name}, ${expected})`;
    case "Int":
      return `${prefix}_int(method_name, fields, ${name}, ${expected})`;
    case "Double":
      return `${prefix}_double(method_name, fields, ${name}, ${expected})`;
    case "Bool":
      return `${prefix}_bool(method_name, fields, ${name}, ${expected})`;
    default:
      return field.optional
        ? `typed_optional_result_json(fields, ${name})`
        : `typed_required_result_json(method_name, fields, ${name})`;
  }
}

function emitFromJson(out, structNameValue, methodNameValue, fields, useRefs = false) {
  out.push(
    "///|",
    `pub fn ${structNameValue}::from_json(`,
    "  params : Json,",
    `) -> ${structNameValue} raise ProtocolSchemaError {`,
    `  let method_name = ${q(methodNameValue)}`,
    "  ignore(cdp_schema_event(method_name~, params=params))",
    "  let fields = typed_json_fields(method_name, params)",
    "  {",
  );
  for (const field of fields) {
    out.push(`    ${snake(field.name)}: ${decodeExpr(field, useRefs)},`);
  }
  out.push("  }", "}", "");
}

function emitResultFromJson(
  out,
  structNameValue,
  methodNameValue,
  fields,
  useRefs = false,
) {
  out.push(
    "///|",
    `pub fn ${structNameValue}::from_json(`,
    "  result : Json,",
    `) -> ${structNameValue} raise ProtocolSchemaError {`,
    `  let method_name = ${q(methodNameValue)}`,
    "  let response : CdpResponseMessage = {",
    "    id: 0,",
    "    result: Some(result),",
    "    error: None,",
    "    session_id: None,",
    "  }",
    "  ignore(cdp_schema_response(method_name~, response))",
    "  let fields = typed_result_fields(method_name, result)",
    "  {",
  );
  for (const field of fields) {
    out.push(`    ${snake(field.name)}: ${decodeResultExpr(field, useRefs)},`);
  }
  out.push("  }", "}", "");
}

function emitDomainTypeFromJson(
  out,
  structNameValue,
  fields,
  transparent,
  useRefs = false,
) {
  const transparentBaseType = transparent
    ? typeNameForField(fields[0].domain, fields[0])
    : undefined;
  const transparentArrayRaises = transparent &&
    fields[0].type === "array" &&
    arrayItemType(fields[0].domain, fields[0].items, useRefs);
  const canRaise = !transparent ||
    transparentArrayRaises ||
    ["String", "Int", "Double", "Bool"].includes(transparentBaseType);
  out.push(
    "///|",
    `pub fn ${structNameValue}::from_json(value : Json) -> ${structNameValue} raise ProtocolSchemaError {`,
  );
  if (!canRaise) {
    out.pop();
    out.push(
      `pub fn ${structNameValue}::from_json(value : Json) -> ${structNameValue} {`,
    );
  }
  if (canRaise) {
    out.push(`  let method_name = ${q(structNameValue)}`);
  }
  if (transparent) {
    const field = fields[0];
    const expected = q(valueKind(field));
    if (field.type === "array" && arrayItemType(field.domain, field.items, useRefs)) {
      out.push(`  { value: ${decodeArrayExpr(field, false, "value")} }`);
      out.push("}", "");
      return;
    }
    switch (transparentBaseType) {
      case "String":
        out.push(
          "  match value {",
          "    String(inner) => { value: inner }",
          "    _ => raise ProtocolSchemaError::InvalidParameterType(method_name, \"value\", " +
            expected +
            ")",
          "  }",
        );
        break;
      case "Int":
        out.push(
          "  match value {",
          "    Number(inner, ..) => {",
          "      let int = inner.to_int()",
          "      if int.to_double() == inner {",
          "        { value: int }",
          "      } else {",
          "        raise ProtocolSchemaError::InvalidParameterType(method_name, \"value\", " +
            expected +
            ")",
          "      }",
          "    }",
          "    _ => raise ProtocolSchemaError::InvalidParameterType(method_name, \"value\", " +
            expected +
            ")",
          "  }",
        );
        break;
      case "Double":
        out.push(
          "  match value {",
          "    Number(inner, ..) => { value: inner }",
          "    _ => raise ProtocolSchemaError::InvalidParameterType(method_name, \"value\", " +
            expected +
            ")",
          "  }",
        );
        break;
      case "Bool":
        out.push(
          "  match value {",
          "    True => { value: true }",
          "    False => { value: false }",
          "    _ => raise ProtocolSchemaError::InvalidParameterType(method_name, \"value\", " +
            expected +
            ")",
          "  }",
        );
        break;
      default:
        out.push("  { value, }");
        break;
    }
  } else {
    out.push("  let fields = typed_json_fields(method_name, value)", "  {");
    for (const field of fields) {
      out.push(`    ${snake(field.name)}: ${decodeExpr(field, useRefs)},`);
    }
    out.push("  }");
  }
  out.push("}", "");
}

function annotateFields(domain, fields) {
  return (fields ?? []).map((field) => ({ ...field, domain }));
}

function domainTypeFields(type) {
  if (type.kind === "object" && type.original?.properties?.length > 0) {
    return annotateFields(type.domain, type.original.properties);
  }
  return [
    {
      name: "value",
      domain: type.domain,
      type: type.original?.type,
      $ref: type.original?.$ref,
      items: type.original?.items,
    },
  ];
}

const typed = [
  "///|",
  "// Generated by tools/gen_protocol_manifest.mjs. Do not edit by hand.",
  "",
  "///|",
  `pub fn protocol_typed_command_builder_count() -> Int { ${commands.length} }`,
  "",
  "///|",
  `pub fn protocol_typed_command_params_count() -> Int { ${
    commands.filter((command) => {
      const original = protocols
        .flatMap(([, data]) => data.domains)
        .find((domain) => domain.domain === command.domain)
        ?.commands?.find((item) => item.name === command.name);
      return (original?.parameters ?? []).length > 0;
    }).length
  } }`,
  "",
  "///|",
  `pub fn protocol_typed_command_result_count() -> Int { ${
    commands.filter((command) => {
      const original = protocols
        .flatMap(([, data]) => data.domains)
        .find((domain) => domain.domain === command.domain)
        ?.commands?.find((item) => item.name === command.name);
      return (original?.returns ?? []).length > 0;
    }).length
  } }`,
  "",
  "///|",
  `pub fn protocol_typed_command_result_decoder_count() -> Int { ${
    commands.filter((command) => {
      const original = protocols
        .flatMap(([, data]) => data.domains)
        .find((domain) => domain.domain === command.domain)
        ?.commands?.find((item) => item.name === command.name);
      return (original?.returns ?? []).length > 0;
    }).length
  } }`,
  "",
  "///|",
  `pub fn protocol_typed_event_builder_count() -> Int { ${events.length} }`,
  "",
  "///|",
  `pub fn protocol_typed_event_params_count() -> Int { ${
    events.filter((event) => {
      const original = protocols
        .flatMap(([, data]) => data.domains)
        .find((domain) => domain.domain === event.domain)
        ?.events?.find((item) => item.name === event.name);
      return (original?.parameters ?? []).length > 0;
    }).length
  } }`,
  "",
  "///|",
  `pub fn protocol_typed_event_decoder_count() -> Int { ${
    events.filter((event) => {
      const original = protocols
        .flatMap(([, data]) => data.domains)
        .find((domain) => domain.domain === event.domain)
        ?.events?.find((item) => item.name === event.name);
      return (original?.parameters ?? []).length > 0;
    }).length
  } }`,
  "",
  "///|",
  `pub fn protocol_typed_domain_type_count() -> Int { ${types.length} }`,
  "",
];

function typedDomainFileName(domain) {
  return `typed_generated_${snake(domain)}.mbt`;
}

const typedByDomain = new Map();

function typedLinesForDomain(domain) {
  if (!typedByDomain.has(domain)) {
    typedByDomain.set(domain, [
      "///|",
      "// Generated by tools/gen_protocol_manifest.mjs. Do not edit by hand.",
      "",
    ]);
  }
  return typedByDomain.get(domain);
}

for (const type of types) {
  const original = protocols
    .flatMap(([, data]) => data.domains)
    .find((domain) => domain.domain === type.domain)
    ?.types?.find((item) => item.id === type.name);
  const typeWithOriginal = { ...type, original };
  const generatedName = domainTypeName(type.domain, type.name);
  const fields = domainTypeFields(typeWithOriginal);
  const transparent = !(type.kind === "object" && original?.properties?.length > 0);
  const out = typedLinesForDomain(type.domain);
  emitStruct(out, generatedName, fields, true);
  emitToJson(out, generatedName, fields, { transparent, useRefs: true });
  emitDomainTypeFromJson(out, generatedName, fields, transparent, true);
}

for (const command of commands) {
  const original = protocols
    .flatMap(([, data]) => data.domains)
    .find((domain) => domain.domain === command.domain)
    ?.commands?.find((item) => item.name === command.name);
  const params = annotateAnonymousArrayItems(
    command.domain,
    `${command.name}Params`,
    annotateFields(command.domain, original?.parameters ?? []),
  );
  const returns = annotateAnonymousArrayItems(
    command.domain,
    `${command.name}Result`,
    annotateFields(command.domain, original?.returns ?? []),
  );
  const paramsName = structName(command.domain, command.name, "Params");
  const resultName = structName(command.domain, command.name, "Result");
  const out = typedLinesForDomain(command.domain);
  if (params.length > 0) {
    emitAnonymousArrayItems(out, params);
    emitStruct(out, paramsName, params, true);
    emitToJson(out, paramsName, params, { useRefs: true });
  }
  if (returns.length > 0) {
    emitAnonymousArrayItems(out, returns);
    emitStruct(out, resultName, returns, true);
    emitResultFromJson(
      out,
      resultName,
      methodName(command.domain, command.name),
      returns,
      true,
    );
  }
  out.push("///|");
  if (params.length > 0) {
    out.push(
      `pub fn ${commandBuilderName(command.domain, command.name)}(`,
      "  id~ : Int,",
      `  params : ${paramsName},`,
      "  session_id? : String,",
      ") -> CdpCommandMessage raise ProtocolSchemaError {",
      "  cdp_schema_command(",
      "    id~,",
      `    method_name=${q(methodName(command.domain, command.name))},`,
      "    params=params.to_json(),",
      "    session_id?,",
      "  )",
      "}",
      "",
    );
  } else {
    out.push(
      `pub fn ${commandBuilderName(command.domain, command.name)}(`,
      "  id~ : Int,",
      "  session_id? : String,",
      ") -> CdpCommandMessage raise ProtocolSchemaError {",
      "  cdp_schema_command(",
      "    id~,",
      `    method_name=${q(methodName(command.domain, command.name))},`,
      "    session_id?,",
      "  )",
      "}",
      "",
    );
  }
}

for (const event of events) {
  const original = protocols
    .flatMap(([, data]) => data.domains)
    .find((domain) => domain.domain === event.domain)
    ?.events?.find((item) => item.name === event.name);
  const params = annotateAnonymousArrayItems(
    event.domain,
    `${event.name}EventParams`,
    annotateFields(event.domain, original?.parameters ?? []),
  );
  const paramsName = structName(event.domain, event.name, "EventParams");
  const out = typedLinesForDomain(event.domain);
  if (params.length > 0) {
    emitAnonymousArrayItems(out, params);
    emitStruct(out, paramsName, params, true);
    emitToJson(out, paramsName, params, { useRefs: true });
    emitFromJson(out, paramsName, methodName(event.domain, event.name), params, true);
  }
  out.push("///|");
  if (params.length > 0) {
    out.push(
      `pub fn ${eventBuilderName(event.domain, event.name)}(`,
      `  params : ${paramsName},`,
      "  session_id? : String,",
      ") -> CdpEventMessage raise ProtocolSchemaError {",
      "  cdp_schema_event(",
      `    method_name=${q(methodName(event.domain, event.name))},`,
      "    params=params.to_json(),",
      "    session_id?,",
      "  )",
      "}",
      "",
    );
  } else {
    out.push(
      `pub fn ${eventBuilderName(event.domain, event.name)}(`,
      "  session_id? : String,",
      ") -> CdpEventMessage raise ProtocolSchemaError {",
      "  cdp_schema_event(",
      `    method_name=${q(methodName(event.domain, event.name))},`,
      "    session_id?,",
      "  )",
      "}",
      "",
    );
  }
}

outputFiles.set("protocol/typed_generated_index.mbt", typed.join("\n"));
for (const [domain, domainLines] of typedByDomain) {
  outputFiles.set(
    `protocol/${typedDomainFileName(domain)}`,
    domainLines.join("\n"),
  );
}

run();

function run() {
  let ok = true;
  ok = validateSourceCounts() && ok;
  ok = validateGeneratedCounts() && ok;
  printSummary();
  if (checkMode) {
    ok = validateGeneratedFiles(formatOutputFiles()) && ok;
    if (!ok) process.exit(1);
    console.log("protocol generator check: ok");
    return;
  }
  writeGeneratedFiles();
}

function validateSourceCounts() {
  let ok = true;
  for (const source of sourceSummaries) {
    const expected = expectedSources.get(source.protocol);
    if (!expected) {
      fail(`missing expected counts for ${source.protocol}`);
      ok = false;
      continue;
    }
    if (source.domainCount !== expected.domains) {
      fail(`${source.protocol} domain count ${source.domainCount} != ${expected.domains}`);
      ok = false;
    }
    if (source.commandCount !== expected.commands) {
      fail(`${source.protocol} command count ${source.commandCount} != ${expected.commands}`);
      ok = false;
    }
    if (source.eventCount !== expected.events) {
      fail(`${source.protocol} event count ${source.eventCount} != ${expected.events}`);
      ok = false;
    }
    if (source.typeCount !== expected.types) {
      fail(`${source.protocol} type count ${source.typeCount} != ${expected.types}`);
      ok = false;
    }
  }
  return ok;
}

function validateGeneratedCounts() {
  const totals = sourceSummaries.reduce((acc, source) => ({
    domains: acc.domains + source.domainCount,
    commands: acc.commands + source.commandCount,
    events: acc.events + source.eventCount,
    types: acc.types + source.typeCount,
  }), { domains: 0, commands: 0, events: 0, types: 0 });
  let ok = true;
  if (domains.length !== totals.domains) {
    fail(`generated domain count ${domains.length} != ${totals.domains}`);
    ok = false;
  }
  if (commands.length !== totals.commands) {
    fail(`generated command count ${commands.length} != ${totals.commands}`);
    ok = false;
  }
  if (events.length !== totals.events) {
    fail(`generated event count ${events.length} != ${totals.events}`);
    ok = false;
  }
  if (types.length !== totals.types) {
    fail(`generated type count ${types.length} != ${totals.types}`);
    ok = false;
  }
  return ok;
}

function printSummary() {
  for (const source of sourceSummaries) {
    console.log(
      `${source.protocol}: domains=${source.domainCount} commands=${source.commandCount} ` +
      `events=${source.eventCount} types=${source.typeCount} sha256=${source.sha256}`,
    );
  }
  console.log(
    `total: domains=${domains.length} commands=${commands.length} ` +
    `events=${events.length} types=${types.length}`,
  );
}

function validateGeneratedFiles(expectedFiles) {
  let ok = true;
  for (const [relative, content] of expectedFiles) {
    const path = join(root, relative);
    let current;
    try {
      current = readFileSync(path, "utf8");
    } catch {
      fail(`missing generated file ${relative}`);
      ok = false;
      continue;
    }
    if (current !== content) {
      fail(`generated file is stale: ${relative}`);
      ok = false;
    }
  }
  const expectedTypedFiles = new Set(
    [...outputFiles.keys()].filter(file => file.startsWith("protocol/typed_generated")),
  );
  for (const file of readdirSync(join(root, "protocol"))) {
    if (/^typed_generated(?:_|\.mbt)/.test(file)) {
      const relative = `protocol/${file}`;
      if (!expectedTypedFiles.has(relative)) {
        fail(`unexpected generated file ${relative}`);
        ok = false;
      }
    }
  }
  return ok;
}

function formatOutputFiles() {
  const entries = [...outputFiles.entries()];
  const tempFiles = entries.map(([relative], index) => {
    const suffix = relative
      .replace(/^protocol\//, "")
      .replace(/[^A-Za-z0-9_]+/g, "_");
    return join(root, "protocol", `__protocol_generator_check_${index}_${suffix}.mbt`);
  });
  try {
    for (let index = 0; index < entries.length; index += 1) {
      writeFileSync(tempFiles[index], entries[index][1]);
    }
    const result = spawnSync("moon", ["fmt", ...tempFiles], {
      cwd: root,
      encoding: "utf8",
    });
    if (result.status !== 0) {
      if (result.stdout) console.error(result.stdout.trimEnd());
      if (result.stderr) console.error(result.stderr.trimEnd());
      fail("moon fmt failed while formatting generated check output");
      process.exit(1);
    }
    const formatted = new Map();
    for (let index = 0; index < entries.length; index += 1) {
      formatted.set(entries[index][0], readFileSync(tempFiles[index], "utf8"));
    }
    return formatted;
  } finally {
    for (const tempFile of tempFiles) {
      try {
        rmSync(tempFile);
      } catch {
        // Best-effort cleanup for check-only temporary formatter inputs.
      }
    }
  }
}

function writeGeneratedFiles() {
  for (const file of readdirSync(join(root, "protocol"))) {
    if (/^typed_generated(?:_|\.mbt)/.test(file)) {
      rmSync(join(root, "protocol", file));
    }
  }
  for (const [relative, content] of outputFiles) {
    writeFileSync(join(root, relative), content);
  }
}
