///|
pub fn html_to_sexp(source : String) -> Result[String, String] {
  let document = @html5.parse(source)
  serialize_sexp_fragment(document)
}

///|
fn serialize_sexp_fragment(document : @html5.Document) -> Result[String, String] {
  let node_ids = document.get_children(0)
  render_sexp_fragment_terms(document, node_ids).map(terms => terms.join("\n"))
}

///|
fn render_sexp_fragment_terms(
  document : @html5.Document,
  node_ids : Array[Int],
) -> Result[Array[String], String] {
  let terms : Array[String] = []
  append_sexp_fragment_terms(document, terms, node_ids).map(_ => terms)
}

///|
fn render_node_as_sexp_terms(
  document : @html5.Document,
  node_id : Int,
) -> Result[Array[String], String] {
  if node_id == document.document_element {
    return render_document_element_as_fragment_terms(document, node_id)
  }
  render_node_as_sexp_term(document, node_id).map(x => x.map_or([], xs => [xs]))
}

///|
fn render_document_element_as_fragment_terms(
  document : @html5.Document,
  node_id : Int,
) -> Result[Array[String], String] {
  match document.get_node(node_id) {
    Some(@html5.ElementNode(element)) => {
      let terms : Array[String] = []
      for child_id in element.children {
        let node_ids = html_document_fragment_child_ids(document, child_id)
        let result = append_sexp_fragment_terms(document, terms, node_ids)
        guard result is Err(error) else {  }
        return Err(error)
      }
      Ok(terms)
    }
    _ => Err("internal error: document root is not an html element")
  }
}

///|
fn append_sexp_fragment_terms(
  document : @html5.Document,
  terms : Array[String],
  node_ids : Array[Int],
) -> Result[Unit, String] {
  for node_id in node_ids {
    match render_node_as_sexp_terms(document, node_id) {
      Ok(node_terms) => append_terms(terms, node_terms)
      Err(error) => return Err(error)
    }
  }
  Ok(())
}

///|
fn html_document_fragment_child_ids(
  document : @html5.Document,
  child_id : Int,
) -> Array[Int] {
  if child_id == document.head_element || child_id == document.body_element {
    document.get_children(child_id)
  } else {
    [child_id]
  }
}

///|
fn render_node_as_sexp_term(
  document : @html5.Document,
  node_id : Int,
) -> Result[String?, String] {
  match document.get_node(node_id) {
    Some(@html5.TextNode(text)) => render_text_as_sexp_term(text)
    Some(@html5.CommentNode(text)) => Ok(Some(render_comment_as_sexp_term(text)))
    Some(@html5.ElementNode(element)) =>
      render_element_as_sexp_term(document, node_id, element)
    Some(@html5.DocumentTypeNode(..)) => Ok(None)
    Some(@html5.DocumentNode(children~))
    | Some(@html5.DocumentFragmentNode(children~)) =>
      render_nodes_as_sexp_term(document, children)
    None => Err("internal error: missing html node #" + node_id.to_string())
  }
}

///|
fn render_nodes_as_sexp_term(
  document : @html5.Document,
  node_ids : Array[Int],
) -> Result[String?, String] {
  collect_sexp_terms(document, node_ids).map(join_non_empty_terms)
}

///|
fn render_text_as_sexp_term(text : String) -> Result[String?, String] {
  if !text.is_empty() && !starts_with_whitespace(text) {
    return Ok(Some(escape_sexp_text(text)))
  }
  Ok(Some(render_raw_text_form(text)))
}

///|
fn render_comment_as_sexp_term(text : String) -> String {
  let trimmed = text.trim().to_owned()
  "(% \{escape_sexp_text(trimmed)})"
}

///|
fn render_element_as_sexp_term(
  document : @html5.Document,
  node_id : Int,
  element : @html5.Element,
) -> Result[String?, String] {
  let builder = StringBuilder::new()
  builder.write_char('(')
  builder.write_string(element.tag_name)
  match append_sexp_attribute_forms(builder, element.attributes) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match
    append_child_sexp_terms(
      builder,
      document,
      html_element_child_ids(document, node_id, element),
    ) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  builder.write_char(')')
  Ok(Some(builder.to_string()))
}

///|
fn append_sexp_attribute_forms(
  builder : StringBuilder,
  attrs : Array[(String, String)],
) -> Result[Unit, String] {
  for attr in attrs {
    let (name, value) = attr
    builder.write_char(' ')
    match render_attribute_as_sexp_form(name, value) {
      Ok(attr_term) => builder.write_string(attr_term)
      Err(error) => return Err(error)
    }
  }
  Ok(())
}

///|
fn append_child_sexp_terms(
  builder : StringBuilder,
  document : @html5.Document,
  node_ids : Array[Int],
) -> Result[Unit, String] {
  collect_sexp_terms(document, node_ids).map(child_terms => {
    for term in child_terms {
      builder.write_char(' ')
      builder.write_string(term)
    }
  })
}

///|
fn html_element_child_ids(
  document : @html5.Document,
  node_id : Int,
  element : @html5.Element,
) -> Array[Int] {
  match document.get_template_content(node_id) {
    id if id != @html5.NO_NODE => document.get_children(id)
    _ => element.children
  }
}

///|
fn render_attribute_as_sexp_form(
  name : String,
  value : String,
) -> Result[String, String] {
  if value.is_empty() {
    return Ok("(:" + name + ")")
  }
  if starts_with_whitespace(value) {
    return Err(
      "unsupported html attribute: leading whitespace value on " + name,
    )
  }
  Ok("(:" + name + " " + escape_sexp_text(value) + ")")
}

///|
fn collect_sexp_terms(
  document : @html5.Document,
  node_ids : Array[Int],
) -> Result[Array[String], String] {
  let terms : Array[String] = []
  for node_id in node_ids {
    match render_node_as_sexp_term(document, node_id) {
      Ok(Some(term)) => terms.push(term)
      Ok(None) => ()
      Err(error) => return Err(error)
    }
  }
  Ok(terms)
}

///|
fn append_terms(target : Array[String], terms : Array[String]) -> Unit {
  target.append(terms)
}

///|
fn starts_with_whitespace(text : String) -> Bool {
  text.get_char(0).map_or(false, ch => ch.is_whitespace())
}

///|
fn render_raw_text_form(text : String) -> String {
  "(# " + escape_sexp_text(text) + ")"
}

///|
fn join_non_empty_terms(terms : Array[String]) -> String? {
  if terms.is_empty() {
    None
  } else {
    Some(terms.join("\n"))
  }
}

///|
fn escape_sexp_text(text : String) -> String {
  let chars = text.to_array()
  let builder = StringBuilder::new()
  let mut index = 0
  while index < chars.length() {
    let ch = chars[index]
    if ch == '\\' {
      if index + 1 < chars.length() {
        let next = chars[index + 1]
        if next == '(' || next == ')' {
          builder.write_char('\\')
        }
      }
      builder.write_char(ch)
    } else if ch == '(' || ch == ')' {
      builder.write_char('\\')
      builder.write_char(ch)
    } else {
      builder.write_char(ch)
    }
    index = index + 1
  }
  builder.to_string()
}
