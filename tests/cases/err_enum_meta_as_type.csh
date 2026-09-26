// Enum<T> is not a type.
// expect-error: 'Enum<T>' is not a type; it gives facts about an enum: Enum<T>.Count, .Min, .Max, .Values, .Names

enum Color : int32 { Red, Green }

int Main()
{
    Enum<Color> e;
    return 0;
}
