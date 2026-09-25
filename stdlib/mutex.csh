// Mutex<T>: a value that several threads share, guarded by a lock.
//
//     var counter = Mutex<int>.Create(0);
//
//     thread void Count(Mutex<int> counter, int times)
//     {
//         for (var i = 0; i < times; i += 1)
//         {
//             using (var guard = counter.Lock())      // unlocked again when the block is left
//                 guard.Set(guard.Get() + 1);
//         }
//     }
//
// A Mutex<T> is a handle: copies share the same value and lock, and it can be passed to 'thread' functions. The value
// only goes in and out as a copy that shares no reference count with anything else (Memory.CopyForThread: strings are
// copied into new blocks), so T must be a type that can be copied between threads: numbers, bool, char, enums,
// strings, SharedPtr<T> of thread-safe values, and Optional<T>/Error<T>/structs made of them - not arrays or
// containers. While a guard is held, Get/Set are safe from every thread; Mutex.Get/Set lock just for the one call.
//
// The generic bodies here are only compiled when Mutex<T> is used, which the frozen C++ compiler never does (it does
// not know Memory.CopyForThread).

namespace System;

using System.Native;

// The lock and the value, in the block of a SharedPtr (so freeing it frees both). pthread_mutex_t is kept as inline
// storage like in _ThreadCore (64 bytes are enough on every platform this compiles for).
struct _MutexState<T>
{
    int64 _m0; int64 _m1; int64 _m2; int64 _m3; int64 _m4; int64 _m5; int64 _m6; int64 _m7;
    T Value; // only touched under the lock (the struct itself is internal)

    void Init()
    {
        unsafe { pthread_mutex_init(&_m0, null); }
    }

    void Lock()
    {
        unsafe { pthread_mutex_lock(&_m0); }
    }

    void Unlock()
    {
        unsafe { pthread_mutex_unlock(&_m0); }
    }

    T Read()
    {
        return Memory.CopyForThread(Value);
    }

    void Write(T value)
    {
        Value = Memory.CopyForThread(value);
    }
}

struct Mutex<T>
{
    SharedPtr<_MutexState<T>> _state;

    static Mutex<T> Create(T value)
    {
        var state = SharedPtr<_MutexState<T>>.Create(_MutexState<T> { Value = Memory.CopyForThread(value) });
        unsafe { state.Ptr()->Init(); }
        return Mutex<T> { _state = state };
    }

    // Waits for the lock and returns a guard that holds it; Dispose() (e.g. through 'using') releases it.
    MutexGuard<T> Lock()
    {
        return MutexGuard<T>.Acquire(_state);
    }

    // A copy of the value (locks for the duration of the call).
    T Get()
    {
        unsafe
        {
            _MutexState<T>* p = _state.Ptr();
            p->Lock();
            T value = p->Read();
            p->Unlock();
            return value;
        }
    }

    // Replaces the value (locks for the duration of the call).
    void Set(T value)
    {
        unsafe
        {
            _MutexState<T>* p = _state.Ptr();
            p->Lock();
            p->Write(value);
            p->Unlock();
        }
    }
}

// Holds the lock of a Mutex<T> until Dispose(). Copies of a guard share the "held" flag, so the lock is released once.
// A guard cannot be passed to another thread (the thread that locked a mutex has to unlock it).
struct MutexGuard<T> : IDisposable
{
    SharedPtr<_MutexState<T>> _state;
    bool[] _held;

    // Used by Mutex<T>.Lock().
    static MutexGuard<T> Acquire(SharedPtr<_MutexState<T>> state)
    {
        unsafe { state.Ptr()->Lock(); }
        return MutexGuard<T> { _state = state, _held = new bool[] { true } };
    }

    T Get()
    {
        _CheckHeld();
        unsafe { return _state.Ptr()->Read(); }
    }

    void Set(T value)
    {
        _CheckHeld();
        unsafe { _state.Ptr()->Write(value); }
    }

    void Dispose()
    {
        if (_held == null || !_held[0])
            return;
        _held[0] = false;
        unsafe { _state.Ptr()->Unlock(); }
    }

    void _CheckHeld()
    {
        if (_held == null || !_held[0])
            Environment.Panic("the MutexGuard was already disposed (the lock is released)");
    }
}
