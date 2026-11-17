;
;  injections.scm
;  for Vue
;
;  CotEditor
;  https://coteditor.com
;
;  © 2026 1024jp
;

; MARK: Script
; ----------------------------

; <script lang="ts">
((script_element
  (start_tag
    (attribute
      (attribute_name) @_lang
      (quoted_attribute_value
        (attribute_value) @_value)))
  (raw_text) @injection.content)
 (#eq? @_lang "lang")
 (#eq? @_value "ts")
 (#set! injection.language "typescript"))

; <script lang="tsx">
((script_element
  (start_tag
    (attribute
      (attribute_name) @_lang
      (quoted_attribute_value
        (attribute_value) @_value)))
  (raw_text) @injection.content)
 (#eq? @_lang "lang")
 (#eq? @_value "tsx")
 (#set! injection.language "tsx"))

; <script lang="jsx">
((script_element
  (start_tag
    (attribute
      (attribute_name) @_lang
      (quoted_attribute_value
        (attribute_value) @_value)))
  (raw_text) @injection.content)
 (#eq? @_lang "lang")
 (#eq? @_value "jsx")
 (#set! injection.language "jsx"))

; <script> without `lang`, or with lang="js"
((script_element
  (start_tag) @_start
  (raw_text) @injection.content)
 (#not-match? @_start "lang=[\"'](ts|tsx|jsx)[\"']")
 (#set! injection.language "javascript"))


; MARK: Style
; ----------------------------

((style_element
  (raw_text) @injection.content)
 (#set! injection.language "css"))


; MARK: Template Expressions
; ----------------------------

; -> Parse template expressions separately from the script
;    because they are not always valid code on their own, e.g. `item in items`.
((interpolation
  (raw_text) @injection.content)
 (#set! injection.language "vue_expression"))

((directive_attribute
  (quoted_attribute_value
    (attribute_value) @injection.content))
 (#set! injection.language "vue_expression"))
