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
    "__dos_GetVar|__cs_DOSBase|-906|d1,d2,d3,d4",
    // graphics.library (for Amiga.Hardware: taking the machine over and giving it back)
    "__gfx_LoadView|__cs_GfxBase|-222|a1",
    "__gfx_WaitTOF|__cs_GfxBase|-270|",
    "__gfx_WaitBlit|__cs_GfxBase|-228|",
    "__gfx_OwnBlitter|__cs_GfxBase|-456|",
    "__gfx_DisownBlitter|__cs_GfxBase|-462|"];

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

// The startup code (amiga-startup.s, embedded when cshc is compiled): it must be the first code of the program.
// stackSize: the size of the program's own stack.
const string AmigaStartupText = embed("amiga-startup.s");

string AmigaStartupAsm(int stackSize)
{
    return AmigaStartupText.Replace("@STACK@", stackSize.ToString()).Replace("@STUBS@", AmigaStubsAsm());
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
