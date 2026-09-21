// The runtime of the generated programs, written as LLVM IR text and put into every module. There is no runtime
// library: strings, reference counting and panics are IR helpers (like in the C++ compiler, CodeGenRuntime.cpp).
//
// A heap block (string or array) is { i64 refcount, i64 length, payload... }. String literals start with a huge
// reference count and are never freed.

namespace CShift.CodeGen;

using System;

// stderr comes from the C library in different ways.
string StderrLoad(bool windows)
{
    if (windows)
        return "  %err = call ptr @__acrt_iob_func(i32 2)\n";
    return "  %err = load ptr, ptr @stderr\n";
}

string RuntimeGlobals(bool windows, bool arcStats)
{
    string text =
        "@.cs.panic = private constant [11 x i8] c\"panic: %s\\0A\\00\"\n" +
        "@.cs.empty = private constant [1 x i8] zeroinitializer\n" +
        "@.cs.oom = private constant [14 x i8] c\"out of memory\\00\"\n" +
        "@.cs.line = private constant [6 x i8] c\"%.*s\\0A\\00\"\n" +
        "@.cs.text = private constant [5 x i8] c\"%.*s\\00\"\n" +
        "@.cs.fmt.i64 = private constant [5 x i8] c\"%lld\\00\"\n" +
        "@.cs.fmt.u64 = private constant [5 x i8] c\"%llu\\00\"\n" +
        "@.cs.fmt.f64 = private constant [6 x i8] c\"%.15g\\00\"\n" +
        "@.cs.fmt.f32 = private constant [5 x i8] c\"%.7g\\00\"\n" +
        "@.cs.true = private global { i64, i64, [5 x i8] } { i64 1152921504606846976, i64 4, [5 x i8] c\"true\\00\" }\n" +
        "@.cs.false = private global { i64, i64, [6 x i8] } { i64 1152921504606846976, i64 5, [6 x i8] c\"false\\00\" }\n";
    if (!windows)
        text += "@stderr = external global ptr\n";
    if (arcStats)
        text += "@__cs_allocs = internal global i64 0\n@__cs_frees = internal global i64 0\n" +
                "@.cs.arc = private constant [40 x i8] c\"[arc] allocs=%lld frees=%lld live=%lld\\0A\\00\"\n";
    return text + "\n";
}

string RuntimeFunctions(bool windows, bool arcStats)
{
    string text =
        "declare ptr @calloc(i64, i64)\n" +
        "declare void @free(ptr)\n" +
        "declare void @exit(i32)\n" +
        "declare i32 @memcmp(ptr, ptr, i64)\n" +
        "declare i64 @strlen(ptr)\n" +
        "declare i32 @printf(ptr, ...)\n" +
        "declare i32 @fprintf(ptr, ptr, ...)\n" +
        "declare i32 @snprintf(ptr, i64, ptr, ...)\n" +
        "declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1)\n" +
        "declare void @llvm.memmove.p0.p0.i64(ptr, ptr, i64, i1)\n";
    if (windows)
        text += "declare ptr @__acrt_iob_func(i32)\n";
    text += "\n";

    // panic: prints "panic: <message>" to stderr and exits with code 101
    text += "define internal void @__cs_panic(ptr %msg) noinline noreturn {\nentry:\n" + StderrLoad(windows) +
            "  call i32 (ptr, ptr, ...) @fprintf(ptr %err, ptr @.cs.panic, ptr %msg)\n" +
            "  call void @exit(i32 101)\n  unreachable\n}\n\n";

    // alloc(payload size, length): a zeroed block with reference count 1
    text += "define internal ptr @__cs_alloc(i64 %size, i64 %len) {\nentry:\n" +
            "  %total = add i64 %size, 16\n" +
            "  %p = call ptr @calloc(i64 1, i64 %total)\n" +
            "  %isnull = icmp eq ptr %p, null\n" +
            "  br i1 %isnull, label %oom, label %ok\n" +
            "oom:\n  call void @__cs_panic(ptr @.cs.oom)\n  unreachable\n" +
            "ok:\n  store i64 1, ptr %p\n" +
            (arcStats ? "  %n = load i64, ptr @__cs_allocs\n  %n1 = add i64 %n, 1\n  store i64 %n1, ptr @__cs_allocs\n" : "") +
            "  %lenp = getelementptr i8, ptr %p, i64 8\n  store i64 %len, ptr %lenp\n  ret ptr %p\n}\n\n";

    text += "define internal i64 @__cs_len(ptr %s) {\nentry:\n" +
            "  %isnull = icmp eq ptr %s, null\n  br i1 %isnull, label %null, label %load\n" +
            "load:\n  %lenp = getelementptr i8, ptr %s, i64 8\n  %len = load i64, ptr %lenp\n  ret i64 %len\n" +
            "null:\n  ret i64 0\n}\n\n";

    text += "define internal ptr @__cs_data(ptr %s) {\nentry:\n" +
            "  %p = getelementptr i8, ptr %s, i64 16\n" +
            "  %isnull = icmp eq ptr %s, null\n" +
            "  %r = select i1 %isnull, ptr @.cs.empty, ptr %p\n  ret ptr %r\n}\n\n";

    text += "define internal void @__cs_retain(ptr %p) {\nentry:\n" +
            "  %isnull = icmp eq ptr %p, null\n  br i1 %isnull, label %done, label %inc\n" +
            "inc:\n  %rc = load i64, ptr %p\n  %rc1 = add i64 %rc, 1\n  store i64 %rc1, ptr %p\n  br label %done\n" +
            "done:\n  ret void\n}\n\n";

    // release of a block without references inside (strings, arrays of plain values)
    text += "define internal void @__cs_release_flat(ptr %p) {\nentry:\n" +
            "  %isnull = icmp eq ptr %p, null\n  br i1 %isnull, label %done, label %dec\n" +
            "dec:\n  %rc = load i64, ptr %p\n  %rc1 = sub i64 %rc, 1\n  store i64 %rc1, ptr %p\n" +
            "  %zero = icmp eq i64 %rc1, 0\n  br i1 %zero, label %free, label %done\n" +
            "free:\n  call void @free(ptr %p)\n" +
            (arcStats ? "  %f = load i64, ptr @__cs_frees\n  %f1 = add i64 %f, 1\n  store i64 %f1, ptr @__cs_frees\n" : "") +
            "  br label %done\n" +
            "done:\n  ret void\n}\n\n";

    text += "define internal ptr @__cs_concat(ptr %a, ptr %b) {\nentry:\n" +
            "  %la = call i64 @__cs_len(ptr %a)\n  %lb = call i64 @__cs_len(ptr %b)\n" +
            "  %len = add i64 %la, %lb\n  %size = add i64 %len, 1\n" +
            "  %r = call ptr @__cs_alloc(i64 %size, i64 %len)\n" +
            "  %dst = getelementptr i8, ptr %r, i64 16\n" +
            "  %da = call ptr @__cs_data(ptr %a)\n" +
            "  call void @llvm.memcpy.p0.p0.i64(ptr %dst, ptr %da, i64 %la, i1 false)\n" +
            "  %dst2 = getelementptr i8, ptr %dst, i64 %la\n" +
            "  %db = call ptr @__cs_data(ptr %b)\n" +
            "  call void @llvm.memcpy.p0.p0.i64(ptr %dst2, ptr %db, i64 %lb, i1 false)\n" +
            "  ret ptr %r\n}\n\n";

    // substring(string, start, count): a new string; panics if the range is not inside the string
    text += "@.cs.substr = private constant [23 x i8] c\"substring out of range\\00\"\n" +
            "define internal ptr @__cs_substring(ptr %s, i32 %start, i32 %count) {\nentry:\n" +
            "  %len = call i64 @__cs_len(ptr %s)\n" +
            "  %a = sext i32 %start to i64\n  %n = sext i32 %count to i64\n" +
            "  %neg1 = icmp slt i64 %a, 0\n  %neg2 = icmp slt i64 %n, 0\n  %neg = or i1 %neg1, %neg2\n" +
            "  %end = add i64 %a, %n\n  %past = icmp sgt i64 %end, %len\n  %bad = or i1 %neg, %past\n" +
            "  br i1 %bad, label %range, label %ok\n" +
            "range:\n  call void @__cs_panic(ptr @.cs.substr)\n  unreachable\n" +
            "ok:\n  %size = add i64 %n, 1\n  %r = call ptr @__cs_alloc(i64 %size, i64 %n)\n" +
            "  %d = call ptr @__cs_data(ptr %s)\n  %src = getelementptr i8, ptr %d, i64 %a\n" +
            "  %dst = getelementptr i8, ptr %r, i64 16\n" +
            "  call void @llvm.memcpy.p0.p0.i64(ptr %dst, ptr %src, i64 %n, i1 false)\n  ret ptr %r\n}\n\n";

    text += "define internal i1 @__cs_streq(ptr %a, ptr %b) {\nentry:\n" +
            "  %la = call i64 @__cs_len(ptr %a)\n  %lb = call i64 @__cs_len(ptr %b)\n" +
            "  %same = icmp eq i64 %la, %lb\n  br i1 %same, label %cmp, label %ne\n" +
            "cmp:\n  %da = call ptr @__cs_data(ptr %a)\n  %db = call ptr @__cs_data(ptr %b)\n" +
            "  %c = call i32 @memcmp(ptr %da, ptr %db, i64 %la)\n  %eq = icmp eq i32 %c, 0\n  ret i1 %eq\n" +
            "ne:\n  ret i1 false\n}\n\n";

    // print(string, newline)
    text += "define internal void @__cs_print(ptr %s, i1 %nl) {\nentry:\n" +
            "  %len = call i64 @__cs_len(ptr %s)\n  %len32 = trunc i64 %len to i32\n" +
            "  %fmt = select i1 %nl, ptr @.cs.line, ptr @.cs.text\n" +
            "  %d = call ptr @__cs_data(ptr %s)\n" +
            "  call i32 (ptr, ...) @printf(ptr %fmt, i32 %len32, ptr %d)\n  ret void\n}\n\n";
    text += "define internal void @__cs_eprint(ptr %s, i1 %nl) {\nentry:\n" + StderrLoad(windows) +
            "  %len = call i64 @__cs_len(ptr %s)\n  %len32 = trunc i64 %len to i32\n" +
            "  %fmt = select i1 %nl, ptr @.cs.line, ptr @.cs.text\n" +
            "  %d = call ptr @__cs_data(ptr %s)\n" +
            "  call i32 (ptr, ptr, ...) @fprintf(ptr %err, ptr %fmt, i32 %len32, ptr %d)\n  ret void\n}\n\n";

    // make_args(argc, argv): the command line arguments without the program name as a string array
    text += "define internal ptr @__cs_make_args(i32 %argc, ptr %argv) {\nentry:\n" +
            "  %gt = icmp sgt i32 %argc, 1\n  %m = sub i32 %argc, 1\n  %c32 = select i1 %gt, i32 %m, i32 0\n" +
            "  %count = sext i32 %c32 to i64\n  %bytes = mul i64 %count, 8\n" +
            "  %arr = call ptr @__cs_alloc(i64 %bytes, i64 %count)\n" +
            "  %data = getelementptr i8, ptr %arr, i64 16\n  br label %loop\n" +
            "loop:\n  %i = phi i64 [ 0, %entry ], [ %next, %body ]\n" +
            "  %more = icmp ult i64 %i, %count\n  br i1 %more, label %body, label %done\n" +
            "body:\n  %j = add i64 %i, 1\n  %ap = getelementptr ptr, ptr %argv, i64 %j\n  %s = load ptr, ptr %ap\n" +
            "  %len = call i64 @strlen(ptr %s)\n  %size = add i64 %len, 1\n" +
            "  %str = call ptr @__cs_alloc(i64 %size, i64 %len)\n  %dst = getelementptr i8, ptr %str, i64 16\n" +
            "  call void @llvm.memcpy.p0.p0.i64(ptr %dst, ptr %s, i64 %len, i1 false)\n" +
            "  %ep = getelementptr ptr, ptr %data, i64 %i\n  store ptr %str, ptr %ep\n" +
            "  %next = add i64 %i, 1\n  br label %loop\n" +
            "done:\n  ret ptr %arr\n}\n\n";

    // number to string
    text += FormatHelper("i64", "i64", "@.cs.fmt.i64");
    text += FormatHelper("u64", "i64", "@.cs.fmt.u64");
    text += FormatHelper("f64", "double", "@.cs.fmt.f64");
    text += FormatHelper("f32", "double", "@.cs.fmt.f32");
    return text;
}

// __cs_fmt_<name>(argType): formats one number with snprintf into a new string.
string FormatHelper(string name, string argType, string format)
{
    return "define internal ptr @__cs_fmt_" + name + "(" + argType + " %v) {\nentry:\n" +
           "  %n = call i32 (ptr, i64, ptr, ...) @snprintf(ptr null, i64 0, ptr " + format + ", " + argType + " %v)\n" +
           "  %n64 = sext i32 %n to i64\n  %size = add i64 %n64, 1\n" +
           "  %r = call ptr @__cs_alloc(i64 %size, i64 %n64)\n" +
           "  %dst = getelementptr i8, ptr %r, i64 16\n" +
           "  call i32 (ptr, i64, ptr, ...) @snprintf(ptr %dst, i64 %size, ptr " + format + ", " + argType + " %v)\n" +
           "  ret ptr %r\n}\n\n";
}
