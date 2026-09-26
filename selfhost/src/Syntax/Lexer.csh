// The lexer: turns source text (UTF-8) into tokens.

namespace CShift.Syntax;

using System;

struct Lexer
{
    string Src;
    int FileId;
    Diagnostics Diag;
    int Pos;
    int Line;
    int Col;
    Dictionary<string, TokenKind> Keywords;

    static Lexer Create(string source, int fileId, Diagnostics diag)
    {
        var lexer = Lexer { Src = source, FileId = fileId, Diag = diag, Pos = 0, Line = 1, Col = 1 };
        lexer.Keywords = Dictionary<string, TokenKind>.Create();
        lexer.Keywords.Set("namespace", TokenKind.KwNamespace);
        lexer.Keywords.Set("using", TokenKind.KwUsing);
        lexer.Keywords.Set("struct", TokenKind.KwStruct);
        lexer.Keywords.Set("interface", TokenKind.KwInterface);
        lexer.Keywords.Set("enum", TokenKind.KwEnum);
        lexer.Keywords.Set("extern", TokenKind.KwExtern);
        lexer.Keywords.Set("unsafe", TokenKind.KwUnsafe);
        lexer.Keywords.Set("unchecked", TokenKind.KwUnchecked);
        lexer.Keywords.Set("if", TokenKind.KwIf);
        lexer.Keywords.Set("else", TokenKind.KwElse);
        lexer.Keywords.Set("while", TokenKind.KwWhile);
        lexer.Keywords.Set("do", TokenKind.KwDo);
        lexer.Keywords.Set("for", TokenKind.KwFor);
        lexer.Keywords.Set("foreach", TokenKind.KwForeach);
        lexer.Keywords.Set("in", TokenKind.KwIn);
        lexer.Keywords.Set("switch", TokenKind.KwSwitch);
        lexer.Keywords.Set("case", TokenKind.KwCase);
        lexer.Keywords.Set("default", TokenKind.KwDefault);
        lexer.Keywords.Set("break", TokenKind.KwBreak);
        lexer.Keywords.Set("continue", TokenKind.KwContinue);
        lexer.Keywords.Set("return", TokenKind.KwReturn);
        lexer.Keywords.Set("new", TokenKind.KwNew);
        lexer.Keywords.Set("try", TokenKind.KwTry);
        lexer.Keywords.Set("is", TokenKind.KwIs);
        lexer.Keywords.Set("const", TokenKind.KwConst);
        lexer.Keywords.Set("ref", TokenKind.KwRef);
        lexer.Keywords.Set("static", TokenKind.KwStatic);
        lexer.Keywords.Set("true", TokenKind.KwTrue);
        lexer.Keywords.Set("false", TokenKind.KwFalse);
        lexer.Keywords.Set("null", TokenKind.KwNull);
        lexer.Keywords.Set("this", TokenKind.KwThis);
        lexer.Keywords.Set("sizeof", TokenKind.KwSizeof);
        // 'start' (as in 'start Foo(...)') is not a keyword: the parser recognizes it by its position (ParseUnary).
        return lexer;
    }

    // ---- character access ----

    char Peek(int ahead)
    {
        int i = Pos + ahead;
        if (i < Src.Length)
            return Src[i];
        return '\0';
    }

    bool AtEnd()
    {
        return Pos >= Src.Length;
    }

    char Advance()
    {
        char c = Src[Pos];
        Pos += 1;
        if (c == '\n')
        {
            Line += 1;
            Col = 1;
        }
        else if ((c & 0xC0) != 0x80) // UTF-8 continuation bytes do not count as columns
        {
            Col += 1;
        }
        return c;
    }

    SourceLoc Here()
    {
        return SourceLoc { File = FileId, Line = Line, Col = Col };
    }

    Error<Token> Fail(SourceLoc loc, string message)
    {
        return error(message, loc.Pack());
    }

    static bool IsIdentStart(char c)
    {
        return Char.IsLetter(c) || c == '_' || c >= 0x80;
    }

    static bool IsIdentPart(char c)
    {
        return IsIdentStart(c) || Char.IsDigit(c);
    }

    // ---- whitespace and comments ----

    void SkipTrivia()
    {
        while (!AtEnd())
        {
            char c = Peek(0);
            if (Char.IsWhiteSpace(c))
            {
                Advance();
            }
            else if (c == '/' && Peek(1) == '/')
            {
                while (!AtEnd() && Peek(0) != '\n')
                    Advance();
            }
            else if (c == '/' && Peek(1) == '*')
            {
                SourceLoc start = Here();
                Advance();
                Advance();
                while (!AtEnd() && !(Peek(0) == '*' && Peek(1) == '/'))
                    Advance();
                if (AtEnd())
                {
                    Diag.ReportAt(start, "unterminated block comment");
                }
                else
                {
                    Advance();
                    Advance();
                }
            }
            else
            {
                break;
            }
        }
    }

    // ---- the token list ----

    List<Token> Tokenize()
    {
        var tokens = List<Token>.Create();
        while (true)
        {
            SkipTrivia();
            if (AtEnd())
                break;

            char c = Peek(0);
            if (c == '$' && Peek(1) == '"')
            {
                int mark = tokens.Count();
                SourceLoc interpLoc = Here();
                var interp = LexInterpolated(tokens);
                if (interp is error interpError)
                {
                    Diag.Report(FileId, interpError.Message, interpError.Code);
                    // continue after the string with an empty string in its place (no follow-up errors)
                    while (tokens.Count() > mark)
                        tokens.RemoveAt(tokens.Count() - 1);
                    while (!AtEnd() && Peek(0) != '"' && Peek(0) != '\n')
                        Advance();
                    if (!AtEnd() && Peek(0) == '"')
                        Advance();
                    tokens.Add(Token { Kind = TokenKind.StringLit, Loc = interpLoc, Text = "" });
                }
                continue;
            }
            Error<Token> result;
            if (Char.IsDigit(c))
                result = LexNumber();
            else if (c == '"')
                result = LexString();
            else if (c == '\'')
                result = LexChar();
            else if (IsIdentStart(c))
                result = LexIdentifier();
            else
                result = LexPunct();

            if (result is Token t)
                tokens.Add(t);
            else
                Diag.Report(FileId, result.Message, result.Code);
        }
        var eof = Token { Kind = TokenKind.Eof, Loc = Here(), Text = "" };
        tokens.Add(eof);
        return tokens;
    }

    Error<Token> LexIdentifier()
    {
        var t = Token { Loc = Here(), Text = "" };
        int start = Pos;
        while (!AtEnd() && IsIdentPart(Peek(0)))
            Advance();
        t.Text = Src.Substring(start, Pos - start);
        t.Kind = Keywords.GetOrDefault(t.Text, TokenKind.Ident);
        return t;
    }

    // ---- numbers ----

    Error<Token> LexNumber()
    {
        var t = Token { Loc = Here(), Text = "" };

        if (Peek(0) == '0' && (Peek(1) == 'x' || Peek(1) == 'X' || Peek(1) == 'b' || Peek(1) == 'B'))
        {
            bool hex = Peek(1) == 'x' || Peek(1) == 'X';
            Advance();
            Advance();
            uint64 value = 0;
            int digits = 0;
            while (!AtEnd())
            {
                char c = Peek(0);
                int d;
                if (c == '_')
                {
                    Advance();
                    continue;
                }
                if (Char.IsDigit(c))
                    d = c - '0';
                else if (hex && Char.IsHexDigit(c))
                    d = Char.HexValue(c);
                else
                    break;
                if (!hex && d > 1)
                    break;
                if ((value >> (hex ? 60 : 63)) != 0)
                    return Fail(t.Loc, "integer literal is too large");
                value = value * (hex ? 16u : 2u) + (uint64)d;
                digits += 1;
                Advance();
            }
            if (digits == 0)
                return Fail(t.Loc, "invalid numeric literal");
            t.Kind = TokenKind.IntLit;
            t.IntValue = value;
        }
        else
        {
            var digits = StringBuilder.Create();
            bool isFloat = false;
            while (Char.IsDigit(Peek(0)) || Peek(0) == '_')
            {
                char c = Advance();
                if (c != '_')
                    digits.Append(c);
            }
            if (Peek(0) == '.' && Char.IsDigit(Peek(1)))
            {
                isFloat = true;
                digits.Append(Advance());
                while (Char.IsDigit(Peek(0)) || Peek(0) == '_')
                {
                    char c = Advance();
                    if (c != '_')
                        digits.Append(c);
                }
            }
            if ((Peek(0) == 'e' || Peek(0) == 'E') &&
                (Char.IsDigit(Peek(1)) || ((Peek(1) == '+' || Peek(1) == '-') && Char.IsDigit(Peek(2)))))
            {
                isFloat = true;
                digits.Append(Advance());
                if (Peek(0) == '+' || Peek(0) == '-')
                    digits.Append(Advance());
                while (Char.IsDigit(Peek(0)))
                    digits.Append(Advance());
            }

            string text = digits.ToString();
            if (isFloat || Peek(0) == 'f' || Peek(0) == 'F' || Peek(0) == 'd' || Peek(0) == 'D')
            {
                t.Kind = TokenKind.FloatLit;
                var parsed = text.ParseDouble();
                if (parsed is double f)
                    t.FloatValue = f;
                else
                    return Fail(t.Loc, "invalid numeric literal");
                if (Peek(0) == 'f' || Peek(0) == 'F')
                {
                    t.IsFloat32 = true;
                    Advance();
                }
                else if (Peek(0) == 'd' || Peek(0) == 'D')
                {
                    Advance();
                }
            }
            else
            {
                t.Kind = TokenKind.IntLit;
                uint64 value = 0;
                for (var i = 0; i < text.Length; i += 1)
                {
                    uint64 d = (uint64)(text[i] - '0');
                    if (value > (0xFFFFFFFFFFFFFFFFul - d) / 10)
                        return Fail(t.Loc, "integer literal is too large");
                    value = value * 10 + d;
                }
                t.IntValue = value;
            }
        }

        if (t.Kind == TokenKind.IntLit)
        {
            // Suffixes: u, l, ul
            while (Peek(0) == 'u' || Peek(0) == 'U' || Peek(0) == 'l' || Peek(0) == 'L')
            {
                char c = Advance();
                if (c == 'u' || c == 'U')
                    t.IsUnsigned = true;
                else
                    t.IsLong = true;
            }
        }

        if (IsIdentStart(Peek(0)))
            return Fail(Here(), "invalid suffix on numeric literal");
        return t;
    }

    // ---- strings and characters ----

    static void AppendUtf8(StringBuilder sb, uint32 cp)
    {
        if (cp < 0x80)
        {
            sb.Append((char)cp);
        }
        else if (cp < 0x800)
        {
            sb.Append((char)(0xC0 | (cp >> 6)));
            sb.Append((char)(0x80 | (cp & 0x3F)));
        }
        else if (cp < 0x10000)
        {
            sb.Append((char)(0xE0 | (cp >> 12)));
            sb.Append((char)(0x80 | ((cp >> 6) & 0x3F)));
            sb.Append((char)(0x80 | (cp & 0x3F)));
        }
        else
        {
            sb.Append((char)(0xF0 | (cp >> 18)));
            sb.Append((char)(0x80 | ((cp >> 12) & 0x3F)));
            sb.Append((char)(0x80 | ((cp >> 6) & 0x3F)));
            sb.Append((char)(0x80 | (cp & 0x3F)));
        }
    }

    // Reads an escape sequence after the backslash and returns its value (a code point for \u, a byte for \x).
    Error<uint32> LexEscape()
    {
        SourceLoc loc = Here();
        char c = Advance();
        switch (c)
        {
        case 'n': return 10u;
        case 't': return 9u;
        case 'r': return 13u;
        case '0': return 0u;
        case 'a': return 7u;
        case 'b': return 8u;
        case 'f': return 12u;
        case 'v': return 11u;
        case '\\': return 92u;
        case '\'': return 39u;
        case '"': return 34u;
        case 'x':
        case 'u':
        {
            int count = c == 'x' ? 2 : 4;
            uint32 value = 0;
            for (var i = 0; i < count; i += 1)
            {
                if (!Char.IsHexDigit(Peek(0)))
                    return error("invalid escape sequence", loc.Pack());
                char h = Advance();
                value = value * 16u + (uint32)Char.HexValue(h);
            }
            return value;
        }
        default:
            return error("unknown escape sequence '\\" + c.ToString() + "'", loc.Pack());
        }
    }

    Error<Token> LexString()
    {
        var t = Token { Kind = TokenKind.StringLit, Loc = Here() };
        var text = StringBuilder.Create();
        Advance(); // opening quote
        while (true)
        {
            if (AtEnd() || Peek(0) == '\n')
                return Fail(t.Loc, "unterminated string literal");
            char c = Advance();
            if (c == '"')
                break;
            if (c == '\\')
            {
                bool isU = Peek(0) == 'u';
                var escape = LexEscape();
                if (escape is uint32 cp)
                {
                    if (isU)
                        AppendUtf8(text, cp);
                    else
                        text.Append((char)cp); // \xHH is a raw byte
                }
                else
                {
                    return error(escape.Message, escape.Code);
                }
            }
            else
            {
                text.Append(c);
            }
        }
        t.Text = text.ToString();
        return t;
    }

    // $"a {x} b {y + 1} c": InterpStart("a "), the tokens of x, InterpMid(" b "), the tokens of y + 1, InterpEnd(" c").
    // A string without holes is a plain StringLit. "{{" and "}}" are literal braces; the escapes are those of strings.
    Error<void> LexInterpolated(List<Token> tokens)
    {
        SourceLoc start = Here();
        Advance(); // $
        Advance(); // "
        var text = StringBuilder.Create();
        var textLoc = start;
        bool anyHole = false;
        while (true)
        {
            if (AtEnd() || Peek(0) == '\n')
                return error("unterminated interpolated string", start.Pack());
            char c = Advance();
            if (c == '"')
                break;
            if (c == '{' && Peek(0) == '{')
            {
                Advance();
                text.Append('{');
            }
            else if (c == '}' && Peek(0) == '}')
            {
                Advance();
                text.Append('}');
            }
            else if (c == '}')
                return error("a single '}' in an interpolated string must be written as '}}'", Here().Pack());
            else if (c == '{')
            {
                tokens.Add(Token { Kind = anyHole ? TokenKind.InterpMid : TokenKind.InterpStart, Loc = textLoc, Text = text.ToString() });
                text.Clear();
                anyHole = true;
                // the tokens of the hole, up to the matching '}'
                int depth = 0;
                int first = tokens.Count();
                while (true)
                {
                    SkipTrivia();
                    if (AtEnd())
                        return error("unterminated interpolated string", start.Pack());
                    char h = Peek(0);
                    if (h == '}' && depth == 0)
                        break;
                    if (h == '$' && Peek(1) == '"')
                    {
                        try LexInterpolated(tokens);
                        continue;
                    }
                    Error<Token> result;
                    if (Char.IsDigit(h))
                        result = LexNumber();
                    else if (h == '"')
                        result = LexString();
                    else if (h == '\'')
                        result = LexChar();
                    else if (IsIdentStart(h))
                        result = LexIdentifier();
                    else
                        result = LexPunct();
                    var tok = try result;
                    if (tok.Kind == TokenKind.LBrace)
                        depth += 1;
                    else if (tok.Kind == TokenKind.RBrace)
                        depth -= 1;
                    tokens.Add(tok);
                }
                if (tokens.Count() == first)
                    return error("empty hole '{}' in an interpolated string", Here().Pack());
                textLoc = Here();
                Advance(); // }
            }
            else if (c == '\\')
            {
                bool isU = Peek(0) == 'u';
                uint32 cp = try LexEscape();
                if (isU)
                    AppendUtf8(text, cp);
                else
                    text.Append((char)cp);
            }
            else
                text.Append(c);
        }
        tokens.Add(Token { Kind = anyHole ? TokenKind.InterpEnd : TokenKind.StringLit, Loc = anyHole ? textLoc : start, Text = text.ToString() });
        return;
    }

    Error<Token> LexChar()
    {
        var t = Token { Kind = TokenKind.CharLit, Loc = Here(), Text = "" };
        Advance(); // opening quote
        if (AtEnd() || Peek(0) == '\n')
            return Fail(t.Loc, "unterminated char literal");

        uint32 value;
        char c = Advance();
        if (c == '\\')
        {
            var escape = LexEscape();
            if (escape is uint32 cp)
                value = cp;
            else
                return error(escape.Message, escape.Code);
        }
        else
        {
            value = (uint32)c;
        }

        if (value > 0xFF)
            return Fail(t.Loc, "char literals are single UTF-8 code units (0-255)");
        if (Peek(0) != '\'')
            return Fail(t.Loc, "char literal must contain exactly one UTF-8 code unit");
        Advance();
        t.IntValue = (uint64)value;
        return t;
    }

    // ---- punctuation ----

    bool Match(char next)
    {
        if (Peek(0) == next)
        {
            Advance();
            return true;
        }
        return false;
    }

    Error<Token> LexPunct()
    {
        var t = Token { Loc = Here(), Text = "" };
        char c = Advance();
        switch (c)
        {
        case '{': t.Kind = TokenKind.LBrace; break;
        case '}': t.Kind = TokenKind.RBrace; break;
        case '(': t.Kind = TokenKind.LParen; break;
        case ')': t.Kind = TokenKind.RParen; break;
        case '[': t.Kind = TokenKind.LBracket; break;
        case ']': t.Kind = TokenKind.RBracket; break;
        case ';': t.Kind = TokenKind.Semi; break;
        case ',': t.Kind = TokenKind.Comma; break;
        case ':': t.Kind = TokenKind.Colon; break;
        case '?': t.Kind = TokenKind.Question; break;
        case '~': t.Kind = TokenKind.Tilde; break;
        case '.':
            if (Peek(0) == '.' && Peek(1) == '.')
            {
                Advance();
                Advance();
                t.Kind = TokenKind.Ellipsis;
            }
            else
            {
                t.Kind = TokenKind.Dot;
            }
            break;
        case '+':
            if (Peek(0) == '+')
                return Fail(t.Loc, "the '++' operator does not exist, use '+= 1'");
            t.Kind = Match('=') ? TokenKind.PlusAssign : TokenKind.Plus;
            break;
        case '-':
            if (Peek(0) == '-')
                return Fail(t.Loc, "the '--' operator does not exist, use '-= 1'");
            if (Match('>'))
                t.Kind = TokenKind.Arrow;
            else
                t.Kind = Match('=') ? TokenKind.MinusAssign : TokenKind.Minus;
            break;
        case '*': t.Kind = Match('=') ? TokenKind.StarAssign : TokenKind.Star; break;
        case '/': t.Kind = Match('=') ? TokenKind.SlashAssign : TokenKind.Slash; break;
        case '%': t.Kind = Match('=') ? TokenKind.PercentAssign : TokenKind.Percent; break;
        case '&':
            if (Match('&'))
                t.Kind = TokenKind.AmpAmp;
            else
                t.Kind = Match('=') ? TokenKind.AmpAssign : TokenKind.Amp;
            break;
        case '|':
            if (Match('|'))
                t.Kind = TokenKind.PipePipe;
            else
                t.Kind = Match('=') ? TokenKind.PipeAssign : TokenKind.Pipe;
            break;
        case '^': t.Kind = Match('=') ? TokenKind.CaretAssign : TokenKind.Caret; break;
        case '!': t.Kind = Match('=') ? TokenKind.NotEq : TokenKind.Bang; break;
        case '=': t.Kind = Match('=') ? TokenKind.EqEq : (Match('>') ? TokenKind.FatArrow : TokenKind.Assign); break;
        case '<':
            if (Match('<'))
                t.Kind = Match('=') ? TokenKind.ShlAssign : TokenKind.Shl;
            else
                t.Kind = Match('=') ? TokenKind.LtEq : TokenKind.Lt;
            break;
        case '>': t.Kind = Match('=') ? TokenKind.GtEq : TokenKind.Gt; break;
        default:
            return Fail(t.Loc, "unexpected character '" + c.ToString() + "'");
        }
        return t;
    }
}
