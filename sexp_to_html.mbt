///|
pub fn sexp_to_html(source : String) -> Result[String, String] {
  parse_document(Cursor::new(source.to_array(), 0)).map(render_document)
}
