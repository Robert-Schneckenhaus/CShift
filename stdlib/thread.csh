// Real OS threads: the 'thread' keyword and the built-in types Thread / Thread<T>.
//
//     thread int Square(int x) { return x * x; }
//
//     void Main()
//     {
//         Thread<int> t = Square(6);
//         Console.WriteLine(t.Join());   // 36
//     }
//
// A 'thread' function may only see its own parameters and return a value: the compiler rejects any read or
// write of a global variable, transitively through every function it calls. Its parameters must be plain value
// types or SharedPtr<T> - no 'ref'/'const ref', no raw pointers, no Action/Func (see docs/language/threading.md).
// Calling it does not run it - it starts a new OS thread and immediately returns a handle: Thread for a 'void'
// result, Thread<T> otherwise.
//
// This file has two parts:
//  - _ThreadCore / _ThreadControl<T> (the leading underscore marks a struct as private by this codebase's
//    convention: not meant to be named from ordinary code): the mutex, condition variable and flags shared
//    between the spawning/joining side and the worker thread, and the methods that guard them. Those methods
//    have plain names (Init, WaitCompleted, ...) rather than a leading underscore, because they are called from
//    Thread/Thread<T>/_ThreadVoid - a different struct - and only a struct's own methods may touch its
//    '_'-prefixed (private) fields; the struct name is the privacy boundary here, not the method name.
//  - Thread / Thread<T> themselves: Join, Cancel, CancelAndWait, IsCompleted, IsCancelled, and the private
//    '_TryGetResult' that backs the 'thread is T result' pattern. ('Thread', the plain non-generic handle, is
//    actually named '_ThreadVoid' below - the compiler maps the bare spelling 'Thread' to it, see
//    CodeGenThread.cpp, because this codebase's structs cannot be overloaded by type-argument count.)
//
// The code generator (CodeGenThread.cpp) calls a handful of these methods directly - by name, through a raw
// pointer, exactly like CShift code calling them through '->' - when it spawns a thread and when it emits
// 'Thread.Cancelled'.

namespace System;

using System.Native;

// pthread_mutex_t/pthread_cond_t are kept as inline storage (not a separate allocation) so that freeing a
// thread's control block - a SharedPtr, see below - leaves nothing else to free or leak. 64 bytes is generous
// for both of them on every platform this compiles for.
struct _ThreadCore
{
    int64 _m0; int64 _m1; int64 _m2; int64 _m3; int64 _m4; int64 _m5; int64 _m6; int64 _m7;
    int64 _c0; int64 _c1; int64 _c2; int64 _c3; int64 _c4; int64 _c5; int64 _c6; int64 _c7;
    bool _completed;
    bool _cancelRequested;

    void Init()
    {
        unsafe
        {
            pthread_mutex_init(&_m0, null);
            pthread_cond_init(&_c0, null);
        }
    }

    void MarkCompleted()
    {
        unsafe
        {
            pthread_mutex_lock(&_m0);
            _completed = true;
            pthread_cond_broadcast(&_c0);
            pthread_mutex_unlock(&_m0);
        }
    }

    // Waits until the thread has finished, whether it ran to completion or was cancelled.
    void WaitCompleted()
    {
        unsafe
        {
            pthread_mutex_lock(&_m0);
            while (!_completed)
                pthread_cond_wait(&_c0, &_m0);
            pthread_mutex_unlock(&_m0);
        }
    }

    // Requests cancellation; does not wait.
    void RequestCancel()
    {
        unsafe
        {
            pthread_mutex_lock(&_m0);
            _cancelRequested = true;
            pthread_mutex_unlock(&_m0);
        }
    }

    bool IsCompleted()
    {
        unsafe
        {
            pthread_mutex_lock(&_m0);
            bool v = _completed;
            pthread_mutex_unlock(&_m0);
            return v;
        }
    }

    bool IsCancelled()
    {
        unsafe
        {
            pthread_mutex_lock(&_m0);
            bool v = _cancelRequested;
            pthread_mutex_unlock(&_m0);
            return v;
        }
    }

    // True once the thread has completed with a value, i.e. 'Cancel'/'CancelAndWait' was never called for it.
    // Both flags are read under the same lock so the two cannot be observed in an inconsistent combination.
    bool HasResult()
    {
        unsafe
        {
            pthread_mutex_lock(&_m0);
            bool v = _completed && !_cancelRequested;
            pthread_mutex_unlock(&_m0);
            return v;
        }
    }
}

// 'Core' must stay the very first field: the compiler-generated trampoline, and Thread.Cancelled, pass around a
// raw '_ThreadCore*' that - for a Thread<T> - actually points at the first field of a '_ThreadControl<T>'. That
// is safe exactly because Core is field 0.
struct _ThreadControl<T>
{
    _ThreadCore Core;
    T _result;

    // Called by the trampoline of a thread function that returns a value, right before Core.MarkCompleted().
    void SetResult(T value)
    {
        _result = value;
    }

    T GetResult()
    {
        return _result;
    }
}

// The handle returned by calling a 'thread void' function. Written to the language as bare 'Thread' - the
// compiler resolves that spelling to this struct (see CodeGenThread.cpp); 'Thread<T>' below is a separate,
// ordinary generic struct that this codebase's type system cannot give the very same name at a different arity.
struct _ThreadVoid
{
    SharedPtr<_ThreadCore> _core;

    static _ThreadVoid _Wrap(SharedPtr<_ThreadCore> core)
    {
        return _ThreadVoid { _core = core };
    }

    void Join()
    {
        unsafe { _core.Ptr()->WaitCompleted(); }
    }

    void Cancel()
    {
        unsafe { _core.Ptr()->RequestCancel(); }
    }

    void CancelAndWait()
    {
        Cancel();
        Join();
    }

    bool IsCompleted()
    {
        unsafe { return _core.Ptr()->IsCompleted(); }
    }

    bool IsCancelled()
    {
        unsafe { return _core.Ptr()->IsCancelled(); }
    }
}

// The handle returned by calling a 'thread T' function (T other than void).
struct Thread<T>
{
    SharedPtr<_ThreadControl<T>> _core;

    static Thread<T> _Wrap(SharedPtr<_ThreadControl<T>> core)
    {
        return Thread<T> { _core = core };
    }

    // Waits until the thread has finished and returns what it returned - even if it was cancelled: a cancelled
    // thread still has to return a value of type T (see the language guide).
    T Join()
    {
        unsafe
        {
            _ThreadControl<T>* p = _core.Ptr();
            p->Core.WaitCompleted();
            return p->GetResult();
        }
    }

    void Cancel()
    {
        unsafe { _core.Ptr()->Core.RequestCancel(); }
    }

    void CancelAndWait()
    {
        Cancel();
        Join();
    }

    bool IsCompleted()
    {
        unsafe { return _core.Ptr()->Core.IsCompleted(); }
    }

    bool IsCancelled()
    {
        unsafe { return _core.Ptr()->Core.IsCancelled(); }
    }

    // Backs 'thread is T result': non-blocking, and not true if the thread is still running or was cancelled -
    // even if it did return a value. Call Join() to get the value regardless of how it finished.
    Optional<T> _TryGetResult()
    {
        unsafe
        {
            _ThreadControl<T>* p = _core.Ptr();
            if (!p->Core.HasResult())
                return null;
            return p->GetResult();
        }
    }
}
