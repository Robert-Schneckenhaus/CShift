# Grammar

The complete syntax of CShift in the [notation](README.md#notation) of this reference. The rules are collected from
the chapters, which also give their meaning; the expression rules spell out the [precedence table](expressions.md#precedence).
The grammar describes the syntax only: whether a program is valid also depends on the rules of the chapters (types,
names, the bodies that are not allowed after `if`, ...).

## Lexical grammar

See [lexical structure](lexical.md) for comments, white space, the keywords and the contextual words.

```ebnf
Identifier = IdentStart { IdentStart | Digit } ;
IdentStart = 'A'..'Z' | 'a'..'z' | '_' | any byte of a non-ASCII UTF-8 character ;
Digit      = '0'..'9' ;
HexDigit   = Digit | 'a'..'f' | 'A'..'F' ;

IntegerLiteral = ( DecimalDigits | '0x' HexDigits | '0X' HexDigits | '0b' BinDigits | '0B' BinDigits ) [ IntSuffix ] ;
DecimalDigits  = Digit { Digit | '_' } ;
HexDigits      = HexDigit { HexDigit | '_' } ;
BinDigits      = ( '0' | '1' ) { '0' | '1' | '_' } ;
IntSuffix      = any combination of 'u', 'U', 'l', 'L' ;

FloatLiteral = DecimalDigits [ '.' DecimalDigits ] [ Exponent ] [ FloatSuffix ] ;   (* with '.', an exponent or a suffix *)
Exponent     = ( 'e' | 'E' ) [ '+' | '-' ] Digit { Digit } ;
FloatSuffix  = 'f' | 'F' | 'd' | 'D' ;

CharLiteral   = "'" ( any character but "'", '\' and a line break | Escape ) "'" ;
StringLiteral = '"' { any character but '"', '\' and a line break | Escape } '"' ;
Escape        = '\' ( 'n' | 't' | 'r' | '0' | 'a' | 'b' | 'f' | 'v' | '\' | "'" | '"' )
              | '\x' HexDigit HexDigit
              | '\u' HexDigit HexDigit HexDigit HexDigit ;

InterpolatedString = '$"' { Text | '{{' | '}}' | Hole } '"' ;
Hole               = '{' Expression [ ',' Alignment ] [ ':' Format ] '}' ;
Alignment          = [ '-' ] DecimalDigits ;
Format             = a letter and up to two digits ;

Literal = IntegerLiteral | FloatLiteral | CharLiteral | StringLiteral | InterpolatedString
        | 'true' | 'false' | 'null' ;
```

## Programs

See [programs and names](programs.md).

```ebnf
CompilationUnit = { TopLevel } ;
TopLevel        = NamespaceDecl | UsingDecl | ImportDecl | LinkDecl
                | StructDecl | InterfaceDecl | UnionDecl | EnumDecl | ErrorEnumDecl
                | FunctionDecl | ConstDecl | GlobalDecl ;

NamespaceDecl = 'namespace' QualifiedName ';' ;
QualifiedName = Identifier { '.' Identifier } ;
UsingDecl     = 'using' QualifiedName ';' ;
ImportDecl    = 'using' QualifiedName 'from' StringLiteral ';' ;
LinkDecl      = 'link' StringLiteral [ ';' ] ;
```

## Types

See [types](types.md).

```ebnf
Type      = NamedType { '*' | '[' ']' } ;
NamedType = QualifiedName [ '<' TypeArg { ',' TypeArg } '>' ] ;
TypeArg   = Type | IntegerLiteral ;       (* a number only for the size of Fixed<T, N> *)
```

## Declarations

See [declarations](declarations.md).

```ebnf
StructDecl  = 'struct' Identifier [ TypeParams ] [ ':' Type { ',' Type } ] { Constraint } '{' { Member } '}' ;
Member      = Field | Method ;
Field       = Type Identifier ';' ;
Method      = { 'static' | 'unsafe' | 'thread' } Type Identifier [ TypeParams ] '(' [ Params ] ')' { Constraint }
              ( Block | ';' ) ;

InterfaceDecl   = 'interface' Identifier [ TypeParams ] '{' { InterfaceMethod } '}' ;
InterfaceMethod = Type Identifier '(' [ Params ] ')' ';' ;

UnionDecl = 'union' Identifier [ ':' Type { ',' Type } ] '{' Type { ',' Type } [ ',' ] '}' ;

EnumDecl      = 'enum' Identifier ':' Type '{' [ EnumMember { ',' EnumMember } [ ',' ] ] '}' ;
ErrorEnumDecl = 'error' Identifier '{' [ EnumMember { ',' EnumMember } [ ',' ] ] '}' ;
EnumMember    = Identifier [ '=' ConstantExpression ] ;

FunctionDecl = { 'unsafe' | 'thread' } Type Identifier [ TypeParams ] '(' [ Params ] ')' { Constraint } Block
             | 'extern' '"C"' Type Identifier '(' [ Params ] [ ',' '...' ] ')' ( ';' | Block ) ;
Params       = Param { ',' Param } ;
Param        = [ 'ref' | 'const' 'ref' ] Type Identifier ;

TypeParams = '<' Identifier { ',' Identifier } '>' ;
Constraint = 'where' Identifier ':' Type { ',' Type } ;

ConstDecl  = 'const' Type Identifier '=' ConstantExpression ';' ;
GlobalDecl = Type Identifier [ '=' Expression ] ';' ;

ConstantExpression = Expression ;   (* computed when the program is compiled *)
```

## Statements

See [statements](statements.md).

```ebnf
Statement = Block | ';' | LocalDecl | ConstDecl | ExpressionStatement
          | IfStatement | WhileStatement | DoStatement | ForStatement | ForeachStatement | SwitchStatement
          | 'break' ';' | 'continue' ';' | 'return' [ Expression ] ';'
          | UsingStatement | UsingLocal | UnsafeStatement | UncheckedBlock ;

Block               = '{' { Statement } '}' ;
LocalDecl           = ( Type | 'var' ) Identifier [ '=' Expression ] ';' ;
ExpressionStatement = Expression ';' ;
Body                = Statement ;   (* not an if, while, do, for, foreach, switch or using (...) *)

IfStatement      = 'if' '(' Expression ')' Body [ 'else' ( IfStatement | Body ) ] ;
WhileStatement   = 'while' '(' Expression ')' Body ;
DoStatement      = 'do' Body 'while' '(' Expression ')' ';' ;
ForStatement     = 'for' '(' [ ForInit ] ';' [ Expression ] ';' [ Expression { ',' Expression } ] ')' Body ;
ForInit          = ( Type | 'var' ) Identifier [ '=' Expression ] | Expression ;
ForeachStatement = 'foreach' '(' ( Type | 'var' ) Identifier 'in' Expression ')' Body ;

SwitchStatement = 'switch' '(' Expression ')' '{' { SwitchSection } '}' ;
SwitchSection   = CaseLabel { CaseLabel } { Statement } ;
CaseLabel       = 'case' Expression ':' | 'case' Type Identifier ':' | 'default' ':' ;

UsingStatement  = 'using' '(' ( Type | 'var' ) Identifier '=' Expression ')' Body ;
UsingLocal      = 'using' [ Type | 'var' ] Identifier '=' Expression ';' ;
UnsafeStatement = 'unsafe' Block | 'unsafe' Statement ;
UncheckedBlock  = 'unchecked' Block ;
```

## Expressions

See [expressions](expressions.md). Each level binds tighter than the one before it.

```ebnf
Expression     = Assignment ;
Assignment     = Conditional [ AssignOp Assignment ] ;
AssignOp       = '=' | '+=' | '-=' | '*=' | '/=' | '%=' | '&=' | '|=' | '^=' | '<<=' | '>>=' ;
Conditional    = LogicalOr [ '?' Assignment ':' Assignment ] ;
LogicalOr      = LogicalAnd { '||' LogicalAnd } ;
LogicalAnd     = BitOr { '&&' BitOr } ;
BitOr          = BitXor { '|' BitXor } ;
BitXor         = BitAnd { '^' BitAnd } ;
BitAnd         = Equality { '&' Equality } ;
Equality       = Relational { ( '==' | '!=' ) Relational } ;
Relational     = Shift { ( '<' | '>' | '<=' | '>=' ) Shift | 'is' Pattern } ;
Shift          = Additive { ( '<<' | '>>' ) Additive } ;
Additive       = Multiplicative { ( '+' | '-' ) Multiplicative } ;
Multiplicative = Unary { ( '*' | '/' | '%' ) Unary } ;

Unary = ( '-' | '+' | '!' | '~' | '*' | '&' ) Unary
      | '(' Type ')' Unary                        (* a cast *)
      | 'try' Unary
      | 'ref' Unary                               (* only as an argument *)
      | 'start' Postfix                           (* a call of a thread function *)
      | Postfix ;

Postfix = Primary { '.' Identifier [ TypeArgs ] | '->' Identifier | Arguments | '[' Index ']' | Initializer } ;
TypeArgs    = '<' TypeArg { ',' TypeArg } '>' ;
Arguments   = '(' [ Expression { ',' Expression } ] ')' ;
Index       = IndexValue | [ IndexValue ] '..' [ IndexValue ] ;
IndexValue  = [ '^' ] Expression ;
Initializer = '{' [ FieldInit { ',' FieldInit } [ ',' ] ] '}' ;
FieldInit   = Identifier '=' Expression ;

Primary = Literal
        | QualifiedName [ TypeArgs ]
        | 'this'
        | '(' Expression ')'
        | Collection
        | Lambda
        | New
        | ErrorValue
        | 'sizeof' '(' Type ')'
        | 'default' '(' Type ')'
        | 'unchecked' '(' Expression ')'
        | 'embed' '(' StringLiteral ')'
        | 'embed_filenames' '(' StringLiteral ')'
        | 'embed_lines' '(' StringLiteral ')' ;

Pattern = [ 'not' ] ( Type [ Identifier ] | 'null' | 'error' [ Identifier ] ) ;

New = 'new' Type ( '(' ')' | Initializer | '[' Expression ']' { '[' ']' } | '[' ']' ArrayInit )
    | 'new' '(' ')'
    | 'new' Initializer ;
ArrayInit = '{' [ Expression { ',' Expression } [ ',' ] ] '}' ;

Collection = '[' [ Element { ',' Element } [ ',' ] ] ']' ;
Element    = Expression | '..' Expression ;

ErrorValue = 'error' '(' Expression [ ',' Expression ] ')' ;

Lambda       = LambdaParams '=>' ( Expression | Block ) ;
LambdaParams = Identifier | '(' [ Identifier { ',' Identifier } | Param { ',' Param } ] ')' ;
```

**Ambiguities** are resolved like this:

* `(T)x` is a cast when `(T)` parses as a type and is followed by a name, a literal, `(`, `!`, `~`, `new`, `this`,
  `sizeof`, `embed`, `embed_filenames`, `embed_lines`, `null`, `true`, `false`, `try` or `unchecked`. Before `-`, `+`,
  `*` and `&` it is a cast only for a built-in type name or a pointer or array type: `(int)-x` is a cast, `(a) - b` a
  subtraction.
* `Name<...>` in an expression has type arguments only when they parse as types, contain no number, and are followed
  by `(`, `.`, `{`, `;`, `,` or `)`; otherwise `<` is a comparison (`a < b, c > (d)`).
* `>>` closes two type argument lists (`List<List<int>>`); in an expression it is a shift.
* A statement that starts with `Type Identifier` followed by `=` or `;` is a declaration; otherwise it is an
  expression.
* `(` starts a lambda when the parentheses are followed by `=>`; `Identifier =>` is a lambda with one parameter.
* `error(` in an expression is an error value; `error` is otherwise an ordinary name.
