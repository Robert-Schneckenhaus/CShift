// expect-error: 'Action' supports at most 8 parameters
int Main()
{
    Action<int, int, int, int, int, int, int, int, int> a = null;
    return 0;
}
