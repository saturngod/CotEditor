;
;  highlights.scm
;  for Vue
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


; MARK: Commands
; ----------------------------

(doctype) @commands

(directive_name) @commands


; MARK: Attributes
; ----------------------------

(attribute_name) @attributes

(directive_attribute
  [
    ":"
    "@"
    "#"
    "."
  ] @attributes)

(directive_value) @attributes
(dynamic_directive_inner_value) @variables
(directive_modifier) @attributes


; MARK: Strings
; ----------------------------

(attribute
  (attribute_value) @strings)

(attribute
  (quoted_attribute_value) @strings)

(directive_attribute
  (quoted_attribute_value
    [
      "\""
      "'"
    ] @strings))


; MARK: Characters
; ----------------------------

(entity) @characters

(interpolation
  [
    "{{"
    "}}"
  ] @characters.special)


; MARK: Comments
; ----------------------------

(comment) @comments


; MARK: Injections
; ----------------------------

; -> Mark the ranges injected to other languages
;    so that the highlights of the injected languages are confined to them.
(raw_text) @_injected

(directive_attribute
  (quoted_attribute_value
    (attribute_value) @_injected))
