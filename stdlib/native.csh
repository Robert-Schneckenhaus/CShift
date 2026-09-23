// Imports of the C library used by the standard library.
// "using System.Native;" makes them available to your own programs as well.

namespace System.Native;

// stdio (files)
extern "C" void* fopen(char* path, char* mode);
extern "C" int fclose(void* file);
extern "C" uint64 fread(void* buffer, uint64 size, uint64 count, void* file);
extern "C" uint64 fwrite(void* buffer, uint64 size, uint64 count, void* file);
extern "C" int remove(char* path);

// stdlib
extern "C" double strtod(char* text, char** end);

// math
extern "C" double sin(double x);
extern "C" double cos(double x);
extern "C" double tan(double x);
extern "C" double asin(double x);
extern "C" double acos(double x);
extern "C" double atan(double x);
extern "C" double atan2(double y, double x);
extern "C" double sinh(double x);
extern "C" double cosh(double x);
extern "C" double tanh(double x);
extern "C" double exp(double x);
extern "C" double log(double x);
extern "C" double log2(double x);
extern "C" double log10(double x);
extern "C" double pow(double x, double y);
extern "C" double cbrt(double x);
extern "C" double hypot(double x, double y);
extern "C" double floor(double x);
extern "C" double ceil(double x);
extern "C" double trunc(double x);
extern "C" double nearbyint(double x);
extern "C" double fabs(double x);

// Threads (System.Threading). pthread_mutex_t/pthread_cond_t are treated as opaque blobs of memory that the
// caller owns (see System.Threading._ThreadCore, which reserves inline storage for them); pthread_create,
// pthread_detach and pthread_self are only ever used by the code generator itself when a 'thread' function is
// spawned (CodeGenThread.cpp), not from CShift code, so they are not declared here.
extern "C" int pthread_mutex_init(void* mutex, void* attr);
extern "C" int pthread_mutex_lock(void* mutex);
extern "C" int pthread_mutex_unlock(void* mutex);
extern "C" int pthread_cond_init(void* cond, void* attr);
extern "C" int pthread_cond_wait(void* cond, void* mutex);
extern "C" int pthread_cond_broadcast(void* cond);
