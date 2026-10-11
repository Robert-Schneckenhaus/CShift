// The declarations of the built-in types (see README.md in this folder): only for the documentation.

/// Text output to the console: stdout and stderr.
///
/// ```
/// Console.WriteLine("Hello");
/// Console.Write(42);                       // numbers, bool, char, enums and slices become text
/// Console.WriteErrorLine("warning: ...");
/// ```
///
/// The argument can be anything that becomes text in `"x" + value`: strings, string slices, numbers, `bool`,
/// `char`, enums, and structs with a `string ToString()`.
struct Console
{
    /// Writes `value` to stdout.
    static void Write(string value);

    /// Writes `value` and a line break (`\n`) to stdout.
    static void WriteLine(string value);

    /// Writes a line break to stdout.
    static void WriteLine();

    /// Writes `value` to stderr.
    static void WriteError(string value);

    /// Writes `value` and a line break to stderr.
    static void WriteErrorLine(string value);

    /// Writes a line break to stderr.
    static void WriteErrorLine();
}

/// The running program: ending it, with an exit code or with a panic.
struct Environment
{
    /// Ends the program with the exit code `code` (0: success).
    static void Exit(int code);

    /// Ends the program because of a bug: writes `message` and where the panic happened (file, line, column and
    /// function; for a function of the standard library also where the program called it) to stderr and exits with
    /// code 101.
    static void Panic(string message);
}

/// Raw memory (`unsafe`): allocating and freeing blocks, volatile accesses for hardware registers, and copies of
/// values for other threads.
struct Memory
{
    /// A new block of `size` bytes (the C library's `malloc`), not cleared.
    static void* Allocate(nuint size);

    /// Frees a block from [Memory.Allocate].
    static void Free(void* block);

    /// Reads the value at `address` with a volatile access: the compiler neither drops nor merges it (hardware
    /// registers, memory that something else changes).
    static T VolatileRead<T>(T* address);

    /// Writes `value` to `address` with a volatile access: every write reaches the memory, in order.
    static void VolatileWrite<T>(T* address, T value);

    /// A copy of `value` that shares no reference count with anything else (strings are copied into new blocks), so
    /// that another thread can own it. [Mutex] uses it.
    static T CopyForThread<T>(T value);
}
