#include "Dump.h"

#include <cstring>

namespace
{
std::string hexByte(unsigned value)
{
    static const char digits[] = "0123456789abcdef";
    std::string s;
    s += digits[(value >> 4) & 15];
    s += digits[value & 15];
    return s;
}

// Printable ASCII as is, everything else as \xHH.
std::string escapeText(const std::string& s)
{
    std::string out;
    for (unsigned char c : s)
    {
        if (c == '\\')
            out += "\\\\";
        else if (c == '"')
            out += "\\\"";
        else if (c >= 32 && c < 127)
            out += (char)c;
        else
            out += "\\x" + hexByte(c);
    }
    return out;
}

// The 64 bits of a double as 16 hex digits.
std::string doubleBits(double value)
{
    uint64_t bits;
    std::memcpy(&bits, &value, sizeof(bits));
    std::string s;
    for (int shift = 60; shift >= 0; shift -= 4)
        s += "0123456789abcdef"[(bits >> shift) & 15];
    return s;
}
} // namespace

void dumpTokens(const std::vector<Token>& tokens, std::ostream& out)
{
    for (const Token& t : tokens)
    {
        out << t.loc.line << ":" << t.loc.col << " " << (int)t.kind;
        switch (t.kind)
        {
        case Tok::Ident: out << " " << t.text; break;
        case Tok::StringLit: out << " \"" << escapeText(t.text) << "\""; break;
        case Tok::IntLit: out << " " << t.intValue << (t.isUnsigned ? " u" : "") << (t.isLong ? " l" : ""); break;
        case Tok::CharLit: out << " " << t.intValue; break;
        case Tok::FloatLit: out << " " << doubleBits(t.floatValue) << (t.isFloat32 ? " f" : ""); break;
        default:
            if (t.kind >= Tok::KwNamespace && t.kind <= Tok::KwSizeof)
                out << " " << t.text;
            break;
        }
        out << "\n";
    }
}

