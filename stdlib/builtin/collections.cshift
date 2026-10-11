// The declarations of the built-in types (see README.md in this folder): only for the documentation.

/// An array, `T[]`: a fixed number of values, created with `new T[n]` (zeroed) or `new T[] { a, b }` / `[a, b]`.
///
/// ```
/// var squares = new int[10];
/// for (var i = 0; i < squares.Length; i += 1)
///     squares[i] = i * i;
/// foreach (var s in squares[1..4])     // a Slice<int>: 1, 4, 9
///     Console.WriteLine(s);
/// ```
///
/// Arrays have reference semantics: assigning one shares the elements (reference counted); [Array.Clone] copies.
/// `a[i]` checks the index (a panic outside of 0 to `Length - 1`), `a[^1]` is the last element, `a[i..j]` a
/// [Slice] (a view). A [List] grows; an array does not.
struct Array<T>
{
    /// The number of elements.
    int Length;

    /// A copy of the array (new storage with the same elements).
    T[] Clone();

    /// Copies `count` elements of `source` from `sourceIndex` to `destination` from `destinationIndex` (the ranges may
    /// overlap).
    /// @panics when a range is not inside of its array.
    static void Copy(T[] source, int sourceIndex, T[] destination, int destinationIndex, int count);
}

/// A fixed-size array stored inline: `Fixed<int, 16>` is 16 ints inside the variable or struct, with no allocation.
///
/// ```
/// struct Palette { Fixed<uint16, 32> Colors; }
/// var p = Palette { };
/// p.Colors[3] = 0x0F00;
/// ```
///
/// A `Fixed` is a value: assigning it copies all elements. Indexing is checked; `foreach` and slicing work like on
/// arrays. C arrays in imported C structs become `Fixed`.
struct Fixed<T, N>
{
    /// The number of elements, `N` (a constant).
    int Length;

    /// A new array with the elements.
    T[] ToArray();
}

/// A view of a part of an array: `a[i..j]`, `a[..j]`, `a[i..]`. Nothing is copied, and writing `slice[k]` writes the
/// array.
///
/// A slice has `Length`, `s[i]` (also `s[^i]`), `foreach` and slicing again; [Slice<T>.ToArray] copies. Functions
/// that only read take a [ReadOnlySlice], to which a `Slice<T>` and a `T[]` convert.
struct Slice<T>
{
    /// The number of elements.
    int Length;

    /// A new array with the elements of the slice.
    T[] ToArray();

    /// A pointer to the first element (`unsafe`).
    T* Ptr();
}

/// A read-only view of elements: a [Slice], an array, or a constant (`const ReadOnlySlice<int> Primes = [2, 3, 5];`,
/// `Enum<T>.Values`, `embed("*.txt")`).
///
/// A function that takes a `ReadOnlySlice<T>` accepts arrays, slices and constants alike. It can also be a
/// parameter of a `thread` function when its elements can be copied between threads (the thread gets its own copy).
struct ReadOnlySlice<T>
{
    /// The number of elements.
    int Length;

    /// A new array with the elements.
    T[] ToArray();

    /// A pointer to the first element (`unsafe`).
    T* Ptr();
}

/// A view of a part of a string: `s[i..j]`, and the results of [String.Trim], [String.Split] and
/// [String.Substring]. Nothing is copied; [StringSlice.ToString] copies.
///
/// A string converts to a `StringSlice` for free, so the functions of [String] take slices and work on parts of a
/// text. `==` compares the text and `+` joins it like a string. Slices are `IEquatable`, `IHashable` and `IComparable`
/// like strings: keys of a [Dictionary], elements of a sorted [List].
struct StringSlice
{
    /// The length in bytes.
    int Length;

    /// A new string with the text of the slice.
    string ToString();

    /// A pointer to the first byte (`unsafe`); the text is not followed by a 0 byte.
    char* Ptr();

    /// The text as a C string (`unsafe`): followed by a 0 byte, for C functions. A slice that reaches the end of its
    /// string is passed as it is; any other slice is copied into a string that lives until the end of the statement.
    char* CStr();

    /// The bytes of the text (UTF-8) as a view, for functions that take bytes; nothing is copied. (A `StringSlice`
    /// converts to `ReadOnlySlice<char>` by itself.)
    ReadOnlySlice<uint8> AsBytes();
}
