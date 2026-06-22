///|
/// Returns true for the opening delimiter of an S-expression list.
pub fn is_sexp_open_paren(ch : Char) -> Bool {
  ch == '('
}

///|
/// Returns true for the closing delimiter of an S-expression list.
pub fn is_sexp_close_paren(ch : Char) -> Bool {
  ch == ')'
}

///|
/// Returns true for either S-expression list delimiter.
pub fn is_sexp_paren(ch : Char) -> Bool {
  is_sexp_open_paren(ch) || is_sexp_close_paren(ch)
}

///|
/// Returns true for characters escaped by S-expression text syntax.
pub fn is_sexp_text_escape_target(ch : Char) -> Bool {
  is_sexp_paren(ch)
}
