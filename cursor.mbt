///|
priv struct Cursor {
  source : String
  index : Int
}

///|
fn Cursor::new(source : String) -> Cursor {
  { source, index: 0 }
}

///|
fn Cursor::is_end(self : Cursor) -> Bool {
  self.index >= self.source.length()
}

///|
fn Cursor::peek(self : Cursor) -> Char? {
  guard !self.is_end() else { None }
  self.source.get_char(self.index)
}

///|
fn Cursor::code_unit_length(self : Cursor) -> Int {
  self.source.length()
}

///|
fn Cursor::unsafe_char_at(self : Cursor, index : Int) -> Char {
  self.source.get_char(index).unwrap()
}

///|
fn Cursor::next_char_index(self : Cursor, index : Int) -> Int {
  match () {
    _ if index >= self.code_unit_length() => index
    _ if self.source.code_unit_at(index).is_leading_surrogate() => index + 2
    _ => index + 1
  }
}

///|
fn Cursor::advance_code_units(self : Cursor, amount : Int) -> Cursor {
  { source: self.source, index: self.index + amount }
}

///|
fn Cursor::with_index(self : Cursor, index : Int) -> Cursor {
  { source: self.source, index }
}

///|
fn Cursor::skip_whitespace(self : Cursor) -> Cursor {
  let mut index = self.index
  while index < self.code_unit_length() {
    let code = self.source.code_unit_at(index).to_int()
    if code < 0x80 {
      guard is_ascii_whitespace_code(code) else { break }
      index = index + 1
    } else {
      let ch = self.source.get_char(index).unwrap()
      guard ch.is_whitespace() else { break }
      index = index + ch.utf16_len()
    }
  }
  self.with_index(index)
}

///|
/// True for the ASCII whitespace code units: tab through carriage return and space.
fn is_ascii_whitespace_code(code : Int) -> Bool {
  code == 0x20 || (code >= 0x09 && code <= 0x0D)
}

///|
fn Cursor::slice_until(self : Cursor, end : Int) -> String {
  self.source.sub(start=self.index, end~).to_owned()
}

///|
fn Cursor::error(self : Cursor, message : String) -> String {
  let (line, column) = line_column_at(self.source, self.index)
  "parse error at line \{line}, column \{column}: \{message}"
}

///|
/// Computes the 1-based line and column of a UTF-16 code-unit offset in `source`.
fn line_column_at(source : String, offset : Int) -> (Int, Int) {
  let mut line = 1
  let mut column = 1
  let mut index = 0
  while index < offset {
    guard source.get_char(index) is Some(ch) else { break }
    if ch == '\n' {
      line = line + 1
      column = 1
    } else {
      column = column + 1
    }
    index = index + ch.utf16_len()
  }
  (line, column)
}
