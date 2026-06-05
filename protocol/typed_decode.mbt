///|
fn typed_json_fields(
  method_name : String,
  params : Json,
) -> Map[String, Json] raise ProtocolSchemaError {
  guard params is Object(fields) else {
    raise ProtocolSchemaError::ExpectedParamsObject(method_name)
  }
  fields
}

///|
fn typed_required_json(
  method_name : String,
  fields : Map[String, Json],
  name : String,
) -> Json raise ProtocolSchemaError {
  match fields.get(name) {
    Some(value) => value
    None => raise ProtocolSchemaError::MissingParameter(method_name, name)
  }
}

///|
fn typed_optional_json(fields : Map[String, Json], name : String) -> Json? {
  match fields.get(name) {
    Some(Null) | None => None
    Some(value) => Some(value)
  }
}

///|
fn typed_required_string(
  method_name : String,
  fields : Map[String, Json],
  name : String,
  expected : String,
) -> String raise ProtocolSchemaError {
  match typed_required_json(method_name, fields, name) {
    String(value) => value
    _ =>
      raise ProtocolSchemaError::InvalidParameterType(
        method_name, name, expected,
      )
  }
}

///|
fn typed_optional_string(
  method_name : String,
  fields : Map[String, Json],
  name : String,
  expected : String,
) -> String? raise ProtocolSchemaError {
  match typed_optional_json(fields, name) {
    Some(String(value)) => Some(value)
    Some(_) =>
      raise ProtocolSchemaError::InvalidParameterType(
        method_name, name, expected,
      )
    None => None
  }
}

///|
fn typed_required_int(
  method_name : String,
  fields : Map[String, Json],
  name : String,
  expected : String,
) -> Int raise ProtocolSchemaError {
  match typed_required_json(method_name, fields, name) {
    Number(value, ..) => {
      let int = value.to_int()
      if int.to_double() == value {
        int
      } else {
        raise ProtocolSchemaError::InvalidParameterType(
          method_name, name, expected,
        )
      }
    }
    _ =>
      raise ProtocolSchemaError::InvalidParameterType(
        method_name, name, expected,
      )
  }
}

///|
fn typed_optional_int(
  method_name : String,
  fields : Map[String, Json],
  name : String,
  expected : String,
) -> Int? raise ProtocolSchemaError {
  match typed_optional_json(fields, name) {
    Some(Number(value, ..)) => {
      let int = value.to_int()
      if int.to_double() == value {
        Some(int)
      } else {
        raise ProtocolSchemaError::InvalidParameterType(
          method_name, name, expected,
        )
      }
    }
    Some(_) =>
      raise ProtocolSchemaError::InvalidParameterType(
        method_name, name, expected,
      )
    None => None
  }
}

///|
fn typed_required_double(
  method_name : String,
  fields : Map[String, Json],
  name : String,
  expected : String,
) -> Double raise ProtocolSchemaError {
  match typed_required_json(method_name, fields, name) {
    Number(value, ..) => value
    _ =>
      raise ProtocolSchemaError::InvalidParameterType(
        method_name, name, expected,
      )
  }
}

///|
fn typed_optional_double(
  method_name : String,
  fields : Map[String, Json],
  name : String,
  expected : String,
) -> Double? raise ProtocolSchemaError {
  match typed_optional_json(fields, name) {
    Some(Number(value, ..)) => Some(value)
    Some(_) =>
      raise ProtocolSchemaError::InvalidParameterType(
        method_name, name, expected,
      )
    None => None
  }
}

///|
fn typed_required_bool(
  method_name : String,
  fields : Map[String, Json],
  name : String,
  expected : String,
) -> Bool raise ProtocolSchemaError {
  match typed_required_json(method_name, fields, name) {
    True => true
    False => false
    _ =>
      raise ProtocolSchemaError::InvalidParameterType(
        method_name, name, expected,
      )
  }
}

///|
fn typed_optional_bool(
  method_name : String,
  fields : Map[String, Json],
  name : String,
  expected : String,
) -> Bool? raise ProtocolSchemaError {
  match typed_optional_json(fields, name) {
    Some(True) => Some(true)
    Some(False) => Some(false)
    Some(_) =>
      raise ProtocolSchemaError::InvalidParameterType(
        method_name, name, expected,
      )
    None => None
  }
}

///|
fn typed_param_array(
  method_name : String,
  value : Json,
  name : String,
  expected : String,
) -> Array[Json] raise ProtocolSchemaError {
  match value {
    Array(items) => items
    _ =>
      raise ProtocolSchemaError::InvalidParameterType(
        method_name, name, expected,
      )
  }
}

///|
fn typed_array_string(
  method_name : String,
  name : String,
  expected : String,
  value : Json,
) -> String raise ProtocolSchemaError {
  match value {
    String(inner) => inner
    _ =>
      raise ProtocolSchemaError::InvalidParameterType(
        method_name, name, expected,
      )
  }
}

///|
fn typed_array_int(
  method_name : String,
  name : String,
  expected : String,
  value : Json,
) -> Int raise ProtocolSchemaError {
  match value {
    Number(inner, ..) => {
      let int = inner.to_int()
      if int.to_double() == inner {
        int
      } else {
        raise ProtocolSchemaError::InvalidParameterType(
          method_name, name, expected,
        )
      }
    }
    _ =>
      raise ProtocolSchemaError::InvalidParameterType(
        method_name, name, expected,
      )
  }
}

///|
fn typed_array_double(
  method_name : String,
  name : String,
  expected : String,
  value : Json,
) -> Double raise ProtocolSchemaError {
  match value {
    Number(inner, ..) => inner
    _ =>
      raise ProtocolSchemaError::InvalidParameterType(
        method_name, name, expected,
      )
  }
}

///|
fn typed_result_fields(
  method_name : String,
  result : Json,
) -> Map[String, Json] raise ProtocolSchemaError {
  guard result is Object(fields) else {
    raise ProtocolSchemaError::ExpectedResultObject(method_name)
  }
  fields
}

///|
fn typed_required_result_json(
  method_name : String,
  fields : Map[String, Json],
  name : String,
) -> Json raise ProtocolSchemaError {
  match fields.get(name) {
    Some(value) => value
    None => raise ProtocolSchemaError::MissingReturn(method_name, name)
  }
}

///|
fn typed_optional_result_json(
  fields : Map[String, Json],
  name : String,
) -> Json? {
  match fields.get(name) {
    Some(Null) | None => None
    Some(value) => Some(value)
  }
}

///|
fn typed_required_result_string(
  method_name : String,
  fields : Map[String, Json],
  name : String,
  expected : String,
) -> String raise ProtocolSchemaError {
  match typed_required_result_json(method_name, fields, name) {
    String(value) => value
    _ =>
      raise ProtocolSchemaError::InvalidReturnType(method_name, name, expected)
  }
}

///|
fn typed_optional_result_string(
  method_name : String,
  fields : Map[String, Json],
  name : String,
  expected : String,
) -> String? raise ProtocolSchemaError {
  match typed_optional_result_json(fields, name) {
    Some(String(value)) => Some(value)
    Some(_) =>
      raise ProtocolSchemaError::InvalidReturnType(method_name, name, expected)
    None => None
  }
}

///|
fn typed_result_array(
  method_name : String,
  value : Json,
  name : String,
  expected : String,
) -> Array[Json] raise ProtocolSchemaError {
  match value {
    Array(items) => items
    _ =>
      raise ProtocolSchemaError::InvalidReturnType(method_name, name, expected)
  }
}

///|
fn typed_result_array_string(
  method_name : String,
  name : String,
  expected : String,
  value : Json,
) -> String raise ProtocolSchemaError {
  match value {
    String(inner) => inner
    _ =>
      raise ProtocolSchemaError::InvalidReturnType(method_name, name, expected)
  }
}

///|
fn typed_result_array_int(
  method_name : String,
  name : String,
  expected : String,
  value : Json,
) -> Int raise ProtocolSchemaError {
  match value {
    Number(inner, ..) => {
      let int = inner.to_int()
      if int.to_double() == inner {
        int
      } else {
        raise ProtocolSchemaError::InvalidReturnType(
          method_name, name, expected,
        )
      }
    }
    _ =>
      raise ProtocolSchemaError::InvalidReturnType(method_name, name, expected)
  }
}

///|
fn typed_required_result_int(
  method_name : String,
  fields : Map[String, Json],
  name : String,
  expected : String,
) -> Int raise ProtocolSchemaError {
  match typed_required_result_json(method_name, fields, name) {
    Number(value, ..) => {
      let int = value.to_int()
      if int.to_double() == value {
        int
      } else {
        raise ProtocolSchemaError::InvalidReturnType(
          method_name, name, expected,
        )
      }
    }
    _ =>
      raise ProtocolSchemaError::InvalidReturnType(method_name, name, expected)
  }
}

///|
fn typed_optional_result_int(
  method_name : String,
  fields : Map[String, Json],
  name : String,
  expected : String,
) -> Int? raise ProtocolSchemaError {
  match typed_optional_result_json(fields, name) {
    Some(Number(value, ..)) => {
      let int = value.to_int()
      if int.to_double() == value {
        Some(int)
      } else {
        raise ProtocolSchemaError::InvalidReturnType(
          method_name, name, expected,
        )
      }
    }
    Some(_) =>
      raise ProtocolSchemaError::InvalidReturnType(method_name, name, expected)
    None => None
  }
}

///|
fn typed_required_result_double(
  method_name : String,
  fields : Map[String, Json],
  name : String,
  expected : String,
) -> Double raise ProtocolSchemaError {
  match typed_required_result_json(method_name, fields, name) {
    Number(value, ..) => value
    _ =>
      raise ProtocolSchemaError::InvalidReturnType(method_name, name, expected)
  }
}

///|
fn typed_required_result_bool(
  method_name : String,
  fields : Map[String, Json],
  name : String,
  expected : String,
) -> Bool raise ProtocolSchemaError {
  match typed_required_result_json(method_name, fields, name) {
    True => true
    False => false
    _ =>
      raise ProtocolSchemaError::InvalidReturnType(method_name, name, expected)
  }
}

///|
fn typed_optional_result_bool(
  method_name : String,
  fields : Map[String, Json],
  name : String,
  expected : String,
) -> Bool? raise ProtocolSchemaError {
  match typed_optional_result_json(fields, name) {
    Some(True) => Some(true)
    Some(False) => Some(false)
    Some(_) =>
      raise ProtocolSchemaError::InvalidReturnType(method_name, name, expected)
    None => None
  }
}
