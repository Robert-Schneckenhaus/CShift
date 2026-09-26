// Error<void>: a result without a value (success or error). "return;" or reaching the end
// of the function means success.
// expect-exit: 0

int Check(string name, bool ok)
{
    if (ok)
        return 0;
    Console.WriteLine("FAIL: " + name);
    return 1;
}

Error<void> Step(int i)
{
    if (i == 3)
        return error("step 3 failed", 3);
    // falls off the end: success
}

Error<void> Explicit()
{
    return;
}

Error<void> RunAll(int n)
{
    for (var i = 0; i < n; i += 1)
    {
        try Step(i);
    }
    return;
}

Error<int> Count(int n)
{
    try RunAll(n);
    return n;
}

Error<void> Forward(string text)
{
    var value = try Parse(text);
    if (value < 0)
        return error("negative");
    return;
}

Error<int> Parse(string text)
{
    if (text.Length == 0)
        return error("empty");
    return text.Length;
}

int Main()
{
    int f = 0;

    f += Check("implicit success", !(Step(1) is error));
    var ok = Step(1);
    f += Check("success is not an error", !(ok is error));
    if (ok)
        f += 0;
    else
        f += 1;
    f += Check("explicit return", !(Explicit() is error));

    var failed = Step(3);
    f += Check("error", !failed && failed.Message == "step 3 failed" && failed.Code == 3);

    f += Check("try in loop success", !(RunAll(3) is error));
    var stopped = RunAll(5);
    f += Check("try in loop failure", !stopped && stopped.Code == 3);

    if (Count(2) is int two)
        f += Check("Error<int> after try", two == 2);
    else
        f += 1;
    f += Check("Error<int> failure", !Count(9) && Count(9).Message == "step 3 failed");

    f += Check("try with value", !(Forward("abc") is error) && Forward("") is error empty && empty.Message == "empty");

    Error<void> assigned = error("assigned");
    f += Check("assign error", !assigned && assigned.Message == "assigned");
    Error<void> defaulted;
    f += Check("default is an error without message", !defaulted && defaulted.Message == null);

    return f;
}
