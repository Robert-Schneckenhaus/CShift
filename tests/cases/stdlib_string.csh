// Standard library: string helpers (namespace String), parsing and Encoding.
// Main returns the number of failed checks.
// expect-exit: 0

using System;

int Check(string name, bool ok)
{
    if (ok)
        return 0;
    Console.WriteLine("FAIL: " + name);
    return 1;
}

int Main()
{
    int f = 0;
    string s = "Hello, World";

    // ---- searching ----
    f += Check("Contains string", s.Contains("World") && !s.Contains("world"));
    f += Check("Contains char", s.Contains('W') && !s.Contains('z'));
    f += Check("IndexOf", s.IndexOf("o") == 4 && s.IndexOf('o') == 4 && s.IndexOf("o", 5) == 8 && s.IndexOf("xyz") == -1);
    f += Check("LastIndexOf", s.LastIndexOf('o') == 8 && s.LastIndexOf('z') == -1);
    f += Check("StartsWith/EndsWith", s.StartsWith("Hello") && !s.StartsWith("World") && s.EndsWith("World") &&
                                       !s.EndsWith("Hello") && s.StartsWith("") && !"ab".StartsWith("abc"));

    // ---- transforming ----
    f += Check("Trim", "  \t x y \n".Trim() == "x y" && "".Trim() == "" && "   ".Trim() == "");
    f += Check("ToUpper/ToLower", "Hello1".ToUpper() == "HELLO1" && "Hello1".ToLower() == "hello1");
    f += Check("Replace", "a-b-c".Replace("-", "+") == "a+b+c" && "aaa".Replace("aa", "b") == "ba" &&
                          "abc".Replace("x", "y") == "abc" && "a--b".Replace("--", "") == "ab");
    f += Check("Repeat", "ab".Repeat(3) == "ababab" && "x".Repeat(0) == "");

    // ---- splitting / joining ----
    var parts = "a,b,,c".Split(',');
    f += Check("Split char", parts.Length == 4 && parts[0] == "a" && parts[1] == "b" && parts[2] == "" && parts[3] == "c");
    var parts2 = "one::two::three".Split("::");
    f += Check("Split string", parts2.Length == 3 && parts2[0] == "one" && parts2[1] == "two" && parts2[2] == "three");
    f += Check("Split none", "abc".Split(',').Length == 1 && "".Split(',').Length == 1);
    f += Check("Join", string.Join("-", parts2) == "one-two-three" && string.Join(",", new string[0]) == "");
    f += Check("Join(Split)", string.Join(",", "1;2;3".Split(';')) == "1,2,3");
    f += Check("IsNullOrEmpty", string.IsNullOrEmpty(null) && string.IsNullOrEmpty("") && !string.IsNullOrEmpty("a"));

    string nothing = null;
    f += Check("null string helpers", !nothing.Contains("a") && nothing.Trim() == "" && nothing.Split(',').Length == 1);

    // ---- equality, hash, ordering (IEquatable / IHashable / IComparable) ----
    f += Check("Equals", "abc".Equals("abc") && !"abc".Equals("abd"));
    f += Check("GetHashCode", "abc".GetHashCode() == "abc".GetHashCode() && "abc".GetHashCode() != "abd".GetHashCode());
    f += Check("CompareTo", "a".CompareTo("b") < 0 && "b".CompareTo("a") > 0 && "abc".CompareTo("abc") == 0 &&
                            "ab".CompareTo("abc") < 0 && "Z".CompareTo("a") < 0);

    // ---- parsing ----
    if ("123".ParseInt() is int v1)
        f += Check("ParseInt", v1 == 123);
    else
        f += 1;
    if ("-45".ParseInt() is int v2)
        f += Check("ParseInt negative", v2 == -45);
    else
        f += 1;
    if ("+7".ParseInt() is int v3)
        f += Check("ParseInt plus", v3 == 7);
    else
        f += 1;
    if ("-2147483648".ParseInt() is int v4)
        f += Check("ParseInt min", v4 == int.MinValue);
    else
        f += 1;
    f += Check("ParseInt errors", !"".ParseInt() && !"12x".ParseInt() && !"-".ParseInt() && !"2147483648".ParseInt());
    f += Check("ParseInt message", "12x".ParseInt().Message.Contains("12x"));
    if ("9223372036854775807".ParseInt64() is int64 v5)
        f += Check("ParseInt64 max", v5 == int64.MaxValue);
    else
        f += 1;
    if ("-9223372036854775808".ParseInt64() is int64 v6)
        f += Check("ParseInt64 min", v6 == int64.MinValue);
    else
        f += 1;
    f += Check("ParseInt64 overflow", !"9223372036854775808".ParseInt64());
    if ("3.25".ParseDouble() is double d1)
        f += Check("ParseDouble", d1 == 3.25);
    else
        f += 1;
    if ("-1e3".ParseDouble() is double d2)
        f += Check("ParseDouble exponent", d2 == -1000);
    else
        f += 1;
    f += Check("ParseDouble errors", !"abc".ParseDouble() && !"1.5x".ParseDouble() && !"".ParseDouble());

    // ---- strings from bytes ----
    f += Check("FromBytes", string.FromBytes(new uint8[] { 65, 66, 67 }) == "ABC");
    f += Check("FromBytes range", string.FromBytes(new uint8[] { 65, 66, 67 }, 1, 2) == "BC");

    // ---- Encoding ----
    var utf8 = Encoding.UTF8();
    var ascii = Encoding.ASCII();
    f += Check("Encoding names", utf8.Name() == "UTF-8" && ascii.Name() == "ASCII");

    string text = "héllo €"; // h, e-acute (2 bytes), llo, space, euro sign (3 bytes)
    var bytes = utf8.GetBytes(text);
    f += Check("UTF-8 GetBytes", bytes.Length == 10 && bytes[0] == 0x68 && bytes[1] == 0xC3 && bytes[2] == 0xA9 && bytes[7] == 0xE2);
    f += Check("UTF-8 GetByteCount", utf8.GetByteCount(text) == 10);
    if (utf8.GetString(bytes) is string back)
        f += Check("UTF-8 round trip", back == text);
    else
        f += 1;
    if (utf8.GetString(bytes, 0, 1) is string first)
        f += Check("UTF-8 partial", first == "h");
    else
        f += 1;

    f += Check("UTF-8 invalid byte", !utf8.GetString(new uint8[] { 0x68, 0xFF }));
    f += Check("UTF-8 truncated", !utf8.GetString(new uint8[] { 0xE2, 0x82 }));
    f += Check("UTF-8 overlong", !utf8.GetString(new uint8[] { 0xC0, 0x80 }));
    f += Check("UTF-8 surrogate", !utf8.GetString(new uint8[] { 0xED, 0xA0, 0x80 }));
    f += Check("UTF-8 bad continuation", !utf8.GetString(new uint8[] { 0xC3, 0x28 }));
    f += Check("UTF-8 range", !utf8.GetString(bytes, 5, 100));
    f += Check("UTF-8 message", utf8.GetString(new uint8[] { 0x68, 0xFF }).Message.Contains("index 1"));

    var asciiBytes = ascii.GetBytes("héllo");
    f += Check("ASCII GetBytes", asciiBytes.Length == 5 && asciiBytes[0] == 0x68 && asciiBytes[1] == 0x3F && asciiBytes[4] == 0x6F);
    f += Check("ASCII GetByteCount", ascii.GetByteCount("€") == 1);
    if (ascii.GetString(new uint8[] { 72, 105 }) is string hi)
        f += Check("ASCII GetString", hi == "Hi");
    else
        f += 1;
    f += Check("ASCII rejects high bytes", !ascii.GetString(new uint8[] { 72, 200 }));

    return f;
}
