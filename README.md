# S-Expression Notation for HTML

## Example

- keep comments
  
  ```sexp
  (% I want you to know since you came in my life)
  ```
  
  $$\Updownarrow$$
  
  ```html
  <!-- I want you to know since you came in my life -->
  ```

- syntactic white spaces between terms will be ignored

  ```sexp
  (p One hundred million and two thousand years from now 
    (span (:style font-family: "Alegreya Sans SC", sans-serif) 
            爱してる) )
  ```

  $$\Updownarrow$$

  ```html
  <p>One hundred million and two thousand years from now 
    <span style="font-family: \"Alegreya Sans SC", sans-serif\">爱してる</span>
  </p>
  ```

- only parentheses need to be escaped

  ```sexp
  (details (:open) 
    (summary every day every night) 
    \(I've been waiting to share my love with you\) 
    you give light into the darkness skies )
  ```

  $$\Updownarrow$$

  ```html
  <details open>
    <summary>every day every night</summary>
    (I've been waiting to share my love with you)
    you give light into the darkness skies
  </details>
  ```

## Specification

see [SPEC.md](./SPEC.md). 
