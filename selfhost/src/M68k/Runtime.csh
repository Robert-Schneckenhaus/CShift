// The helpers of the 68000 backend, written in assembly: what the 68000 cannot do in one instruction (32-bit
// multiplication and division, 64-bit multiplication and division, overflow checks of multiplications). They use the
// C calling convention (arguments on the stack, results in d0 or d0:d1) and keep d2-d7/a2-a6.

namespace CShift.M68k;

using System;

string RuntimeAsm()
{
    return
    // ---- 32 x 32 -> 32 (the low half) ----
    "__mulsi3:\n" +
    "\tmove.l\t(4,%sp),%d0\n" +
    "\tmove.l\t(8,%sp),%d1\n" +
    "\tjmp\t__cs68k_mul32\n" +
    // d0 * d1 -> d0 (registers: d1 is clobbered)
    "__cs68k_mul32:\n" +
    "\tmovem.l\t%d2-%d3,-(%sp)\n" +
    "\tmove.l\t%d0,%d2\n" +
    "\tswap\t%d2\n" +
    "\tmulu.w\t%d1,%d2\n" +          // ah * bl
    "\tmove.l\t%d1,%d3\n" +
    "\tswap\t%d3\n" +
    "\tmulu.w\t%d0,%d3\n" +          // al * bh
    "\tadd.w\t%d3,%d2\n" +
    "\tswap\t%d2\n" +
    "\tclr.w\t%d2\n" +               // the cross products << 16
    "\tmulu.w\t%d1,%d0\n" +          // al * bl
    "\tadd.l\t%d2,%d0\n" +
    "\tmovem.l\t(%sp)+,%d2-%d3\n" +
    "\trts\n" +

    // ---- unsigned 32 / 32: d0 = n, d1 = d -> d0 = quotient, d1 = remainder (shift and subtract) ----
    "__cs68k_udivmod:\n" +
    "\tmovem.l\t%d2-%d3,-(%sp)\n" +
    "\tmove.l\t%d1,%d3\n" +
    "\tmoveq\t#0,%d1\n" +
    "\tmoveq\t#31,%d2\n" +
    ".Lcs_udiv_loop:\n" +
    "\tadd.l\t%d0,%d0\n" +
    "\taddx.l\t%d1,%d1\n" +
    "\tcmp.l\t%d3,%d1\n" +
    "\tbcs.s\t.Lcs_udiv_next\n" +
    "\tsub.l\t%d3,%d1\n" +
    "\taddq.l\t#1,%d0\n" +
    ".Lcs_udiv_next:\n" +
    "\tdbra\t%d2,.Lcs_udiv_loop\n" +
    "\tmovem.l\t(%sp)+,%d2-%d3\n" +
    "\trts\n" +
    "__udivsi3:\n" +
    "\tmove.l\t(4,%sp),%d0\n" +
    "\tmove.l\t(8,%sp),%d1\n" +
    "\tjmp\t__cs68k_udivmod\n" +
    "__umodsi3:\n" +
    "\tmove.l\t(4,%sp),%d0\n" +
    "\tmove.l\t(8,%sp),%d1\n" +
    "\tjsr\t__cs68k_udivmod\n" +
    "\tmove.l\t%d1,%d0\n" +
    "\trts\n" +
    // signed: divide the magnitudes; the quotient is negative if the signs differ, the remainder has the dividend's sign
    "__cs68k_sdivmod:\n" +
    "\tmovem.l\t%d2-%d3,-(%sp)\n" +
    "\tmove.l\t%d0,%d2\n" +          // dividend (for the remainder's sign)
    "\tmove.l\t%d0,%d3\n" +
    "\teor.l\t%d1,%d3\n" +           // sign of the quotient
    "\ttst.l\t%d0\n" +
    "\tbpl.s\t.Lcs_sdiv_a\n" +
    "\tneg.l\t%d0\n" +
    ".Lcs_sdiv_a:\n" +
    "\ttst.l\t%d1\n" +
    "\tbpl.s\t.Lcs_sdiv_b\n" +
    "\tneg.l\t%d1\n" +
    ".Lcs_sdiv_b:\n" +
    "\tjsr\t__cs68k_udivmod\n" +
    "\ttst.l\t%d3\n" +
    "\tbpl.s\t.Lcs_sdiv_c\n" +
    "\tneg.l\t%d0\n" +
    ".Lcs_sdiv_c:\n" +
    "\ttst.l\t%d2\n" +
    "\tbpl.s\t.Lcs_sdiv_d\n" +
    "\tneg.l\t%d1\n" +
    ".Lcs_sdiv_d:\n" +
    "\tmovem.l\t(%sp)+,%d2-%d3\n" +
    "\trts\n" +
    "__divsi3:\n" +
    "\tmove.l\t(4,%sp),%d0\n" +
    "\tmove.l\t(8,%sp),%d1\n" +
    "\tjmp\t__cs68k_sdivmod\n" +
    "__modsi3:\n" +
    "\tmove.l\t(4,%sp),%d0\n" +
    "\tmove.l\t(8,%sp),%d1\n" +
    "\tjsr\t__cs68k_sdivmod\n" +
    "\tmove.l\t%d1,%d0\n" +
    "\trts\n" +

    // ---- unsigned 32 x 32 -> 64: d0 * d1 -> d0 (high) : d1 (low), from four 16 x 16 products ----
    "__cs68k_umul64:\n" +
    "\tmovem.l\t%d2-%d5,-(%sp)\n" +
    "\tmove.l\t%d0,%d2\n" +
    "\tmove.l\t%d0,%d3\n" +
    "\tswap\t%d3\n" +                // d3.w = ah
    "\tmove.l\t%d1,%d4\n" +
    "\tswap\t%d4\n" +                // d4.w = bh
    "\tmove.l\t%d2,%d5\n" +          // d5.w = al
    "\tmulu.w\t%d1,%d2\n" +          // d2 = al * bl
    "\tmove.l\t%d3,%d0\n" +          // d0.w = ah
    "\tmulu.w\t%d1,%d3\n" +          // d3 = ah * bl
    "\tmulu.w\t%d4,%d5\n" +          // d5 = al * bh
    "\tmulu.w\t%d0,%d4\n" +          // d4 = ah * bh
    "\tadd.l\t%d5,%d3\n" +           // middle = ah*bl + al*bh; a carry is worth 2^48
    "\tbcc.s\t.Lcs_umul64_a\n" +
    "\tadd.l\t#65536,%d4\n" +
    ".Lcs_umul64_a:\n" +
    "\tmove.l\t%d3,%d5\n" +
    "\tswap\t%d5\n" +
    "\tmoveq\t#0,%d0\n" +
    "\tmove.w\t%d5,%d0\n" +          // middle >> 16
    "\tclr.w\t%d5\n" +               // middle << 16
    "\tadd.l\t%d5,%d2\n" +           // low
    "\taddx.l\t%d0,%d4\n" +          // high (+ the carry of low)
    "\tmove.l\t%d4,%d0\n" +
    "\tmove.l\t%d2,%d1\n" +
    "\tmovem.l\t(%sp)+,%d2-%d5\n" +
    "\trts\n" +

    // ---- the low 64 bits of a 64 x 64 product: (a on the stack, then b) -> d0:d1 ----
    "__muldi3:\n" +
    "\tmovem.l\t%d2-%d4,-(%sp)\n" +
    "\tmove.l\t(20,%sp),%d0\n" +     // a low
    "\tmove.l\t(28,%sp),%d1\n" +     // b low
    "\tjsr\t__cs68k_umul64\n" +
    "\tmove.l\t%d0,%d2\n" +          // high of al*bl
    "\tmove.l\t%d1,%d3\n" +          // low
    "\tmove.l\t(16,%sp),%d0\n" +     // a high
    "\tmove.l\t(28,%sp),%d1\n" +     // b low
    "\tjsr\t__cs68k_mul32\n" +
    "\tadd.l\t%d0,%d2\n" +
    "\tmove.l\t(20,%sp),%d0\n" +     // a low
    "\tmove.l\t(24,%sp),%d1\n" +     // b high
    "\tjsr\t__cs68k_mul32\n" +
    "\tadd.l\t%d0,%d2\n" +
    "\tmove.l\t%d2,%d0\n" +
    "\tmove.l\t%d3,%d1\n" +
    "\tmovem.l\t(%sp)+,%d2-%d4\n" +
    "\trts\n" +

    // ---- 64 x 64 with overflow: (a, b on the stack) -> d0:d1 = product, a0 = 1 if it does not fit ----
    // core: d4:d5 = a, d6:d7 = b (unsigned) -> d0:d1 = the low 64 bits, d2 = 1 if the product needs more
    "__cs68k_umul64o_core:\n" +
    "\tmoveq\t#0,%d2\n" +
    "\ttst.l\t%d4\n" +
    "\tbeq.s\t.Lcs_m64_a\n" +
    "\ttst.l\t%d6\n" +
    "\tbeq.s\t.Lcs_m64_a\n" +
    "\tmoveq\t#1,%d2\n" +            // both high halves: at least 2^64
    ".Lcs_m64_a:\n" +
    "\tmove.l\t%d4,%d0\n" +
    "\tmove.l\t%d7,%d1\n" +
    "\tjsr\t__cs68k_umul64\n" +      // ah * bl
    "\tmove.l\t%d0,-(%sp)\n" +
    "\tmove.l\t%d1,-(%sp)\n" +
    "\tmove.l\t%d5,%d0\n" +
    "\tmove.l\t%d6,%d1\n" +
    "\tjsr\t__cs68k_umul64\n" +      // al * bh
    "\tmove.l\t(%sp)+,%d3\n" +
    "\tadd.l\t%d3,%d1\n" +
    "\tmove.l\t(%sp)+,%d3\n" +
    "\taddx.l\t%d3,%d0\n" +          // cross = ah*bl + al*bh
    "\tbcc.s\t.Lcs_m64_b\n" +
    "\tmoveq\t#1,%d2\n" +
    ".Lcs_m64_b:\n" +
    "\ttst.l\t%d0\n" +               // cross must fit into 32 bits
    "\tbeq.s\t.Lcs_m64_c\n" +
    "\tmoveq\t#1,%d2\n" +
    ".Lcs_m64_c:\n" +
    "\tmove.l\t%d1,%d3\n" +
    "\tmove.l\t%d5,%d0\n" +
    "\tmove.l\t%d7,%d1\n" +
    "\tjsr\t__cs68k_umul64\n" +      // al * bl
    "\tadd.l\t%d3,%d0\n" +           // + cross << 32
    "\tbcc.s\t.Lcs_m64_d\n" +
    "\tmoveq\t#1,%d2\n" +
    ".Lcs_m64_d:\n" +
    "\trts\n" +
    "__cs68k_umul64o:\n" +
    "\tmovem.l\t%d2-%d7,-(%sp)\n" +
    "\tmovem.l\t(28,%sp),%d4-%d7\n" +
    "\tjsr\t__cs68k_umul64o_core\n" +
    "\tmove.l\t%d2,%a0\n" +
    "\tmovem.l\t(%sp)+,%d2-%d7\n" +
    "\trts\n" +
    "__cs68k_smul64o:\n" +
    "\tmovem.l\t%d2-%d7,-(%sp)\n" +
    "\tmovem.l\t(28,%sp),%d4-%d7\n" +
    "\tmove.l\t%d4,%d3\n" +
    "\teor.l\t%d6,%d3\n" +
    "\tmove.l\t%d3,-(%sp)\n" +       // the sign of the product
    "\ttst.l\t%d4\n" +
    "\tbpl.s\t.Lcs_s64_a\n" +
    "\tneg.l\t%d5\n" +
    "\tnegx.l\t%d4\n" +
    ".Lcs_s64_a:\n" +
    "\ttst.l\t%d6\n" +
    "\tbpl.s\t.Lcs_s64_b\n" +
    "\tneg.l\t%d7\n" +
    "\tnegx.l\t%d6\n" +
    ".Lcs_s64_b:\n" +
    "\tjsr\t__cs68k_umul64o_core\n" +
    "\tmove.l\t(%sp)+,%d3\n" +
    "\ttst.l\t%d3\n" +
    "\tbpl.s\t.Lcs_s64_pos\n" +
    "\ttst.l\t%d0\n" +               // negative: the magnitude may be 2^63 at most
    "\tbpl.s\t.Lcs_s64_neg\n" +
    "\tcmp.l\t#-2147483648,%d0\n" +
    "\tbne.s\t.Lcs_s64_ovf\n" +
    "\ttst.l\t%d1\n" +
    "\tbeq.s\t.Lcs_s64_neg\n" +
    ".Lcs_s64_ovf:\n" +
    "\tmoveq\t#1,%d2\n" +
    ".Lcs_s64_neg:\n" +
    "\tneg.l\t%d1\n" +
    "\tnegx.l\t%d0\n" +
    "\tbra.s\t.Lcs_s64_done\n" +
    ".Lcs_s64_pos:\n" +
    "\ttst.l\t%d0\n" +
    "\tbpl.s\t.Lcs_s64_done\n" +
    "\tmoveq\t#1,%d2\n" +
    ".Lcs_s64_done:\n" +
    "\tmove.l\t%d2,%a0\n" +
    "\tmovem.l\t(%sp)+,%d2-%d7\n" +
    "\trts\n" +

    // ---- signed 32 x 32 with overflow: (a, b) -> d0 = product, d1 = 1 if it does not fit into 32 bits ----
    "__cs68k_smul32o:\n" +
    "\tmovem.l\t%d2-%d3,-(%sp)\n" +
    "\tmove.l\t(12,%sp),%d0\n" +
    "\tmove.l\t(16,%sp),%d1\n" +
    "\tjsr\t__cs68k_umul64\n" +      // d0:d1 unsigned product
    "\tmove.l\t(12,%sp),%d2\n" +
    "\tbpl.s\t.Lcs_smul_a\n" +
    "\tsub.l\t(16,%sp),%d0\n" +      // a < 0: high -= b
    ".Lcs_smul_a:\n" +
    "\tmove.l\t(16,%sp),%d2\n" +
    "\tbpl.s\t.Lcs_smul_b\n" +
    "\tsub.l\t(12,%sp),%d0\n" +      // b < 0: high -= a
    ".Lcs_smul_b:\n" +
    "\tmove.l\t%d1,%d3\n" +          // fits if high == the sign of low
    "\tadd.l\t%d3,%d3\n" +
    "\tsubx.l\t%d3,%d3\n" +          // d3 = low < 0 ? -1 : 0
    "\tcmp.l\t%d3,%d0\n" +
    "\tsne\t%d2\n" +
    "\tand.l\t#1,%d2\n" +
    "\tmove.l\t%d1,%d0\n" +
    "\tmove.l\t%d2,%d1\n" +
    "\tmovem.l\t(%sp)+,%d2-%d3\n" +
    "\trts\n" +

    // ---- unsigned 64 / 64, shift and subtract over 64 bits ----
    "__cs68k_udivmod64r:\n" +          // registers: d0:d1 = n, d4:d5 = d -> d0:d1 = quotient, d2:d3 = remainder
    "\tmoveq\t#0,%d2\n" +
    "\tmoveq\t#0,%d3\n" +
    "\tmoveq\t#63,%d6\n" +
    ".Lcs_udiv64_loop:\n" +
    "\tadd.l\t%d1,%d1\n" +
    "\taddx.l\t%d0,%d0\n" +
    "\taddx.l\t%d3,%d3\n" +
    "\taddx.l\t%d2,%d2\n" +
    "\tcmp.l\t%d4,%d2\n" +
    "\tbhi.s\t.Lcs_udiv64_sub\n" +
    "\tbcs.s\t.Lcs_udiv64_next\n" +
    "\tcmp.l\t%d5,%d3\n" +
    "\tbcs.s\t.Lcs_udiv64_next\n" +
    ".Lcs_udiv64_sub:\n" +
    "\tsub.l\t%d5,%d3\n" +
    "\tsubx.l\t%d4,%d2\n" +
    "\taddq.l\t#1,%d1\n" +
    ".Lcs_udiv64_next:\n" +
    "\tdbra\t%d6,.Lcs_udiv64_loop\n" +
    "\trts\n" +
    // unsigned and signed wrappers: (n high, n low, d high, d low) on the stack
    "__udivdi3:\n" +
    "\tmovem.l\t%d2-%d7,-(%sp)\n" +
    "\tmovem.l\t(28,%sp),%d0-%d1\n" +
    "\tmovem.l\t(36,%sp),%d4-%d5\n" +
    "\tjsr\t__cs68k_udivmod64r\n" +
    "\tmovem.l\t(%sp)+,%d2-%d7\n" +
    "\trts\n" +
    "__umoddi3:\n" +
    "\tmovem.l\t%d2-%d7,-(%sp)\n" +
    "\tmovem.l\t(28,%sp),%d0-%d1\n" +
    "\tmovem.l\t(36,%sp),%d4-%d5\n" +
    "\tjsr\t__cs68k_udivmod64r\n" +
    "\tmove.l\t%d2,%d0\n" +
    "\tmove.l\t%d3,%d1\n" +
    "\tmovem.l\t(%sp)+,%d2-%d7\n" +
    "\trts\n" +
    "__divdi3:\n" +
    "\tmovem.l\t%d2-%d7,-(%sp)\n" +
    "\tmoveq\t#0,%d7\n" +
    "\tjsr\t__cs68k_sdiv64\n" +
    "\tmovem.l\t(%sp)+,%d2-%d7\n" +
    "\trts\n" +
    "__moddi3:\n" +
    "\tmovem.l\t%d2-%d7,-(%sp)\n" +
    "\tmoveq\t#1,%d7\n" +
    "\tjsr\t__cs68k_sdiv64\n" +
    "\tmovem.l\t(%sp)+,%d2-%d7\n" +
    "\trts\n" +
    // d7 = 0: quotient, 1: remainder; the operands are at (32,sp) (the return addresses and saved registers above)
    "__cs68k_sdiv64:\n" +
    "\tmovem.l\t(32,%sp),%d0-%d1\n" +
    "\tmovem.l\t(40,%sp),%d4-%d5\n" +
    "\tmove.l\t%d0,-(%sp)\n" +       // the dividend's sign (remainder)
    "\tmove.l\t%d0,%d6\n" +
    "\teor.l\t%d4,%d6\n" +
    "\tmove.l\t%d6,-(%sp)\n" +       // the quotient's sign
    "\ttst.l\t%d0\n" +
    "\tbpl.s\t.Lcs_sdiv64_a\n" +
    "\tneg.l\t%d1\n" +
    "\tnegx.l\t%d0\n" +
    ".Lcs_sdiv64_a:\n" +
    "\ttst.l\t%d4\n" +
    "\tbpl.s\t.Lcs_sdiv64_b\n" +
    "\tneg.l\t%d5\n" +
    "\tnegx.l\t%d4\n" +
    ".Lcs_sdiv64_b:\n" +
    "\tjsr\t__cs68k_udivmod64r\n" +
    "\tmove.l\t(%sp)+,%d6\n" +       // quotient sign
    "\tmove.l\t(%sp)+,%d4\n" +       // dividend sign
    "\ttst.l\t%d7\n" +
    "\tbeq.s\t.Lcs_sdiv64_q\n" +
    "\tmove.l\t%d2,%d0\n" +
    "\tmove.l\t%d3,%d1\n" +
    "\tmove.l\t%d4,%d6\n" +
    ".Lcs_sdiv64_q:\n" +
    "\ttst.l\t%d6\n" +
    "\tbpl.s\t.Lcs_sdiv64_done\n" +
    "\tneg.l\t%d1\n" +
    "\tnegx.l\t%d0\n" +
    ".Lcs_sdiv64_done:\n" +
    "\trts\n";
}
