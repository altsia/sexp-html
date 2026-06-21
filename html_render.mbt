///|
const NODE_RENDER_SEPARATOR = ""

///|
pub fn sexp_to_html(
  source : String,
  separator? : String = NODE_RENDER_SEPARATOR,
) -> Result[String, String] {
  parse_sexp_html(source).map(nodes => render_html(nodes, separator~))
}

///|
pub fn render_html(
  nodes : Array[SexpNode],
  separator? : String = NODE_RENDER_SEPARATOR,
) -> String {
  nodes.map(render_node).join(separator)
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
  let builder = StringBuilder()
  builder <+ "< \{tag}"
  append_rendered_attrs(builder, attrs)
  builder <+ ">"
  builder.to_string()
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
    lines.push_iter(
      rendered
      .split("\n")
      .filter(line => line.length() > 0)
      .map(line => indent + line.to_owned()),
    )
  }
}

///|
fn render_element(
  tag : String,
  attrs : Array[(String, String?)],
  children : Array[SexpNode],
) -> String {
  guard !is_void_tag(tag) else { return render_open_tag(tag, attrs) }
  let builder = StringBuilder()
  builder.write_string(render_open_tag(tag, attrs))
  for child in children {
    builder.write_string(render_node(child))
  }
  builder <+ "</"
  builder.write_string(tag)
  builder <+ ">"
  builder.to_string()
}

///|
fn append_rendered_attrs(
  builder : StringBuilder,
  attrs : Array[(String, String?)],
) -> Unit {
  for attr in attrs {
    match attr {
      (name, None) => builder.write_string(name)
      (name, Some(value)) =>
        builder <+ " \{name}=\"\{escape_attribute_value(value)}\""
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
  html_void_tags.contains(tag.to_lower())
}

///|
let html_void_tags : Array[String] = [
  "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param",
  "source", "track", "wbr",
]
