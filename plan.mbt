///|
pub suberror PlanError {
  InvalidPlan(String)
}

///|
pub(all) struct PlanPartition {
  name : String
  first : Int64
  size : Int64
  reserved : Bool
}

///|
pub(all) struct ImageAssignment {
  name : String
  file : String
  partition : String
}

///|
pub struct FlashPlan {
  partitions : Array[PlanPartition]
  images : Array[ImageAssignment]
}

///|
pub fn make_plan(
  partitions : Array[PlanPartition],
  images : Array[ImageAssignment],
) -> FlashPlan raise PlanError {
  if partitions.is_empty() || images.is_empty() {
    raise InvalidPlan("a plan needs at least one partition and one image")
  }
  let by_name : Map[String, PlanPartition] = Map([])
  for part in partitions {
    if part.name.is_empty() || by_name.contains(part.name) {
      raise InvalidPlan("empty or duplicate partition name: \{part.name}")
    }
    if part.first < 0L ||
      part.first >= address_limit ||
      part.size <= 0L ||
      part.size > address_limit - part.first {
      raise InvalidPlan("partition bounds are invalid: \{part.name}")
    }
    by_name[part.name] = part
  }
  let ordered = partitions.copy()
  ordered.sort_by_key(part => part.first)
  for i in 1..<ordered.length() {
    let previous = ordered[i - 1]
    let current = ordered[i]
    if current.first < previous.first + previous.size {
      raise InvalidPlan(
        "partitions overlap: \{previous.name} and \{current.name}",
      )
    }
  }
  let seen : Map[String, Bool] = Map([])
  for image in images {
    if image.name.is_empty() ||
      image.file.is_empty() ||
      seen.contains(image.name) {
      raise InvalidPlan(
        "empty or duplicate image name or empty file: \{image.name}",
      )
    }
    seen[image.name] = true
    match by_name.get(image.partition) {
      None =>
        raise InvalidPlan(
          "image \{image.name} names unknown partition \{image.partition}",
        )
      Some(part) =>
        if part.reserved {
          raise InvalidPlan(
            "image \{image.name} is assigned to reserved partition \{part.name}",
          )
        }
    }
  }
  { partitions: ordered, images: images.copy(), }
}
