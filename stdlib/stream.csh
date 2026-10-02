namespace System;

using System.Native;

/// Where [FileStream.Seek] counts from.
enum SeekOrigin : int
{
    /// From the start of the file.
    Begin = 0,
    /// From the current position.
    Current = 1,
    /// From the end of the file.
    End = 2
}

/// A file, read and written as bytes, with seeking. [StreamReader] reads lines of text, [StreamWriter] writes text.
/// All of them are [IDisposable], so `using` closes them:
///
/// ```
/// using var reader = try StreamReader.Open("data.txt");
/// while (reader.ReadLine() is string line)
///     Console.WriteLine(line);
///
/// using var writer = try StreamWriter.Create("out.txt");
/// writer.WriteLine("first line");
///
/// using var stream = try FileStream.OpenRead("image.bin");
/// var header = new uint8[16];
/// int got = stream.Read(header, 0, 16);
/// ```
///
/// A stream is a struct around the C library's `FILE`: copies of it share the open file, and `Close` (or `Dispose`) of
/// one copy closes it for all; keep one owner. Text is UTF-8.
struct FileStream : IDisposable
{
    void* _file;

    /// Opens an existing file for reading.
    /// @error IoError.CannotOpen the file does not exist or cannot be read.
    static IoError<FileStream> OpenRead(string path)
    {
        return _Open(path, "rb", IoError.CannotOpen, "cannot open file '");
    }

    /// Opens an existing file for reading and writing, from the start, without truncating it.
    /// @error IoError.CannotOpen the file does not exist or cannot be opened.
    static IoError<FileStream> OpenReadWrite(string path)
    {
        return _Open(path, "r+b", IoError.CannotOpen, "cannot open file '");
    }

    /// Creates a new, empty file for writing (an existing one is truncated).
    /// @error IoError.CannotCreate the file cannot be created (a missing folder, no permission).
    static IoError<FileStream> Create(string path)
    {
        return _Open(path, "wb", IoError.CannotCreate, "cannot create file '");
    }

    /// Opens a file for writing at its end; it is created if it does not exist.
    /// @error IoError.CannotCreate the file cannot be opened or created.
    static IoError<FileStream> Append(string path)
    {
        return _Open(path, "ab", IoError.CannotCreate, "cannot open file '");
    }

    static IoError<FileStream> _Open(string path, string mode, IoError code, string message)
    {
        unsafe
        {
            void* f = fopen(path.CStr(), mode.CStr());
            if (f == null)
                return error(message + path + "'", code);
            return FileStream { _file = f };
        }
    }

    /// Whether the stream is open (not closed yet).
    bool IsOpen() { return _file != null; }

    /// Reads up to `count` bytes into `buffer[offset..]`.
    /// @returns the number of bytes read; 0 at the end of the file.
    /// @panics when `offset..offset + count` is not inside of `buffer`.
    int Read(uint8[] buffer, int offset, int count)
    {
        if (offset < 0 || count < 0 || offset + count > buffer.Length)
            Environment.Panic("FileStream.Read: the range " + offset.ToString() + ".." + (offset + count).ToString() +
                              " is outside the buffer (length " + buffer.Length.ToString() + ")");
        if (count == 0 || _file == null)
            return 0;
        unsafe
        {
            return (int)fread(&buffer[offset], 1, (nuint)count, _file);
        }
    }

    /// Reads one byte.
    /// @returns the byte, or -1 at the end of the file.
    int ReadByte()
    {
        var one = new uint8[1];
        return Read(one, 0, 1) == 1 ? (int)one[0] : -1;
    }

    /// Writes `count` bytes of `buffer` from `offset`.
    /// @error IoError.CannotWrite the stream is closed or writing failed.
    /// @panics when `offset..offset + count` is not inside of `buffer`.
    IoError<void> Write(uint8[] buffer, int offset, int count)
    {
        if (offset < 0 || count < 0 || offset + count > buffer.Length)
            Environment.Panic("FileStream.Write: the range " + offset.ToString() + ".." + (offset + count).ToString() +
                              " is outside the buffer (length " + buffer.Length.ToString() + ")");
        if (count == 0)
            return;
        if (_file == null)
            return error("the stream is closed", IoError.CannotWrite);
        unsafe
        {
            if (fwrite(&buffer[offset], 1, (nuint)count, _file) != (nuint)count)
                return error("cannot write to the file", IoError.CannotWrite);
        }
        return;
    }

    /// Writes all of `buffer`.
    /// @error IoError.CannotWrite the stream is closed or writing failed.
    IoError<void> Write(uint8[] buffer)
    {
        return Write(buffer, 0, buffer.Length);
    }

    /// Writes one byte.
    /// @error IoError.CannotWrite the stream is closed or writing failed.
    IoError<void> WriteByte(uint8 value)
    {
        var one = new uint8[1];
        one[0] = value;
        return Write(one, 0, 1);
    }

    /// Writes `text` as UTF-8 bytes.
    /// @error IoError.CannotWrite the stream is closed or writing failed.
    IoError<void> WriteText(StringSlice text)
    {
        if (text.Length == 0)
            return;
        if (_file == null)
            return error("the stream is closed", IoError.CannotWrite);
        unsafe
        {
            if (fwrite(text.Ptr(), 1, (nuint)text.Length, _file) != (nuint)text.Length)
                return error("cannot write to the file", IoError.CannotWrite);
        }
        return;
    }

    /// The position in bytes from the start of the file.
    int64 Position()
    {
        if (_file == null)
            return 0;
        unsafe
        {
            return _Os.Tell(_file);
        }
    }

    /// Moves the position to `offset` bytes from `origin`.
    /// @returns `false` if that is not possible.
    bool Seek(int64 offset, SeekOrigin origin)
    {
        if (_file == null)
            return false;
        unsafe
        {
            return _Os.Seek(_file, offset, (int)origin);
        }
    }

    /// The size of the file in bytes (the position stays).
    int64 Length()
    {
        if (_file == null)
            return 0;
        unsafe
        {
            int64 here = _Os.Tell(_file);
            _Os.Seek(_file, 0, 2);
            int64 end = _Os.Tell(_file);
            _Os.Seek(_file, here, 0);
            return end;
        }
    }

    /// Writes what the C library still holds in its buffer to the file.
    void Flush()
    {
        if (_file == null)
            return;
        unsafe
        {
            _Os.Flush(_file);
        }
    }

    /// Closes the file; the copies of the stream are closed as well. Closing it again does nothing.
    void Close()
    {
        if (_file == null)
            return;
        unsafe
        {
            fclose(_file);
        }
        _file = null;
    }

    /// Closes the file ([FileStream.Close]); `using` calls it.
    void Dispose()
    {
        Close();
    }
}

/// Reads a UTF-8 text file line by line (or all of it).
struct StreamReader : IDisposable
{
    FileStream _stream;
    uint8[] _buffer;
    int _pos;
    int _count;

    /// Opens a UTF-8 text file for reading; a byte order mark at its start is skipped.
    /// @error IoError.CannotOpen the file does not exist or cannot be read.
    static IoError<StreamReader> Open(string path)
    {
        var stream = try FileStream.OpenRead(path);
        var reader = StreamReader { _stream = stream, _buffer = new uint8[4096] };
        // a byte order mark at the start is skipped
        if (reader._Fill() && reader._count >= 3 && reader._buffer[0] == 0xEF && reader._buffer[1] == 0xBB && reader._buffer[2] == 0xBF)
            reader._pos = 3;
        return reader;
    }

    // false at the end of the file
    bool _Fill()
    {
        if (_pos < _count)
            return true;
        _pos = 0;
        _count = _stream.Read(_buffer, 0, _buffer.Length);
        return _count > 0;
    }

    /// Whether the end of the file is reached.
    bool EndOfStream()
    {
        return !_Fill();
    }

    /// The next line, without its line break (`\n` or `\r\n`): `while (reader.ReadLine() is string line) ...`.
    /// @returns nothing (`null`) at the end of the file.
    Optional<string> ReadLine()
    {
        if (!_Fill())
            return null;
        var line = new uint8[128];
        int length = 0;
        while (_Fill())
        {
            uint8 b = _buffer[_pos];
            _pos += 1;
            if (b == '\n')
                break;
            if (length == line.Length)
            {
                var bigger = new uint8[line.Length * 2];
                Array.Copy(line, 0, bigger, 0, length);
                line = bigger;
            }
            line[length] = b;
            length += 1;
        }
        if (length > 0 && line[length - 1] == '\r')
            length -= 1;
        return _Decode(line, length);
    }

    /// The rest of the file. Bytes that are not valid UTF-8 become `?`.
    string ReadToEnd()
    {
        var all = new uint8[_buffer.Length];
        int length = 0;
        while (_Fill())
        {
            int n = _count - _pos;
            if (length + n > all.Length)
            {
                var bigger = new uint8[(length + n) * 2];
                Array.Copy(all, 0, bigger, 0, length);
                all = bigger;
            }
            Array.Copy(_buffer, _pos, all, length, n);
            length += n;
            _pos = _count;
        }
        return _Decode(all, length);
    }

    // bytes that are not valid UTF-8 become '?'
    static string _Decode(uint8[] bytes, int length)
    {
        var text = Encoding.UTF8().GetString(bytes, 0, length);
        if (text is string valid)
            return valid;
        var copy = new uint8[length];
        for (var i = 0; i < length; i += 1)
            copy[i] = bytes[i] < 128 ? bytes[i] : (uint8)'?';
        return Encoding.UTF8().GetString(copy, 0, length) is string ascii ? ascii : "";
    }

    /// Closes the file.
    void Close()
    {
        _stream.Close();
    }

    /// Closes the file ([StreamReader.Close]); `using` calls it.
    void Dispose()
    {
        Close();
    }
}

/// Writes text to a file as UTF-8.
struct StreamWriter : IDisposable
{
    FileStream _stream;

    /// Creates a new, empty text file (an existing one is truncated).
    /// @error IoError.CannotCreate the file cannot be created (a missing folder, no permission).
    static IoError<StreamWriter> Create(string path)
    {
        var stream = try FileStream.Create(path);
        return StreamWriter { _stream = stream };
    }

    /// Opens a text file for writing at its end; it is created if it does not exist.
    /// @error IoError.CannotCreate the file cannot be opened or created.
    static IoError<StreamWriter> Append(string path)
    {
        var stream = try FileStream.Append(path);
        return StreamWriter { _stream = stream };
    }

    /// Writes `text`.
    /// @error IoError.CannotWrite writing failed.
    IoError<void> Write(StringSlice text)
    {
        return _stream.WriteText(text);
    }

    /// Writes `text` and a line break (`\n`).
    /// @error IoError.CannotWrite writing failed.
    IoError<void> WriteLine(StringSlice text)
    {
        try _stream.WriteText(text);
        return _stream.WriteText("\n");
    }

    /// Writes a line break (`\n`).
    /// @error IoError.CannotWrite writing failed.
    IoError<void> WriteLine()
    {
        return _stream.WriteText("\n");
    }

    /// Writes what is still buffered to the file.
    void Flush()
    {
        _stream.Flush();
    }

    /// Closes the file.
    void Close()
    {
        _stream.Close();
    }

    /// Closes the file ([StreamWriter.Close]); `using` calls it.
    void Dispose()
    {
        Close();
    }
}
