// The error codes of the standard library (error enums, see docs/language/error-handling.md): the fallible functions
// return typed results, e.g. IoError<string> File.ReadAllText(...), so a caller can match a code directly:
//
//     switch (File.ReadAllText(path))
//     {
//         case string text: ...
//         case IoError.CannotOpen: ...
//         case error e: ...
//     }
//
// A typed result converts to a plain Error<T> (the code becomes an int), so existing Error<T> code keeps working.

namespace System;

// File operations (File.*).
error IoError
{
    CannotOpen = 1,      // the file does not exist or cannot be read
    CannotWrite = 2,     // writing or closing failed (disk full, ...)
    CannotDelete = 3,
    AlreadyExists = 4,   // File.Copy without overwrite
    InvalidText = 5,     // the content is not valid in the requested encoding (File.ReadAllText)
    CannotCreate = 6     // the file cannot be created or truncated (missing folder, no permission)
}

// Number parsing (string.ParseInt, ParseInt64, ParseDouble).
error ParseError
{
    Invalid = 1,         // not a number
    OutOfRange = 2       // a number, but too large for the type
}

// Decoding bytes (Encoding.GetString).
error EncodingError
{
    OutOfBounds = 1,     // the byte range is outside the array
    NotAscii = 2,        // a byte above 127 for ASCII
    InvalidUtf8 = 3      // malformed UTF-8 (invalid byte, truncated or overlong sequence, surrogate)
}
