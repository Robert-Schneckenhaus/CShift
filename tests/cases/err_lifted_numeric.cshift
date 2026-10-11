// Only view conversions are lifted into results: a number in an Optional is not widened by itself.
// expect-error: cannot implicitly convert 'Optional<int32>' to 'Optional<int64>'

using System;

int Main()
{
    Optional<int> small = 5;
    Optional<int64> big = small;
    return 0;
}
