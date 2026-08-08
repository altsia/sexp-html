///|
pub(all) struct HtmlAttrs(Map[String, String?])

///|
const NODE_RENDER_SEPARATOR = ""

///|
pub fn sexp_to_html(
  source : String,
  separator? : String = NODE_RENDER_SEPARATOR,
) -> Result[String, String] {
  parse_sexp_html(source).map(nodes => render_html_fragment(nodes, separator~))
}

///|
pub fn render_html_fragment(
  nodes : Array[SexpNode],
  separator? : String = NODE_RENDER_SEPARATOR,
) -> String {
  nodes.map(SexpNode::render_html).join(separator)
}

///|
pub fn render_html_document(
  html_attrs : HtmlAttrs,
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
pub fn render_open_tag(tag : String, attrs : HtmlAttrs) -> String {
  let builder = StringBuilder()
  builder <+ "<\{tag}"
  append_serialized_attrs(builder, attrs)
  builder <+ ">"
  builder.to_string()
}

///|
pub fn HtmlAttrs::upsert(
  attrs : HtmlAttrs,
  name : String,
  value : String?,
) -> Unit {
  attrs.0[name] = value
}

///|
pub fn HtmlAttrs::append_class(self : HtmlAttrs, class_name : String) -> Unit {
  let attrs = self.0
  match attrs.get("class") {
    Some(Some(value)) => attrs["class"] = Some(value + " " + class_name)
    _ => attrs["class"] = Some(class_name)
  }
}

///|
fn SexpNode::render_html(self : SexpNode) -> String {
  match self {
    Text(text) => escape_html_text(text)
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
    let rendered = render_html_fragment([node])
    for line in rendered.split("\n") {
      guard line.length() > 0 else { continue }
      builder <+ "\n\{indent}\{line}"
    }
  }
}

///|
fn render_element(
  tag : String,
  attrs : HtmlAttrs,
  children : Array[SexpNode],
) -> String {
  guard !is_void_element_name(tag) else { return render_open_tag(tag, attrs) }
  let builder = StringBuilder()
  builder.write_string(render_open_tag(tag, attrs))
  for child in children {
    builder.write_string(child.render_html())
  }
  builder <+ "</"
  builder.write_string(tag)
  builder <+ ">"
  builder.to_string()
}

///|
fn append_serialized_attrs(builder : StringBuilder, attrs : HtmlAttrs) -> Unit {
  for name, value in attrs.0 {
    match value {
      None => builder <+ " \{name}"
      Some(value) => builder <+ " \{name}=\"\{escape_html_attr_value(value)}\""
    }
  }
}

///|
pub fn is_void_element_name(tag : String) -> Bool {
  html_void_element_names.contains(tag.to_lower())
}

///|
let html_void_element_names : Array[String] = [
  "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param",
  "source", "track", "wbr",
]
