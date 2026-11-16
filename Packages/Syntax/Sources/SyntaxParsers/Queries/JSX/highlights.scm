;
;  highlights.scm
;  for JSX
;
;  CotEditor
;  https://coteditor.com
;
;  © 2026 1024jp
;

; set defaults at first
(identifier) @variables
(property_identifier) @attributes

; UPPER_SNAKE_CASE identifiers
([
    (identifier)
    (shorthand_property_identifier)
    (shorthand_property_identifier_pattern)
 ] @values
 (#match? @values "^[A-Z_][A-Z\\d_]+$"))


; MARK: Keywords
; ----------------------------

[
  "as"
  "async"
  "await"
  "break"
  "case"
  "catch"
  "class"
  "const"
  "continue"
  "debugger"
  "default"
  "delete"
  "do"
  "else"
  "export"
  "extends"
  "finally"
  "for"
  "from"
  "function"
  "get"
  "if"
  "import"
  "in"
  "instanceof"
  "let"
  "new"
  "of"
  "return"
  "set"
  "static"
  "switch"
  "throw"
  "try"
  "typeof"
  "using"
  "var"
  "void"
  "while"
  "with"
  "yield"
] @keywords


; MARK: Commands
; ----------------------------

; function and method calls
(call_expression
  function: (identifier) @commands)
(call_expression
  function: (member_expression
    property: (property_identifier) @commands.method))

; function and method definitions
(function_expression
  name: (identifier) @commands)
(function_declaration
  name: (identifier) @commands)
(method_definition
  name: (property_identifier) @commands.method)

(assignment_expression
  left: (member_expression
    property: (property_identifier) @commands.method)
  right: [(function_expression) (arrow_function)])

(variable_declarator
  name: (identifier) @commands
  value: [(function_expression) (arrow_function)])

(assignment_expression
  left: (identifier) @commands
  right: [(function_expression) (arrow_function)])


; MARK: Types
; ----------------------------

(class_declaration name: (identifier) @types)
(new_expression constructor: (identifier) @types)

; special identifiers
((identifier) @types
  (#match? @types "^[A-Z][a-z]\\w*$"))


; MARK: Attributes
; ----------------------------

; method-like keys (function-valued properties)
(pair
  key: (property_identifier) @commands.method
  value: [(function_expression) (arrow_function)])


; MARK: Variables
; ----------------------------

; built-in variables (mixed env: JS/Node/Browser)
((identifier) @variables
 (#match? @variables "^(arguments|module|console|window|document|globalThis)$"))
 
[
  (this)
  (super)
] @variables.builtin

; -> Normal variables are set at the beginning of the file.


; MARK: Values
; ----------------------------

[
  (true)
  (false)
  (null)
  (undefined)
] @values


; MARK: Numbers
; ----------------------------

(number) @numbers


; MARK: Strings
; ----------------------------

[
  (string)
  (template_string)
] @strings

(regex) @strings


; MARK: Comments
; ----------------------------

(comment) @comments


; MARK: JSX
; ----------------------------

; intrinsic elements (lowercase tag names)
(jsx_opening_element
  name: (identifier) @keywords
  (#match? @keywords "^[a-z]"))
(jsx_closing_element
  name: (identifier) @keywords
  (#match? @keywords "^[a-z]"))
(jsx_self_closing_element
  name: (identifier) @keywords
  (#match? @keywords "^[a-z]"))

; components (capitalized tag names)
(jsx_opening_element
  name: (identifier) @types
  (#match? @types "^[A-Z]"))
(jsx_closing_element
  name: (identifier) @types
  (#match? @types "^[A-Z]"))
(jsx_self_closing_element
  name: (identifier) @types
  (#match? @types "^[A-Z]"))

; namespaced tag names, e.g. <svg:rect>
(jsx_namespace_name) @keywords

; attributes
(jsx_attribute
  (property_identifier) @attributes)
