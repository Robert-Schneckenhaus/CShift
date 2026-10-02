// The declarations of the built-in types (see README.md in this folder): only for the documentation.

/// The handle of a running `thread void` function: `start Work(10)` runs it on its own OS thread and returns a
/// `Thread` right away. A function with a result gives a [Thread<T>] instead.
///
/// ```
/// thread void Work(int n) { ... }
///
/// Thread t = start Work(10);
/// t.Join();
/// ```
struct Thread
{
    /// Inside a thread function: whether its thread was asked to stop ([Thread.Cancel]). The function decides itself
    /// when to look and how to stop.
    static bool Cancelled;

    /// Pauses the calling thread for `milliseconds` (`Thread.Sleep(100)`: a tenth of a second).
    static void Sleep(int milliseconds);

    /// Waits until the thread has finished.
    void Join();

    /// Requests cancellation and does not wait: the thread notices it by reading [Thread.Cancelled].
    void Cancel();

    /// Requests cancellation and waits until the thread has finished.
    void CancelAndWait();

    /// Whether the thread has finished: by returning, or after a cancellation request.
    bool IsCompleted();

    /// Whether [Thread.Cancel] or [Thread.CancelAndWait] was called; the thread may still be running.
    bool IsCancelled();
}

/// A value in a reference-counted box that threads can share: `SharedPtr<T>.Create(value)` moves the value into the
/// box, copies of the `SharedPtr` share it, and the last one frees it. The reference count is atomic, so copies can
/// go to other threads; the value must then be thread-safe itself (no strings, arrays or containers inside).
///
/// The value is not locked: concurrent changes through [SharedPtr<T>.Ptr] need their own synchronization, or a
/// [Mutex].
struct SharedPtr<T>
{
    /// A new box with `value`.
    static SharedPtr<T> Create(T value);

    /// Whether there is no box (a `null` or default `SharedPtr`).
    bool IsNull();

    /// A copy of the value in the box.
    T Get();

    /// A pointer to the value in the box, for changing it in place (`unsafe`).
    T* Ptr();
}
