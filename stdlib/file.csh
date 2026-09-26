// File operations (static). All paths are passed to the C library as they are; text is UTF-8 unless an
// Encoding is given.
//
//     var text = try File.ReadAllText("config.txt");
//     try File.WriteAllText("out.txt", text + "\n");

namespace System;

using System.Native;

struct File
{
    static bool Exists(string path)
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

    static IoError<void> Delete(string path)
    {
        unsafe
        {
            if (remove(path.CStr()) != 0)
                return error("cannot delete file '" + path + "'", IoError.CannotDelete);
        }
        return;
    }

    static IoError<uint8[]> ReadAllBytes(string path)
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
                uint64 n = fread(&data[length], 1, (uint64)(data.Length - length), f);
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

    // Reads a UTF-8 file. A leading byte order mark is removed.
    static IoError<string> ReadAllText(string path)
    {
        return ReadAllText(path, Encoding.UTF8());
    }

    static IoError<string> ReadAllText(string path, Encoding encoding)
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

    // Creates the file or replaces its contents.
    static IoError<void> WriteAllBytes(string path, uint8[] bytes)
    {
        unsafe
        {
            void* f = fopen(path.CStr(), "wb".CStr());
            if (f == null)
                return error("cannot create file '" + path + "'", IoError.CannotCreate);

            int length = bytes.Length;
            uint64 written = 0;
            if (length > 0)
                written = fwrite(&bytes[0], 1, (uint64)length, f);
            int closed = fclose(f);
            if (written != (uint64)length || closed != 0)
                return error("cannot write file '" + path + "'", IoError.CannotWrite);
        }
        return;
    }

    // Copies a file; an existing target is replaced only with 'overwrite'.
    static IoError<void> Copy(string source, string target, bool overwrite)
    {
        if (!overwrite && Exists(target))
            return error("the file '" + target + "' already exists", IoError.AlreadyExists);
        var bytes = try ReadAllBytes(source);
        return WriteAllBytes(target, bytes);
    }

    static IoError<void> Copy(string source, string target)
    {
        return Copy(source, target, false);
    }

    static IoError<void> WriteAllText(string path, string text)
    {
        return WriteAllText(path, text, Encoding.UTF8());
    }

    static IoError<void> WriteAllText(string path, string text, Encoding encoding)
    {
        return WriteAllBytes(path, encoding.GetBytes(text));
    }
}
