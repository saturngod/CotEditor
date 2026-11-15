;
;  highlights.scm
;  for Blade
;
;  CotEditor
;  https://coteditor.com
;
;  © 2026 1024jp
;

; MARK: Keywords
; ----------------------------

(tag_name) @keywords
(erroneous_end_tag_name) @keywords.error

[
  (php_tag)
  (php_end_tag)
] @keywords.tag


; MARK: Commands
; ----------------------------

(doctype) @commands

[
  (directive)
  (directive_start)
  (directive_end)
] @commands


; MARK: Attributes
; ----------------------------

(attribute_name) @attributes


; MARK: Strings
; ----------------------------

(attribute
  (attribute_value) @strings)

(quoted_attribute_value
  (attribute_value) @strings)

(quoted_attribute_value
  [
    "\""
    "'"
  ] @strings)


; MARK: Characters
; ----------------------------

(entity) @characters

[
  "{{"
  "}}"
  "{!!"
  "!!}"
] @characters.special


; MARK: Comments
; ----------------------------

(comment) @comments


; MARK: Injections
; ----------------------------

; -> Mark the ranges injected to other languages
;    so that the highlights of the injected languages are confined to them.
[
  (php_only)
  (parameter)
  (raw_text)
] @_injected
