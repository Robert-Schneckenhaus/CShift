namespace System;

using System.Native;

/// Whole files: reading, writing, copying, moving and deleting them (static functions). The paths are passed to the C
/// library as they are; text is UTF-8 unless an [Encoding] is given.
///
/// ```
/// var text = try File.ReadAllText("config.txt");
/// try File.WriteAllText("out.txt", text + "\n");
/// ```
struct File
{
    /// Whether a file (or directory) exists at `path`.
    static bool Exists(StringSlice path)
    {
        unsafe
        {
            void* f = fopen(path.CStr(), "rb".CStr());
            if (f == null)
                return false;
            fclose(f);
            return true;
        }
    }

    /// Deletes the file at `path`.
    /// @error IoError.CannotDelete the file does not exist or cannot be deleted.
    static IoError<void> Delete(StringSlice path)
    {
        unsafe
        {
            if (remove(path.CStr()) != 0)
                return error("cannot delete file '" + path + "'", IoError.CannotDelete);
        }
        return;
    }

    /// The contents of a file as bytes.
    /// @error IoError.CannotOpen the file does not exist or cannot be read.
    static IoError<uint8[]> ReadAllBytes(StringSlice path)
    {
        unsafe
        {
            void* f = fopen(path.CStr(), "rb".CStr());
            if (f == null)
                return error("cannot open file '" + path + "'", IoError.CannotOpen);

            uint8[] data = new uint8[4096];
            int length = 0;
            while (true)
            {
                if (length == data.Length)
                {
                    var bigger = new uint8[data.Length * 2];
                    Array.Copy(data, 0, bigger, 0, length);
                    data = bigger;
                }
                nuint n = fread(&data[length], 1, (nuint)(data.Length - length), f);
                if (n == 0)
                    break;
                length += (int)n;
            }
            fclose(f);

            var result = new uint8[length];
            Array.Copy(data, 0, result, 0, length);
            return result;
        }
    }

    /// The contents of a UTF-8 text file. A leading byte order mark is removed.
    /// @error IoError.CannotOpen the file does not exist or cannot be read.
    /// @error IoError.InvalidText the file is not valid UTF-8.
    static IoError<string> ReadAllText(StringSlice path)
    {
        return ReadAllText(path, Encoding.UTF8());
    }

    /// The contents of a text file in `encoding`. A leading UTF-8 byte order mark is removed.
    /// @error IoError.CannotOpen the file does not exist or cannot be read.
    /// @error IoError.InvalidText the file is not valid in the encoding.
    static IoError<string> ReadAllText(StringSlice path, Encoding encoding)
    {
        var bytes = try ReadAllBytes(path);
        int start = 0;
        if (encoding.Name() == "UTF-8" && bytes.Length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF)
            start = 3;
        var decoded = encoding.GetString(bytes, start, bytes.Length - start);
        if (decoded is not string text)
            return error(decoded.Message + " in '" + path + "'", IoError.InvalidText);
        return text;
    }

    /// Creates the file or replaces its contents with `bytes`.
    /// @error IoError.CannotCreate the file cannot be created (a missing folder, no permission).
    /// @error IoError.CannotWrite writing failed (the disk is full, ...).
    static IoError<void> WriteAllBytes(StringSlice path, uint8[] bytes)
    {
        unsafe
        {
            void* f = fopen(path.CStr(), "wb".CStr());
            if (f == null)
                return error("cannot create file '" + path + "'", IoError.CannotCreate);

            int length = bytes.Length;
            nuint written = 0;
            if (length > 0)
                written = fwrite(&bytes[0], 1, (nuint)length, f);
            int closed = fclose(f);
            if (written != (nuint)length || closed != 0)
                return error("cannot write file '" + path + "'", IoError.CannotWrite);
        }
        return;
    }

    /// Copies a file; an existing `target` is replaced only with `overwrite`.
    /// @error IoError.AlreadyExists `target` exists and `overwrite` is `false`.
    /// @error IoError.CannotOpen `source` cannot be read.
    /// @error IoError.CannotCreate `target` cannot be created.
    static IoError<void> Copy(StringSlice source, StringSlice target, bool overwrite)
    {
        if (!overwrite && Exists(target))
            return error("the file '" + target + "' already exists", IoError.AlreadyExists);
        var bytes = try ReadAllBytes(source);
        return WriteAllBytes(target, bytes);
    }

    /// Copies a file; an existing `target` is not replaced.
    /// @error IoError.AlreadyExists `target` exists.
    /// @error IoError.CannotOpen `source` cannot be read.
    /// @error IoError.CannotCreate `target` cannot be created.
    static IoError<void> Copy(StringSlice source, StringSlice target)
    {
        return Copy(source, target, false);
    }

    /// Moves (renames) a file; an existing `target` is replaced only with `overwrite`.
    /// @error IoError.CannotOpen `source` does not exist.
    /// @error IoError.AlreadyExists `target` exists and `overwrite` is `false`.
    /// @error IoError.CannotMove the system refused (another drive on AmigaOS, no permission).
    static IoError<void> Move(StringSlice source, StringSlice target, bool overwrite)
    {
        if (!Exists(source))
            return error("the file '" + source + "' does not exist", IoError.CannotOpen);
        if (!overwrite && Exists(target))
            return error("the file '" + target + "' already exists", IoError.AlreadyExists);
        if (!_Os.Rename(source, target))
            return error("cannot move '" + source + "' to '" + target + "'", IoError.CannotMove);
        return;
    }

    /// Moves (renames) a file; an existing `target` is not replaced.
    /// @error IoError.CannotOpen `source` does not exist.
    /// @error IoError.AlreadyExists `target` exists.
    /// @error IoError.CannotMove the system refused (another drive on AmigaOS, no permission).
    static IoError<void> Move(StringSlice source, StringSlice target)
    {
        return Move(source, target, false);
    }

    /// When the file was last written, in local time.
    /// @error IoError.CannotOpen the file does not exist.
    static IoError<DateTime> GetLastWriteTime(StringSlice path)
    {
        var utc = try GetLastWriteTimeUtc(path);
        return utc.ToLocalTime();
    }

    /// When the file was last written, in UTC.
    /// @error IoError.CannotOpen the file does not exist.
    static IoError<DateTime> GetLastWriteTimeUtc(StringSlice path)
    {
        if (_Os.FileWriteTime(path) is int64 ticks)
            return DateTime { Ticks = ticks + _UnixEpochTicks, IsUtc = true };
        return error("cannot read the time of '" + path + "'", IoError.CannotOpen);
    }

    /// Creates the file or replaces its contents with `text` (UTF-8).
    /// @error IoError.CannotCreate the file cannot be created (a missing folder, no permission).
    /// @error IoError.CannotWrite writing failed (the disk is full, ...).
    static IoError<void> WriteAllText(StringSlice path, StringSlice text)
    {
        return WriteAllText(path, text, Encoding.UTF8());
    }

    /// Creates the file or replaces its contents with `text` in `encoding`.
    /// @error IoError.CannotCreate the file cannot be created (a missing folder, no permission).
    /// @error IoError.CannotWrite writing failed (the disk is full, ...).
    static IoError<void> WriteAllText(StringSlice path, StringSlice text, Encoding encoding)
    {
        return WriteAllBytes(path, encoding.GetBytes(text));
    }
}
