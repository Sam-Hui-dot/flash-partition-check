///|
fn address(value : Int64) -> String {
  "0x" + value.to_string(radix=16)
}

///|
fn span_text(span : Range) -> String {
  "[\{address(span.first)}, \{address(span.end_exclusive)})"
}

///|
fn AuditIssue::text(self : AuditIssue) -> String {
  match self {
    Outside(image, part, span) =>
      "\{image} line \{span.line}: \{span_text(span)} outside \{part}"
    ReservedWrite(image, part, span) =>
      "\{image} line \{span.line}: \{span_text(span)} writes reserved \{part}"
    Collision(left, right, span, line) =>
      "\{left} line \{span.line} and \{right} line \{line} both write \{span_text(span)}"
  }
}

///|
fn AuditIssue::json(self : AuditIssue) -> Json {
  let (kind, image, target, span, other_line) = match self {
    Outside(image, part, span) =>
      ("outside_partition", image, part, span, Json::null())
    ReservedWrite(image, part, span) =>
      ("reserved_write", image, part, span, Json::null())
    Collision(left, right, span, line) =>
      ("collision", left, right, span, @json.to_json(line))
  }
  Json::object(
    Map([
      ("kind", Json::string(kind)),
      ("image", Json::string(image)),
      ("target", Json::string(target)),
      ("first", Json::string(address(span.first))),
      ("end_exclusive", Json::string(address(span.end_exclusive))),
      ("line", @json.to_json(span.line)),
      ("other_line", other_line),
    ]),
  )
}

///|
fn ImageSummary::json(self : ImageSummary) -> Json {
  Json::object(
    Map([
      ("name", Json::string(self.name)),
      ("file", Json::string(self.file)),
      ("partition", Json::string(self.partition)),
      ("bytes", Json::string(self.bytes.to_string())),
      ("first", Json::string(address(self.first))),
      ("end_exclusive", Json::string(address(self.end_exclusive))),
    ]),
  )
}

///|
pub fn AuditReport::to_json(self : AuditReport) -> String {
  Json::object(
    Map([
      (
        "status",
        Json::string(if self.issues.is_empty() { "pass" } else { "fail" }),
      ),
      ("issue_count", @json.to_json(self.issues.length())),
      ("images", Json::array(self.images.map(item => item.json()))),
      ("issues", Json::array(self.issues.map(item => item.json()))),
    ]),
  ).stringify()
}

///|
pub fn AuditReport::to_text(self : AuditReport) -> String {
  let status = if self.issues.is_empty() { "PASS" } else { "FAIL" }
  let lines = [
    "\{status}: \{self.images.length()} images, \{self.issues.length()} issues",
  ]
  for image in self.images {
    lines.push(
      "\{image.name} -> \{image.partition}: \{image.bytes} occupied bytes",
    )
  }
  for issue in self.issues {
    lines.push(issue.text())
  }
  lines.join("\n")
}
