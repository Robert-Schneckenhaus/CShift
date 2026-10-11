// The declarations of the built-in types (see README.md in this folder): only for the documentation.

/// A string: immutable UTF-8 text.
///
/// ```
/// string name = "Ann";
/// string greeting = "Hello, " + name + "!";
/// if (greeting.Contains("Ann") && greeting[0] == 'H')
///     Console.WriteLine(greeting.ToUpper());
/// ```
///
/// Strings are values with reference semantics: assigning one shares the text (reference counted), and since a
/// string cannot be changed, that is never visible. `==` compares the text, `+` joins, `$"x = {x}"` interpolates.
/// `s[i]` is the byte at position `i` (a `char`), `s[i..j]` a [StringSlice] (a view, nothing is copied). Positions
/// and lengths are byte offsets.
///
/// Most methods are in the namespace [String] (`s.Trim()` is `String.Trim(s)`); a string converts to a
/// [StringSlice] for free.
struct string : IComparable<string>, IEquatable<string>, IHashable
{
    /// The length in bytes (not in characters: UTF-8 uses 1 to 4 bytes per character).
    int Length;

    /// A copy of the `count` bytes from `start` (`s[start..start + count].ToString()` is the same).
    /// @panics when the range is not inside of the string.
    string Substring(int start, int count);

    /// A copy of the text from `start` to the end.
    /// @panics when `start` is not in 0 to `Length`.
    string Substring(int start);

    /// The string itself.
    string ToString();

    /// A copy of the string in a new block of memory (e.g. to keep a part of a large text without keeping all of it).
    string Clone();

    /// A pointer to the bytes, followed by a 0 byte, for C functions (`unsafe`). It stays valid while the string
    /// lives.
    char* CStr();

    /// The bytes of the string (UTF-8) as a view, for functions that take bytes: `stream.Write(text.AsBytes())`;
    /// nothing is copied. (A string converts to `ReadOnlySlice<char>` by itself.)
    ReadOnlySlice<uint8> AsBytes();

    /// A string from a C string (`unsafe`): the bytes up to the first 0 byte are copied.
    static string FromCStr(char* text);

    /// A string from bytes (UTF-8); they are copied as they are.
    static string FromBytes(uint8[] bytes);

    /// A string from `count` bytes of `bytes`, starting at `start`.
    /// @panics when the range is not inside of the array.
    static string FromBytes(uint8[] bytes, int start, int count);

    /// Whether the strings have the same bytes (also `a == b`).
    bool Equals(string other);

    /// Compares the bytes (ordinal, no locale): negative, 0 or positive.
    int CompareTo(string other);

    /// A hash code of the text, for [Dictionary] keys.
    int GetHashCode();
}
