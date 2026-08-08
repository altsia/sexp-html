///|
pub fn escape_html_text(text : String) -> String {
  escape_html(text, escape_quote=false)
}

///|
pub fn escape_html_attr_value(value : String) -> String {
  escape_html(value, escape_quote=true)
}

///|
/// Single-pass HTML escaping. Returns the input unchanged when nothing needs
/// escaping.
fn escape_html(text : String, escape_quote~ : Bool) -> String {
  let needs = text.any(ch => {
    ch == '&' || ch == '<' || ch == '>' || (escape_quote && ch == '"')
  })
  guard needs else { return text }
  let builder = StringBuilder::new()
  for ch in text {
    match ch {
      '&' => builder.write_string("&amp;")
      '<' => builder.write_string("&lt;")
      '>' => builder.write_string("&gt;")
      '"' if escape_quote => builder.write_string("&quot;")
      _ => builder.write_char(ch)
    }
  }
  builder.to_string()
}
