// A ReadOnlySlice in a result cannot become writable either.
// expect-error: cannot implicitly convert 'Optional<ReadOnlySlice<int32>>' to 'Optional<Slice<int32>>'

using System;

int Main()
{
    Optional<ReadOnlySlice<int>> view = [1, 2];
    Optional<Slice<int>> writable = view;
    return 0;
}
