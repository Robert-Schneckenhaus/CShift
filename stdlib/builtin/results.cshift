// The declarations of the built-in types (see README.md in this folder): only for the documentation.

/// A value or nothing (`null`): the result of a search that can find nothing.
///
/// ```
/// Optional<User> FindUser(int id) { ... return null; }
///
/// if (FindUser(7) is User u)
///     Console.WriteLine(u.Name);
/// ```
///
/// An `Optional<T>` is not a condition: test it with `is T v`, `is null`, `== null` or `switch`. A `T` converts to
/// it. See the language guide (error handling).
struct Optional<T>
{
}

/// A value or an error: the result of something that can fail.
///
/// ```
/// Error<int> Parse(string s) { ... return error("not a number"); }
///
/// switch (Parse(text))
/// {
///     case int n: Console.WriteLine(n); break;
///     case error e: Console.WriteLine(e.Message); break;
/// }
/// int n = try Parse(text);     // passes an error on to the caller
/// ```
///
/// `error("message")` or `error("message", code)` makes the error; `Error<void>` is a result without a value. With an
/// error enum the codes are typed: `IoError<string>` is `Error<string, IoError>` ([IoError]). See the language guide
/// (error handling).
struct Error<T>
{
    /// The message of the error.
    string Message;

    /// The code of the error (0 if none was given; the value of the error enum for a typed result).
    int Code;
}
