// Directories and file names.
//
//     if (!Directory.Exists("out"))
//         Directory.Create("out");
//     var sources = Directory.FindFiles("src", ".csh");
//     string file = Path.Combine("src", "main.csh");
//
// Directory operations are done with the system shell (dir/mkdir on Windows, ls/test/mkdir elsewhere), so they
// do not depend on native functions that differ between systems. Paths may use '/' or '\'.

namespace System;

struct Path
{
    // Joins two path parts with '/' (an empty part is ignored, an absolute second part is returned as it is).
    static string Combine(string a, string b)
    {
        if (a.Length == 0)
            return b;
        if (b.Length == 0)
            return a;
        if (b[0] == '/' || b[0] == '\\' || (b.Length > 1 && b[1] == ':'))
            return b;
        char last = a[a.Length - 1];
        if (last == '/' || last == '\\')
            return a + b;
        return a + "/" + b;
    }

    // All separators as '/'.
    static string Normalize(string path)
    {
        return path.Replace("\\", "/");
    }

    // The path with the separators of the operating system (for commands that are run by the shell).
    static string ToNative(string path)
    {
        if (Process.IsWindows())
            return path.Replace("/", "\\");
        return path;
    }

    // Position of the last separator, -1 if there is none.
    static int _LastSeparator(string path)
    {
        int i = path.Length - 1;
        while (i >= 0)
        {
            if (path[i] == '/' || path[i] == '\\')
                return i;
            i -= 1;
        }
        return -1;
    }

    // The directory part: "a/b/c.txt" -> "a/b", "c.txt" -> "".
    static string GetDirectory(string path)
    {
        int i = _LastSeparator(path);
        if (i < 0)
            return "";
        if (i == 0)
            return path.Substring(0, 1);
        return path.Substring(0, i);
    }

    // The file name: "a/b/c.txt" -> "c.txt".
    static string GetFileName(string path)
    {
        int i = _LastSeparator(path);
        return path.Substring(i + 1);
    }

    // The extension including the dot: "c.txt" -> ".txt", "c" -> "".
    static string GetExtension(string path)
    {
        string name = GetFileName(path);
        int dot = name.LastIndexOf('.');
        if (dot <= 0)
            return "";
        return name.Substring(dot);
    }

    // The file name without directory and extension: "a/b/c.txt" -> "c".
    static string GetStem(string path)
    {
        string name = GetFileName(path);
        int dot = name.LastIndexOf('.');
        if (dot <= 0)
            return name;
        return name.Substring(0, dot);
    }

    // The same path with another extension (".o" or "o").
    static string ChangeExtension(string path, string extension)
    {
        string ext = GetExtension(path);
        string baseName = path.Substring(0, path.Length - ext.Length);
        if (extension.Length > 0 && extension[0] != '.')
            return baseName + "." + extension;
        return baseName + extension;
    }
}

struct Directory
{
    static bool Exists(string path)
    {
        if (Process.IsWindows())
            return Process.Run("dir /ad \"" + Path.ToNative(path) + "\" > nul 2>&1") == 0;
        return Process.Run("test -d \"" + path + "\"") == 0;
    }

    // Creates a directory including missing parents. Returns true if it exists afterwards.
    static bool Create(string path)
    {
        if (Exists(path))
            return true;
        if (Process.IsWindows())
            Process.Run("mkdir \"" + Path.ToNative(path) + "\" > nul 2>&1");
        else
            Process.Run("mkdir -p \"" + path + "\"");
        return Exists(path);
    }

    // The names of the files and directories in a directory (not the paths), sorted.
    static List<string> GetEntries(string path)
    {
        var names = List<string>.Create();
        Optional<string> output;
        if (Process.IsWindows())
            output = Process.RunCapture("dir /b \"" + Path.ToNative(path) + "\" 2> nul");
        else
            output = Process.RunCapture("ls -1A \"" + path + "\" 2>/dev/null");
        if (output is string text)
        {
            foreach (var line in text.Split('\n'))
            {
                string name = line.Trim();
                if (name.Length > 0)
                    names.Add(name);
            }
        }
        names.Sort();
        return names;
    }

    // All files below a directory (recursively) whose name ends with the extension (".csh"; empty = all files).
    // The paths start with the given directory and use '/'. The result is sorted.
    static List<string> FindFiles(string path, string extension)
    {
        var result = List<string>.Create();
        _Collect(Path.Normalize(path), extension, result);
        result.Sort();
        return result;
    }

    static void _Collect(string path, string extension, List<string> result)
    {
        foreach (var name in GetEntries(path))
        {
            string full = Path.Combine(path, name);
            if (Exists(full))
                _Collect(full, extension, result);
            else if (extension.Length == 0 || name.EndsWith(extension))
                result.Add(full);
        }
    }
}
