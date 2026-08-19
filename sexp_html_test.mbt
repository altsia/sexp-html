///|
test "comment serialization" {
  let input = "(% I want you to know since you came in my life)"
  let expected = "<!-- I want you to know since you came in my life -->"
  @test.assert_eq(sexp_to_html(input), Ok(expected))
}

///|
test "comment syntax trims separator whitespace and requires balanced parens" {
  @test.assert_eq(sexp_to_html("(%   hello)"), Ok("<!-- hello -->"))
  @test.assert_eq(
    sexp_to_html("(% hello (world))"),
    Ok("<!-- hello (world) -->"),
  )
  match sexp_to_html("(% hello (world)") {
    Ok(_) => fail("expected an error")
    Err(error) => @test.assert_eq(error.contains("unterminated comment"), true)
  }
}

///|
test "nested element with attribute escaping" {
  let input =
    #|(p One hundred million and two thousand years from now
    #|  (span (:style font-family: "Alegreya Sans SC", sans-serif) 爱してる))
  let expected = "<p>One hundred million and two thousand years from now <span style=\"font-family: &quot;Alegreya Sans SC&quot;, sans-serif\">爱してる</span></p>"
  @test.assert_eq(sexp_to_html(input), Ok(expected))
}

///|
test "escaped parentheses and boolean attribute" {
  let input =
    #|(details (:open)
    #|  (summary every day every night)
    #|  \(I've been waiting to share my love with you\)
    #|  you give light into the darkness skies)
  let expected = "<details open><summary>every day every night</summary> (I've been waiting to share my love with you) you give light into the darkness skies</details>"
  @test.assert_eq(sexp_to_html(input), Ok(expected))
}

///|
test "payload scanner preserves shared escape behavior" {
  @test.assert_eq(
    sexp_to_html("(p slash \\x stays)"),
    Ok("<p>slash \\x stays</p>"),
  )
  @test.assert_eq(
    sexp_to_html("(% keep \\) going)"),
    Ok("<!-- keep ) going -->"),
  )
  @test.assert_eq(
    sexp_to_html("(p (# hello\\)world))"),
    Ok("<p> hello)world</p>"),
  )
  @test.assert_eq(
    sexp_to_html("(div (:title hello\\(x\\)) child)"),
    Ok("<div title=\"hello(x)\">child</div>"),
  )
}

///|
test "payload scanner reports mode-specific unterminated errors" {
  match sexp_to_html("(% hello") {
    Ok(_) => fail("expected an error")
    Err(error) => @test.assert_eq(error.contains("unterminated comment"), true)
  }
  match sexp_to_html("(p (# hello") {
    Ok(_) => fail("expected an error")
    Err(error) =>
      @test.assert_eq(error.contains("unterminated (# ...) text node"), true)
  }
  match sexp_to_html("(div (:title hello") {
    Ok(_) => fail("expected an error")
    Err(error) =>
      @test.assert_eq(error.contains("unterminated attribute"), true)
  }
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
test "whitespace runs collapse to a single space" {
  @test.assert_eq(sexp_to_html("(p one   two)"), Ok("<p>one two</p>"))
  let line_input =
    #|(p line1
    #|line2)
  @test.assert_eq(sexp_to_html(line_input), Ok("<p>line1 line2</p>"))
  @test.assert_eq(sexp_to_html("(p  x)"), Ok("<p>x</p>"))
  let indent_input =
    #|(p
    #|  (b c))
  @test.assert_eq(sexp_to_html(indent_input), Ok("<p><b>c</b></p>"))
}

///|
test "vertical tab and form feed whitespace collapse too" {
  @test.assert_eq(sexp_to_html("(p a\u{000B}b)"), Ok("<p>a b</p>"))
  @test.assert_eq(sexp_to_html("(p a\u{000C}b)"), Ok("<p>a b</p>"))
}

///|
test "space before an element is content, adjacency is no space" {
  @test.assert_eq(sexp_to_html("(p a (b c))"), Ok("<p>a <b>c</b></p>"))
  @test.assert_eq(sexp_to_html("(p a(b c))"), Ok("<p>a<b>c</b></p>"))
  @test.assert_eq(sexp_to_html("(p (b c) a)"), Ok("<p><b>c</b> a</p>"))
  @test.assert_eq(sexp_to_html("(p (b c)a)"), Ok("<p><b>c</b>a</p>"))
  @test.assert_eq(
    sexp_to_html("(p (b c) (d e))"),
    Ok("<p><b>c</b> <d>e</d></p>"),
  )
  @test.assert_eq(sexp_to_html("(p (b c)(d e))"), Ok("<p><b>c</b><d>e</d></p>"))
}

///|
test "trailing space in a text term is content" {
  @test.assert_eq(sexp_to_html("(p x )"), Ok("<p>x </p>"))
}

///|
test "raw text is fully verbatim with no separator consumption" {
  @test.assert_eq(sexp_to_html("(p (#hello))"), Ok("<p>hello</p>"))
  @test.assert_eq(sexp_to_html("(p (# hello))"), Ok("<p> hello</p>"))
  @test.assert_eq(sexp_to_html("(p (#\\(Hello\\)))"), Ok("<p>(Hello)</p>"))
  @test.assert_eq(sexp_to_html("(p (# \\(Hello\\)))"), Ok("<p> (Hello)</p>"))
  @test.assert_eq(sexp_to_html("(p (# a(b))"), Ok("<p> a(b</p>"))
}

///|
test "raw text empty edge cases are valid" {
  @test.assert_eq(sexp_to_html("(p (#))"), Ok("<p></p>"))
  @test.assert_eq(sexp_to_html("(p (# ))"), Ok("<p> </p>"))
}

///|
test "raw text preserves every whitespace character verbatim" {
  @test.assert_eq(sexp_to_html("(p (#   world))"), Ok("<p>   world</p>"))
  let nl_input =
    #|(p (#
    #|world))
  @test.assert_eq(sexp_to_html(nl_input), Ok("<p>\nworld</p>"))
  let space_nl_input =
    #|(p (# 
    #|world))
  @test.assert_eq(sexp_to_html(space_nl_input), Ok("<p> \nworld</p>"))
}

///|
test "raw text remains literal before later attributes" {
  let input = "(div (#  ) (:class x))"
  let expected = "<div class=\"x\">  </div>"
  @test.assert_eq(sexp_to_html(input), Ok(expected))
}

///|
test "document whitespace between terms is content but edges are structural" {
  @test.assert_eq(sexp_to_html("(p a) (p b)"), Ok("<p>a</p> <p>b</p>"))
  @test.assert_eq(sexp_to_html("(p a)(p b)"), Ok("<p>a</p><p>b</p>"))
  @test.assert_eq(sexp_to_html("   (p a)   "), Ok("<p>a</p>"))
  @test.assert_eq(
    sexp_to_html("(p a) between (p b)"),
    Ok("<p>a</p> between <p>b</p>"),
  )
}

///|
test "whitespace before a nested list is part of the preceding text" {
  @test.assert_eq(
    sexp_to_html("(p a  (span x))"),
    Ok("<p>a <span>x</span></p>"),
  )
}

///|
test "whitespace after a list is a separator and collapses to one space" {
  @test.assert_eq(
    sexp_to_html("(p (span x)   world)"),
    Ok("<p><span>x</span> world</p>"),
  )
}

///|
test "trailing whitespace after a list before close is one space" {
  @test.assert_eq(sexp_to_html("(p (span x) )"), Ok("<p><span>x</span> </p>"))
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
    SexpNode::Element("p", Attrs({}), [
      SexpNode::Text("Hello "),
      SexpNode::Element("strong", Attrs({}), [SexpNode::Text("AST")]),
    ]),
  ]
  @test.assert_eq(
    render_html_fragment(nodes),
    "<p>Hello <strong>AST</strong></p>",
  )
}

///|
test "public AST transform can rewrite parsed elements" {
  match parse_sexp("(p (icon search))") {
    Err(error) => fail(error)
    Ok(nodes) => {
      let transformed = nodes.map(transform_icon_test_node)
      @test.assert_eq(
        render_html_fragment(transformed),
        "<p><span class=\"icon\">search</span></p>",
      )
    }
  }
}

///|
test "raw html node renders trusted html without escaping" {
  let nodes = [
    SexpNode::Element("p", Attrs({}), [
      SexpNode::Text("<escaped> "),
      SexpNode::Raw("<em>trusted</em>"),
    ]),
  ]
  @test.assert_eq(
    render_html_fragment(nodes),
    "<p>&lt;escaped&gt; <em>trusted</em></p>",
  )
}

///|
test "document renderer emits doctype and pretty html shell" {
  let html = render_html_document(
    Attrs({ "lang": Some("en") }),
    [SexpNode::Element("title", Attrs({}), [SexpNode::Text("Test")])],
    [SexpNode::Element("p", Attrs({}), [SexpNode::Text("Hello")])],
    Some("html"),
  )
  let expected =
    #|<!DOCTYPE html>
    #|<html lang="en">
    #|  <head>
    #|    <title>Test</title>
    #|  </head>
    #|  <body>
    #|    <p>Hello</p>
    #|  </body>
    #|</html>
  @test.assert_eq(html, expected)
}

///|
test "open tag and attr helpers" {
  let attrs : Attrs = Attrs({})
  attrs.upsert("class", Some("note"))
  attrs.append_class("warning")
  attrs.upsert("id", Some("main"))
  attrs.upsert("id", Some("updated"))
  @test.assert_eq(
    render_open_tag("section", attrs),
    "<section class=\"note warning\" id=\"updated\">",
  )
}

///|
test "parser preserves non-BMP characters" {
  @test.assert_eq(sexp_to_html("(p hi😀there)"), Ok("<p>hi😀there</p>"))
}

///|
test "percent head is a single character" {
  @test.assert_eq(sexp_to_html("(%hello)"), Ok("<!-- hello -->"))
  @test.assert_eq(sexp_to_html("(% hello)"), Ok("<!-- hello -->"))
}

///|
test "raw text standalone verbatim forms" {
  @test.assert_eq(sexp_to_html("(p (#))"), Ok("<p></p>"))
  @test.assert_eq(sexp_to_html("(p (# ))"), Ok("<p> </p>"))
  @test.assert_eq(sexp_to_html("(p (#  ))"), Ok("<p>  </p>"))
}

///|
test "mixed raw and collapsed text" {
  @test.assert_eq(sexp_to_html("(p (# world)  x)"), Ok("<p> world x</p>"))
  @test.assert_eq(sexp_to_html("(p  x  )"), Ok("<p>x </p>"))
}

///|
test "attribute values keep internal whitespace" {
  @test.assert_eq(
    sexp_to_html("(div (:title a  b))"),
    Ok("<div title=\"a  b\"></div>"),
  )
}

///|
test "parse errors report line and column" {
  match sexp_to_html("(p\n  hello\nworld") {
    Ok(_) => fail("expected an error")
    Err(e) =>
      @test.assert_eq(
        e, "parse error at line 3, column 6: unterminated element <p>",
      )
  }
  match sexp_to_html("(br hello)") {
    Ok(_) => fail("expected an error")
    Err(e) =>
      @test.assert_eq(
        e, "parse error at line 1, column 10: void element <br> cannot have child nodes",
      )
  }
  match sexp_to_html("(())") {
    Ok(_) => fail("expected an error")
    Err(e) =>
      @test.assert_eq(
        e, "parse error at line 1, column 2: list head cannot be empty",
      )
  }
  match sexp_to_html("(p (# hello") {
    Ok(_) => fail("expected an error")
    Err(e) =>
      @test.assert_eq(
        e, "parse error at line 1, column 12: unterminated (# ...) text node",
      )
  }
  match sexp_to_html("(p a) unexpected ')'") {
    Ok(_) => fail("expected an error")
    Err(e) =>
      @test.assert_eq(
        e, "parse error at line 1, column 19: unmatched ')' at the top level",
      )
  }
}

///|
fn nested_element_source(depth : Int) -> String {
  let builder = StringBuilder::new()
  for _ in 0..<depth {
    builder.write_string("(div ")
  }
  builder.write_string("x")
  for _ in 0..<depth {
    builder.write_string(")")
  }
  builder.to_string()
}

///|
test "nesting depth is capped at 128" {
  @test.assert_eq(sexp_to_html(nested_element_source(128)) is Ok(_), true)
  match sexp_to_html(nested_element_source(129)) {
    Ok(_) => fail("expected an error")
    Err(e) => @test.assert_eq(e.contains("nesting depth exceeds 128"), true)
  }
}

///|
fn transform_icon_test_node(node : SexpNode) -> SexpNode {
  match node {
    Element("icon", _, children) =>
      SexpNode::Element(
        "span",
        Attrs({ "class": Some("icon") }),
        children.map(transform_icon_test_node),
      )
    Element(tag, attrs, children) =>
      SexpNode::Element(tag, attrs, children.map(transform_icon_test_node))
    _ => node
  }
}
