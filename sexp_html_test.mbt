///|
test "comment serialization" {
  let input = "(% I want you to know since you came in my life)"
  let expected = "<!-- I want you to know since you came in my life -->"
  @test.assert_eq(sexp_to_html(input), Ok(expected))
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
