// Error enums: 'error E { ... }' declares error codes (counting from 1, converting implicitly to int). error(E.X) and
// error("text", E.X) set the code (the message defaults to the member name). Error<T, E> - or E<T> - is a result whose
// code is an E: e.Code is an E, 'is E code' / 'case E code:' bind it, 'case E.Member:' matches one code. Error<T, E>
// converts to Error<T>; 'try' passes an error on only into a result with the same code type (or plain int codes).
// Also Error<Optional<T>, E>, Error<void, E>, a generic Error<T> parameter and 'try' in 'int Main'.
// expect-exit: 1
// expect-stdout: 101 1 102
// expect-stdout: NullReference 101 true
// expect-stdout: null ref 101
// expect-stdout: IndexOutOfRange 1 true
// expect-stdout: code 1
// expect-stdout: no code 0
// expect-stdout: true false
// expect-stdout: baz IndexOutOfRange
// expect-stdout: baz v0
// expect-stdout: plain IndexOutOfRange 1
// expect-stdout: widened 1
// expect-stdout: switch other negative
// expect-stdout: switch value 0
// expect-stdout: switch out of range
// expect-stdout: dynamic Other
// expect-stdout: unknown MyErrorType
// expect-stdout: guard 1
// expect-stdout: failed 1
// expect-stdout: nothing true
// expect-stdout: found user1
// expect-stdout: error Locked 2
// expect-stderr: error: Locked

using System;

error MyErrorType
{
    IndexOutOfRange,
    NullReference = 101,
    Other
}

Error<int> Foo(int x)
{
    if (x == 1)
        return error(MyErrorType.NullReference);
    if (x == 2)
        return error("null ref", MyErrorType.NullReference);
    return x;
}

MyErrorType<int> Bar(int index)
{
    if (index == 0)
        return 0;
    if (index < 0)
        return error("negative");
    return error(MyErrorType.IndexOutOfRange);
}

Error<string, MyErrorType> Baz(int i)
{
    int v = try Bar(i);
    return "v" + v.ToString();
}

Error<int> Plain(int i)
{
    int v = try Bar(i);
    return v + 1;
}

MyErrorType<void> Check(MyErrorType code)
{
    return error(code);
}

int MainPart1()
{
    int asInt = MyErrorType.NullReference;
    Console.WriteLine(asInt.ToString() + " " + ((int)MyErrorType.IndexOutOfRange).ToString() + " " + ((int)MyErrorType.Other).ToString());
    if (Foo(1) is error e1)
        Console.WriteLine(e1.Message + " " + e1.Code.ToString() + " " + (e1.Code == MyErrorType.NullReference).ToString());
    if (Foo(2) is error e2)
        Console.WriteLine(e2.Message + " " + e2.Code.ToString());
    if (Bar(10) is error e3)
        Console.WriteLine(e3.Message + " " + ((int)e3.Code).ToString() + " " + (e3.Code == MyErrorType.IndexOutOfRange).ToString());
    if (Bar(10) is MyErrorType code)
        Console.WriteLine("code " + ((int)code).ToString());
    if (Bar(-1) is MyErrorType c0)
        Console.WriteLine("no code " + ((int)c0).ToString());
    Console.WriteLine((Bar(0) is int).ToString() + " " + (Bar(0) is MyErrorType).ToString());
    if (Baz(3) is error e4) Console.WriteLine("baz " + e4.Message);
    if (Baz(0) is string s) Console.WriteLine("baz " + s);
    if (Plain(3) is error e5) Console.WriteLine("plain " + e5.Message + " " + e5.Code.ToString());
    Error<int> widened = Bar(5);
    if (widened is error e6) Console.WriteLine("widened " + e6.Code.ToString());
    for (var i = -1; i <= 1; i += 1)
    {
        switch (Bar(i))
        {
            case int v:
                Console.WriteLine("switch value " + v.ToString());
                break;
            case MyErrorType.IndexOutOfRange:
                Console.WriteLine("switch out of range");
                break;
            case error e:
                Console.WriteLine("switch other " + e.Message);
                break;
        }
    }
    MyErrorType dyn = MyErrorType.Other;
    if (Check(dyn) is error e7) Console.WriteLine("dynamic " + e7.Message);
    if (Check((MyErrorType)55) is error e8) Console.WriteLine("unknown " + e8.Message);
    if (Bar(3) is not MyErrorType c9)
        return 1;
    Console.WriteLine("guard " + ((int)c9).ToString());
    return 0;
}
error DbError { Offline, Locked }
DbError<Optional<string>> Find(int id)
{
    if (id < 0)
        return error(DbError.Offline);
    if (id == 0)
        return null;
    return "user" + id.ToString();
}
DbError<Optional<string>> Twice(int id)
{
    Optional<string> first = try Find(id);
    return first;
}
string Show<T>(Error<T> r)
{
    if (r is error e)
        return "error " + e.Message + " " + e.Code.ToString();
    return "ok";
}
int Main()
{
    if (MainPart1() != 0)
        return 10;
    for (var id = -1; id <= 1; id += 1)
    {
        var r = Twice(id);
        if (r is DbError code)
            Console.WriteLine("failed " + ((int)code).ToString());
        else if (r is string s)
            Console.WriteLine("found " + s);
        else if (r is Optional<string> o)
            Console.WriteLine("nothing " + (o == null).ToString());
    }
    DbError<int> x = error(DbError.Locked);
    Console.WriteLine(Show(x));
    int v = try x;
    return v;
}

