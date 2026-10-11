// The wasm backend suspends a program in glfwPollEvents and resumes it (tests/wasi-run.mjs does both at once): the
// locals, the struct values in the frame, the recursion and a call through a function pointer survive.
using System;

extern "C" void glfwPollEvents();

struct Pair
{
    string Name;
    double Value;
}

int Deep(int depth, string tag, Pair pair)
{
    if (depth == 0)
    {
        glfwPollEvents();
        return tag.Length + (int)pair.Value;
    }
    int local = depth * 3;
    int result = Deep(depth - 1, tag + "!", Pair { Name = pair.Name, Value = pair.Value + 0.5 });
    return result + local;
}

int Twice(Func<int, int> f, int x)
{
    return f(f(x));
}

int Frame(int x)
{
    glfwPollEvents();
    return x + 1;
}

int Main()
{
    var lines = List<string>.Create();
    for (var i = 0; i < 3; i += 1)
    {
        var pair = Pair { Name = "p" + i.ToString(), Value = i * 1.5 };
        int deep = Deep(4, "ab", pair);
        int twice = Twice(Frame, i * 10);
        lines.Add(pair.Name + " " + deep.ToString() + " " + twice.ToString());
    }
    foreach (var line in lines)
        Console.WriteLine(line);
    return 0;
}
