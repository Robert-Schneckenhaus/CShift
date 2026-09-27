// A format in a hole is only for numbers.
// expect-error: a number format (like ':F2' or ToString("F2")) is only for numbers, not for 'string'

int Main()
{
    string s = "x";
    return $"{s:F2}".Length;
}
