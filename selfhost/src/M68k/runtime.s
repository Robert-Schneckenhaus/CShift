| The helpers of the 68000 backend (see Runtime.csh): what the 68000 cannot do in one instruction (32-bit
| multiplication and division, 64-bit multiplication and division, overflow checks of multiplications). They use the
| C calling convention (arguments on the stack, results in d0 or d0:d1) and keep d2-d7/a2-a6.
| Comments start with '|' (as in GNU as for m68k).

| ---- 32 x 32 -> 32 (the low half) ----
__mulsi3:
	move.l	(4,%sp),%d0
	move.l	(8,%sp),%d1
	jmp	__cs68k_mul32
| d0 * d1 -> d0 (registers: d1 is clobbered)
__cs68k_mul32:
	movem.l	%d2-%d3,-(%sp)
| both factors fit in 16 bits (signed): one muls.w
	move.w	%d0,%d2
	ext.l	%d2
	cmp.l	%d0,%d2
	bne.s	.Lcs_mul32_full
	move.w	%d1,%d2
	ext.l	%d2
	cmp.l	%d1,%d2
	bne.s	.Lcs_mul32_full
	muls.w	%d1,%d0
	movem.l	(%sp)+,%d2-%d3
	rts
.Lcs_mul32_full:
	move.l	%d0,%d2
	swap	%d2
	mulu.w	%d1,%d2		| ah * bl
	move.l	%d1,%d3
	swap	%d3
	mulu.w	%d0,%d3		| al * bh
	add.w	%d3,%d2
	swap	%d2
	clr.w	%d2		| the cross products << 16
	mulu.w	%d1,%d0		| al * bl
	add.l	%d2,%d0
	movem.l	(%sp)+,%d2-%d3
	rts
| ---- unsigned 32 / 32: d0 = n, d1 = d -> d0 = quotient, d1 = remainder (shift and subtract) ----
__cs68k_udivmod:
	movem.l	%d2-%d3,-(%sp)
| a divisor below 65536: two divu.w (the high half of the dividend, then the rest with its remainder)
	move.l	%d1,%d3
	swap	%d3
	tst.w	%d3
	bne.s	.Lcs_udiv_slow
	move.l	%d0,%d2
	clr.w	%d2
	swap	%d2		| the high half of the dividend
	divu.w	%d1,%d2		| remainder : quotient (high)
	move.w	%d2,%d3
	swap	%d3		| the high half of the quotient
	move.w	%d0,%d2		| remainder : the low half of the dividend
	divu.w	%d1,%d2
	move.w	%d2,%d3		| the whole quotient
	clr.w	%d2
	swap	%d2		| the remainder
	move.l	%d3,%d0
	move.l	%d2,%d1
	movem.l	(%sp)+,%d2-%d3
	rts
.Lcs_udiv_slow:
	move.l	%d1,%d3
	moveq	#0,%d1
	moveq	#31,%d2
.Lcs_udiv_loop:
	add.l	%d0,%d0
	addx.l	%d1,%d1
	cmp.l	%d3,%d1
	bcs.s	.Lcs_udiv_next
	sub.l	%d3,%d1
	addq.l	#1,%d0
.Lcs_udiv_next:
	dbra	%d2,.Lcs_udiv_loop
	movem.l	(%sp)+,%d2-%d3
	rts
__udivsi3:
	move.l	(4,%sp),%d0
	move.l	(8,%sp),%d1
	jmp	__cs68k_udivmod
__umodsi3:
	move.l	(4,%sp),%d0
	move.l	(8,%sp),%d1
	jsr	__cs68k_udivmod
	move.l	%d1,%d0
	rts
| signed: divide the magnitudes; the quotient is negative if the signs differ, the remainder has the dividend's sign
__cs68k_sdivmod:
	movem.l	%d2-%d3,-(%sp)
	move.l	%d0,%d2		| dividend (for the remainder's sign)
	move.l	%d0,%d3
	eor.l	%d1,%d3		| sign of the quotient
	tst.l	%d0
	bpl.s	.Lcs_sdiv_a
	neg.l	%d0
.Lcs_sdiv_a:
	tst.l	%d1
	bpl.s	.Lcs_sdiv_b
	neg.l	%d1
.Lcs_sdiv_b:
	jsr	__cs68k_udivmod
	tst.l	%d3
	bpl.s	.Lcs_sdiv_c
	neg.l	%d0
.Lcs_sdiv_c:
	tst.l	%d2
	bpl.s	.Lcs_sdiv_d
	neg.l	%d1
.Lcs_sdiv_d:
	movem.l	(%sp)+,%d2-%d3
	rts
__divsi3:
	move.l	(4,%sp),%d0
	move.l	(8,%sp),%d1
	jmp	__cs68k_sdivmod
__modsi3:
	move.l	(4,%sp),%d0
	move.l	(8,%sp),%d1
	jsr	__cs68k_sdivmod
	move.l	%d1,%d0
	rts
| ---- unsigned 32 x 32 -> 64: d0 * d1 -> d0 (high) : d1 (low), from four 16 x 16 products ----
__cs68k_umul64:
	movem.l	%d2-%d5,-(%sp)
	move.l	%d0,%d2
	move.l	%d0,%d3
	swap	%d3		| d3.w = ah
	move.l	%d1,%d4
	swap	%d4		| d4.w = bh
	move.l	%d2,%d5		| d5.w = al
	mulu.w	%d1,%d2		| d2 = al * bl
	move.l	%d3,%d0		| d0.w = ah
	mulu.w	%d1,%d3		| d3 = ah * bl
	mulu.w	%d4,%d5		| d5 = al * bh
	mulu.w	%d0,%d4		| d4 = ah * bh
	add.l	%d5,%d3		| middle = ah*bl + al*bh; a carry is worth 2^48
	bcc.s	.Lcs_umul64_a
	add.l	#65536,%d4
.Lcs_umul64_a:
	move.l	%d3,%d5
	swap	%d5
	moveq	#0,%d0
	move.w	%d5,%d0		| middle >> 16
	clr.w	%d5		| middle << 16
	add.l	%d5,%d2		| low
	addx.l	%d0,%d4		| high (+ the carry of low)
	move.l	%d4,%d0
	move.l	%d2,%d1
	movem.l	(%sp)+,%d2-%d5
	rts
| ---- the low 64 bits of a 64 x 64 product: (a on the stack, then b) -> d0:d1 ----
__muldi3:
	movem.l	%d2-%d4,-(%sp)
	move.l	(20,%sp),%d0		| a low
	move.l	(28,%sp),%d1		| b low
	jsr	__cs68k_umul64
	move.l	%d0,%d2		| high of al*bl
	move.l	%d1,%d3		| low
	move.l	(16,%sp),%d0		| a high
	move.l	(28,%sp),%d1		| b low
	jsr	__cs68k_mul32
	add.l	%d0,%d2
	move.l	(20,%sp),%d0		| a low
	move.l	(24,%sp),%d1		| b high
	jsr	__cs68k_mul32
	add.l	%d0,%d2
	move.l	%d2,%d0
	move.l	%d3,%d1
	movem.l	(%sp)+,%d2-%d4
	rts
| ---- 64 x 64 with overflow: (a, b on the stack) -> d0:d1 = product, a0 = 1 if it does not fit ----
| core: d4:d5 = a, d6:d7 = b (unsigned) -> d0:d1 = the low 64 bits, d2 = 1 if the product needs more
__cs68k_umul64o_core:
	moveq	#0,%d2
	tst.l	%d4
	beq.s	.Lcs_m64_a
	tst.l	%d6
	beq.s	.Lcs_m64_a
	moveq	#1,%d2		| both high halves: at least 2^64
.Lcs_m64_a:
	move.l	%d4,%d0
	move.l	%d7,%d1
	jsr	__cs68k_umul64		| ah * bl
	move.l	%d0,-(%sp)
	move.l	%d1,-(%sp)
	move.l	%d5,%d0
	move.l	%d6,%d1
	jsr	__cs68k_umul64		| al * bh
	move.l	(%sp)+,%d3
	add.l	%d3,%d1
	move.l	(%sp)+,%d3
	addx.l	%d3,%d0		| cross = ah*bl + al*bh
	bcc.s	.Lcs_m64_b
	moveq	#1,%d2
.Lcs_m64_b:
	tst.l	%d0		| cross must fit into 32 bits
	beq.s	.Lcs_m64_c
	moveq	#1,%d2
.Lcs_m64_c:
	move.l	%d1,%d3
	move.l	%d5,%d0
	move.l	%d7,%d1
	jsr	__cs68k_umul64		| al * bl
	add.l	%d3,%d0		| + cross << 32
	bcc.s	.Lcs_m64_d
	moveq	#1,%d2
.Lcs_m64_d:
	rts
__cs68k_umul64o:
	movem.l	%d2-%d7,-(%sp)
	movem.l	(28,%sp),%d4-%d7
	jsr	__cs68k_umul64o_core
	move.l	%d2,%a0
	movem.l	(%sp)+,%d2-%d7
	rts
__cs68k_smul64o:
	movem.l	%d2-%d7,-(%sp)
	movem.l	(28,%sp),%d4-%d7
	move.l	%d4,%d3
	eor.l	%d6,%d3
	move.l	%d3,-(%sp)		| the sign of the product
	tst.l	%d4
	bpl.s	.Lcs_s64_a
	neg.l	%d5
	negx.l	%d4
.Lcs_s64_a:
	tst.l	%d6
	bpl.s	.Lcs_s64_b
	neg.l	%d7
	negx.l	%d6
.Lcs_s64_b:
	jsr	__cs68k_umul64o_core
	move.l	(%sp)+,%d3
	tst.l	%d3
	bpl.s	.Lcs_s64_pos
	tst.l	%d0		| negative: the magnitude may be 2^63 at most
	bpl.s	.Lcs_s64_neg
	cmp.l	#-2147483648,%d0
	bne.s	.Lcs_s64_ovf
	tst.l	%d1
	beq.s	.Lcs_s64_neg
.Lcs_s64_ovf:
	moveq	#1,%d2
.Lcs_s64_neg:
	neg.l	%d1
	negx.l	%d0
	bra.s	.Lcs_s64_done
.Lcs_s64_pos:
	tst.l	%d0
	bpl.s	.Lcs_s64_done
	moveq	#1,%d2
.Lcs_s64_done:
	move.l	%d2,%a0
	movem.l	(%sp)+,%d2-%d7
	rts
| ---- signed 32 x 32 with overflow: (a, b) -> d0 = product, d1 = 1 if it does not fit into 32 bits ----
__cs68k_smul32o:
	movem.l	%d2-%d3,-(%sp)
	move.l	(12,%sp),%d0
	move.l	(16,%sp),%d1
| both factors fit in 16 bits: one muls.w, and the product always fits
	move.w	%d0,%d2
	ext.l	%d2
	cmp.l	%d0,%d2
	bne.s	.Lcs_smul_slow
	move.w	%d1,%d2
	ext.l	%d2
	cmp.l	%d1,%d2
	bne.s	.Lcs_smul_slow
	muls.w	%d1,%d0
	moveq	#0,%d1
	movem.l	(%sp)+,%d2-%d3
	rts
.Lcs_smul_slow:
	jsr	__cs68k_umul64		| d0:d1 unsigned product
	move.l	(12,%sp),%d2
	bpl.s	.Lcs_smul_a
	sub.l	(16,%sp),%d0		| a < 0: high -= b
.Lcs_smul_a:
	move.l	(16,%sp),%d2
	bpl.s	.Lcs_smul_b
	sub.l	(12,%sp),%d0		| b < 0: high -= a
.Lcs_smul_b:
	move.l	%d1,%d3		| fits if high == the sign of low
	add.l	%d3,%d3
	subx.l	%d3,%d3		| d3 = low < 0 ? -1 : 0
	cmp.l	%d3,%d0
	sne	%d2
	and.l	#1,%d2
	move.l	%d1,%d0
	move.l	%d2,%d1
	movem.l	(%sp)+,%d2-%d3
	rts
| ---- unsigned 64 / 64, shift and subtract over 64 bits ----
__cs68k_udivmod64r:		| registers: d0:d1 = n, d4:d5 = d -> d0:d1 = quotient, d2:d3 = remainder
	moveq	#0,%d2
	moveq	#0,%d3
	moveq	#63,%d6
.Lcs_udiv64_loop:
	add.l	%d1,%d1
	addx.l	%d0,%d0
	addx.l	%d3,%d3
	addx.l	%d2,%d2
	cmp.l	%d4,%d2
	bhi.s	.Lcs_udiv64_sub
	bcs.s	.Lcs_udiv64_next
	cmp.l	%d5,%d3
	bcs.s	.Lcs_udiv64_next
.Lcs_udiv64_sub:
	sub.l	%d5,%d3
	subx.l	%d4,%d2
	addq.l	#1,%d1
.Lcs_udiv64_next:
	dbra	%d6,.Lcs_udiv64_loop
	rts
| unsigned and signed wrappers: (n high, n low, d high, d low) on the stack
__udivdi3:
	movem.l	%d2-%d7,-(%sp)
	movem.l	(28,%sp),%d0-%d1
	movem.l	(36,%sp),%d4-%d5
	jsr	__cs68k_udivmod64r
	movem.l	(%sp)+,%d2-%d7
	rts
__umoddi3:
	movem.l	%d2-%d7,-(%sp)
	movem.l	(28,%sp),%d0-%d1
	movem.l	(36,%sp),%d4-%d5
	jsr	__cs68k_udivmod64r
	move.l	%d2,%d0
	move.l	%d3,%d1
	movem.l	(%sp)+,%d2-%d7
	rts
__divdi3:
	movem.l	%d2-%d7,-(%sp)
	moveq	#0,%d7
	jsr	__cs68k_sdiv64
	movem.l	(%sp)+,%d2-%d7
	rts
__moddi3:
	movem.l	%d2-%d7,-(%sp)
	moveq	#1,%d7
	jsr	__cs68k_sdiv64
	movem.l	(%sp)+,%d2-%d7
	rts
| d7 = 0: quotient, 1: remainder; the operands are at (32,sp) (the return addresses and saved registers above)
__cs68k_sdiv64:
	movem.l	(32,%sp),%d0-%d1
	movem.l	(40,%sp),%d4-%d5
	move.l	%d0,-(%sp)		| the dividend's sign (remainder)
	move.l	%d0,%d6
	eor.l	%d4,%d6
	move.l	%d6,-(%sp)		| the quotient's sign
	tst.l	%d0
	bpl.s	.Lcs_sdiv64_a
	neg.l	%d1
	negx.l	%d0
.Lcs_sdiv64_a:
	tst.l	%d4
	bpl.s	.Lcs_sdiv64_b
	neg.l	%d5
	negx.l	%d4
.Lcs_sdiv64_b:
	jsr	__cs68k_udivmod64r
	move.l	(%sp)+,%d6		| quotient sign
	move.l	(%sp)+,%d4		| dividend sign
	tst.l	%d7
	beq.s	.Lcs_sdiv64_q
	move.l	%d2,%d0
	move.l	%d3,%d1
	move.l	%d4,%d6
.Lcs_sdiv64_q:
	tst.l	%d6
	bpl.s	.Lcs_sdiv64_done
	neg.l	%d1
	negx.l	%d0
.Lcs_sdiv64_done:
	rts
