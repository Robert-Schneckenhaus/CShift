# Lexical structure

A source file is a sequence of tokens: identifiers, keywords, literals, operators and punctuation. White space and
comments separate tokens and are otherwise ignored.

## Source text

A source file (`.csh`) is UTF-8 text. Line breaks are `\n` or `\r\n`. Positions in error messages count lines from
1 and columns in characters (a multi-byte UTF-8 character is one column).

## White space and comments

White space is the space, tab, line breaks and the other ASCII white-space characters.

```
// a line comment, up to the end of the line
/* a block comment, over several lines; block comments do not nest */
/// a doc comment: documents the declaration that follows (see "Doc comments" below)
//! a doc comment of the file's namespace
//// four (or more) slashes: an ordinary comment
```

An unterminated block comment is a compile error.

### Doc comments

Consecutive `///` lines form the doc comment of the token that follows them; the parser attaches it to the
declaration that starts with that token (a struct, field, method, function, constant, global variable, enum, enum
member, interface, interface method, union, error enum). `//!` lines anywhere in a file document the file's namespace.
The text is Markdown with links and tags; the rules and the tags are in [doc comments](../language/doc-comments.md).
A doc comment before anything else (a statement, a `namespace` line) is ignored.

## Identifiers

```ebnf
Identifier = IdentStart { IdentStart | Digit } ;
IdentStart = 'A'..'Z' | 'a'..'z' | '_' | any byte of a non-ASCII UTF-8 character ;
Digit      = '0'..'9' ;
```

Identifiers are case-sensitive. An identifier that starts with `_` declares a private member (see
[declarations](declarations.md#visibility)); otherwise the spelling has no meaning to the compiler. An identifier
cannot be a keyword.

## Keywords

These words are reserved and cannot be used as names:

```
break     case      const     continue  default   do        else      embed
embed_filenames     enum      extern    false     for       foreach   if
in        interface is        namespace new       null      ref       return
sizeof    static    struct    switch    this      true      try       unchecked
unsafe    using     while
```

These words are **contextual**: they have a special meaning only in one position and are ordinary identifiers
elsewhere.

| Word | Special where |
|---|---|
| `thread` | before a function declaration: a [thread function](declarations.md#thread-functions) |
| `start` | before a call: starts a thread (`start F(x)`) |
| `union` | at the top level, followed by a name and `{` or `:`: a [union](declarations.md#unions) |
| `error` | at the top level, followed by a name and `{`: an [error enum](declarations.md#error-enums); in an expression, followed by `(`: an [error value](expressions.md#error-values); in a pattern: `is error`, `case error e` |
| `where` | after a generic declaration: a [constraint](declarations.md#constraints) |
| `not` | after `is`: a negated pattern (`x is not T`) |
| `var` | as the type of a local declaration: the type is inferred |
| `from` | in `using Name from "header.h";` |
| `link` | at the top level, followed by a string: `link "m";` |

The names of the built-in types (`int`, `string`, `bool`, `void`, ...) are identifiers that name types; see
[types](types.md#primitive-types).

## Literals

### Integer literals

```ebnf
IntegerLiteral = ( DecimalDigits | '0x' HexDigits | '0X' HexDigits | '0b' BinDigits | '0B' BinDigits ) [ IntSuffix ] ;
DecimalDigits  = Digit { Digit | '_' } ;
HexDigits      = HexDigit { HexDigit | '_' } ;
BinDigits      = ( '0' | '1' ) { '0' | '1' | '_' } ;
IntSuffix      = any combination of 'u', 'U', 'l', 'L' ;
```

`_` separates digits and is ignored (`1_000_000`, `0xFF_FF`). A literal larger than `2^64 - 1` is a compile error, and
so is a letter directly after a literal (`12abc`).

The type of an integer literal:

| Literal | Type |
|---|---|
| without a suffix | `int32` if the value fits, otherwise `int64`, otherwise `uint64` |
| `u` / `U` | `uint32` if the value fits, otherwise `uint64` |
| `l` / `L` | `int64` if the value fits, otherwise `uint64` |
| `ul`, `lu` (any case) | `uint64` |

A literal without a suffix also **adapts to the type it is used with** when its value fits: `uint8 b = 200;`,
`b + 1` (computed in `uint8`, see [integer arithmetic](expressions.md#integer-arithmetic)), and `double d = 1;`. There
are no negative literals: `-5` is the operator `-` applied to `5` (and is folded into a constant).

### Floating-point literals

```ebnf
FloatLiteral = DecimalDigits [ '.' DecimalDigits ] [ Exponent ] [ FloatSuffix ] ;   (* with '.', an exponent or a suffix *)
Exponent     = ( 'e' | 'E' ) [ '+' | '-' ] Digit { Digit } ;
FloatSuffix  = 'f' | 'F' | 'd' | 'D' ;
```

A digit is required on both sides of the point (`1.5`, not `1.` or `.5`). The type is `double` (`float64`), or
`float` (`float32`) with the suffix `f`/`F`; `d`/`D` is the default and only makes an integer a `double` (`2d`). A
`double` literal converts to `float` implicitly when it is used as one (`float x = 0.5;`).

### Character literals

```ebnf
CharLiteral = "'" ( any character but "'", '\' and a line break | Escape ) "'" ;
```

A character literal is one byte: its type is `char`, an 8-bit type of its own that converts implicitly to and from
`uint8` (see [types](types.md#char)). A character outside ASCII is several
bytes in UTF-8 and therefore cannot be a character literal (`'ä'` is a compile error; `'\xE4'` is the byte 0xE4). The
escapes are those of strings; `\u` must give a value up to 255.

### String literals

```ebnf
StringLiteral = '"' { any character but '"', '\' and a line break | Escape } '"' ;
Escape        = '\' ( 'n' | 't' | 'r' | '0' | 'a' | 'b' | 'f' | 'v' | '\' | "'" | '"' )
              | '\x' HexDigit HexDigit
              | '\u' HexDigit HexDigit HexDigit HexDigit ;
```

| Escape | Value |
|---|---|
| `\n` `\t` `\r` `\0` | line feed, tab, carriage return, the byte 0 |
| `\a` `\b` `\f` `\v` | bell, backspace, form feed, vertical tab |
| `\\` `\'` `\"` | the character itself |
| `\xHH` | the **byte** 0xHH (not a character: `\xE4` alone is not valid UTF-8) |
| `\uHHHH` | the Unicode character U+HHHH, encoded as UTF-8 |

A string literal ends on the same line; an unknown escape is a compile error. The type is `string`.

### Interpolated strings

```ebnf
InterpolatedString = '$"' { Text | '{{' | '}}' | Hole } '"' ;
Hole               = '{' Expression [ ',' Alignment ] [ ':' Format ] '}' ;
Alignment          = [ '-' ] DecimalDigits ;
Format             = a letter and up to two digits ;
```

The text uses the escapes of strings; `{{` and `}}` are literal braces, a single `}` is a compile error. A hole
contains an expression (also nested interpolated strings); at its top level, `,` followed by an alignment and `:`
start the alignment and the format, unless the `:` belongs to a conditional `a ? b : c`. The meaning is described in
[expressions](expressions.md#interpolated-strings).

### Boolean and null literals

`true` and `false` are the values of `bool`. `null` is the empty value of strings, arrays, slices, pointers,
`Optional<T>`, `SharedPtr<T>` and function types (see [types](types.md#null)).

## Operators and punctuation

```
{  }  (  )  [  ]  ;  ,  .  ..  ...  :  ?  ->  =>
+  -  *  /  %  &  |  ^  ~  !  <<  >>
=  ==  !=  <  >  <=  >=  &&  ||
+=  -=  *=  /=  %=  &=  |=  ^=  <<=  >>=
```

`>>` and `>>=` are not single tokens: the parser joins two adjacent `>` (and `>` `>=`) so that `List<List<int>>`
closes two type argument lists. `..` is a range in a slice (`a[1..3]`) and a spread in a collection expression
(`[..a]`); `...` marks a variadic C function; `->` accesses a member through a pointer; `=>` separates the parameters
of a lambda from its body. There is no `++` or `--`, no `??` and no `?.`.
