// A MutexGuard holds the lock; only the thread that locked the mutex may release it.
// expect-error: not 'System.MutexGuard<int32>' (parameter 'guard')

using System;

thread void Release(MutexGuard<int> guard)
{
    guard.Dispose();
}

int Main()
{
    var m = Mutex<int>.Create(1);
    (start Release(m.Lock())).Join();
    return 0;
}
