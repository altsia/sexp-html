///|
pub fn html_to_sexp(source : String) -> Result[String, String] {
  let document = @html5.parse(source)
  serialize_sexp_fragment(document)
}

///|
fn serialize_sexp_fragment(
  document : @html5.Document,
) -> Result[String, String] {
  let node_ids = document.get_children(0)
  collect_fragment_terms(document, node_ids).map(terms => terms.join(""))
}

///|
/// Collects the sexp terms for a list of node ids, flattening the document
/// root into its fragment children.
fn collect_fragment_terms(
  document : @html5.Document,
  node_ids : Array[Int],
) -> Result[Array[String], String] {
  let terms : Array[String] = []
  for node_id in node_ids {
    match render_node_as_sexp_terms(document, node_id) {
      Ok(node_terms) => terms.append(node_terms)
      Err(error) => return Err(error)
    }
  }
  Ok(terms)
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
      let node_ids : Array[Int] = []
      for child_id in element.children {
        node_ids.append(html_document_fragment_child_ids(document, child_id))
      }
      collect_fragment_terms(document, node_ids)
    }
    _ => Err("internal error: document root is not an html element")
  }
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
    Some(@html5.CommentNode(text)) =>
      render_comment_as_sexp_term(text).map(comment => Some(comment))
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
  collect_fragment_terms(document, node_ids).map(join_non_empty_terms)
}

///|
/// Serializes one HTML text node. Bare text is only safe when it cannot be
/// confused with structural whitespace: no leading whitespace and only single
/// internal space characters. Any other text uses the verbatim raw form.
fn render_text_as_sexp_term(text : String) -> Result[String?, String] {
  guard !text.is_empty() else { return Ok(None) }
  guard !text.has_suffix("\\") else {
    return Err(
      "unsupported html text: text ending in a backslash is not representable",
    )
  }
  guard can_use_bare_text(text) else {
    return Ok(Some(render_raw_text_form(text)))
  }
  Ok(Some(escape_sexp_text(text)))
}

///|
/// A text term may be emitted bare when it survives re-parsing unchanged:
/// no leading whitespace, and the only whitespace it may contain is single
/// internal space characters (no tabs, no newlines, no runs of 2+).
fn can_use_bare_text(text : String) -> Bool {
  let chars = text.to_array()
  guard !chars.is_empty() && !chars[0].is_whitespace() else { return false }
  let mut prev_whitespace = false
  for ch in chars {
    if ch.is_whitespace() {
      if ch != ' ' || prev_whitespace {
        return false
      }
      prev_whitespace = true
    } else {
      prev_whitespace = false
    }
  }
  true
}

///|
/// Serializes an HTML comment as `(% ...)`. Canonicalization trims browser
/// comment whitespace before escaping S-expression parens.
fn render_comment_as_sexp_term(text : String) -> Result[String, String] {
  let trimmed = text.trim().to_owned()
  guard !trimmed.has_suffix("\\") else {
    return Err(
      "unsupported html comment: comment ending in a backslash is not representable",
    )
  }
  Ok("(% \{escape_sexp_text(trimmed)})")
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
  match write_sexp_attribute_forms(builder, element.attributes) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match
    write_child_sexp_terms(
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
fn write_sexp_attribute_forms(
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
fn write_child_sexp_terms(
  builder : StringBuilder,
  document : @html5.Document,
  node_ids : Array[Int],
) -> Result[Unit, String] {
  collect_fragment_terms(document, node_ids).map(child_terms => {
    for index, term in child_terms {
      if index == 0 {
        builder.write_char(' ')
      }
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
/// Serializes an HTML attribute form. Empty values become boolean/minimized
/// attrs; leading-whitespace and trailing-backslash values are rejected because
/// they cannot be represented in the plain-text attribute form.
fn render_attribute_as_sexp_form(
  name : String,
  value : String,
) -> Result[String, String] {
  guard !value.is_empty() else { return Ok("(:" + name + ")") }
  guard !starts_with_whitespace(value) else {
    return Err(
      "unsupported html attribute: leading whitespace value on " + name,
    )
  }
  guard !value.has_suffix("\\") else {
    return Err(
      "unsupported html attribute: trailing backslash value on " + name,
    )
  }
  Ok("(:" + name + " " + escape_sexp_text(value) + ")")
}

///|
fn starts_with_whitespace(text : String) -> Bool {
  text.get_char(0).map_or(false, ch => ch.is_whitespace())
}

///|
/// Emits the verbatim raw text form. Content after `#` is literal, so no
/// separator space is added.
fn render_raw_text_form(text : String) -> String {
  "(#" + escape_sexp_text(text) + ")"
}

///|
fn join_non_empty_terms(terms : Array[String]) -> String? {
  guard !terms.is_empty() else { return None }
  Some(terms.join(""))
}

///|
/// Escapes only the characters that are structural in S-expression text terms.
/// Parens become `\(` / `\)`; backslashes are left as literal text.
fn escape_sexp_text(text : String) -> String {
  let chars = text.to_array()
  let builder = StringBuilder::new()
  for ch in chars {
    if is_sexp_text_escape_target(ch) {
      builder.write_char('\\')
    }
    builder.write_char(ch)
  }
  builder.to_string()
}
