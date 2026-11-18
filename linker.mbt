///|
pub suberror LayoutError {
  InvalidLayout(String)
}

///|
#derive(Debug, Eq)
pub(all) struct Partition {
  name : String
  first : Int64
  size : Int64
}

///|
pub extend Partition with @debug.Debug::{to_repr}

///|
pub extend Partition with Eq::{not_equal, equal}

///|
priv struct LayoutTokens {
  items : Array[String]
  mut offset : Int32
}

///|
fn LayoutTokens::peek(self : LayoutTokens) -> String {
  self.items.get(self.offset).unwrap_or("")
}

///|
fn LayoutTokens::take(self : LayoutTokens) -> String raise LayoutError {
  if self.offset == self.items.length() {
    raise InvalidLayout("unexpected end of linker MEMORY block")
  }
  let token = self.items[self.offset]
  self.offset += 1
  token
}

///|
fn LayoutTokens::expect(
  self : LayoutTokens,
  expected : String,
) -> Unit raise LayoutError {
  let actual = self.take()
  if actual != expected {
    raise InvalidLayout("expected \{expected}, got \{actual}")
  }
}

///|
fn layout_word(ch : UInt16) -> Bool {
  (ch >= 48 && ch <= 57) ||
  (ch >= 65 && ch <= 90) ||
  (ch >= 97 && ch <= 122) ||
  ch == 95
}

///|
fn layout_tokens(text : String) -> LayoutTokens raise LayoutError {
  let items = []
  let mut index = 0
  while index < text.length() {
    let ch = text.at(index)
    if ch == 32 || ch == 9 || ch == 10 || ch == 13 {
      index += 1
    } else if ch == 47 && index + 1 < text.length() && text.at(index + 1) == 42 {
      index += 2
      while index + 1 < text.length() &&
            !(text.at(index) == 42 && text.at(index + 1) == 47) {
        index += 1
      }
      if index + 1 >= text.length() {
        raise InvalidLayout("unterminated comment")
      }
      index += 2
    } else if ch == 47 && index + 1 < text.length() && text.at(index + 1) == 47 {
      while index < text.length() && text.at(index) != 10 {
        index += 1
      }
    } else {
      let start = index
      index += 1
      if layout_word(ch) {
        while index < text.length() && layout_word(text.at(index)) {
          index += 1
        }
      }
      items.push(text[start:index].to_owned())
    }
  }
  { items, offset: 0, }
}

///|
fn LayoutTokens::constant(self : LayoutTokens) -> Int64 raise LayoutError {
  if self.peek() == "(" {
    ignore(self.take())
    let value = self.expression()
    self.expect(")")
    return value
  }
  let token = self.take()
  let (number, multiplier) = if token.has_suffix("K") || token.has_suffix("k") {
    (token[:token.length() - 1].to_owned(), 1024L)
  } else if token.has_suffix("M") || token.has_suffix("m") {
    (token[:token.length() - 1].to_owned(), 1048576L)
  } else {
    (token, 1L)
  }
  let value = if number.has_prefix("0x") || number.has_prefix("0X") {
    @string.parse_int64(number[2:], base=16) catch {
      _ => raise InvalidLayout("unsupported constant \{token}")
    }
  } else {
    @string.parse_int64(number[:], base=10) catch {
      _ => raise InvalidLayout("unsupported constant \{token}")
    }
  }
  if value < 0L || value > address_limit / multiplier {
    raise InvalidLayout("constant exceeds 32-bit image address space")
  }
  value * multiplier
}

///|
fn LayoutTokens::expression(self : LayoutTokens) -> Int64 raise LayoutError {
  let mut value = self.constant()
  while self.peek() == "+" || self.peek() == "-" {
    let operator = self.take()
    let operand = self.constant()
    if operator == "+" {
      if value > address_limit - operand {
        raise InvalidLayout("address expression overflows")
      }
      value += operand
    } else {
      if value < operand {
        raise InvalidLayout("negative address expression")
      }
      value -= operand
    }
  }
  value
}

///|
/// Read a named GNU ld MEMORY region with constant ORIGIN and LENGTH.
/// Decimal/hex numbers, K/M suffixes, parentheses, + and - are supported.
pub fn partition_from_linker(
  text : String,
  name : String,
) -> Partition raise LayoutError {
  let tokens = layout_tokens(text)
  while tokens.peek() != "MEMORY" {
    if tokens.peek() == "" {
      raise InvalidLayout("missing MEMORY block")
    }
    ignore(tokens.take())
  }
  ignore(tokens.take())
  tokens.expect("{")
  let mut selected : Partition? = None
  while tokens.peek() != "}" {
    let region = tokens.take()
    if tokens.peek() == "(" {
      ignore(tokens.take())
      while tokens.peek() != ")" {
        ignore(tokens.take())
      }
      ignore(tokens.take())
    }
    tokens.expect(":")
    tokens.expect("ORIGIN")
    tokens.expect("=")
    let first = tokens.expression()
    tokens.expect(",")
    tokens.expect("LENGTH")
    tokens.expect("=")
    let size = tokens.expression()
    if tokens.peek() == ";" {
      ignore(tokens.take())
    }
    if region == name {
      if selected is Some(_) {
        raise InvalidLayout("duplicate region \{name}")
      }
      if first >= address_limit || size <= 0L || size > address_limit - first {
        raise InvalidLayout("invalid region bounds")
      }
      selected = Some({ name, first, size, })
    }
  }
  match selected {
    Some(partition) => partition
    None => raise InvalidLayout("region not found: \{name}")
  }
}
