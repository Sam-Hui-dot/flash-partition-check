///|
test "partition crossing reports just the out-of-range intervals" {
  let image = @flash-partition-check.parse(
    ":020000040001F9\n:0400200001020304D2\n:00000001FF\n",
  )
  assert_true(
    @flash-partition-check.outside_partition(image, 0x10020L, 4L).is_empty(),
  )
  let violations = @flash-partition-check.outside_partition(image, 0x10021L, 2L)
  assert_eq(violations.length(), 2)
  assert_eq(
    (violations[0].first, violations[0].end_exclusive, violations[0].line),
    (0x10020L, 0x10021L, 2),
  )
  assert_eq(
    (violations[1].first, violations[1].end_exclusive, violations[1].line),
    (0x10023L, 0x10024L, 2),
  )
}

///|
test "reject corrupt checksum and conflicting records" {
  try @flash-partition-check.parse(":0400200001020304D3\n:00000001FF\n") catch {
    error => assert_true(error is InvalidHex(1, "checksum mismatch"))
  } noraise {
    _ => fail("expected checksum failure")
  }
  try
    @flash-partition-check.parse(
      ":0400200001020304D2\n:0400200001020304D2\n:00000001FF\n",
    )
  catch {
    error => assert_true(error is InvalidHex(2, "overlapping data record"))
  } noraise {
    _ => fail("expected overlapping records to fail")
  }
}
