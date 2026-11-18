///|
pub suberror FlashError {
  InvalidHex(Int32, String)
  InvalidPartition
}

///|
#derive(Debug, Eq)
pub struct Range {
  first : Int64
  end_exclusive : Int64
  line : Int32
}

///|
pub extend Range with @debug.Debug::{to_repr}

///|
pub extend Range with Eq::{not_equal, equal}

///|
pub struct Image {
  priv ranges : Array[Range]
}

///|
fn byte_at(
  record : StringView,
  offset : Int32,
  line : Int32,
) -> Int32 raise FlashError {
  let field = record[offset:offset + 2]
  for ch in field {
    if !ch.is_ascii_hexdigit() {
      raise InvalidHex(line, "invalid hexadecimal digit")
    }
  }
  parse_address(field).to_int() catch {
    _ => raise InvalidHex(line, "invalid hexadecimal byte")
  }
}

///|
let address_limit : Int64 = 0x1_0000_0000L

///|
/// Parse an unsigned address or size with explicit overflow checking.
pub fn parse_address(
  text : StringView,
  radix~ : Int32 = 16,
) -> Int64 raise FlashError {
  if text.is_empty() || (radix != 10 && radix != 16) {
    raise InvalidPartition
  }
  let mut value = 0L
  for ch in text {
    let scalar = ch.to_int()
    let digit = if scalar >= 48 && scalar <= 57 {
      scalar - 48
    } else if scalar >= 65 && scalar <= 70 {
      scalar - 55
    } else if scalar >= 97 && scalar <= 102 {
      scalar - 87
    } else {
      raise InvalidPartition
    }
    if digit >= radix ||
      value > (address_limit - digit.to_int64()) / radix.to_int64() {
      raise InvalidPartition
    }
    value = value * radix.to_int64() + digit.to_int64()
  }
  value
}

///|
/// Decode and validate an Intel HEX image. The address map is sparse.
pub fn parse(text : String) -> Image raise FlashError {
  let ranges : Array[Range] = []
  let mut base = 0L
  let mut eof = false
  let mut line = 0
  for raw in text.split("\n") {
    line += 1
    let record = raw.trim()
    if record.is_empty() {
      continue
    }
    if eof {
      raise InvalidHex(line, "record after end of file")
    }
    if record.length() < 11 || record.at(0) != 58 {
      raise InvalidHex(line, "expected an Intel HEX record")
    }
    let count = byte_at(record, 1, line)
    if record.length() != 11 + count * 2 {
      raise InvalidHex(line, "byte count does not match record length")
    }
    let mut checksum = 0
    for index in 0..<(count + 5) {
      checksum += byte_at(record, 1 + index * 2, line)
    }
    if (checksum & 255) != 0 {
      raise InvalidHex(line, "checksum mismatch")
    }
    let address = byte_at(record, 3, line) * 256 + byte_at(record, 5, line)
    let kind = byte_at(record, 7, line)
    match kind {
      0 => {
        let first = base + address.to_int64()
        let end_exclusive = first + count.to_int64()
        if end_exclusive > address_limit || address + count > 65536 {
          raise InvalidHex(line, "data record crosses its address window")
        }
        if count > 0 {
          ranges.push({ first, end_exclusive, line, })
        }
      }
      1 if address == 0 && count == 0 => eof = true
      2 | 4 if address == 0 && count == 2 => {
        let upper = (byte_at(record, 9, line) * 256 + byte_at(record, 11, line)).to_int64()
        base = if kind == 2 { upper << 4 } else { upper << 16 }
      }
      3 | 5 if address == 0 && count == 4 => ()
      _ => raise InvalidHex(line, "unsupported or malformed record type")
    }
  }
  if !eof {
    raise InvalidHex(line, "missing end-of-file record")
  }
  if ranges.is_empty() {
    raise InvalidHex(line, "image has no data records")
  }
  ranges.sort_by_key(range => range.first)
  for index in 1..<ranges.length() {
    if ranges[index].first < ranges[index - 1].end_exclusive {
      raise InvalidHex(ranges[index].line, "overlapping data record")
    }
  }
  { ranges, }
}

///|
/// Report every occupied interval outside a partition expressed in the same
/// absolute address space as the image.
pub fn outside_partition(
  image : Image,
  first : Int64,
  size : Int64,
) -> Array[Range] raise FlashError {
  if first < 0L ||
    first >= address_limit ||
    size <= 0L ||
    size > address_limit - first {
    raise InvalidPartition
  }
  let end_exclusive = first + size
  let violations = []
  for range in image.ranges {
    if range.first < first {
      let stop = if range.end_exclusive < first {
        range.end_exclusive
      } else {
        first
      }
      violations.push({
        first: range.first,
        end_exclusive: stop,
        line: range.line,
      })
    }
    if range.end_exclusive > end_exclusive {
      let start = if range.first > end_exclusive {
        range.first
      } else {
        end_exclusive
      }
      violations.push({
        first: start,
        end_exclusive: range.end_exclusive,
        line: range.line,
      })
    }
  }
  violations
}

///|
/// Join consecutive out-of-partition spans in address order. The line
/// identifies the first contributing data record.
pub fn coalesce_violations(violations : Array[Range]) -> Array[Range] {
  let spans : Array[Range] = []
  for range in violations {
    if spans.last() is Some(previous) && previous.end_exclusive == range.first {
      spans[spans.length() - 1] = {
        first: previous.first,
        end_exclusive: range.end_exclusive,
        line: previous.line,
      }
    } else {
      spans.push(range)
    }
  }
  spans
}
