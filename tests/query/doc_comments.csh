// Doc comments (///, //!): the hover shows them as Markdown; 'cshiftc doc' writes them as JSON (tests/run_tests.sh).
// query: 47 36 => "doc": "Adds two points.\n\n**Parameters**\n- `other`: the point to add, in the same units.\n\n**Returns** the sum, see `Point.X`."
// query: 48 25 => "doc": "The horizontal position."
// query: 49 13 => "doc": "The colors of a `Point`.\n\n```\nvar c = Color.Red;\n```"
// query: 49 19 => "doc": "Red, the first color."
// query: 50 13 => "doc": "Parses a number.\n\n**Errors**\n- `ParseError.Invalid`: the text is not a number.\n\n*Since 0.22*"
// query: 51 12 => "hover": "int32 Plain(int32 x)", "definition"
//! Points and colors.
using System;

/// A point in the plane.
struct Point
{
    /// The horizontal position.
    int X;
    int Y;

    /// Adds two points.
    /// @param other the point to add,
    ///   in the same units.
    /// @returns the sum, see [Point.X].
    Point Add(Point other) { return Point { X = X + other.X, Y = Y + other.Y }; }
}

/// The colors of a [Point].
///
/// ```
/// var c = Color.Red;
/// ```
enum Color : uint8
{
    /// Red, the first color.
    Red = 1,
    Green
}

/// Parses a number.
/// @error ParseError.Invalid the text is not a number.
/// @since 0.22
ParseError<int> Number(string text) { return text.ParseInt(); }

//// four slashes: an ordinary comment
int Plain(int x) { return x; }

int Main()
{
    var p = Point { X = 1, Y = 2 }.Add(Point { X = 3, Y = 4 });
    Console.WriteLine(p.X.ToString());
    var c = Color.Red;
    var n = Number("12");
    return Plain(c == Color.Red ? 0 : 1);
}
