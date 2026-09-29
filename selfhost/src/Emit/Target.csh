// What the generated code depends on of the target: the size of pointers (and so of sizes, lengths and indexes) and
// the alignments that LLVM gives the scalar types in a struct (from the target's data layout, which clang adds to the
// module: the IR itself has none).
//
// 64-bit targets are the default (an empty triple is the host). A triple whose architecture has 32-bit pointers
// (m68k, i386..i686, arm, ...) makes sizes 32 bits: the header of a string or array block is { i32 refcount,
// i32 length }, a slice is { ptr, ptr, i32 }, nint/nuint have 32 bits.

namespace CShift.Emit;

using System;

struct TargetInfo
{
    int PtrBytes;     // 8 or 4
    int PtrAlign;     // alignment of a pointer in a struct
    int I32Align;     // ... of int32 (and float32 on m68k, see FloatAlign)
    int I64Align;     // ... of int64
    int F64Align;     // ... of float64
    string SizeIr;    // the LLVM type of sizes, lengths and indexes: "i64" or "i32"

    static TargetInfo Of(string triple)
    {
        string arch = triple.ToLower();
        int dash = arch.IndexOf('-');
        if (dash >= 0)
            arch = arch.Substring(0, dash);
        if (!Has32BitPointers(arch))
            return TargetInfo { PtrBytes = 8, PtrAlign = 8, I32Align = 4, I64Align = 8, F64Align = 8, SizeIr = "i64" };
        if (arch == "m68k")
            return TargetInfo { PtrBytes = 4, PtrAlign = 2, I32Align = 2, I64Align = 4, F64Align = 8, SizeIr = "i32" };
        bool x86 = arch == "x86" || (arch.Length == 4 && arch.StartsWith("i") && arch.EndsWith("86"));
        bool windows = triple.ToLower().Contains("windows") || triple.ToLower().Contains("mingw");
        if (x86 && !windows)
            return TargetInfo { PtrBytes = 4, PtrAlign = 4, I32Align = 4, I64Align = 4, F64Align = 4, SizeIr = "i32" };
        return TargetInfo { PtrBytes = 4, PtrAlign = 4, I32Align = 4, I64Align = 8, F64Align = 8, SizeIr = "i32" };
    }

    static bool Has32BitPointers(string arch)
    {
        if (arch == "m68k" || arch == "x86" || arch == "arm" || arch == "armeb" || arch == "thumb" || arch == "thumbeb" ||
            arch == "mips" || arch == "mipsel" || arch == "powerpc" || arch == "ppc" || arch == "riscv32" ||
            arch == "wasm32" || arch == "sparc" || arch == "sparcel" || arch == "hexagon" || arch == "xtensa")
            return true;
        if (arch.Length == 4 && arch.StartsWith("i") && arch.EndsWith("86"))
            return true; // i386 .. i686
        return arch.StartsWith("armv") || arch.StartsWith("thumbv");
    }

    // The bytes in front of the elements of a string or array block (refcount and length).
    int HeaderBytes() { return 2 * PtrBytes; }

    // The reference count of a block that is never freed (string literals, constant arrays): so large that it never
    // reaches 0.
    string ImmortalCount() { return PtrBytes == 8 ? "1152921504606846976" : "268435456"; }

    // The alignment of a scalar of 'bytes' bytes in a struct.
    int ScalarAlign(int bytes, bool isFloat)
    {
        if (bytes <= 1)
            return 1;
        if (bytes == 2)
            return 2;
        if (bytes == 4)
            return isFloat ? 4 : I32Align;
        return isFloat ? F64Align : I64Align;
    }
}
