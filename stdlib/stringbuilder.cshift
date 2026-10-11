namespace System;

extern "C" void* memcpy(void* dest, void* source, nuint count);

/// The storage behind a [StringBuilder]; use [StringBuilder] instead.
/// @internal
struct StringBuilderState
{
    uint8[] Data;
    int Length;
}

/// Builds a string without copying it for every '+'.
///
/// ```
/// using System;
///
/// var sb = StringBuilder.Create();
/// sb.Append("x = ");
/// sb.Append(42.ToString());
/// sb.Append('\n');
/// string text = sb.ToString();
/// ```
///
/// Like List<T>, a StringBuilder is a small handle to shared storage: copies see the same text. The storage is made
/// by StringBuilder.Create(); the zero value (`new()`, a field without a value) is an empty text that can be read but
/// not changed: Append panics.
struct StringBuilder
{
    StringBuilderState[] _state;

    /// A new, empty builder.
    static StringBuilder Create()
    {
        return StringBuilder { _state = new StringBuilderState[1] };
    }

    /// A new, empty builder with room for `capacity` bytes before it has to grow.
    static StringBuilder Create(int capacity)
    {
        var sb = Create();
        sb._Reserve(capacity);
        return sb;
    }

    /// Whether the builder has storage: made by Create(), not the zero value (which cannot change).
    bool IsCreated()
    {
        return _state != null;
    }

    /// The length of the text so far, in bytes.
    int Length()
    {
        if (_state == null)
            return 0;
        return _state[0].Length;
    }

    /// Appends `text`: a string or a part of one (a `StringSlice`; a string converts to it for free).
    /// @panics when the builder was not created ([StringBuilder.IsCreated]).
    void Append(StringSlice text)
    {
        if (_state == null)
            Environment.Panic(_NotCreated());
        int n = text.Length;
        if (n == 0)
            return;
        _Reserve(Length() + n);
        unsafe
        {
            uint8* target = &_state[0].Data[_state[0].Length];
            memcpy((void*)target, (void*)text.Ptr(), (nuint)n);
        }
        _state[0].Length += n;
    }

    /// Appends the character `c` (a byte).
    void Append(char c)
    {
        if (_state == null)
            Environment.Panic(_NotCreated());
        _Reserve(Length() + 1);
        _state[0].Data[_state[0].Length] = (uint8)c;
        _state[0].Length += 1;
    }

    /// Appends `text` and a line break (`\n`).
    void AppendLine(StringSlice text)
    {
        if (_state == null)
            Environment.Panic(_NotCreated());
        Append(text);
        Append('\n');
    }

    /// Appends a line break (`\n`).
    void AppendLine()
    {
        if (_state == null)
            Environment.Panic(_NotCreated());
        Append('\n');
    }

    /// The character (byte) at `index`; the text is UTF-8.
    /// @panics when `index` is not in 0 to `Length() - 1`.
    char Get(int index)
    {
        if (index < 0 || index >= Length())
            Environment.Panic("StringBuilder index out of range (index " + index.ToString() + ", length " + Length().ToString() + ")");
        return (char)_state[0].Data[index];
    }

    /// Removes all text.
    void Clear()
    {
        if (_state != null)
            _state[0].Length = 0;
    }


    /// The text from `start` to the end, as a new string.
    /// @panics when `start` is not in 0 to `Length()`.
    string Substring(int start)
    {
        if (_state == null || start >= _state[0].Length)
            return "";
        if (start < 0)
            Environment.Panic("StringBuilder index out of range (index " + start.ToString() + ")");
        return string.FromBytes(_state[0].Data, start, _state[0].Length - start);
    }

    /// Cuts the text to its first `length` bytes.
    /// @panics when `length` is not in 0 to `Length()`.
    void Truncate(int length)
    {
        if (length < 0 || length > Length())
            Environment.Panic("StringBuilder length out of range (length " + length.ToString() + ", current length " + Length().ToString() + ")");
        if (_state != null)
            _state[0].Length = length;
    }

    /// The text as a string.
    string ToString()
    {
        if (_state == null || _state[0].Length == 0)
            return "";
        return string.FromBytes(_state[0].Data, 0, _state[0].Length);
    }

    static string _NotCreated()
    {
        return "the StringBuilder was not created (StringBuilder.Create()): the zero value (new(), a field without a value) is empty and cannot change";
    }

    void _Reserve(int needed)
    {
        uint8[] data = _state[0].Data;
        int capacity = data == null ? 0 : data.Length;
        if (needed <= capacity)
            return;
        int size = capacity < 16 ? 16 : capacity;
        while (size < needed)
            size = size * 2;
        var grown = new uint8[size];
        if (data != null)
            Array.Copy(data, 0, grown, 0, _state[0].Length);
        _state[0].Data = grown;
    }
}
