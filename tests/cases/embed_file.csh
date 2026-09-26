// embed("file") puts the content of a file into a string constant when the program is compiled: \r\n and \n, quotes,
// backslashes, braces and UTF-8 stay as they are (only a byte order mark is dropped), so writing the constant with
// File.WriteAllText gives the same content back. The path is relative to this source file.
// expect-exit: 0
// expect-stdout: length 109 0
// expect-stdout: bom true crlf true lf true quote true end true
// expect-stdout: roundtrip 109 true
// expect-stdout: local true

using System;

const string Shader = embed("embed/shader.glsl");
const string Empty = embed("embed/empty.txt");
const string Other = Shader;                       // an embedded constant is an ordinary string constant

int Main()
{
    Console.WriteLine("length " + Shader.Length.ToString() + " " + Empty.Length.ToString());
    bool bom = Shader.StartsWith("#version 330 core\r\n");   // the file starts with a byte order mark, which is dropped
    bool crlf = Shader.Contains("core\r\n//");
    bool lf = Shader.Contains("$dollar\n\tcolor");
    bool quote = Shader.Contains("\"quotes\", \\backslashes\\ and 'single' {braces}");
    bool end = Shader.EndsWith("ü" + "ñ €\r\n");
    Console.WriteLine("bom " + bom.ToString().ToLower() + " crlf " + crlf.ToString().ToLower() + " lf " + lf.ToString().ToLower() +
                      " quote " + quote.ToString().ToLower() + " end " + end.ToString().ToLower());

    string path = "embed_file_roundtrip.tmp";
    if (File.WriteAllText(path, Other) is error)
        return 1;
    var read = File.ReadAllBytes(path);
    File.Delete(path);
    if (read is uint8[] bytes)
    {
        bool same = bytes.Length == Shader.Length;
        for (var i = 0; same && i < bytes.Length; i += 1)
            same = (int)bytes[i] == (int)Shader[i];
        Console.WriteLine("roundtrip " + bytes.Length.ToString() + " " + same.ToString().ToLower());
    }
    else
    {
        return 2;
    }

    const string Local = embed("embed/shader.glsl");
    Console.WriteLine("local " + (Local == Shader).ToString().ToLower());
    return 0;
}
