// expect-error: operator cannot mix 'uint64' and signed types
// Only the small types without a sign meet uint64 as uint64; a signed one still needs a cast (like in C#).
int Main()
{
    uint64 big = 1;
    int8 n = -1;
    var x = big + n;
    return 0;
}
