// Character classification (ASCII), like System.Char in C#:
//
//     if (Char.IsDigit(c)) ...

namespace Char;

bool IsDigit(char c)
{
    return c >= '0' && c <= '9';
}

bool IsUpper(char c)
{
    return c >= 'A' && c <= 'Z';
}

bool IsLower(char c)
{
    return c >= 'a' && c <= 'z';
}

bool IsLetter(char c)
{
    return IsUpper(c) || IsLower(c);
}

bool IsLetterOrDigit(char c)
{
    return IsLetter(c) || IsDigit(c);
}

bool IsHexDigit(char c)
{
    return IsDigit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
}

bool IsWhiteSpace(char c)
{
    return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\v' || c == '\f';
}

char ToUpper(char c)
{
    if (IsLower(c))
        return (char)(c - 32);
    return c;
}

char ToLower(char c)
{
    if (IsUpper(c))
        return (char)(c + 32);
    return c;
}

// Value of a hexadecimal digit, or -1.
int HexValue(char c)
{
    if (IsDigit(c))
        return c - '0';
    if (c >= 'a' && c <= 'f')
        return c - 'a' + 10;
    if (c >= 'A' && c <= 'F')
        return c - 'A' + 10;
    return -1;
}
