#include "Lexer.h"

#include <cctype>
#include <cmath>
#include <unordered_map>

namespace
{
const std::unordered_map<std::string, Tok>& keywords()
{
    static const std::unordered_map<std::string, Tok> map = {
        {"namespace", Tok::KwNamespace}, {"using", Tok::KwUsing},       {"struct", Tok::KwStruct},
        {"interface", Tok::KwInterface}, {"enum", Tok::KwEnum},         {"extern", Tok::KwExtern},
        {"unsafe", Tok::KwUnsafe},       {"unchecked", Tok::KwUnchecked}, {"if", Tok::KwIf},
        {"else", Tok::KwElse},           {"while", Tok::KwWhile},       {"do", Tok::KwDo},
        {"for", Tok::KwFor},             {"foreach", Tok::KwForeach},   {"in", Tok::KwIn},
        {"switch", Tok::KwSwitch},       {"case", Tok::KwCase},         {"default", Tok::KwDefault},
        {"break", Tok::KwBreak},         {"continue", Tok::KwContinue}, {"return", Tok::KwReturn},
        {"new", Tok::KwNew},             {"try", Tok::KwTry},           {"is", Tok::KwIs},
        {"where", Tok::KwWhere},         {"const", Tok::KwConst},       {"ref", Tok::KwRef},
        {"static", Tok::KwStatic},       {"true", Tok::KwTrue},         {"false", Tok::KwFalse},
        {"null", Tok::KwNull},           {"this", Tok::KwThis},         {"sizeof", Tok::KwSizeof},
    };
    return map;
}

bool isIdentStart(char c) { return std::isalpha((unsigned char)c) || c == '_' || (unsigned char)c >= 0x80; }
bool isIdentPart(char c) { return isIdentStart(c) || std::isdigit((unsigned char)c); }
} // namespace

const char* tokenName(Tok kind)
{
    switch (kind)
    {
    case Tok::Eof: return "end of file";
    case Tok::Ident: return "identifier";
    case Tok::IntLit: return "integer literal";
    case Tok::FloatLit: return "float literal";
    case Tok::CharLit: return "char literal";
    case Tok::StringLit: return "string literal";
    case Tok::LBrace: return "'{'";
    case Tok::RBrace: return "'}'";
    case Tok::LParen: return "'('";
    case Tok::RParen: return "')'";
    case Tok::LBracket: return "'['";
    case Tok::RBracket: return "']'";
    case Tok::Semi: return "';'";
    case Tok::Comma: return "','";
    case Tok::Dot: return "'.'";
    case Tok::Colon: return "':'";
    case Tok::Assign: return "'='";
    case Tok::Lt: return "'<'";
    case Tok::Gt: return "'>'";
    case Tok::KwIn: return "'in'";
    case Tok::KwWhile: return "'while'";
    case Tok::KwStruct: return "'struct'";
    default: return "token";
    }
}

Lexer::Lexer(const std::string& source, int fileId, Diagnostics& diag) : src(source), fileId(fileId), diag(diag) {}

char Lexer::peek(size_t ahead) const
{
    return pos + ahead < src.size() ? src[pos + ahead] : '\0';
}

char Lexer::advance()
{
    char c = src[pos++];
    if (c == '\n')
    {
        line += 1;
        col = 1;
    }
    else if ((c & 0xC0) != 0x80) // do not count UTF-8 continuation bytes
    {
        col += 1;
    }
    return c;
}

void Lexer::skipTrivia()
{
    while (!atEnd())
    {
        char c = peek();
        if (std::isspace((unsigned char)c))
        {
            advance();
        }
        else if (c == '/' && peek(1) == '/')
        {
            while (!atEnd() && peek() != '\n')
                advance();
        }
        else if (c == '/' && peek(1) == '*')
        {
            SourceLoc start = here();
            advance();
            advance();
            while (!atEnd() && !(peek() == '*' && peek(1) == '/'))
                advance();
            if (atEnd())
                diag.error(start, "unterminated block comment");
            else
            {
                advance();
                advance();
            }
        }
        else
        {
            break;
        }
    }
}

std::vector<Token> Lexer::tokenize()
{
    std::vector<Token> tokens;
    while (true)
    {
        skipTrivia();
        if (atEnd())
            break;

        char c = peek();
        try
        {
            if (std::isdigit((unsigned char)c))
                tokens.push_back(lexNumber());
            else if (c == '"')
                tokens.push_back(lexString());
            else if (c == '\'')
                tokens.push_back(lexChar());
            else if (isIdentStart(c))
                tokens.push_back(lexIdentifier());
            else
                tokens.push_back(lexPunct());
        }
        catch (const CompileError& e)
        {
            diag.error(e);
        }
    }

    Token eof;
    eof.kind = Tok::Eof;
    eof.loc = here();
    tokens.push_back(eof);
    return tokens;
}

Token Lexer::lexIdentifier()
{
    Token t;
    t.loc = here();
    while (!atEnd() && isIdentPart(peek()))
        t.text += advance();

    auto it = keywords().find(t.text);
    t.kind = it != keywords().end() ? it->second : Tok::Ident;
    return t;
}

Token Lexer::lexNumber()
{
    Token t;
    t.loc = here();

    // Hex / binary integers
    if (peek() == '0' && (peek(1) == 'x' || peek(1) == 'X' || peek(1) == 'b' || peek(1) == 'B'))
    {
        bool hex = peek(1) == 'x' || peek(1) == 'X';
        advance();
        advance();
        uint64_t value = 0;
        int digits = 0;
        while (!atEnd())
        {
            char c = peek();
            int d;
            if (c == '_')
            {
                advance();
                continue;
            }
            if (std::isdigit((unsigned char)c))
                d = c - '0';
            else if (hex && std::isxdigit((unsigned char)c))
                d = std::tolower(c) - 'a' + 10;
            else
                break;
            if (!hex && d > 1)
                break;
            if (value >> (hex ? 60 : 63))
                fail(t.loc, "integer literal is too large");
            value = value * (hex ? 16 : 2) + d;
            digits += 1;
            advance();
        }
        if (digits == 0)
            fail(t.loc, "invalid numeric literal");
        t.kind = Tok::IntLit;
        t.intValue = value;
    }
    else
    {
        std::string digits;
        bool isFloat = false;
        while (std::isdigit((unsigned char)peek()) || peek() == '_')
        {
            char c = advance();
            if (c != '_')
                digits += c;
        }
        if (peek() == '.' && std::isdigit((unsigned char)peek(1)))
        {
            isFloat = true;
            digits += advance();
            while (std::isdigit((unsigned char)peek()) || peek() == '_')
            {
                char c = advance();
                if (c != '_')
                    digits += c;
            }
        }
        if ((peek() == 'e' || peek() == 'E') &&
            (std::isdigit((unsigned char)peek(1)) ||
             ((peek(1) == '+' || peek(1) == '-') && std::isdigit((unsigned char)peek(2)))))
        {
            isFloat = true;
            digits += advance();
            if (peek() == '+' || peek() == '-')
                digits += advance();
            while (std::isdigit((unsigned char)peek()))
                digits += advance();
        }

        if (isFloat || peek() == 'f' || peek() == 'F' || peek() == 'd' || peek() == 'D')
        {
            t.kind = Tok::FloatLit;
            t.floatValue = std::strtod(digits.c_str(), nullptr);
            if (peek() == 'f' || peek() == 'F')
            {
                t.isFloat32 = true;
                advance();
            }
            else if (peek() == 'd' || peek() == 'D')
            {
                advance();
            }
        }
        else
        {
            t.kind = Tok::IntLit;
            uint64_t value = 0;
            for (char c : digits)
            {
                uint64_t d = (uint64_t)(c - '0');
                if (value > (UINT64_MAX - d) / 10)
                    fail(t.loc, "integer literal is too large");
                value = value * 10 + d;
            }
            t.intValue = value;
        }
    }

    if (t.kind == Tok::IntLit)
    {
        // Suffixes: u, l, ul
        while (peek() == 'u' || peek() == 'U' || peek() == 'l' || peek() == 'L')
        {
            char c = advance();
            if (c == 'u' || c == 'U')
                t.isUnsigned = true;
            else
                t.isLong = true;
        }
    }

    if (isIdentStart(peek()))
        fail(here(), "invalid suffix on numeric literal");
    return t;
}

void Lexer::appendUtf8(std::string& out, uint32_t cp)
{
    if (cp < 0x80)
    {
        out += (char)cp;
    }
    else if (cp < 0x800)
    {
        out += (char)(0xC0 | (cp >> 6));
        out += (char)(0x80 | (cp & 0x3F));
    }
    else if (cp < 0x10000)
    {
        out += (char)(0xE0 | (cp >> 12));
        out += (char)(0x80 | ((cp >> 6) & 0x3F));
        out += (char)(0x80 | (cp & 0x3F));
    }
    else
    {
        out += (char)(0xF0 | (cp >> 18));
        out += (char)(0x80 | ((cp >> 12) & 0x3F));
        out += (char)(0x80 | ((cp >> 6) & 0x3F));
        out += (char)(0x80 | (cp & 0x3F));
    }
}

// Reads an escape sequence after the backslash. Returns the code point;
// for \xHH the value is a raw byte (< 0x100) and flagged by the caller via range.
uint32_t Lexer::lexEscape()
{
    SourceLoc loc = here();
    char c = advance();
    switch (c)
    {
    case 'n': return '\n';
    case 't': return '\t';
    case 'r': return '\r';
    case '0': return 0;
    case 'a': return 7;
    case 'b': return 8;
    case 'f': return 12;
    case 'v': return 11;
    case '\\': return '\\';
    case '\'': return '\'';
    case '"': return '"';
    case 'x':
    case 'u':
    {
        int count = c == 'x' ? 2 : 4;
        uint32_t value = 0;
        for (int i = 0; i < count; i += 1)
        {
            if (!std::isxdigit((unsigned char)peek()))
                fail(loc, "invalid escape sequence");
            char h = advance();
            value = value * 16 + (std::isdigit((unsigned char)h) ? h - '0' : std::tolower(h) - 'a' + 10);
        }
        return value;
    }
    default:
        fail(loc, std::string("unknown escape sequence '\\") + c + "'");
    }
}

Token Lexer::lexString()
{
    Token t;
    t.kind = Tok::StringLit;
    t.loc = here();
    advance(); // opening quote
    while (true)
    {
        if (atEnd() || peek() == '\n')
            fail(t.loc, "unterminated string literal");
        char c = advance();
        if (c == '"')
            break;
        if (c == '\\')
        {
            bool isU = peek() == 'u';
            uint32_t cp = lexEscape();
            if (isU)
                appendUtf8(t.text, cp);
            else
                t.text += (char)cp; // \xHH is a raw byte
        }
        else
        {
            t.text += c;
        }
    }
    return t;
}

Token Lexer::lexChar()
{
    Token t;
    t.kind = Tok::CharLit;
    t.loc = here();
    advance(); // opening quote
    if (atEnd() || peek() == '\n')
        fail(t.loc, "unterminated char literal");

    uint32_t value;
    char c = advance();
    if (c == '\\')
        value = lexEscape();
    else
        value = (unsigned char)c;

    if (value > 0xFF)
        fail(t.loc, "char literals are single UTF-8 code units (0-255)");
    if (peek() != '\'')
        fail(t.loc, "char literal must contain exactly one UTF-8 code unit");
    advance();
    t.intValue = value;
    return t;
}

Token Lexer::lexPunct()
{
    Token t;
    t.loc = here();
    char c = advance();
    auto match = [&](char next) {
        if (peek() == next)
        {
            advance();
            return true;
        }
        return false;
    };

    switch (c)
    {
    case '{': t.kind = Tok::LBrace; break;
    case '}': t.kind = Tok::RBrace; break;
    case '(': t.kind = Tok::LParen; break;
    case ')': t.kind = Tok::RParen; break;
    case '[': t.kind = Tok::LBracket; break;
    case ']': t.kind = Tok::RBracket; break;
    case ';': t.kind = Tok::Semi; break;
    case ',': t.kind = Tok::Comma; break;
    case ':': t.kind = Tok::Colon; break;
    case '?': t.kind = Tok::Question; break;
    case '~': t.kind = Tok::Tilde; break;
    case '.':
        if (peek() == '.' && peek(1) == '.')
        {
            advance();
            advance();
            t.kind = Tok::Ellipsis;
        }
        else
            t.kind = Tok::Dot;
        break;
    case '+':
        if (peek() == '+')
            fail(t.loc, "the '++' operator does not exist, use '+= 1'");
        t.kind = match('=') ? Tok::PlusAssign : Tok::Plus;
        break;
    case '-':
        if (peek() == '-')
            fail(t.loc, "the '--' operator does not exist, use '-= 1'");
        if (match('>'))
            t.kind = Tok::Arrow;
        else
            t.kind = match('=') ? Tok::MinusAssign : Tok::Minus;
        break;
    case '*': t.kind = match('=') ? Tok::StarAssign : Tok::Star; break;
    case '/': t.kind = match('=') ? Tok::SlashAssign : Tok::Slash; break;
    case '%': t.kind = match('=') ? Tok::PercentAssign : Tok::Percent; break;
    case '&':
        if (match('&'))
            t.kind = Tok::AmpAmp;
        else
            t.kind = match('=') ? Tok::AmpAssign : Tok::Amp;
        break;
    case '|':
        if (match('|'))
            t.kind = Tok::PipePipe;
        else
            t.kind = match('=') ? Tok::PipeAssign : Tok::Pipe;
        break;
    case '^': t.kind = match('=') ? Tok::CaretAssign : Tok::Caret; break;
    case '!': t.kind = match('=') ? Tok::NotEq : Tok::Bang; break;
    case '=': t.kind = match('=') ? Tok::EqEq : Tok::Assign; break;
    case '<':
        if (match('<'))
            t.kind = match('=') ? Tok::ShlAssign : Tok::Shl;
        else
            t.kind = match('=') ? Tok::LtEq : Tok::Lt;
        break;
    case '>': t.kind = match('=') ? Tok::GtEq : Tok::Gt; break;
    default:
        fail(t.loc, std::string("unexpected character '") + c + "'");
    }
    return t;
}
