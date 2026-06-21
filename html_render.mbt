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
  html_attrs : Array[(String, String?)],
  head : Array[SexpNode],
  body : Array[SexpNode],
  doctype : String?,
) -> String {
  let builder = StringBuilder()
  if doctype is Some(value) {
    builder <+ "<!DOCTYPE \{value}>\n"
  }
  builder.write_string(render_open_tag("html", html_attrs))
  builder <+ "\n  <head>"
  push_rendered_lines(builder, head, "    ")
  builder <+ "\n  </head>\n  <body>"
  push_rendered_lines(builder, body, "    ")
  builder <+ "\n  </body>\n</html>"
  builder.to_string()
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
    if attrs[i] is (existing, _) && existing == name {
      attrs[i] = (name, value)
      return
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
    if attrs[i] is ("class", Some(value)) {
      attrs[i] = ("class", Some(value + " " + class_name))
      return
    }
    if attrs[i] is ("class", None) {
      attrs[i] = ("class", Some(class_name))
      return
    }
  }
  attrs.push(("class", Some(class_name)))
}

///|
fn render_node(node : SexpNode) -> String {
  match node {
    Text(text) => html_escape_text(text)
    Comment(text) => "<!-- " + text + " -->"
    RawHtml(html) => html
    Element(tag, attrs, children) => render_element(tag, attrs, children)
  }
}

///|
fn push_rendered_lines(
  builder : StringBuilder,
  nodes : Array[SexpNode],
  indent : String,
) -> Unit {
  for node in nodes {
    let rendered = render_html([node])
    for line in rendered.split("\n") {
      if line.length() > 0 {
        builder <+ "\n\{indent}\{line}"
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
        builder <+ " \{name}=\"\{html_escape_attribute_value(value)}\""
    }
  }
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
