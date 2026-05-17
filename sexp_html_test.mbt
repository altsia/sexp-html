///|
test "comment serialization" {
  let input = "(% I want you to know since you came in my life)"
  let expected = "<!-- I want you to know since you came in my life -->"
  @test.assert_eq(sexp_to_html(input), Ok(expected))
}

///|
test "comment syntax trims separator whitespace and requires balanced parens" {
  @test.assert_eq(sexp_to_html("(%   hello)"), Ok("<!-- hello -->"))
  @test.assert_eq(sexp_to_html("(% hello (world))"), Ok("<!-- hello (world) -->"))
  match sexp_to_html("(% hello (world)") {
    Ok(_) => fail("expected an error")
    Err(error) => @test.assert_eq(error.contains("unterminated comment"), true)
  }
}

///|
test "nested element with attribute escaping" {
  let input = "(p One hundred million and two thousand years from now\n  (span (:style font-family: \"Alegreya Sans SC\", sans-serif) 爱してる))"
  let expected = "<p>One hundred million and two thousand years from now\n  <span style=\"font-family: &quot;Alegreya Sans SC&quot;, sans-serif\">爱してる</span></p>"
  @test.assert_eq(sexp_to_html(input), Ok(expected))
}

///|
test "escaped parentheses and boolean attribute" {
  let input = "(details (:open)\n  (summary every day every night)\n  \\(I've been waiting to share my love with you\\)\n  you give light into the darkness skies)"
  let expected = "<details open><summary>every day every night</summary>(I've been waiting to share my love with you)\n  you give light into the darkness skies</details>"
  @test.assert_eq(sexp_to_html(input), Ok(expected))
}

///|
test "attributes may follow children and last one wins" {
  let input = "(div hello (:class a) (:class b) (:id main))"
  let expected = "<div class=\"b\" id=\"main\">hello</div>"
  @test.assert_eq(sexp_to_html(input), Ok(expected))
}

///|
test "void elements cannot have children" {
  match sexp_to_html("(br hello)") {
    Ok(_) => fail("expected an error")
    Err(error) => @test.assert_eq(error.contains("void element"), true)
  }
}

///|
test "attribute values cannot contain nested structure" {
  match sexp_to_html("(:title (b hello))") {
    Ok(_) => fail("expected an error")
    Err(error) => @test.assert_eq(error.contains("attribute"), true)
  }
}

///|
test "standalone space form serializes to one space" {
  @test.assert_eq(sexp_to_html("(~)"), Ok(" "))
}

///|
test "spaced element form adds spaces on both sides" {
  let input = "(p (~span Hello)world)"
  let expected = "<p> <span>Hello</span> world</p>"
  @test.assert_eq(sexp_to_html(input), Ok(expected))
}

///|
test "raw text form preserves leading whitespace and escaped parens" {
  let input = "(p (# \\(Hello\\)))"
  let expected = "<p>(Hello)</p>"
  @test.assert_eq(sexp_to_html(input), Ok(expected))
}

///|
test "raw text empty edge cases are valid" {
  @test.assert_eq(sexp_to_html("(p (#))"), Ok("<p></p>"))
  @test.assert_eq(sexp_to_html("(p (# ))"), Ok("<p></p>"))
}

///|
test "raw text consumes only one separator whitespace" {
  let input = "(p (#   world))"
  let expected = "<p>  world</p>"
  @test.assert_eq(sexp_to_html(input), Ok(expected))
}

///|
test "raw text separator may be any whitespace character" {
  @test.assert_eq(sexp_to_html("(p (#\nworld))"), Ok("<p>world</p>"))
  @test.assert_eq(sexp_to_html("(p (# \nworld))"), Ok("<p>\nworld</p>"))
}

///|
test "raw text remains literal before later attributes" {
  let input = "(div (#  ) (:class x))"
  let expected = "<div class=\"x\"> </div>"
  @test.assert_eq(sexp_to_html(input), Ok(expected))
}

///|
test "lists must have a non-empty head term" {
  match sexp_to_html("(())") {
    Ok(_) => fail("expected an error")
    Err(error) => @test.assert_eq(error.contains("list head"), true)
  }
}

///|
test "public AST can be rendered directly" {
  let nodes = [
    SexpNode::Element(
      "p",
      [],
      [
        SexpNode::Text("Hello "),
        SexpNode::Element("strong", [], [SexpNode::Text("AST")]),
      ],
    ),
  ]
  @test.assert_eq(render_html(nodes), "<p>Hello <strong>AST</strong></p>")
}

///|
test "public AST transform can rewrite parsed elements" {
  match parse_sexp_html("(p (icon search))") {
    Err(error) => fail(error)
    Ok(nodes) => {
      let transformed = transform_icon_test_nodes(nodes)
      @test.assert_eq(
        render_html(transformed),
        "<p><span class=\"icon\">search</span></p>",
      )
    }
  }
}

///|
test "custom renderer can emit html for selected nodes" {
  let input = "(article (markdown **Hello**))"
  let expected = "<article><strong>Hello</strong></article>"
  @test.assert_eq(sexp_to_html_with(input, render_markdown_test_node), Ok(expected))
}

///|
test "custom renderer keeps default escaping for other nodes" {
  let input = "(p <escaped> (raw-html <em>trusted</em>))"
  let expected = "<p>&lt;escaped&gt; <em>trusted</em></p>"
  @test.assert_eq(sexp_to_html_with(input, render_raw_html_test_node), Ok(expected))
}

///|
test "html fragment to sexp element" {
  let input = "<p>Hello</p>"
  @test.assert_eq(html_to_sexp(input), Ok("(p Hello)"))
}

///|
test "html fragment with nested content and attrs" {
  let input = "<details open><summary>every day every night</summary>(I've been waiting)</details>"
  let expected = "(details (:open) (summary every day every night) \\(I've been waiting\\))"
  @test.assert_eq(html_to_sexp(input), Ok(expected))
}

///|
test "leading spaces become explicit space forms" {
  let input = "<p><span>Hello</span> world</p>"
  let expected = "(p (span Hello) (#  world))"
  @test.assert_eq(html_to_sexp(input), Ok(expected))
}

///|
test "html full document is flattened back to fragment" {
  let input = "<!DOCTYPE html><html><head><title>Test</title></head><body><p>World</p></body></html>"
  let expected = "(title Test)\n(p World)"
  @test.assert_eq(html_to_sexp(input), Ok(expected))
}

///|
test "leading newline becomes raw text form" {
  let input = "<p><span>Hello</span>\nworld</p>"
  let expected = "(p (span Hello) (# \nworld))"
  @test.assert_eq(html_to_sexp(input), Ok(expected))
}

///|
test "whitespace-only text nodes use canonical raw text forms" {
  @test.assert_eq(html_to_sexp("<p> </p>"), Ok("(p (#  ))"))
  @test.assert_eq(html_to_sexp("<p>\n</p>"), Ok("(p (# \n))"))
}

///|
test "html comments are trimmed when canonicalized" {
  @test.assert_eq(html_to_sexp("<!--  hello  -->"), Ok("(% hello)"))
  @test.assert_eq(html_to_sexp("<!--   -->"), Ok("(% )"))
}

///|
test "html attrs with leading whitespace values are unsupported" {
  match html_to_sexp("<div title=\" hello\"></div>") {
    Ok(_) => fail("expected an error")
    Err(error) => @test.assert_eq(error.contains("leading whitespace"), true)
  }
}

///|
test "empty html attr values canonicalize to minimized attrs" {
  @test.assert_eq(html_to_sexp("<details open></details>"), Ok("(details (:open))"))
  @test.assert_eq(html_to_sexp("<div class=\"\"></div>"), Ok("(div (:class))"))
}

///|
fn transform_icon_test_nodes(nodes : Array[SexpNode]) -> Array[SexpNode] {
  let transformed : Array[SexpNode] = []
  for node in nodes {
    transformed.push(transform_icon_test_node(node))
  }
  transformed
}

///|
fn transform_icon_test_node(node : SexpNode) -> SexpNode {
  match node {
    Element("icon", _, children) =>
      SexpNode::Element(
        "span",
        [("class", Some("icon"))],
        transform_icon_test_nodes(children),
      )
    Element(tag, attrs, children) =>
      SexpNode::Element(tag, attrs, transform_icon_test_nodes(children))
    _ => node
  }
}

///|
fn render_markdown_test_node(node : SexpNode) -> String? {
  match node {
    Element("markdown", _, [Text("**Hello**")]) => Some("<strong>Hello</strong>")
    _ => None
  }
}

///|
fn render_raw_html_test_node(node : SexpNode) -> String? {
  match node {
    Element("raw-html", _, [Text(html)]) => Some(html)
    _ => None
  }
}
