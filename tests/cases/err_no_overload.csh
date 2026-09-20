// expect-error: no matching function for call 'Print(bool)'
void Print(int value)
{
}

void Print(string value)
{
}

int Main()
{
    Print(true);
    return 0;
}
