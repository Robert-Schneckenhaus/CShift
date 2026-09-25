// Directories and file names.
//
//     if (!Directory.Exists("out"))
//         Directory.Create("out");
//     var sources = Directory.FindFiles("src", ".csh");
//     string file = Path.Combine("src", "main.csh");
//
// Directory operations use the C library (opendir/readdir/mkdir, which MinGW-w64 provides on Windows as well). Paths
// may use '/' or '\'.

namespace System;

using System.Native;

extern "C" void* opendir(char* path);
extern "C" void* readdir(void* dir);
extern "C" int closedir(void* dir);
extern "C" int mkdir(char* path, int mode);
extern "C" char* getcwd(char* buffer, uint64 size);

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

    // True for "/x", "\\x" and "C:/x".
    static bool IsRooted(string path)
    {
        return path.Length > 0 && (path[0] == '/' || path[0] == '\\' || (path.Length > 1 && path[1] == ':'));
    }

    // The absolute path, with '/' separators and without "." and ".." parts (relative paths start at the current
    // directory).
    static string GetFullPath(string path)
    {
        string full = Normalize(IsRooted(path) ? path : Combine(Directory.GetCurrentDirectory(), path));
        string prefix = "";
        if (full.Length > 1 && full[1] == ':')
        {
            prefix = full.Substring(0, 2);
            full = full.Substring(2);
        }
        var parts = List<string>.Create();
        foreach (var part in full.Split('/'))
        {
            if (part.Length == 0 || part == ".")
                continue;
            if (part == "..")
            {
                if (parts.Count() > 0)
                    parts.RemoveAt(parts.Count() - 1);
            }
            else
                parts.Add(part);
        }
        return prefix + "/" + string.Join("/", parts.ToArray());
    }

    // The path of 'path' relative to the directory 'relativeTo' ("../lib/a.txt"); both are made absolute first. On
    // another drive the absolute path is returned.
    static string GetRelativePath(string relativeTo, string path)
    {
        string from = GetFullPath(relativeTo);
        string to = GetFullPath(path);
        bool windows = Process.IsWindows();
        if (from.Length > 1 && to.Length > 1 && from[1] == ':' && (to[1] != ':' || from[0].ToString().ToLower() != to[0].ToString().ToLower()))
            return to;
        string[] a = from.Split('/');
        string[] b = to.Split('/');
        int common = 0;
        while (common < a.Length && common < b.Length && (windows ? a[common].ToLower() == b[common].ToLower() : a[common] == b[common]))
            common += 1;
        var parts = List<string>.Create();
        for (var i = common; i < a.Length; i += 1)
        {
            if (a[i].Length > 0)
                parts.Add("..");
        }
        for (var i = common; i < b.Length; i += 1)
        {
            if (b[i].Length > 0)
                parts.Add(b[i]);
        }
        return parts.Count() == 0 ? "." : string.Join("/", parts.ToArray());
    }
}

struct Directory
{
    // The current working directory, with '/' separators.
    static string GetCurrentDirectory()
    {
        unsafe
        {
            char* buffer = (char*)Memory.Allocate(4096);
            string result = "";
            if (getcwd(buffer, 4096) != null)
                result = string.FromCStr(buffer);
            Memory.Free(buffer);
            return Path.Normalize(result);
        }
    }

    static bool Exists(string path)
    {
        unsafe
        {
            void* dir = opendir(path.CStr());
            if (dir == null)
                return false;
            closedir(dir);
            return true;
        }
    }

    // Creates a directory including missing parents. Returns true if it exists afterwards.
    static bool Create(string path)
    {
        if (path.Length == 0 || Exists(path))
            return true;
        string parent = Path.GetDirectory(path);
        if (parent.Length > 0 && parent != path && !(parent.Length == 2 && parent[1] == ':'))
            Create(parent);
        unsafe
        {
            mkdir(path.CStr(), 493); // 0755 (the mode is ignored on Windows)
        }
        return Exists(path);
    }

    // Where readdir puts the name in its 'struct dirent': the layout of the C library of the system.
    static int _NameOffset()
    {
        if (Process.IsWindows())
            return 8;  // MinGW-w64: long d_ino, unsigned short d_reclen, unsigned short d_namlen, char d_name[]
        if (File.Exists("/System/Library/CoreServices/SystemVersion.plist"))
            return 21; // macOS: d_ino, d_seekoff, d_reclen, d_namlen, d_type, d_name
        return 19;     // Linux (glibc, musl): d_ino, d_off, d_reclen, d_type, d_name
    }

    // The names of the files and directories in a directory (not the paths, without "." and ".."), sorted.
    static List<string> GetEntries(string path)
    {
        var names = List<string>.Create();
        int offset = _NameOffset();
        unsafe
        {
            void* dir = opendir(path.CStr());
            if (dir == null)
                return names;
            while (true)
            {
                void* entry = readdir(dir);
                if (entry == null)
                    break;
                string name = string.FromCStr((char*)((uint8*)entry + offset));
                if (name != "." && name != "..")
                    names.Add(name);
            }
            closedir(dir);
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
