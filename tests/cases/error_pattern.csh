// 'is error e' matches a failed Error<T> and binds the whole result (e.Message, e.Code), also in a switch and for
// Error<Optional<T>>.
// expect-exit: 0
// expect-stdout: error negative key 7
// expect-stdout: switch: negative key
// expect-stdout: nothing found
// expect-stdout: value 1

using System;
Error<Optional<int>> Find(int k) { if (k < 0) return error("negative key", 7); if (k == 0) return null; return k; }
int Main()
{
    for (var k = -1; k <= 1; k += 1)
    {
        var r = Find(k);
        if (r is error e)
            Console.WriteLine($"error {e.Message} {e.Code}");
        else if (r is int v)
            Console.WriteLine($"value {v}");
        else
            Console.WriteLine("nothing found");
        switch (r)
        {
            case error failure:
                Console.WriteLine("switch: " + failure.Message);
                break;
            case Optional<int> o:
                Console.WriteLine("switch: ok");
                break;
        }
    }
    return 0;
}
