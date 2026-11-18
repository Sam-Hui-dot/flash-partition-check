///|
extern "js" fn resolve_image(manifest : String, file : String) -> String =
  #|(manifest, file) => {
  #|  const path = process.getBuiltinModule("node:path");
  #|  return path.resolve(path.dirname(manifest), file);
  #|}

///|
suberror ImageInputError {
  InvalidImageInput(String)
}

///|
fn read_assigned_image(
  manifest : String,
  item : @flash.ImageAssignment,
) -> @flash.Image raise ImageInputError {
  let path = resolve_image(manifest, item.file)
  @flash.parse(read_text(path)) catch {
    @flash.InvalidHex(line, message) =>
      raise InvalidImageInput(
        "\{item.name} (\{item.file}), line \{line}: \{message}",
      )
    @flash.InvalidPartition =>
      raise InvalidImageInput("\{item.name} (\{item.file}): invalid partition")
  }
}

///|
fn run_manifest(path : String, json_output : Bool) -> Unit {
  try {
    let plan = @flash.parse_manifest(read_text(path))
    let inputs : Map[String, @flash.Image] = Map([])
    for item in plan.images {
      inputs[item.name] = read_assigned_image(path, item)
    }
    let report = @flash.audit_plan(plan, inputs)
    println(if json_output { report.to_json() } else { report.to_text() })
    if !report.issues.is_empty() {
      exit_with(1)
    }
  } catch {
    @flash.InvalidPlan(message) | InvalidImageInput(message) => {
      println(
        if json_output {
          invalid_json(message)
        } else {
          "Invalid input: " + message
        },
      )
      exit_with(2)
    }
    error => {
      println(
        if json_output {
          invalid_json(error.to_string())
        } else {
          error.to_string()
        },
      )
      exit_with(2)
    }
  }
}

///|
fn invalid_json(message : String) -> String {
  Json::object(
    Map([
      ("status", Json::string("invalid")),
      ("message", Json::string(message)),
    ]),
  ).stringify()
}
