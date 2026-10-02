// What the C library of WebAssembly (wasi-libc) does not have: a WebAssembly program has one thread and cannot start
// other programs. The locks of Mutex<T> do nothing (nothing else runs), Process.Run and Process.RunCapture report
// that the command could not be started. Threads themselves ('start') are a compile error on WebAssembly.

namespace System;

extern "C" int pthread_mutex_init(void* mutex, void* attr) { return 0; }
extern "C" int pthread_mutex_lock(void* mutex) { return 0; }
extern "C" int pthread_mutex_unlock(void* mutex) { return 0; }
extern "C" int pthread_cond_init(void* cond, void* attr) { return 0; }
extern "C" int pthread_cond_broadcast(void* cond) { return 0; }

extern "C" int pthread_cond_wait(void* cond, void* mutex)
{
    // nothing else could wake it up
    Environment.Panic("waiting for a thread on WebAssembly, which has only one");
    return 0;
}

extern "C" int system(char* command) { return -1; }
extern "C" void* popen(char* command, char* mode) { return null; }
extern "C" int pclose(void* stream) { return -1; }

extern "C" char* getenv(char* name);
extern "C" int chdir(char* path);

// Called before Main: WASI starts in the directory "/", the host passes its current directory in PWD (tests/wasi-run.mjs
// makes the whole file system visible): relative paths then mean the same as in a native program.
extern "C" void __cs_wasi_start()
{
    unsafe
    {
        char* pwd = getenv("PWD".CStr());
        if (pwd != null)
            chdir(pwd);
    }
}
