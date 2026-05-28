///|
pub struct Cursor {
  chars : Array[Char]
  index : Int
}

///|
fn Cursor::new(chars : Array[Char], index : Int) -> Cursor {
  { chars, index }
}

///|
fn Cursor::is_end(self : Cursor) -> Bool {
  self.index >= self.chars.length()
}

///|
fn Cursor::peek(self : Cursor) -> Char? {
  if self.is_end() {
    None
  } else {
    Some(self.char_at(self.index))
  }
}

///|
fn Cursor::length(self : Cursor) -> Int {
  self.chars.length()
}

///|
fn Cursor::char_at(self : Cursor, index : Int) -> Char {
  self.chars[index]
}

///|
fn Cursor::advance(self : Cursor, amount : Int) -> Cursor {
  { chars: self.chars, index: self.index + amount }
}

///|
fn Cursor::at(self : Cursor, index : Int) -> Cursor {
  { chars: self.chars, index }
}

///|
fn Cursor::skip_whitespace(self : Cursor) -> Cursor {
  let mut index = self.index
  while index < self.length() && self.char_at(index).is_whitespace() {
    index = index + 1
  }
  self.at(index)
}

///|
fn Cursor::slice_to_string(self : Cursor, end : Int) -> String {
  String::from_array(self.chars.view(start=self.index, end~))
}

///|
fn Cursor::error(self : Cursor, message : String) -> String {
  error_at(self.index, message)
}
