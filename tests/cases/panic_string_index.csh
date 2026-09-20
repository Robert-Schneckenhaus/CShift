// expect-exit: 101
// expect-stderr: panic: string index out of range
int Main()
{
    string s = "abc";
    int i = 3;
    return s[i];
}
