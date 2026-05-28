///|
pub fn sexp_to_html(source : String) -> Result[String, String] {
  parse_sexp_html(source).map(render_html)
}

///|
pub fn render_html(nodes : Array[SexpNode]) -> String {
  let parts : Array[String] = []
  for node in nodes {
    parts.push(render_node(node))
  }
  parts.join("")
}

///|
pub fn render_html_document(
  attrs : Array[(String, String?)],
  head : Array[SexpNode],
  body : Array[SexpNode],
  doctype : String?,
) -> String {
  let lines : Array[String] = []
  match doctype {
    Some(value) => lines.push("<!DOCTYPE \{value}>")
    None => ()
  }
  lines.push(render_open_tag("html", attrs))
  lines.push("  <head>")
  push_rendered_lines(lines, head, "    ")
  lines.push("  </head>")
  lines.push("  <body>")
  push_rendered_lines(lines, body, "    ")
  lines.push("  </body>")
  lines.push("</html>")
  lines.join("\n")
}

///|
pub fn render_open_tag(
  tag : String,
  attrs : Array[(String, String?)],
) -> String {
  let parts : Array[String] = ["<", tag]
  append_rendered_attrs(parts, attrs)
  parts.push(">")
  parts.join("")
}

///|
pub fn upsert_attr(
  attrs : Array[(String, String?)],
  name : String,
  value : String?,
) -> Unit {
  for i in 0..<attrs.length() {
    match attrs[i] {
      (existing, _) if existing == name => {
        attrs[i] = (name, value)
        return
      }
      _ => ()
    }
  }
  attrs.push((name, value))
}

///|
pub fn append_class(
  attrs : Array[(String, String?)],
  class_name : String,
) -> Unit {
  for i in 0..<attrs.length() {
    match attrs[i] {
      ("class", Some(value)) => {
        attrs[i] = ("class", Some(value + " " + class_name))
        return
      }
      ("class", None) => {
        attrs[i] = ("class", Some(class_name))
        return
      }
      _ => ()
    }
  }
  attrs.push(("class", Some(class_name)))
}

///|
fn render_node(node : SexpNode) -> String {
  match node {
    Text(text) => escape_text(text)
    Comment(text) => "<!-- " + text + " -->"
    RawHtml(html) => html
    Element(tag, attrs, children) => render_element(tag, attrs, children)
  }
}

///|
fn push_rendered_lines(
  lines : Array[String],
  nodes : Array[SexpNode],
  indent : String,
) -> Unit {
  for node in nodes {
    let rendered = render_html([node])
    for line in rendered.split("\n") {
      if line.length() > 0 {
        lines.push(indent + line.to_owned())
      }
    }
  }
}

///|
fn render_element(
  tag : String,
  attrs : Array[(String, String?)],
  children : Array[SexpNode],
) -> String {
  let parts : Array[String] = ["<", tag]
  append_rendered_attrs(parts, attrs)
  parts.push(">")
  if is_void_tag(tag) {
    return parts.join("")
  }
  for child in children {
    parts.push(render_node(child))
  }
  parts.push("</")
  parts.push(tag)
  parts.push(">")
  parts.join("")
}

///|
fn append_rendered_attrs(
  parts : Array[String],
  attrs : Array[(String, String?)],
) -> Unit {
  for attr in attrs {
    match attr {
      (name, None) => {
        parts.push(" ")
        parts.push(name)
      }
      (name, Some(value)) => {
        parts.push(" ")
        parts.push(name)
        parts.push("=\"")
        parts.push(escape_attribute_value(value))
        parts.push("\"")
      }
    }
  }
}

///|
fn escape_text(text : String) -> String {
  text
  .replace_all(old="&", new="&amp;")
  .replace_all(old="<", new="&lt;")
  .replace_all(old=">", new="&gt;")
}

///|
fn escape_attribute_value(value : String) -> String {
  value
  .replace_all(old="&", new="&amp;")
  .replace_all(old="<", new="&lt;")
  .replace_all(old=">", new="&gt;")
  .replace_all(old="\"", new="&quot;")
}

///|
pub fn is_void_tag(tag : String) -> Bool {
  let lower = tag.to_lower()
  lower == "area" ||
  lower == "base" ||
  lower == "br" ||
  lower == "col" ||
  lower == "embed" ||
  lower == "hr" ||
  lower == "img" ||
  lower == "input" ||
  lower == "link" ||
  lower == "meta" ||
  lower == "param" ||
  lower == "source" ||
  lower == "track" ||
  lower == "wbr"
}
