// StringBuilder: builds a string without copying it for every '+'.
//
//     using System;
//
//     var sb = StringBuilder.Create();
//     sb.Append("x = ");
//     sb.Append(42.ToString());
//     sb.Append('\n');
//     string text = sb.ToString();
//
// Like List<T>, a StringBuilder is a small handle to shared storage: copies see the same text. Start it with
// StringBuilder.Create() before you hand it out.

namespace System;

extern "C" void* memcpy(void* dest, void* source, uint64 count);

struct StringBuilderState
{
    uint8[] Data;
    int Length;
}

struct StringBuilder
{
    StringBuilderState[] _state;

    static StringBuilder Create()
    {
        return StringBuilder { _state = new StringBuilderState[1] };
    }

    static StringBuilder Create(int capacity)
    {
        var sb = Create();
        sb._Reserve(capacity);
        return sb;
    }

    int Length()
    {
        if (_state == null)
            return 0;
        return _state[0].Length;
    }

    // A string or a part of one (StringSlice: a string converts to it for free).
    void Append(StringSlice text)
    {
        int n = text.Length;
        if (n == 0)
            return;
        _Reserve(Length() + n);
        unsafe
        {
            uint8* target = &_state[0].Data[_state[0].Length];
            memcpy((void*)target, (void*)text.Ptr(), (uint64)n);
        }
        _state[0].Length += n;
    }

    void Append(char c)
    {
        _Reserve(Length() + 1);
        _state[0].Data[_state[0].Length] = (uint8)c;
        _state[0].Length += 1;
    }

    void AppendLine(StringSlice text)
    {
        Append(text);
        Append('\n');
    }

    void AppendLine()
    {
        Append('\n');
    }

    // The character at index (bytes; the text is UTF-8).
    char Get(int index)
    {
        if (index < 0 || index >= Length())
            Environment.Panic("StringBuilder index out of range");
        return (char)_state[0].Data[index];
    }

    void Clear()
    {
        if (_state != null)
            _state[0].Length = 0;
    }


    // The text from 'start' to the end.
    string Substring(int start)
    {
        if (_state == null || start >= _state[0].Length)
            return "";
        if (start < 0)
            Environment.Panic("StringBuilder index out of range");
        return string.FromBytes(_state[0].Data, start, _state[0].Length - start);
    }

    // Cuts the text to 'length' characters (bytes).
    void Truncate(int length)
    {
        if (length < 0 || length > Length())
            Environment.Panic("StringBuilder length out of range");
        if (_state != null)
            _state[0].Length = length;
    }

    string ToString()
    {
        if (_state == null || _state[0].Length == 0)
            return "";
        return string.FromBytes(_state[0].Data, 0, _state[0].Length);
    }

    void _Reserve(int needed)
    {
        if (_state == null)
            _state = new StringBuilderState[1];
        uint8[] data = _state[0].Data;
        int capacity = data == null ? 0 : data.Length;
        if (needed <= capacity)
            return;
        int size = capacity < 16 ? 16 : capacity;
        while (size < needed)
            size = size * 2;
        var grown = new uint8[size];
        for (var i = 0; i < _state[0].Length; i += 1)
            grown[i] = data[i];
        _state[0].Data = grown;
    }
}
