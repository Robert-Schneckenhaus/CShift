// Errors around threads, all in one run.
// expect-error: err_several_threads.csh:15:16: error: undefined name 'missing'
// expect-error: err_several_threads.csh:25:27: error: no matching function for call 'Work(string)': argument 1: cannot convert 'string' to 'int32'
// expect-error: err_several_threads.csh:26:13: error: call to the 'thread' function 'Work' must be prefixed with 'start': 'start Work(...)'
// expect-error: err_several_threads.csh:27:19: error: 'start' can only be used with a 'thread' function, not 'Plain'
// expect-error: err_several_threads.csh:28:21: error: 'Thread.Cancelled' can only be used inside a 'thread' function
// expect-error: err_several_threads.csh:29:16: error: cannot implicitly convert 'int32' to 'string'

using System;

thread int Work(int x)
{
    if (Thread.Cancelled)
        return 0;
    return x + missing;
}

int Plain(int x)
{
    return x;
}

void Main()
{
    Thread<int> t = start Work("one");
    int r = Work(2);
    var p = start Plain(3);
    bool c = Thread.Cancelled;
    string s = t.Join();
    Console.WriteLine(r);
}
