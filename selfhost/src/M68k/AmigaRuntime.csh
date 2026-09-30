// The assembly part of the AmigaOS runtime: the startup code (it comes first in the code hunk, where AmigaOS starts a
// program), exit, the stubs that call the functions of exec.library and dos.library (their arguments are in registers,
// the library base in a6), the entries of printf/fprintf/snprintf (their variable arguments are passed on to
// __cs_vformat in stdlib/amiga/libc.csh) and fast memcpy/memmove/memset/memcmp/strlen.

namespace CShift.M68k;

using System;

// A stub: a C function name(args...) that calls a library function with the arguments in the given registers.
struct LibStub
{
    string Name;
    string Base;   // the symbol that holds the library base
    int Offset;    // the library vector offset (negative)
    string Regs;   // "d1,d2,d3": the registers of the arguments, in order
}

const ReadOnlySlice<string> AmigaStubs = [
    // exec.library
    "__exec_AllocMem|__cs_SysBase|-198|d0,d1",
    "__exec_FreeMem|__cs_SysBase|-210|a1,d0",
    "__exec_FindTask|__cs_SysBase|-294|a1",
    "__exec_OpenLibrary|__cs_SysBase|-552|a1,d0",
    "__exec_CloseLibrary|__cs_SysBase|-414|a1",
    "__exec_WaitPort|__cs_SysBase|-384|a0",
    "__exec_GetMsg|__cs_SysBase|-372|a0",
    "__exec_ReplyMsg|__cs_SysBase|-378|a1",
    "__exec_Forbid|__cs_SysBase|-132|",
    "__exec_Permit|__cs_SysBase|-138|",
    // dos.library
    "__dos_Open|__cs_DOSBase|-30|d1,d2",
    "__dos_Close|__cs_DOSBase|-36|d1",
    "__dos_Read|__cs_DOSBase|-42|d1,d2,d3",
    "__dos_Write|__cs_DOSBase|-48|d1,d2,d3",
    "__dos_Input|__cs_DOSBase|-54|",
    "__dos_Output|__cs_DOSBase|-60|",
    "__dos_Seek|__cs_DOSBase|-66|d1,d2,d3",
    "__dos_DeleteFile|__cs_DOSBase|-72|d1",
    "__dos_Rename|__cs_DOSBase|-78|d1,d2",
    "__dos_Lock|__cs_DOSBase|-84|d1,d2",
    "__dos_UnLock|__cs_DOSBase|-90|d1",
    "__dos_Examine|__cs_DOSBase|-102|d1,d2",
    "__dos_ExNext|__cs_DOSBase|-108|d1,d2",
    "__dos_CreateDir|__cs_DOSBase|-120|d1",
    "__dos_CurrentDir|__cs_DOSBase|-126|d1",
    "__dos_IoErr|__cs_DOSBase|-132|",
    "__dos_DateStamp|__cs_DOSBase|-192|d1",
    "__dos_Delay|__cs_DOSBase|-198|d1",
    "__dos_Execute|__cs_DOSBase|-222|d1,d2,d3",
    "__dos_NameFromLock|__cs_DOSBase|-402|d1,d2,d3",
    "__dos_SystemTagList|__cs_DOSBase|-606|d1,d2",
    "__dos_GetVar|__cs_DOSBase|-906|d1,d2,d3,d4"];

// The registers a stub has to keep (the C convention keeps d2-d7/a2-a6).
string StubAsm(string name, string libBase, int offset, string regs)
{
    var saved = List<string>.Create();
    var args = regs.Length > 0 ? regs.Split(',') : new StringSlice[0];
    foreach (var r in args)
    {
        string reg = r.ToString();
        bool scratch = reg == "d0" || reg == "d1" || reg == "a0" || reg == "a1";
        if (!scratch)
            saved.Add("%" + reg);
    }
    saved.Add("%a6");
    var sb = StringBuilder.Create();
    sb.Append(name + ":\n");
    sb.Append("\tmovem.l\t" + string.Join("/", saved.ToArray()) + ",-(%sp)\n");
    int skip = 4 + 4 * saved.Count(); // the return address and the saved registers
    for (var i = 0; i < args.Length; i += 1)
        sb.Append("\tmove.l\t(" + (skip + 4 * i).ToString() + ",%sp),%" + args[i].ToString() + "\n");
    sb.Append("\tmove.l\t" + libBase + ",%a6\n");
    sb.Append("\tjsr\t(" + offset.ToString() + ",%a6)\n");
    sb.Append("\tmovem.l\t(%sp)+," + string.Join("/", saved.ToArray()) + "\n");
    sb.Append("\tmove.l\t%d0,%a0\n"); // pointer results: in a0 as well
    sb.Append("\trts\n");
    return sb.ToString();
}

// The startup code: it must be the first code of the program. stackSize: the size of the program's own stack (the
// stack of a CLI program is often only 4 KB, too small for CShift's stack frames).
string AmigaStartupAsm(int stackSize)
{
    return
    "\t.text\n" +
    "__cs_start:\n" +
    "\tmovem.l\t%d2-%d7/%a2-%a6,-(%sp)\n" +
    "\tmove.l\t%a0,__cs_ArgPtr\n" +
    "\tmove.l\t%d0,__cs_ArgLen\n" +
    "\tmove.l\t4,%a6\n" +
    "\tmove.l\t%a6,__cs_SysBase\n" +
    // started from the Workbench? (pr_CLI == 0): take its message
    "\tsub.l\t%a1,%a1\n" +
    "\tjsr\t(-294,%a6)\n" +                 // FindTask(NULL)
    "\tmove.l\t%d0,__cs_ThisTask\n" +
    "\tmove.l\t%d0,%a2\n" +
    "\ttst.l\t(172,%a2)\n" +                // pr_CLI
    "\tbne\t.Lcs_cli\n" +
    "\tlea\t(92,%a2),%a0\n" +               // pr_MsgPort
    "\tjsr\t(-384,%a6)\n" +                 // WaitPort
    "\tlea\t(92,%a2),%a0\n" +
    "\tjsr\t(-372,%a6)\n" +                 // GetMsg
    "\tmove.l\t%d0,__cs_WBMessage\n" +
    ".Lcs_cli:\n" +
    // the program's own stack
    "\tmove.l\t#" + stackSize.ToString() + ",%d0\n" +
    "\tmoveq\t#0,%d1\n" +
    "\tjsr\t(-198,%a6)\n" +                 // AllocMem(size, MEMF_ANY)
    "\ttst.l\t%d0\n" +
    "\tbeq\t.Lcs_nostack\n" +
    "\tmove.l\t%d0,__cs_Stack\n" +
    "\tmove.l\t%sp,__cs_SavedSP\n" +
    "\tmove.l\t%d0,%sp\n" +
    "\tadd.l\t#" + stackSize.ToString() + ",%sp\n" +
    "\tjsr\t__cs_amiga_main\n" +            // opens dos.library, runs main, cleans up; d0 = the return code
    "\tbra\t__cs_return\n" +
    ".Lcs_nostack:\n" +
    "\tmoveq\t#20,%d0\n" +
    "\tmovem.l\t(%sp)+,%d2-%d7/%a2-%a6\n" +
    "\trts\n" +

    // exit(code): cleans up and returns to AmigaOS
    "exit:\n" +
    "\tmove.l\t(4,%sp),%d0\n" +
    "\tmove.l\t%d0,-(%sp)\n" +
    "\tjsr\t__cs_amiga_cleanup\n" +
    "\tmove.l\t(%sp)+,%d0\n" +
    "__cs_return:\n" +
    "\tmove.l\t__cs_SavedSP,%sp\n" +
    "\tmove.l\t%d0,-(%sp)\n" +
    "\tmove.l\t__cs_SysBase,%a6\n" +
    "\tmove.l\t__cs_Stack,%a1\n" +
    "\tmove.l\t#" + stackSize.ToString() + ",%d0\n" +
    "\tjsr\t(-210,%a6)\n" +                 // FreeMem(stack)
    "\tmove.l\t__cs_WBMessage,%d0\n" +
    "\tbeq\t.Lcs_nowb\n" +
    "\tjsr\t(-132,%a6)\n" +                 // Forbid: the Workbench must not unload us before we are gone
    "\tmove.l\t__cs_WBMessage,%a1\n" +
    "\tjsr\t(-378,%a6)\n" +                 // ReplyMsg
    ".Lcs_nowb:\n" +
    "\tmove.l\t(%sp)+,%d0\n" +
    "\tmovem.l\t(%sp)+,%d2-%d7/%a2-%a6\n" +
    "\trts\n" +

    // printf(fmt, ...), fprintf(file, fmt, ...), snprintf(buf, size, fmt, ...), vsnprintf is not needed:
    // __cs_vformat(kind, target, size, fmt, args)
    "printf:\n" +
    "\tlea\t(8,%sp),%a0\n" +
    "\tmove.l\t%a0,-(%sp)\n" +
    "\tmove.l\t(8,%sp),-(%sp)\n" +
    "\tclr.l\t-(%sp)\n" +
    "\tclr.l\t-(%sp)\n" +
    "\tclr.l\t-(%sp)\n" +
    "\tjsr\t__cs_vformat\n" +
    "\tlea\t(20,%sp),%sp\n" +
    "\trts\n" +
    "fprintf:\n" +
    "\tlea\t(12,%sp),%a0\n" +
    "\tmove.l\t%a0,-(%sp)\n" +
    "\tmove.l\t(12,%sp),-(%sp)\n" +
    "\tclr.l\t-(%sp)\n" +
    "\tmove.l\t(16,%sp),-(%sp)\n" +
    "\tmove.l\t#1,-(%sp)\n" +
    "\tjsr\t__cs_vformat\n" +
    "\tlea\t(20,%sp),%sp\n" +
    "\trts\n" +
    "snprintf:\n" +
    "\tlea\t(16,%sp),%a0\n" +
    "\tmove.l\t%a0,-(%sp)\n" +
    "\tmove.l\t(16,%sp),-(%sp)\n" +
    "\tmove.l\t(16,%sp),-(%sp)\n" +
    "\tmove.l\t(16,%sp),-(%sp)\n" +
    "\tmove.l\t#2,-(%sp)\n" +
    "\tjsr\t__cs_vformat\n" +
    "\tlea\t(20,%sp),%sp\n" +
    "\trts\n" +

    // memcpy(dst, src, n): longs while both are even, then bytes
    "memcpy:\n" +
    "\tmove.l\t(4,%sp),%a0\n" +
    "\tmove.l\t(8,%sp),%a1\n" +
    "\tmove.l\t(12,%sp),%d1\n" +
    "\tmove.l\t%a0,%d0\n" +
    ".Lcs_copy_fwd:\n" +
    "\tmove.l\t%a0,%d0\n" +
    "\tmove.l\t%a1,-(%sp)\n" +
    "\tor.l\t(%sp)+,%d0\n" +
    "\tbtst\t#0,%d0\n" +
    "\tbne\t.Lcs_copy_bytes\n" +
    ".Lcs_copy_longs:\n" +
    "\tcmp.l\t#4,%d1\n" +
    "\tbcs\t.Lcs_copy_bytes\n" +
    "\tmove.l\t(%a1)+,(%a0)+\n" +
    "\tsubq.l\t#4,%d1\n" +
    "\tbra\t.Lcs_copy_longs\n" +
    ".Lcs_copy_bytes:\n" +
    "\ttst.l\t%d1\n" +
    "\tbeq\t.Lcs_copy_done\n" +
    "\tmove.b\t(%a1)+,(%a0)+\n" +
    "\tsubq.l\t#1,%d1\n" +
    "\tbra\t.Lcs_copy_bytes\n" +
    ".Lcs_copy_done:\n" +
    "\tmove.l\t(4,%sp),%d0\n" +
    "\tmove.l\t%d0,%a0\n" +
    "\trts\n" +
    // memmove: forwards when dst < src, else backwards
    "memmove:\n" +
    "\tmove.l\t(4,%sp),%a0\n" +
    "\tmove.l\t(8,%sp),%a1\n" +
    "\tmove.l\t(12,%sp),%d1\n" +
    "\tcmp.l\t%a1,%a0\n" +
    "\tbcs\t.Lcs_copy_fwd\n" +
    "\tadd.l\t%d1,%a0\n" +
    "\tadd.l\t%d1,%a1\n" +
    ".Lcs_move_back:\n" +
    "\ttst.l\t%d1\n" +
    "\tbeq\t.Lcs_copy_done\n" +
    "\tmove.b\t-(%a1),-(%a0)\n" +
    "\tsubq.l\t#1,%d1\n" +
    "\tbra\t.Lcs_move_back\n" +
    // memset(dst, value, n)
    "memset:\n" +
    "\tmove.l\t(4,%sp),%a0\n" +
    "\tmove.l\t(8,%sp),%d0\n" +
    "\tmove.l\t(12,%sp),%d1\n" +
    ".Lcs_set_loop:\n" +
    "\ttst.l\t%d1\n" +
    "\tbeq\t.Lcs_set_done\n" +
    "\tmove.b\t%d0,(%a0)+\n" +
    "\tsubq.l\t#1,%d1\n" +
    "\tbra\t.Lcs_set_loop\n" +
    ".Lcs_set_done:\n" +
    "\tmove.l\t(4,%sp),%d0\n" +
    "\tmove.l\t%d0,%a0\n" +
    "\trts\n" +
    // memcmp(a, b, n): the difference of the first bytes that differ (unsigned)
    "memcmp:\n" +
    "\tmove.l\t(4,%sp),%a0\n" +
    "\tmove.l\t(8,%sp),%a1\n" +
    "\tmove.l\t(12,%sp),%d1\n" +
    "\tmoveq\t#0,%d0\n" +
    ".Lcs_cmp_loop:\n" +
    "\ttst.l\t%d1\n" +
    "\tbeq\t.Lcs_cmp_done\n" +
    "\tsubq.l\t#1,%d1\n" +
    "\tcmpm.b\t(%a1)+,(%a0)+\n" +
    "\tbeq\t.Lcs_cmp_loop\n" +
    "\tmoveq\t#0,%d0\n" +
    "\tmove.b\t-(%a0),%d0\n" +
    "\tmove.l\t%d2,-(%sp)\n" +
    "\tmoveq\t#0,%d2\n" +
    "\tmove.b\t-(%a1),%d2\n" +
    "\tsub.l\t%d2,%d0\n" +
    "\tmove.l\t(%sp)+,%d2\n" +
    ".Lcs_cmp_done:\n" +
    "\trts\n" +
    // strlen(s)
    "strlen:\n" +
    "\tmove.l\t(4,%sp),%a0\n" +
    "\tmove.l\t%a0,%d0\n" +
    ".Lcs_len_loop:\n" +
    "\ttst.b\t(%a0)+\n" +
    "\tbne\t.Lcs_len_loop\n" +
    "\tsub.l\t%d0,%a0\n" +
    "\tmove.l\t%a0,%d0\n" +
    "\tsubq.l\t#1,%d0\n" +
    "\trts\n" +
    // the runtime's variables for CShift code: __cs_amiga_get(index), __cs_amiga_set(index, value)
    "__cs_amiga_get:\n" +
    "\tmove.l\t(4,%sp),%d0\n" +
    "\tlsl.l\t#2,%d0\n" +
    "\tlea\t__cs_Vars,%a0\n" +
    "\tmove.l\t(0,%a0,%d0.l),%d0\n" +
    "\tmove.l\t%d0,%a0\n" +
    "\trts\n" +
    "__cs_amiga_set:\n" +
    "\tmove.l\t(4,%sp),%d0\n" +
    "\tlsl.l\t#2,%d0\n" +
    "\tlea\t__cs_Vars,%a0\n" +
    "\tmove.l\t(8,%sp),(0,%a0,%d0.l)\n" +
    "\trts\n" +
    AmigaStubsAsm() +

    "\t.data\n" +
    "\t.even\n" +
    "__cs_Vars:\n" +
    "__cs_SysBase:\t.long\t0\n" +
    "__cs_DOSBase:\t.long\t0\n" +
    "__cs_ThisTask:\t.long\t0\n" +
    "__cs_WBMessage:\t.long\t0\n" +
    "__cs_ArgPtr:\t.long\t0\n" +
    "__cs_ArgLen:\t.long\t0\n" +
    "__cs_Stack:\t.long\t0\n" +
    "__cs_SavedSP:\t.long\t0\n" +
    "stdout:\t.long\t0\n" +
    "stderr:\t.long\t0\n" +
    "\t.text\n";
}

string AmigaStubsAsm()
{
    var sb = StringBuilder.Create();
    foreach (var line in AmigaStubs)
    {
        var parts = line.Split('|');
        sb.Append(StubAsm(parts[0].ToString(), parts[1].ToString(), (int)AsmNumber(parts[2].ToString()), parts[3].ToString()));
    }
    return sb.ToString();
}
