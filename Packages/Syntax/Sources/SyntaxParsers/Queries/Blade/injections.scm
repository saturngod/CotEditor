;
;  Injections.scm
;  for Blade
;
;  CotEditor
;  https://coteditor.com
;
;  © 2026 1024jp
;

; MARK: PHP
; ----------------------------

((php_only) @injection.content
 (#set! injection.language "php_only"))

; -> Parse directive arguments separately from the other PHP code
;    because they are not always valid PHP on their own, e.g. `($users as $user)`.
((parameter) @injection.content
 (#set! injection.language "php_parameter"))


; MARK: JavaScript and CSS
; ----------------------------

((script_element
  (raw_text) @injection.content)
 (#set! injection.language "javascript"))

((style_element
  (raw_text) @injection.content)
 (#set! injection.language "css"))
