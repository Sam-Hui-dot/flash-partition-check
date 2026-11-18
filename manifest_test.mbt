///|
fn manifest_fixture(start : String) -> String {
  "{\"partitions\":[{\"name\":\"app\",\"start\":\"" +
  start +
  "\",\"size\":\"0x4\"}],\"images\":[{\"name\":\"build\",\"file\":\"a.hex\",\"partition\":\"app\"}]}"
}

///|
test "manifest accepts final address and rejects an overflow by a byte" {
  let plan = @flash-partition-check.parse_manifest(
    manifest_fixture("0xfffffffc"),
  )
  assert_eq(plan.partitions[0].first, 0xFFFF_FFFCL)
  try
    @flash-partition-check.parse_manifest(manifest_fixture("0xfffffffd"))
  catch {
    InvalidPlan(message) =>
      assert_eq(message, "partition bounds are invalid: app")
  } noraise {
    _ => fail("overflow is invalid")
  }
}

///|
test "manifest rejects duplicate JSON keys and accidental property typos" {
  let good = manifest_fixture("0x0")
  for
    malformed in [
      good.replace_all(
        old="\"size\":\"0x4\"",
        new="\"size\":\"0x4\",\"size\":\"0x8\"",
      ),
      good.replace_all(old="\"size\"", new="\"length\""),
    ] {
    try @flash-partition-check.parse_manifest(malformed) catch {
      InvalidPlan(_) => ()
    } noraise {
      _ => fail("ambiguous flash plan must be rejected")
    }
  }
}

///|
test "audit does not infer writes through holes or count boundary touches" {
  let plan = @flash-partition-check.parse_manifest(
    "{\"partitions\":[{\"name\":\"app\",\"start\":\"0x0\",\"size\":\"0x20\"}],\"images\":[{\"name\":\"a\",\"file\":\"a.hex\",\"partition\":\"app\"},{\"name\":\"b\",\"file\":\"b.hex\",\"partition\":\"app\"}]}",
  )
  let a = @flash-partition-check.parse(
    ":01000000AA55\n:01000200AA53\n:00000001FF\n",
  )
  let b = @flash-partition-check.parse(":01000100AA54\n:00000001FF\n")
  let report = @flash-partition-check.audit_plan(
    plan,
    Map([("a", a), ("b", b)]),
  )
  assert_true(report.issues.is_empty())
  assert_eq(report.images[0].bytes, 2L)
}
