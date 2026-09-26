// Enum<T> has only Count, Min, Max, Values and Names.
// expect-error: Enum<Color> has no member 'Length' (only Count, Min, Max, Values and Names)

enum Color : int32 { Red, Green }

int Main()
{
    return Enum<Color>.Length;
}
