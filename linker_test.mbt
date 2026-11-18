///|
test "read real GNU MEMORY constants and arithmetic without executing script" {
  let layout = "/* MEMORY { bogus } */ MEMORY { FLASH (rx) : ORIGIN = 0x26000, LENGTH = (0xED000 - 0x26000) RAM(rwx):ORIGIN=0x20000000,LENGTH=256K }"
  assert_eq(@flash-partition-check.partition_from_linker(layout, "FLASH"), {
    name: "FLASH",
    first: 0x26000L,
    size: 0xC7000L,
  })
  assert_eq(
    @flash-partition-check.partition_from_linker(layout, "RAM").size,
    262144L,
  )
}

///|
test "reject unknown expressions and duplicate regions" {
  try
    @flash-partition-check.partition_from_linker(
      "MEMORY { FLASH : ORIGIN = 0, LENGTH = LENGTH(OTHER) }", "FLASH",
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("unknown expressions must be rejected")
  }
  try
    @flash-partition-check.partition_from_linker(
      "MEMORY { FLASH:ORIGIN=0,LENGTH=16 FLASH:ORIGIN=16,LENGTH=16 }", "FLASH",
    )
  catch {
    error => assert_true(error is InvalidLayout("duplicate region FLASH"))
  } noraise {
    _ => fail("duplicate region must be rejected")
  }
}
