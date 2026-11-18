///|
pub struct ImageSummary {
  name : String
  file : String
  partition : String
  bytes : Int64
  first : Int64
  end_exclusive : Int64
}

///|
pub(all) enum AuditIssue {
  Outside(String, String, Range)
  ReservedWrite(String, String, Range)
  Collision(String, String, Range, Int32)
}

///|
pub struct AuditReport {
  images : Array[ImageSummary]
  issues : Array[AuditIssue]
}

///|
fn intersect(left : Range, right : Range) -> Range? {
  let first = if left.first > right.first { left.first } else { right.first }
  let stop = if left.end_exclusive < right.end_exclusive {
    left.end_exclusive
  } else {
    right.end_exclusive
  }
  if first < stop {
    Some({ first, end_exclusive: stop, line: left.line, })
  } else {
    None
  }
}

///|
fn collisions(
  left_name : String,
  left : Image,
  right_name : String,
  right : Image,
  issues : Array[AuditIssue],
) -> Unit {
  let mut i = 0
  let mut j = 0
  while i < left.ranges.length() && j < right.ranges.length() {
    let a = left.ranges[i]
    let b = right.ranges[j]
    if intersect(a, b) is Some(span) {
      issues.push(Collision(left_name, right_name, span, b.line))
    }
    if a.end_exclusive <= b.end_exclusive {
      i += 1
    }
    if b.end_exclusive <= a.end_exclusive {
      j += 1
    }
  }
}

///|
/// Image data is keyed by assignment name so the caller controls file access.
pub fn audit_plan(
  plan : FlashPlan,
  inputs : Map[String, Image],
) -> AuditReport raise PlanError {
  // Revalidate because the public report-facing arrays can be edited by callers.
  let plan = make_plan(plan.partitions, plan.images)
  let parts : Map[String, PlanPartition] = Map([])
  let reserved : Array[PlanPartition] = []
  for part in plan.partitions {
    parts[part.name] = part
    if part.reserved {
      reserved.push(part)
    }
  }
  let issues : Array[AuditIssue] = []
  let images : Array[ImageSummary] = []
  let parsed : Array[(String, Image)] = []
  for assignment in plan.images {
    guard inputs.get(assignment.name) is Some(image) else {
      raise InvalidPlan("image data missing for \{assignment.name}")
    }
    let part = parts[assignment.partition]
    let mut bytes = 0L
    for range in image.ranges {
      bytes += range.end_exclusive - range.first
      for item in reserved {
        let target : Range = {
          first: item.first,
          end_exclusive: item.first + item.size,
          line: 0,
        }
        if intersect(range, target) is Some(span) {
          issues.push(ReservedWrite(assignment.name, item.name, span))
        }
      }
    }
    for
      violation in coalesce_violations(
        outside_partition(image, part.first, part.size) catch {
          _ => raise InvalidPlan("invalid bounds for \{part.name}")
        },
      ) {
      issues.push(Outside(assignment.name, part.name, violation))
    }
    for pair in parsed {
      collisions(pair.0, pair.1, assignment.name, image, issues)
    }
    parsed.push((assignment.name, image))
    images.push({
      name: assignment.name,
      file: assignment.file,
      partition: part.name,
      bytes,
      first: image.ranges[0].first,
      end_exclusive: image.ranges[image.ranges.length() - 1].end_exclusive,
    })
  }
  { images, issues, }
}
