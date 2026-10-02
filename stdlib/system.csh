//! The standard library: collections ([List], [Dictionary], [HashSet], [Stack], [Queue]), text ([StringBuilder],
//! [Encoding], [Regex], [JsonValue]), files and folders ([File], [Directory], [Path], [FileStream],
//! [StreamReader], [StreamWriter]), time ([DateTime], [TimeSpan], [Stopwatch]), processes, random numbers and
//! threads ([Thread], [Mutex]).
//!
//! ```
//! using System;
//!
//! int Main()
//! {
//!     var names = List<string>.Create();
//!     names.Add("Ann");
//!     Console.WriteLine(names[0]);
//!     return 0;
//! }
//! ```
//!
//! Functions that can fail return typed results, e.g. `IoError<string>` from [File.ReadAllText]: the value or one of
//! the codes of an error enum ([IoError], [ParseError], [EncodingError], [JsonError], [RegexError]).

namespace System;
