// The runtime of the generated programs, written as LLVM IR text and put into every module. There is no runtime
// library: strings, reference counting and panics are IR helpers (like in the C++ compiler, CodeGenRuntime.cpp).
//
// A heap block (string or array) is { size refcount, size length, payload... } (size: i64, or i32 on a 32-bit target,
// see Emit/Target.csh). String literals start with a huge reference count and are never freed.

namespace CShift.CodeGen;

using System;
using CShift.Emit;

// stderr comes from the C library in different ways.
string StderrLoad(bool windows)
{
    if (windows)
        return "  %err = call ptr @__acrt_iob_func(i32 2)\n";
    return "  %err = load ptr, ptr @stderr\n";
}

// ... and stdout.
string StdoutLoad(bool windows)
{
    if (windows)
        return "  %out = call ptr @__acrt_iob_func(i32 1)\n";
    return "  %out = load ptr, ptr @stdout\n";
}

string RuntimeGlobals(bool windows, bool arcStats, IrWriter ir)
{
    string text =
        "@.cs.panic = private constant [8 x i8] c\"panic: \\00\"\n" +
        "@.cs.panic.at = private constant [6 x i8] c\"  at \\00\"\n" +
        "@.cs.panic.from = private constant [15 x i8] c\"  called from \\00\"\n" +
        "@.cs.panic.index = private constant [9 x i8] c\" (index \\00\"\n" +
        "@.cs.panic.length = private constant [10 x i8] c\", length \\00\"\n" +
        "@.cs.panic.end = private constant [3 x i8] c\")\\0A\\00\"\n" +
        "@.cs.error = private constant [8 x i8] c\"error: \\00\"\n" +
        "@.cs.nl = private constant [2 x i8] c\"\\0A\\00\"\n" +
        "@.cs.empty = private constant [1 x i8] zeroinitializer\n" +
        "@.cs.oom = private constant [14 x i8] c\"out of memory\\00\"\n" +
        "@.cs.fmt.g = private constant [5 x i8] c\"%.*g\\00\"\n" +
        Sized("@.cs.true = private global { $S, $S, [5 x i8] } { $S $I, $S 4, [5 x i8] c\"true\\00\" }\n" +
              "@.cs.false = private global { $S, $S, [6 x i8] } { $S $I, $S 5, [6 x i8] c\"false\\00\" }\n", ir);
    if (!windows)
        text += "@stdout = external global ptr\n@stderr = external global ptr\n";
    if (arcStats)
        text += Sized("@__cs_allocs = internal global $S 0\n@__cs_frees = internal global $S 0\n@__cs_threads = internal global $S 0\n", ir) +
                "@.cs.arc = private constant [40 x i8] c\"[arc] allocs=%lld frees=%lld live=%lld\\0A\\00\"\n";
    return text + "\n";
}

// A declaration of a C function that the runtime calls, unless the program declares the function itself (possibly
// with another signature: the runtime then calls it through its own type).
string CDeclare(IrWriter ir, string name, string declaration)
{
    if (ir.Declared.Contains("@" + name))
        return "";
    return declaration + "\n";
}

string RuntimeFunctions(bool windows, bool arcStats, IrWriter ir)
{
    string text =
        CDeclare(ir, "calloc", "declare ptr @calloc($S, $S)") +
        CDeclare(ir, "free", "declare void @free(ptr)") +
        CDeclare(ir, "exit", "declare void @exit(i32)") +
        CDeclare(ir, "memcmp", "declare i32 @memcmp(ptr, ptr, $S)") +
        CDeclare(ir, "strlen", "declare $S @strlen(ptr)") +
        CDeclare(ir, "fwrite", "declare $S @fwrite(ptr, $S, $S, ptr)") +
        CDeclare(ir, "snprintf", "declare i32 @snprintf(ptr, $S, ptr, ...)") +
        CDeclare(ir, "strtod", "declare double @strtod(ptr, ptr)") +
        "declare void @llvm.memcpy.p0.p0.$S(ptr, ptr, $S, i1)\n" +
        "declare void @llvm.memmove.p0.p0.$S(ptr, ptr, $S, i1)\n";
    if (windows)
        text += CDeclare(ir, "__acrt_iob_func", "declare ptr @__acrt_iob_func(i32)");
    text += "\n";

    // The runtime writes with fwrite only, so a program that does not call printf itself does not need it (on AmigaOS
    // the formatting code of printf is a part of the program).
    // write(file, data, length, newline): a line of up to 255 bytes is written in one piece
    text += "define internal void @__cs_write(ptr %file, ptr %data, $S %len, i1 %nl) {\nentry:\n  %buf = alloca [256 x i8]\n" +
            "  br i1 %nl, label %line, label %plain\n" +
            "plain:\n  call $S @fwrite(ptr %data, $S 1, $S %len, ptr %file)\n  ret void\n" +
            "line:\n  %small = icmp ult $S %len, 256\n  br i1 %small, label %join, label %two\n" +
            "join:\n  call void @llvm.memcpy.p0.p0.$S(ptr %buf, ptr %data, $S %len, i1 false)\n" +
            "  %end = getelementptr i8, ptr %buf, $S %len\n  store i8 10, ptr %end\n  %n = add $S %len, 1\n" +
            "  call $S @fwrite(ptr %buf, $S 1, $S %n, ptr %file)\n  ret void\n" +
            "two:\n  call $S @fwrite(ptr %data, $S 1, $S %len, ptr %file)\n" +
            "  call $S @fwrite(ptr @.cs.nl, $S 1, $S 1, ptr %file)\n  ret void\n}\n\n";
    // puts(file, C string) without a newline
    text += "define internal void @__cs_puts(ptr %file, ptr %s) {\nentry:\n  %len = call $S @strlen(ptr %s)\n" +
            "  call void @__cs_write(ptr %file, ptr %s, $S %len, i1 false)\n  ret void\n}\n\n";
    // report(prefix, C string): "<prefix><text>\n" to stderr
    text += "define internal void @__cs_report(ptr %prefix, ptr %s) {\nentry:\n" + StderrLoad(windows) +
            "  call void @__cs_puts(ptr %err, ptr %prefix)\n" +
            "  %len = call $S @strlen(ptr %s)\n  call void @__cs_write(ptr %err, ptr %s, $S %len, i1 true)\n  ret void\n}\n\n";

    // digits(value, signed, end): writes the decimal digits of the value (with '-') backwards before 'end' (24 bytes
    // are enough) and returns where they start. Below 2^32 it divides with 32 bits (much faster on a 32-bit CPU).
    text += "define internal ptr @__cs_digits(i64 %v, i1 %signed, ptr %end) {\nentry:\n" +
            "  %neg0 = icmp slt i64 %v, 0\n  %neg = and i1 %neg0, %signed\n  %minus = sub i64 0, %v\n" +
            "  %mag = select i1 %neg, i64 %minus, i64 %v\n  br label %big\n" +
            "big:\n  %bv = phi i64 [ %mag, %entry ], [ %bq, %bigbody ]\n  %bp = phi ptr [ %end, %entry ], [ %bp1, %bigbody ]\n" +
            "  %wide = icmp ugt i64 %bv, 4294967295\n  br i1 %wide, label %bigbody, label %small\n" +
            "bigbody:\n  %bq = udiv i64 %bv, 10\n  %br = urem i64 %bv, 10\n  %bc = trunc i64 %br to i8\n  %bd = add i8 %bc, 48\n" +
            "  %bp1 = getelementptr i8, ptr %bp, i32 -1\n  store i8 %bd, ptr %bp1\n  br label %big\n" +
            "small:\n  %w0 = trunc i64 %bv to i32\n  br label %loop\n" +
            "loop:\n  %w = phi i32 [ %w0, %small ], [ %q, %loop ]\n  %p = phi ptr [ %bp, %small ], [ %p1, %loop ]\n" +
            "  %q = udiv i32 %w, 10\n  %r = urem i32 %w, 10\n  %c = trunc i32 %r to i8\n  %d = add i8 %c, 48\n" +
            "  %p1 = getelementptr i8, ptr %p, i32 -1\n  store i8 %d, ptr %p1\n" +
            "  %more = icmp ne i32 %q, 0\n  br i1 %more, label %loop, label %sign\n" +
            "sign:\n  br i1 %neg, label %addminus, label %done\n" +
            "addminus:\n  %m = getelementptr i8, ptr %p1, i32 -1\n  store i8 45, ptr %m\n  ret ptr %m\n" +
            "done:\n  ret ptr %p1\n}\n\n";

    // panic: prints "panic: <message>" to stderr and exits with code 101
    text += "define internal void @__cs_panic(ptr %msg) noinline noreturn {\nentry:\n" +
            "  call void @__cs_report(ptr @.cs.panic, ptr %msg)\n" +
            "  call void @exit(i32 101)\n  unreachable\n}\n\n";

    // A failed check in the program: "panic: <message>", the line "  at <file:line:column in Function>" and, for a check
    // inside a library function that reports its caller, "  called from <call site>" (null: none).
    text += "define internal void @__cs_panic_where(ptr %where, ptr %caller) {\nentry:\n" +
            "  call void @__cs_report(ptr @.cs.panic.at, ptr %where)\n" +
            "  %known = icmp ne ptr %caller, null\n" +
            "  br i1 %known, label %called, label %done\n" +
            "called:\n  call void @__cs_report(ptr @.cs.panic.from, ptr %caller)\n  br label %done\n" +
            "done:\n  ret void\n}\n\n";
    text += "define internal void @__cs_panic_at(ptr %msg, ptr %where, ptr %caller) noinline noreturn {\nentry:\n" +
            "  call void @__cs_report(ptr @.cs.panic, ptr %msg)\n" +
            "  call void @__cs_panic_where(ptr %where, ptr %caller)\n" +
            "  call void @exit(i32 101)\n  unreachable\n}\n\n";
    // ... and for an index: "panic: <message> (index i, length n)"
    text += "define internal void @__cs_panic_index(ptr %msg, i64 %index, i64 %length, ptr %where, ptr %caller) noinline noreturn {\nentry:\n" +
            "  %buf = alloca [24 x i8]\n  %end = getelementptr i8, ptr %buf, i32 23\n  store i8 0, ptr %end\n" + StderrLoad(windows) +
            "  call void @__cs_puts(ptr %err, ptr @.cs.panic)\n  call void @__cs_puts(ptr %err, ptr %msg)\n" +
            "  call void @__cs_puts(ptr %err, ptr @.cs.panic.index)\n" +
            "  %i = call ptr @__cs_digits(i64 %index, i1 true, ptr %end)\n  call void @__cs_puts(ptr %err, ptr %i)\n" +
            "  call void @__cs_puts(ptr %err, ptr @.cs.panic.length)\n" +
            "  %n = call ptr @__cs_digits(i64 %length, i1 true, ptr %end)\n  call void @__cs_puts(ptr %err, ptr %n)\n" +
            "  call void @__cs_puts(ptr %err, ptr @.cs.panic.end)\n" +
            "  call void @__cs_panic_where(ptr %where, ptr %caller)\n" +
            "  call void @exit(i32 101)\n  unreachable\n}\n\n";

    // alloc(payload size, length): a zeroed block with reference count 1
    text += "define internal ptr @__cs_alloc($S %size, $S %len) {\nentry:\n" +
            "  %total = add $S %size, $H\n" +
            "  %p = call ptr @calloc($S 1, $S %total)\n" +
            "  %isnull = icmp eq ptr %p, null\n" +
            "  br i1 %isnull, label %oom, label %ok\n" +
            "oom:\n  call void @__cs_panic(ptr @.cs.oom)\n  unreachable\n" +
            "ok:\n  store $S 1, ptr %p\n" +
            (arcStats ? "  %n = atomicrmw add ptr @__cs_allocs, $S 1 monotonic\n" : "") +
            "  %lenp = getelementptr i8, ptr %p, $S $P\n  store $S %len, ptr %lenp\n  ret ptr %p\n}\n\n";

    text += "define internal $S @__cs_len(ptr %s) {\nentry:\n" +
            "  %isnull = icmp eq ptr %s, null\n  br i1 %isnull, label %null, label %load\n" +
            "load:\n  %lenp = getelementptr i8, ptr %s, $S $P\n  %len = load $S, ptr %lenp\n  ret $S %len\n" +
            "null:\n  ret $S 0\n}\n\n";

    text += "define internal ptr @__cs_data(ptr %s) {\nentry:\n" +
            "  %p = getelementptr i8, ptr %s, $S $H\n" +
            "  %isnull = icmp eq ptr %s, null\n" +
            "  %r = select i1 %isnull, ptr @.cs.empty, ptr %p\n  ret ptr %r\n}\n\n";

    text += "define internal void @__cs_retain(ptr %p) {\nentry:\n" +
            "  %isnull = icmp eq ptr %p, null\n  br i1 %isnull, label %done, label %inc\n" +
            "inc:\n  %rc = load $S, ptr %p\n  %rc1 = add $S %rc, 1\n  store $S %rc1, ptr %p\n  br label %done\n" +
            "done:\n  ret void\n}\n\n";

    // release of a block without references inside (strings, arrays of plain values)
    text += "define internal void @__cs_release_flat(ptr %p) {\nentry:\n" +
            "  %isnull = icmp eq ptr %p, null\n  br i1 %isnull, label %done, label %dec\n" +
            "dec:\n  %rc = load $S, ptr %p\n  %rc1 = sub $S %rc, 1\n  store $S %rc1, ptr %p\n" +
            "  %zero = icmp eq $S %rc1, 0\n  br i1 %zero, label %free, label %done\n" +
            "free:\n  call void @free(ptr %p)\n" +
            (arcStats ? "  %f = atomicrmw add ptr @__cs_frees, $S 1 monotonic\n" : "") +
            "  br label %done\n" +
            "done:\n  ret void\n}\n\n";

    text += "define internal ptr @__cs_concat(ptr %a, ptr %b) {\nentry:\n" +
            "  %la = call $S @__cs_len(ptr %a)\n  %lb = call $S @__cs_len(ptr %b)\n" +
            "  %len = add $S %la, %lb\n  %size = add $S %len, 1\n" +
            "  %r = call ptr @__cs_alloc($S %size, $S %len)\n" +
            "  %dst = getelementptr i8, ptr %r, $S $H\n" +
            "  %da = call ptr @__cs_data(ptr %a)\n" +
            "  call void @llvm.memcpy.p0.p0.$S(ptr %dst, ptr %da, $S %la, i1 false)\n" +
            "  %dst2 = getelementptr i8, ptr %dst, $S %la\n" +
            "  %db = call ptr @__cs_data(ptr %b)\n" +
            "  call void @llvm.memcpy.p0.p0.$S(ptr %dst2, ptr %db, $S %lb, i1 false)\n" +
            "  ret ptr %r\n}\n\n";

    // substring(string, start, count): a new string; panics if the range is not inside the string
    text += "@.cs.substr = private constant [23 x i8] c\"substring out of range\\00\"\n" +
            "define internal ptr @__cs_substring(ptr %s, i32 %start, i32 %count) {\nentry:\n" +
            "  %len = call $S @__cs_len(ptr %s)\n" +
            "  " + SizeFromI32(ir, "%a", "%start") + "  " + SizeFromI32(ir, "%n", "%count") +
            "  %neg1 = icmp slt $S %a, 0\n  %neg2 = icmp slt $S %n, 0\n  %neg = or i1 %neg1, %neg2\n" +
            "  %end = add $S %a, %n\n  %past = icmp sgt $S %end, %len\n  %bad = or i1 %neg, %past\n" +
            "  br i1 %bad, label %range, label %ok\n" +
            "range:\n  call void @__cs_panic(ptr @.cs.substr)\n  unreachable\n" +
            "ok:\n  %size = add $S %n, 1\n  %r = call ptr @__cs_alloc($S %size, $S %n)\n" +
            "  %d = call ptr @__cs_data(ptr %s)\n  %src = getelementptr i8, ptr %d, $S %a\n" +
            "  %dst = getelementptr i8, ptr %r, $S $H\n" +
            "  call void @llvm.memcpy.p0.p0.$S(ptr %dst, ptr %src, $S %n, i1 false)\n  ret ptr %r\n}\n\n";

    text += "define internal i1 @__cs_streq(ptr %a, ptr %b) {\nentry:\n" +
            "  %la = call $S @__cs_len(ptr %a)\n  %lb = call $S @__cs_len(ptr %b)\n" +
            "  %same = icmp eq $S %la, %lb\n  br i1 %same, label %cmp, label %ne\n" +
            "cmp:\n  %da = call ptr @__cs_data(ptr %a)\n  %db = call ptr @__cs_data(ptr %b)\n" +
            "  %c = call i32 @memcmp(ptr %da, ptr %db, $S %la)\n  %eq = icmp eq i32 %c, 0\n  ret i1 %eq\n" +
            "ne:\n  ret i1 false\n}\n\n";

    // print(string, newline)
    text += "define internal void @__cs_print(ptr %s, i1 %nl) {\nentry:\n" + StdoutLoad(windows) +
            "  %len = call $S @__cs_len(ptr %s)\n  %d = call ptr @__cs_data(ptr %s)\n" +
            "  call void @__cs_write(ptr %out, ptr %d, $S %len, i1 %nl)\n  ret void\n}\n\n";
    text += "define internal void @__cs_eprint(ptr %s, i1 %nl) {\nentry:\n" + StderrLoad(windows) +
            "  %len = call $S @__cs_len(ptr %s)\n  %d = call ptr @__cs_data(ptr %s)\n" +
            "  call void @__cs_write(ptr %err, ptr %d, $S %len, i1 %nl)\n  ret void\n}\n\n";

    // slice_cstr(data, length, keep): the bytes of a StringSlice followed by a 0 byte, for C. That is the slice itself
    // if a 0 byte follows it (a slice up to the end of its string: the string's terminator); otherwise a new string
    // with a copy, stored in *keep for the caller to release (*keep is null if nothing was copied)
    text += "define internal ptr @__cs_slice_cstr(ptr %d, $S %len, ptr %keep) {\nentry:\n" +
            "  store ptr null, ptr %keep\n" +
            // an empty slice may have no data pointer at all (null), or a made-up one (a null string as a slice)
            "  %isempty = icmp eq $S %len, 0\n  br i1 %isempty, label %empty, label %check\n" +
            "empty:\n  ret ptr @.cs.empty\n" +
            "check:\n  %endp = getelementptr i8, ptr %d, $S %len\n  %b = load i8, ptr %endp\n" +
            "  %z = icmp eq i8 %b, 0\n  br i1 %z, label %direct, label %copy\n" +
            "direct:\n  ret ptr %d\n" +
            "copy:\n  %size = add $S %len, 1\n  %r = call ptr @__cs_alloc($S %size, $S %len)\n" +
            "  %dst = getelementptr i8, ptr %r, $S $H\n" +
            "  call void @llvm.memcpy.p0.p0.$S(ptr %dst, ptr %d, $S %len, i1 false)\n" +
            "  store ptr %r, ptr %keep\n  ret ptr %dst\n}\n\n";

    // from_cstr(char*): copies a NUL-terminated C string into a new string (null stays null)
    text += "define internal ptr @__cs_from_cstr(ptr %p) {\nentry:\n" +
            "  %isnull = icmp eq ptr %p, null\n  br i1 %isnull, label %null, label %copy\n" +
            "null:\n  ret ptr null\n" +
            "copy:\n  %len = call $S @strlen(ptr %p)\n  %size = add $S %len, 1\n" +
            "  %r = call ptr @__cs_alloc($S %size, $S %len)\n  %dst = getelementptr i8, ptr %r, $S $H\n" +
            "  call void @llvm.memcpy.p0.p0.$S(ptr %dst, ptr %p, $S %len, i1 false)\n  ret ptr %r\n}\n\n";

    // make_args(argc, argv): the command line arguments without the program name as a string array
    text += "define internal ptr @__cs_make_args(i32 %argc, ptr %argv) {\nentry:\n" +
            "  %gt = icmp sgt i32 %argc, 1\n  %m = sub i32 %argc, 1\n  %c32 = select i1 %gt, i32 %m, i32 0\n" +
            "  " + SizeFromI32(ir, "%count", "%c32").Trim() + "\n  %bytes = mul $S %count, $P\n" +
            "  %arr = call ptr @__cs_alloc($S %bytes, $S %count)\n" +
            "  %data = getelementptr i8, ptr %arr, $S $H\n  br label %loop\n" +
            "loop:\n  %i = phi $S [ 0, %entry ], [ %next, %body ]\n" +
            "  %more = icmp ult $S %i, %count\n  br i1 %more, label %body, label %done\n" +
            "body:\n  %j = add $S %i, 1\n  %ap = getelementptr ptr, ptr %argv, $S %j\n  %s = load ptr, ptr %ap\n" +
            "  %len = call $S @strlen(ptr %s)\n  %size = add $S %len, 1\n" +
            "  %str = call ptr @__cs_alloc($S %size, $S %len)\n  %dst = getelementptr i8, ptr %str, $S $H\n" +
            "  call void @llvm.memcpy.p0.p0.$S(ptr %dst, ptr %s, $S %len, i1 false)\n" +
            "  %ep = getelementptr ptr, ptr %data, $S %i\n  store ptr %str, ptr %ep\n" +
            "  %next = add $S %i, 1\n  br label %loop\n" +
            "done:\n  ret ptr %arr\n}\n\n";

    // number to string
    text += FormatHelper("i64", true);
    text += FormatHelper("u64", false);
    text += RoundTripHelper(ir, "f64", 15, 17, false);
    text += RoundTripHelper(ir, "f32", 6, 9, true);

    // --arc-stats: a joined thread may still be releasing its last references (Join returns when the thread function
    // has finished, the worker then drops its reference to the control block). Before the balance is printed, wait
    // until every started thread has done so (@__cs_threads counts them), at most ~0.5 s for threads that still run.
    if (arcStats)
        text += CDeclare(ir, "fprintf", "declare i32 @fprintf(ptr, ptr, ...)") + CDeclare(ir, "usleep", "declare i32 @usleep(i32)") +
            "define internal void @__cs_arc_wait_threads() {\nentry:\n  br label %loop\n" +
            "loop:\n  %i = phi i32 [ 0, %entry ], [ %next, %wait ]\n" +
            "  %running = load atomic $S, ptr @__cs_threads seq_cst, align $P\n" +
            "  %none = icmp eq $S %running, 0\n  br i1 %none, label %done, label %check\n" +
            "check:\n  %more = icmp slt i32 %i, 500\n  br i1 %more, label %wait, label %done\n" +
            "wait:\n  %slept = call i32 @usleep(i32 1000)\n  %next = add i32 %i, 1\n  br label %loop\n" +
            "done:\n  ret void\n}\n\n";
    return Sized(text, ir);
}

// The runtime's text for the target: $S is the type of sizes (i64 or i32), $P the size of a pointer, $H the size of a
// block header, $I the reference count of an immortal block.
string Sized(string text, IrWriter ir)
{
    var t = ir.Target;
    return text.Replace("$S", t.SizeIr).Replace("$P", t.PtrBytes.ToString()).Replace("$H", t.HeaderBytes().ToString())
               .Replace("$I", t.ImmortalCount());
}

// "dst = sext i32 src to <size>" (without the indentation), or a copy if sizes are 32 bits.
string SizeFromI32(IrWriter ir, string dst, string src)
{
    if (ir.Target.SizeIr == "i32")
        return dst + " = bitcast i32 " + src + " to i32\n";
    return dst + " = sext i32 " + src + " to " + ir.Target.SizeIr + "\n";
}

// "dst = trunc <size> src to i32", or a copy if sizes are 32 bits.
string SizeToI32Line(IrWriter ir, string dst, string src)
{
    if (ir.Target.SizeIr == "i32")
        return dst + " = bitcast i32 " + src + " to i32\n";
    return dst + " = trunc " + ir.Target.SizeIr + " " + src + " to i32\n";
}

// __cs_fmt_<name>(double): the shortest text that reads back as the same number ("%.<p>g" with the smallest precision p
// from 'first' to 'last' for which strtod gives the value again; like C#'s "R"): 0.1 stays "0.1", 1.0 / 3.0 becomes
// "0.3333333333333333". For float, the value is compared after rounding to float.
string RoundTripHelper(IrWriter ir, string name, int first, int last, bool single)
{
    string text = "define internal ptr @__cs_fmt_" + name + "(double %v) {\nentry:\n  %buf = alloca [48 x i8]\n  br label %p" +
                  first.ToString() + "\n";
    for (var p = first; p <= last; p += 1)
    {
        string ps = p.ToString();
        text += "p" + ps + ":\n" +
                "  call i32 (ptr, $S, ptr, ...) @snprintf(ptr %buf, $S 48, ptr @.cs.fmt.g, i32 " + ps + ", double %v)\n";
        if (p == last)
        {
            text += "  br label %done\n";
            continue;
        }
        text += "  %back" + ps + " = call double @strtod(ptr %buf, ptr null)\n";
        if (single)
            text += "  %bf" + ps + " = fptrunc double %back" + ps + " to float\n  %vf" + ps + " = fptrunc double %v to float\n" +
                    "  %same" + ps + " = fcmp oeq float %bf" + ps + ", %vf" + ps + "\n";
        else
            text += "  %same" + ps + " = fcmp oeq double %back" + ps + ", %v\n";
        text += "  br i1 %same" + ps + ", label %done, label %p" + (p + 1).ToString() + "\n";
    }
    text += "done:\n  %n = call $S @strlen(ptr %buf)\n  %size = add $S %n, 1\n" +
            "  %r = call ptr @__cs_alloc($S %size, $S %n)\n  %dst = getelementptr i8, ptr %r, $S $H\n" +
            "  call void @llvm.memcpy.p0.p0.$S(ptr %dst, ptr %buf, $S %n, i1 false)\n  ret ptr %r\n}\n\n";
    return text;
}

// __cs_fmt_<name>(i64): the decimal digits of an integer as a new string.
string FormatHelper(string name, bool signed)
{
    return "define internal ptr @__cs_fmt_" + name + "(i64 %v) {\nentry:\n  %buf = alloca [24 x i8]\n" +
           "  %end = getelementptr i8, ptr %buf, i32 24\n" +
           "  %start = call ptr @__cs_digits(i64 %v, i1 " + (signed ? "true" : "false") + ", ptr %end)\n" +
           "  %a = ptrtoint ptr %start to $S\n  %b = ptrtoint ptr %end to $S\n  %n = sub $S %b, %a\n  %size = add $S %n, 1\n" +
           "  %r = call ptr @__cs_alloc($S %size, $S %n)\n" +
           "  %dst = getelementptr i8, ptr %r, $S $H\n" +
           "  call void @llvm.memcpy.p0.p0.$S(ptr %dst, ptr %start, $S %n, i1 false)\n" +
           "  ret ptr %r\n}\n\n";
}
