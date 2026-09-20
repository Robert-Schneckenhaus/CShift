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

    static Error<void> Delete(string path)
    {
        unsafe
        {
            if (remove(path.CStr()) != 0)
                return error("cannot delete file '" + path + "'", 3);
        }
        return;
    }

    static Error<uint8[]> ReadAllBytes(string path)
    {
        unsafe
        {
            void* f = fopen(path.CStr(), "rb".CStr());
            if (f == null)
                return error("cannot open file '" + path + "'", 1);

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
    static Error<string> ReadAllText(string path)
    {
        return ReadAllText(path, Encoding.UTF8());
    }

    static Error<string> ReadAllText(string path, Encoding encoding)
    {
        var bytes = try ReadAllBytes(path);
        int start = 0;
        if (encoding.Name() == "UTF-8" && bytes.Length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF)
            start = 3;
        return encoding.GetString(bytes, start, bytes.Length - start);
    }

    // Creates the file or replaces its contents.
    static Error<void> WriteAllBytes(string path, uint8[] bytes)
    {
        unsafe
        {
            void* f = fopen(path.CStr(), "wb".CStr());
            if (f == null)
                return error("cannot create file '" + path + "'", 1);

            int length = bytes.Length;
            uint64 written = 0;
            if (length > 0)
                written = fwrite(&bytes[0], 1, (uint64)length, f);
            int closed = fclose(f);
            if (written != (uint64)length || closed != 0)
                return error("cannot write file '" + path + "'", 2);
        }
        return;
    }

    static Error<void> WriteAllText(string path, string text)
    {
        return WriteAllText(path, text, Encoding.UTF8());
    }

    static Error<void> WriteAllText(string path, string text, Encoding encoding)
    {
        return WriteAllBytes(path, encoding.GetBytes(text));
    }
}
