///|
pub struct Cursor {
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
fn Cursor::length(self : Cursor) -> Int {
  self.source.length()
}

///|
fn Cursor::unsafe_char_at(self : Cursor, index : Int) -> Char {
  self.source.get_char(index).unwrap()
}

///|
fn Cursor::next_index(self : Cursor, index : Int) -> Int {
  match () {
    _ if index >= self.length() => index
    _ if self.source.code_unit_at(index).is_leading_surrogate() => index + 2
    _ => index + 1
  }
}

///|
fn Cursor::advance(self : Cursor, amount : Int) -> Cursor {
  { source: self.source, index: self.index + amount }
}

///|
fn Cursor::at(self : Cursor, index : Int) -> Cursor {
  { source: self.source, index }
}

///|
fn Cursor::skip_whitespace(self : Cursor) -> Cursor {
  let mut index = self.index
  while index < self.length() && self.unsafe_char_at(index).is_whitespace() {
    index = self.next_index(index)
  }
  self.at(index)
}

///|
fn Cursor::slice_to_string(self : Cursor, end : Int) -> String {
  self.source.sub(start=self.index, end~).to_owned()
}

///|
fn Cursor::error(self : Cursor, message : String) -> String {
  error_at(self.index, message)
}

///|
fn error_at(index : Int, message : String) -> String {
  "parse error at offset \{index}: \{message}"
}
