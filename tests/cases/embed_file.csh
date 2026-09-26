// embed("file") puts the exact content of a file into a string constant when the program is compiled: a byte order
// mark, \r\n and \n, quotes, backslashes, braces and UTF-8 stay as they are, so writing the constant with
// File.WriteAllText gives the same bytes back. The path is relative to this source file.
// expect-exit: 0
// expect-stdout: length 112 0
// expect-stdout: bom true crlf true lf true quote true end true
// expect-stdout: roundtrip 112 true
// expect-stdout: local true

using System;

const string Shader = embed("embed/shader.glsl");
const string Empty = embed("embed/empty.txt");
const string Other = Shader;                       // an embedded constant is an ordinary string constant

int Main()
{
    Console.WriteLine("length " + Shader.Length.ToString() + " " + Empty.Length.ToString());
    bool bom = (int)Shader[0] == 0xEF && (int)Shader[1] == 0xBB && (int)Shader[2] == 0xBF;
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
