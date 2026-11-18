///|
extern "js" fn read_text(path : String) -> String =
  #|(path) => {
  #|  try { return process.getBuiltinModule("node:fs").readFileSync(path, "utf8"); }
  #|  catch (error) { console.error(error.message); process.exit(2); }
  #|}

///|
extern "js" fn exit_with(code : Int32) -> Unit = "(code) => { process.exitCode = code; }"

///|
fn main {
  let args = @env.args()
  if args.length() >= 3 && args[2] == "--manifest" {
    if args.length() == 4 || (args.length() == 5 && args[4] == "--json") {
      run_manifest(args[3], args.length() == 5)
      return
    }
  }
  if args.length() != 6 {
    println(
      "Usage: flash-partition-check IMAGE.hex PARTITION START_HEX SIZE_HEX\n       flash-partition-check --linker IMAGE.hex SCRIPT.ld REGION\n       flash-partition-check --manifest PLAN.json [--json]",
    )
    exit_with(2)
    return
  }
  try {
    let partition = if args[2] == "--linker" {
      @flash.partition_from_linker(read_text(args[4]), args[5])
    } else {
      @flash.Partition::{
        name: args[3],
        first: @flash.parse_address(args[4][:], radix=16),
        size: @flash.parse_address(args[5][:], radix=16),
      }
    }
    let image_path = if args[2] == "--linker" { args[3] } else { args[2] }
    let image = @flash.parse(read_text(image_path))
    let violations = @flash.coalesce_violations(
      @flash.outside_partition(image, partition.first, partition.size),
    )
    if violations.is_empty() {
      println("PASS: all data records are inside \{partition.name}")
    } else {
      println(
        "FAIL: \{violations.length()} out-of-partition intervals in \{image_path}",
      )
      for index, violation in violations {
        if index == 10 {
          println("Remaining intervals omitted from CLI output")
          break
        }
        println(
          "FAIL \{image_path}:\{violation.line}: [0x\{violation.first.to_string(radix=16)}, 0x\{violation.end_exclusive.to_string(radix=16)}) outside \{partition.name}",
        )
      }
      exit_with(1)
    }
  } catch {
    @flash.InvalidHex(line, message) => {
      println("Invalid Intel HEX at line \{line}: \{message}")
      exit_with(2)
    }
    @flash.InvalidPartition => {
      println("Invalid partition bounds")
      exit_with(2)
    }
    error => {
      println(error.to_string())
      exit_with(2)
    }
  }
}
