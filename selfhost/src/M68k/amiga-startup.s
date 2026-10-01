| The startup code of AmigaOS programs (see AmigaRuntime.csh): it must be the first code of the program. When it is
| used, the placeholder STACK (between @ signs) becomes the size of the program's own stack (the stack of a CLI program
| is often only 4 KB, too small for CShift's stack frames) and STUBS the stubs that call the libraries (AmigaStubsAsm).
| Comments start with '|' (as in GNU as for m68k).

	.text
__cs_start:
	movem.l	%d2-%d7/%a2-%a6,-(%sp)
	move.l	%a0,__cs_ArgPtr
	move.l	%d0,__cs_ArgLen
	move.l	4,%a6
	move.l	%a6,__cs_SysBase
| started from the Workbench? (pr_CLI == 0): take its message
	sub.l	%a1,%a1
	jsr	(-294,%a6)		| FindTask(NULL)
	move.l	%d0,__cs_ThisTask
	move.l	%d0,%a2
	tst.l	(172,%a2)		| pr_CLI
	bne	.Lcs_cli
	lea	(92,%a2),%a0		| pr_MsgPort
	jsr	(-384,%a6)		| WaitPort
	lea	(92,%a2),%a0
	jsr	(-372,%a6)		| GetMsg
	move.l	%d0,__cs_WBMessage
.Lcs_cli:
| the program's own stack
	move.l	#@STACK@,%d0
	moveq	#0,%d1
	jsr	(-198,%a6)		| AllocMem(size, MEMF_ANY)
	tst.l	%d0
	beq	.Lcs_nostack
	move.l	%d0,__cs_Stack
	move.l	%sp,__cs_SavedSP
	move.l	%d0,%sp
	add.l	#@STACK@,%sp
	jsr	__cs_amiga_main		| opens dos.library, runs main, cleans up; d0 = the return code
	bra	__cs_return
.Lcs_nostack:
	moveq	#20,%d0
	movem.l	(%sp)+,%d2-%d7/%a2-%a6
	rts
| exit(code): cleans up and returns to AmigaOS
exit:
	move.l	(4,%sp),%d0
	move.l	%d0,-(%sp)
	jsr	__cs_amiga_cleanup
	move.l	(%sp)+,%d0
__cs_return:
	move.l	__cs_SavedSP,%sp
	move.l	%d0,-(%sp)
	move.l	__cs_SysBase,%a6
	move.l	__cs_Stack,%a1
	move.l	#@STACK@,%d0
	jsr	(-210,%a6)		| FreeMem(stack)
	move.l	__cs_WBMessage,%d0
	beq	.Lcs_nowb
	jsr	(-132,%a6)		| Forbid: the Workbench must not unload us before we are gone
	move.l	__cs_WBMessage,%a1
	jsr	(-378,%a6)		| ReplyMsg
.Lcs_nowb:
	move.l	(%sp)+,%d0
	movem.l	(%sp)+,%d2-%d7/%a2-%a6
	rts
| printf(fmt, ...), fprintf(file, fmt, ...), snprintf(buf, size, fmt, ...), vsnprintf is not needed:
| __cs_vformat(kind, target, size, fmt, args)
printf:
	lea	(8,%sp),%a0
	move.l	%a0,-(%sp)
	move.l	(8,%sp),-(%sp)
	clr.l	-(%sp)
	clr.l	-(%sp)
	clr.l	-(%sp)
	jsr	__cs_vformat
	lea	(20,%sp),%sp
	rts
fprintf:
	lea	(12,%sp),%a0
	move.l	%a0,-(%sp)
	move.l	(12,%sp),-(%sp)
	clr.l	-(%sp)
	move.l	(16,%sp),-(%sp)
	move.l	#1,-(%sp)
	jsr	__cs_vformat
	lea	(20,%sp),%sp
	rts
snprintf:
	lea	(16,%sp),%a0
	move.l	%a0,-(%sp)
	move.l	(16,%sp),-(%sp)
	move.l	(16,%sp),-(%sp)
	move.l	(16,%sp),-(%sp)
	move.l	#2,-(%sp)
	jsr	__cs_vformat
	lea	(20,%sp),%sp
	rts
| memcpy(dst, src, n): longs while both are even, then bytes
memcpy:
	move.l	(4,%sp),%a0
	move.l	(8,%sp),%a1
	move.l	(12,%sp),%d1
	move.l	%a0,%d0
.Lcs_copy_fwd:
	move.l	%a0,%d0
	move.l	%a1,-(%sp)
	or.l	(%sp)+,%d0
	btst	#0,%d0
	bne	.Lcs_copy_bytes
.Lcs_copy_longs:
	cmp.l	#4,%d1
	bcs	.Lcs_copy_bytes
	move.l	(%a1)+,(%a0)+
	subq.l	#4,%d1
	bra	.Lcs_copy_longs
.Lcs_copy_bytes:
	tst.l	%d1
	beq	.Lcs_copy_done
	move.b	(%a1)+,(%a0)+
	subq.l	#1,%d1
	bra	.Lcs_copy_bytes
.Lcs_copy_done:
	move.l	(4,%sp),%d0
	move.l	%d0,%a0
	rts
| memmove: forwards when dst < src, else backwards
memmove:
	move.l	(4,%sp),%a0
	move.l	(8,%sp),%a1
	move.l	(12,%sp),%d1
	cmp.l	%a1,%a0
	bcs	.Lcs_copy_fwd
	add.l	%d1,%a0
	add.l	%d1,%a1
.Lcs_move_back:
	tst.l	%d1
	beq	.Lcs_copy_done
	move.b	-(%a1),-(%a0)
	subq.l	#1,%d1
	bra	.Lcs_move_back
| memset(dst, value, n)
memset:
	move.l	(4,%sp),%a0
	move.l	(8,%sp),%d0
	move.l	(12,%sp),%d1
.Lcs_set_loop:
	tst.l	%d1
	beq	.Lcs_set_done
	move.b	%d0,(%a0)+
	subq.l	#1,%d1
	bra	.Lcs_set_loop
.Lcs_set_done:
	move.l	(4,%sp),%d0
	move.l	%d0,%a0
	rts
| memcmp(a, b, n): the difference of the first bytes that differ (unsigned)
memcmp:
	move.l	(4,%sp),%a0
	move.l	(8,%sp),%a1
	move.l	(12,%sp),%d1
	moveq	#0,%d0
.Lcs_cmp_loop:
	tst.l	%d1
	beq	.Lcs_cmp_done
	subq.l	#1,%d1
	cmpm.b	(%a1)+,(%a0)+
	beq	.Lcs_cmp_loop
	moveq	#0,%d0
	move.b	-(%a0),%d0
	move.l	%d2,-(%sp)
	moveq	#0,%d2
	move.b	-(%a1),%d2
	sub.l	%d2,%d0
	move.l	(%sp)+,%d2
.Lcs_cmp_done:
	rts
| strlen(s)
strlen:
	move.l	(4,%sp),%a0
	move.l	%a0,%d0
.Lcs_len_loop:
	tst.b	(%a0)+
	bne	.Lcs_len_loop
	sub.l	%d0,%a0
	move.l	%a0,%d0
	subq.l	#1,%d0
	rts
| the runtime's variables for CShift code: __cs_amiga_get(index), __cs_amiga_set(index, value)
__cs_amiga_get:
	move.l	(4,%sp),%d0
	lsl.l	#2,%d0
	lea	__cs_Vars,%a0
	move.l	(0,%a0,%d0.l),%d0
	move.l	%d0,%a0
	rts
__cs_amiga_libtable:
	lea	__cs_amiga_libs,%a0
	move.l	%a0,%d0
	rts
__cs_amiga_set:
	move.l	(4,%sp),%d0
	lsl.l	#2,%d0
	lea	__cs_Vars,%a0
	move.l	(8,%sp),(0,%a0,%d0.l)
	rts
@STUBS@	.data
	.even
__cs_Vars:
__cs_SysBase:	.long	0
__cs_DOSBase:	.long	0
__cs_ThisTask:	.long	0
__cs_WBMessage:	.long	0
__cs_ArgPtr:	.long	0
__cs_ArgLen:	.long	0
__cs_Stack:	.long	0
__cs_SavedSP:	.long	0
stdout:	.long	0
stderr:	.long	0
__cs_GfxBase:	.long	0
	.text
