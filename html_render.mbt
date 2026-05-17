///|
fn render_document(nodes : Array[Node]) -> String {
  let parts : Array[String] = []
  for node in nodes {
    parts.push(render_node(node))
  }
  parts.join("")
}

///|
fn render_node(node : Node) -> String {
  match node {
    Text(text) => escape_text(text)
    RawText(text) => escape_text(text)
    Space => " "
    Comment(text) => "<!-- " + text + " -->"
    Element(tag, attrs, children) => render_element(tag, attrs, children)
    SpacedElement(tag, attrs, children) =>
      " " + render_element(tag, attrs, children) + " "
  }
}

///|
fn render_element(
  tag : String,
  attrs : Array[(String, String?)],
  children : Array[Node],
) -> String {
  let parts : Array[String] = ["<", tag]
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
