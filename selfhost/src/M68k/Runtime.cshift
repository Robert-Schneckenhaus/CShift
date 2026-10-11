// The helpers of the 68000 backend, written in assembly: what the 68000 cannot do in one instruction (32-bit
// multiplication and division, 64-bit multiplication and division, overflow checks of multiplications). They use the
// C calling convention (arguments on the stack, results in d0 or d0:d1) and keep d2-d7/a2-a6.

namespace CShift.M68k;

using System;

// runtime.s, embedded when cshc is compiled
const string RuntimeAsmText = embed("runtime.s");

string RuntimeAsm()
{
    return RuntimeAsmText;
}
