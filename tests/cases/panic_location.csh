// expect-exit: 101
// expect-stderr: panic: array index out of range (index 5, length 3)
// expect-stderr: panic_location.csh:14:21 in Row.Get
// arc-ignore
// A panic shows where it happened (file:line:column and the function) and, for an index, the index and the length.
struct Row
{
    int[] Cells;

    int Get(int column)
    {
        if (column < 0)
            return 0;
        return Cells[column];
    }
}

int Main()
{
    var row = Row { Cells = [1, 2, 3] };
    return row.Get(5);
}
