///|
fn required_array(
  fields : Map[String, Json],
  name : String,
) -> Array[Json] raise PlanError {
  guard fields.get(name) is Some(Array(items)) else {
    raise InvalidPlan("expected array field \{name}")
  }
  items
}

///|
fn required_string(
  fields : Map[String, Json],
  name : String,
  context : String,
) -> String raise PlanError {
  guard fields.get(name) is Some(String(value)) && !value.is_empty() else {
    raise InvalidPlan("\{context}.\{name} must be a nonempty string")
  }
  value
}

///|
fn allowed_fields(
  fields : Map[String, Json],
  names : Array[String],
  context : String,
) -> Unit raise PlanError {
  for field, _ in fields {
    if !names.contains(field) {
      raise InvalidPlan("unknown field \{context}.\{field}")
    }
  }
}

///|
fn hex_field(
  fields : Map[String, Json],
  field : String,
  context : String,
) -> Int64 raise PlanError {
  let value = required_string(fields, field, context)
  if !value.has_prefix("0x") || value.length() < 3 || value.length() > 11 {
    raise InvalidPlan(
      "\{context}.\{field} must be a hexadecimal address or length",
    )
  }
  for digit in value[2:] {
    if !digit.is_ascii_hexdigit() {
      raise InvalidPlan("\{context}.\{field} has an invalid hexadecimal digit")
    }
  }
  @string.parse_int64(value[2:], base=16) catch {
    _ =>
      raise InvalidPlan("\{context}.\{field} has an invalid hexadecimal value")
  }
}

///|
fn parse_partition(item : Json, index : Int32) -> PlanPartition raise PlanError {
  let context = "partitions[\{index}]"
  guard item is Object(fields) else {
    raise InvalidPlan("expected object at " + context)
  }
  allowed_fields(fields, ["name", "start", "size", "reserved"], context)
  let reserved = match fields.get("reserved") {
    None | Some(False) => false
    Some(True) => true
    _ => raise InvalidPlan("\{context}.reserved must be a boolean")
  }
  {
    name: required_string(fields, "name", context),
    first: hex_field(fields, "start", context),
    size: hex_field(fields, "size", context),
    reserved,
  }
}

///|
fn parse_assignment(
  item : Json,
  index : Int32,
) -> ImageAssignment raise PlanError {
  let context = "images[\{index}]"
  guard item is Object(fields) else {
    raise InvalidPlan("expected object at " + context)
  }
  allowed_fields(fields, ["name", "file", "partition"], context)
  {
    name: required_string(fields, "name", context),
    file: required_string(fields, "file", context),
    partition: required_string(fields, "partition", context),
  }
}

///|
/// Parse a release manifest. File I/O is handled by the caller, not the library.
pub fn parse_manifest(text : String) -> FlashPlan raise PlanError {
  let root = @json.parse(
    text[:],
    reject_duplicate_keys=true,
    max_nesting_depth=8,
  ) catch {
    error => raise InvalidPlan("invalid JSON manifest: \{error}")
  }
  guard root is Object(fields) else {
    raise InvalidPlan("manifest root must be an object")
  }
  allowed_fields(fields, ["partitions", "images"], "manifest")
  let partitions = []
  let images = []
  for index, value in required_array(fields, "partitions") {
    partitions.push(parse_partition(value, index))
  }
  for index, value in required_array(fields, "images") {
    images.push(parse_assignment(value, index))
  }
  make_plan(partitions, images)
}
