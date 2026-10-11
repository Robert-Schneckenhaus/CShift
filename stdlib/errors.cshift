namespace System;

/// The errors of file and folder operations ([File], [Directory], [FileStream]).
///
/// A function returns `IoError<T>`: the result, or one of these codes. A `switch` can handle each code:
///
/// ```
/// switch (File.ReadAllText(path))
/// {
///     case string text: Console.WriteLine(text); break;
///     case IoError.CannotOpen: Console.WriteLine("no such file"); break;
///     case error e: Console.WriteLine(e.Message); break;
/// }
/// ```
///
/// A typed result converts to a plain `Error<T>` (the code becomes an `int`).
error IoError
{
    /// The file does not exist or cannot be read.
    CannotOpen = 1,
    /// Writing or closing failed (the disk is full, ...).
    CannotWrite = 2,
    /// The file or folder cannot be deleted.
    CannotDelete = 3,
    /// The target exists already (e.g. [File.Copy] without overwriting).
    AlreadyExists = 4,
    /// The content is not valid in the requested encoding ([File.ReadAllText] with an [Encoding]).
    InvalidText = 5,
    /// The file cannot be created or truncated (a missing folder, no permission).
    CannotCreate = 6,
    /// Moving or renaming failed ([File.Move], [Directory.Move]), e.g. to another drive on AmigaOS or without
    /// permission.
    CannotMove = 7
}

/// The errors of parsing numbers ([String.ParseInt], [String.ParseInt64], [String.ParseDouble]).
error ParseError
{
    /// The text is not a number.
    Invalid = 1,
    /// The text is a number, but too large or too small for the type.
    OutOfRange = 2
}

/// The errors of decoding bytes into text ([Encoding.GetString]).
error EncodingError
{
    /// The byte range is outside of the array.
    OutOfBounds = 1,
    /// A byte above 127 in ASCII.
    NotAscii = 2,
    /// Malformed UTF-8: an invalid byte, a truncated or overlong sequence, or a surrogate.
    InvalidUtf8 = 3
}
