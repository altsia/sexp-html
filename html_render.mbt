///|
pub(all) struct HtmlAttrs(Array[(String, String?)])

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
  let attrs = attrs.0
  for i in 0..<attrs.length() {
    if attrs[i] is (existing, _) && existing == name {
      attrs[i] = (name, value)
      return
    }
  }
  attrs.push((name, value))
}

///|
pub fn HtmlAttrs::append_class(self : HtmlAttrs, class_name : String) -> Unit {
  let attrs = self.0
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
      if line.length() > 0 {
        builder <+ "\n\{indent}\{line}"
      }
    }
  }
}

///|
fn render_element(
  tag : String,
  attrs : HtmlAttrs,
  children : Array[SexpNode],
) -> String {
  guard !is_void_element_name(tag) else { return render_open_tag(tag, attrs.0) }
  let builder = StringBuilder()
  builder.write_string(render_open_tag(tag, attrs.0))
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
  for attr in attrs.0 {
    match attr {
      (name, None) => builder <+ " \{name}"
      (name, Some(value)) =>
        builder <+ " \{name}=\"\{escape_html_attr_value(value)}\""
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
