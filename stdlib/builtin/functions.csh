// The declarations of the built-in types (see README.md in this folder): only for the documentation.

/// A function value without a result: `Action<int, string>` takes an `int` and a `string`. Up to 8 parameters.
///
/// ```
/// Action<string> log = s => Console.WriteLine("log: " + s);
/// log("started");
/// ```
///
/// A function, a lambda or a closure (it captures read-only copies) can be assigned to it; without captures it is a
/// plain C function pointer. See the language guide (functions).
struct Action
{
    /// Calls the function (the same as `f(...)`).
    void Invoke(...);
}

/// A function value with a result: the last type argument is the result, `Func<int, int, int>` takes two `int`s
/// and returns an `int`. Up to 8 parameters.
///
/// ```
/// Func<int, int> square = x => x * x;
/// int nine = square(3);
/// ```
struct Func
{
    /// Calls the function (the same as `f(...)`) and returns its result.
    void Invoke(...);
}

/// Facts about an enum type, all of them constants (usable in other constants too).
///
/// ```
/// for (var i = 0; i < Enum<Color>.Count; i += 1)
///     Console.WriteLine(Enum<Color>.Names[i] + " = " + (int)Enum<Color>.Values[i]);
/// ```
struct Enum<T>
{
    /// The number of declared members (members that share a value count separately).
    static int Count;

    /// The smallest value.
    static T Min;

    /// The largest value.
    static T Max;

    /// All members in declaration order.
    static ReadOnlySlice<T> Values;

    /// The names of the members, in declaration order.
    static ReadOnlySlice<string> Names;
}
