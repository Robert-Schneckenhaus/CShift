// Text dump of a token list. The format is the same as in the C++ compiler (cshiftc --dump-tokens), so that the
// two lexers can be compared:
//     line:col kind [text] [value]

namespace CShift.Syntax;

using System;

// Escapes a string for the dump: printable ASCII as is, everything else as \xHH.
string EscapeText(string s)
{
    var sb = StringBuilder.Create();
    for (var i = 0; i < s.Length; i += 1)
    {
        char c = s[i];
        if (c == '\\')
            sb.Append("\\\\");
        else if (c == '"')
            sb.Append("\\\"");
        else if (c >= 32 && c < 127)
            sb.Append(c);
        else
            sb.Append("\\x" + HexByte((int)c));
    }
    return sb.ToString();
}

string HexByte(int value)
{
    string digits = "0123456789abcdef";
    return digits.Substring((value >> 4) & 15, 1) + digits.Substring(value & 15, 1);
}

// The 64 bits of a double as 16 hex digits (float values are compared bit by bit).
string DoubleBits(double value)
{
    uint64 bits = 0;
    unsafe
    {
        double copy = value;
        bits = *(uint64*)&copy;
    }
    var sb = StringBuilder.Create();
    for (var shift = 60; shift >= 0; shift -= 4)
        sb.Append(HexByte((int)((bits >> shift) & 15)).Substring(1, 1));
    return sb.ToString();
}

string DumpToken(Token t)
{
    string line = t.Loc.Line.ToString() + ":" + t.Loc.Col.ToString() + " " + ((int)t.Kind).ToString();
    switch (t.Kind)
    {
    case TokenKind.Ident:
        return line + " " + t.Text;
    case TokenKind.StringLit:
        return line + " \"" + EscapeText(t.Text) + "\"";
    case TokenKind.IntLit:
        return line + " " + t.IntValue.ToString() + (t.IsUnsigned ? " u" : "") + (t.IsLong ? " l" : "");
    case TokenKind.CharLit:
        return line + " " + t.IntValue.ToString();
    case TokenKind.FloatLit:
        return line + " " + DoubleBits(t.FloatValue) + (t.IsFloat32 ? " f" : "");
    default:
        if (t.Kind >= TokenKind.KwNamespace && t.Kind <= TokenKind.KwSizeof)
            return line + " " + t.Text;
        return line;
    }
}
