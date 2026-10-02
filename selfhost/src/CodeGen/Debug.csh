// Debug information (-g): the source location of every instruction, and a subprogram for every function of the
// program and the standard library. LLVM turns the metadata into DWARF, so gdb and lldb can set breakpoints on lines,
// step through the code and show where a program is (the call stack with files and lines). The metadata itself is
// written by Emit/IrWriter.csh; this file connects it with the source files and locations of the code generator.
//
// Functions the code generator makes up (the initializers of the globals, thread trampolines, the C entry point, the
// runtime helpers) have no subprogram: a debugger shows them without a line.

namespace CShift.CodeGen;

using System;
using CShift.Syntax;
using CShift.Sema;
using CShift.Emit;

// The pretty printers for gdb (tools/debug/cshift_gdb.py), embedded when cshc is compiled: every program built with
// -g carries them in the section .debug_gdb_scripts, where gdb finds them (when the program's folder is in gdb's
// auto-load safe path).
const string GdbScript = embed("../../../tools/debug/cshift_gdb.py");

// The section with the gdb script (ELF only), kept by @llvm.used.
string DebugGdbScriptGlobal(Compiler cg)
{
    string text = "\u0004gdb.inlined-script.cshift\n" + GdbScript;
    string escaped = IrWriter.EscapeBytes(text);
    return "@__cs_gdb_script = internal constant [" + (text.Length + 1).ToString() + " x i8] c\"" + escaped + "\\00\", section \".debug_gdb_scripts\", align 1\n" +
           "@llvm.used = appending global [1 x ptr] [ptr @__cs_gdb_script], section \"llvm.metadata\"\n";
}

// The location of what is being written: for the message of a panic, and for the debug information.
void SetLoc(Compiler cg, SourceLoc loc)
{
    cg.St[0].Loc = loc;
    // a location in another file (an expression from a declaration elsewhere) would get the wrong file
    if (cg.Ir.Debug && loc.File == SourceFileId(cg, cg.Fn[0].File))
        cg.Ir.SetDebugLoc(loc.Line, loc.Col);
}

// The number of a source file in the locations (SourceLoc.File) for its index in cg.Files (the File of functions,
// structs and globals). They differ once C headers have been imported (their files are numbered too).
int SourceFileId(Compiler cg, int fileIndex)
{
    return fileIndex >= 0 && fileIndex < cg.Files.Count() ? cg.Files.Get(fileIndex).FileId : -1;
}

// The file node of a source file (its index in cg.Files): the full path for files on disk, the name for the embedded
// standard library.
string DebugFileOf(Compiler cg, int fileIndex)
{
    string path = cg.Diag.Files.Get(SourceFileId(cg, fileIndex));
    if (path.StartsWith("<"))
        return cg.Ir.DebugFile("", path);
    string full = Path.GetFullPath(path);
    return cg.Ir.DebugFile(Path.GetDirectory(full), Path.GetFileName(full));
}

// The compile unit, named after the first source file of the program.
string DebugUnitOf(Compiler cg)
{
    int file = 0;
    for (var i = 0; i < cg.Files.Count(); i += 1)
    {
        if (!cg.Files.Get(i).IsPrelude)
        {
            file = i;
            break;
        }
    }
    return cg.Ir.DebugUnit(DebugFileOf(cg, file));
}

// ---------------------------------------------------------------------------
// Variables and their types
// ---------------------------------------------------------------------------

// A variable (or parameter: arg > 0) for the debugger. byRef: the slot holds the address of the value ('ref'
// parameters, 'this').
void DebugDeclare(Compiler cg, string name, int type, string slot, bool byRef, int arg)
{
    if (slot.Length == 0 || name.Length == 0 || name.StartsWith("$"))
        return;
    string t = DebugType(cg, type);
    if (byRef)
        t = DebugPointer(cg, t);
    var loc = cg.St[0].Loc;
    int line = loc.File == SourceFileId(cg, cg.Fn[0].File) ? loc.Line : 0;
    cg.Ir.DebugVariable(name, arg, t, slot, line);
}

string DebugPointer(Compiler cg, string target)
{
    return cg.Ir.MetaNode("!DIDerivedType(tag: DW_TAG_pointer_type, baseType: " + (target.Length > 0 ? target : "null") +
                          ", size: " + (cg.Ir.Target.PtrBytes * 8).ToString() + ")");
}

string DebugBasic(Compiler cg, string name, int bits, string encoding)
{
    return cg.Ir.MetaNode("!DIBasicType(name: " + IrWriter.MetaString(name) + ", size: " + bits.ToString() + ", encoding: " +
                          encoding + ")");
}

// The integer of sizes and lengths (the header of blocks, slices).
string DebugSizeType(Compiler cg)
{
    return DebugBasic(cg, cg.Ir.Target.PtrBytes == 8 ? "int64" : "int32", cg.Ir.Target.PtrBytes * 8, "DW_ATE_signed");
}

// One member of a struct-like type, at its offset (in bytes).
string DebugMember(Compiler cg, string name, string type, int64 size, int64 offset)
{
    return cg.Ir.MetaNode("!DIDerivedType(tag: DW_TAG_member, name: " + IrWriter.MetaString(name) + ", baseType: " +
                          (type.Length > 0 ? type : "null") + ", size: " + (size * 8).ToString() + ", offset: " +
                          (offset * 8).ToString() + ")");
}

// The members of a type that is laid out like a C struct (names[i] has the type types[i]).
string DebugMembers(Compiler cg, string[] names, int[] memberTypes)
{
    var items = List<string>.Create();
    int64 pos = 0;
    for (var i = 0; i < names.Length; i += 1)
    {
        var l = TypeLayout(cg, memberTypes[i]);
        pos = AlignUp(pos, l.Align);
        items.Add(DebugMember(cg, names[i], DebugType(cg, memberTypes[i]), l.Size, pos));
        pos += l.Size;
    }
    return cg.Ir.MetaNode("!{" + string.Join(", ", items.ToArray()) + "}");
}

string DebugStruct(Compiler cg, string name, int64 size, string elements)
{
    return "!DICompositeType(tag: DW_TAG_structure_type, name: " + IrWriter.MetaString(name) + ", size: " + (size * 8).ToString() +
           ", elements: " + elements + ")";
}

// The debug type of a CShift type (its node, "" for void).
string DebugType(Compiler cg, int t)
{
    var types = cg.Types;
    var ir = cg.Ir;
    string key = "type:" + t.ToString();
    var cached = ir.MetaIds.TryGet(key);
    if (cached is string known)
        return known;
    string name = types.Name(t);
    var kind = types.Kind(t);
    string result;
    switch (kind)
    {
    case TypeKind.Void:
        return "";
    case TypeKind.Bool:
        result = DebugBasic(cg, "bool", 8, "DW_ATE_boolean");
        break;
    case TypeKind.Int:
        result = DebugBasic(cg, name, types.Bits(t), types.IsSigned(t) ? "DW_ATE_signed" : "DW_ATE_unsigned");
        break;
    case TypeKind.Char:
        result = DebugBasic(cg, "char", types.Bits(t), types.Bits(t) == 8 ? "DW_ATE_unsigned_char" : "DW_ATE_UTF");
        break;
    case TypeKind.Float:
        result = DebugBasic(cg, name, types.Bits(t), "DW_ATE_float");
        break;
    case TypeKind.Enum:
    {
        var info = GetEnumInfo(cg, t);
        var items = List<string>.Create();
        for (var i = 0; i < info.Names.Length; i += 1)
            items.Add(ir.MetaNode("!DIEnumerator(name: " + IrWriter.MetaString(info.Names[i]) + ", value: " + info.Values[i].ToString() + ")"));
        result = ir.MetaNode("!DICompositeType(tag: DW_TAG_enumeration_type, name: " + IrWriter.MetaString(name) + ", size: " +
                             types.Bits(t).ToString() + ", baseType: " + DebugType(cg, info.Base) + ", elements: " +
                             ir.MetaNode("!{" + string.Join(", ", items.ToArray()) + "}") + ")");
        break;
    }
    case TypeKind.Pointer:
    {
        // reserved first: a pointer can lead back to a struct that contains it
        string id = ir.MetaReserve();
        ir.MetaIds.Set(key, id);
        ir.MetaDefine(id, "!DIDerivedType(tag: DW_TAG_pointer_type, baseType: " + DebugTypeOrNull(cg, types.Elem(t)) + ", size: " +
                          (ir.Target.PtrBytes * 8).ToString() + ")");
        return id;
    }
    case TypeKind.String:
    case TypeKind.Array:
    case TypeKind.SharedPtr:
        return DebugBlockType(cg, t, key);
    case TypeKind.Struct:
    {
        string id = ir.MetaReserve();
        ir.MetaIds.Set(key, id);
        var si = GetStructInfo(cg, t);
        var decl = cg.Structs.Get(si.Entry).Decl;
        int64 size = TypeLayout(cg, t).Size;
        string elements = ir.MetaNode("!{}");
        if (!decl.ExplicitLayout && !si.Opaque)
        {
            // the base struct comes first, then the fields in their order
            var names = List<string>.Create();
            var memberTypes = List<int>.Create();
            if (si.Base != 0)
            {
                names.Add("base");
                memberTypes.Add(si.Base);
            }
            foreach (var f in si.Fields)
            {
                names.Add(f.Name);
                memberTypes.Add(f.Type);
            }
            elements = DebugMembers(cg, names.ToArray(), memberTypes.ToArray());
        }
        ir.MetaDefine(id, DebugStruct(cg, name, size, elements));
        return id;
    }
    case TypeKind.Optional:
        result = DebugValueStruct(cg, t, key, new string[] { "HasValue", "Value" }, new int[] { types.Bool, types.Elem(t) });
        return result;
    case TypeKind.Error:
    {
        int elem = types.Elem(t);
        if (types.IsVoid(elem))
            return DebugValueStruct(cg, t, key, new string[] { "Ok", "Message", "Code" }, new int[] { types.Bool, types.String, types.I32 });
        return DebugValueStruct(cg, t, key, new string[] { "Ok", "Value", "Message", "Code" }, new int[] { types.Bool, elem, types.String, types.I32 });
    }
    case TypeKind.Slice:
    case TypeKind.ReadOnlySlice:
    case TypeKind.StringSlice:
    {
        string id = ir.MetaReserve();
        ir.MetaIds.Set(key, id);
        int64 p = (int64)ir.Target.PtrBytes;
        int elem = SliceElemType(cg, t);
        string items = ir.MetaNode("!{" + DebugMember(cg, "owner", DebugPointer(cg, ""), p, 0) + ", " +
                                   DebugMember(cg, "data", DebugPointer(cg, DebugType(cg, elem)), p, p) + ", " +
                                   DebugMember(cg, "length", DebugSizeType(cg), p, 2 * p) + "}");
        ir.MetaDefine(id, DebugStruct(cg, name, 3 * p, items));
        return id;
    }
    case TypeKind.Function:
    case TypeKind.Interface:
    {
        int64 p = (int64)ir.Target.PtrBytes;
        string items = ir.MetaNode("!{" + DebugMember(cg, kind == TypeKind.Function ? "function" : "data", DebugPointer(cg, ""), p, 0) + ", " +
                                   DebugMember(cg, kind == TypeKind.Function ? "environment" : "table", DebugPointer(cg, ""), p, p) + "}");
        result = ir.MetaNode(DebugStruct(cg, name, 2 * p, items));
        break;
    }
    case TypeKind.Fixed:
    {
        string id = ir.MetaReserve();
        ir.MetaIds.Set(key, id);
        ir.MetaDefine(id, "!DICompositeType(tag: DW_TAG_array_type, baseType: " + DebugTypeOrNull(cg, types.Elem(t)) + ", size: " +
                          (TypeLayout(cg, t).Size * 8).ToString() + ", elements: " +
                          ir.MetaNode("!{" + ir.MetaNode("!DISubrange(count: " + types.Count(t).ToString() + ")") + "}") + ")");
        return id;
    }
    case TypeKind.Union:
    {
        // { tag, value }: the tag (0: empty, k: member k - 1) and the members on top of each other
        string id = ir.MetaReserve();
        ir.MetaIds.Set(key, id);
        var ui = GetUnionInfo(cg, t);
        int64 align = 1;
        int64 largest = 0;
        var members = List<string>.Create();
        foreach (var m in ui.Members)
        {
            var l = TypeLayout(cg, m);
            if (l.Align > align)
                align = l.Align;
            if (l.Size > largest)
                largest = l.Size;
            members.Add(DebugMember(cg, types.Name(m), DebugType(cg, m), l.Size, 0));
        }
        int64 offset = AlignUp(4, (int64)ir.Target.ScalarAlign((int)align, false));
        string value = ir.MetaNode("!DICompositeType(tag: DW_TAG_union_type, name: " + IrWriter.MetaString(name + " (value)") + ", size: " +
                                   (largest * 8).ToString() + ", elements: " + ir.MetaNode("!{" + string.Join(", ", members.ToArray()) + "}") + ")");
        string items = ir.MetaNode("!{" + DebugMember(cg, "tag", DebugType(cg, types.I32), 4, 0) + ", " + DebugMember(cg, "value", value, largest, offset) + "}");
        ir.MetaDefine(id, DebugStruct(cg, name, TypeLayout(cg, t).Size, items));
        return id;
    }
    default:
        result = DebugPointer(cg, "");
        break;
    }
    ir.MetaIds.Set(key, result);
    return result;
}

string DebugTypeOrNull(Compiler cg, int t)
{
    string d = DebugType(cg, t);
    return d.Length > 0 ? d : "null";
}

// Optional<T> and Error<T>: a struct of the given members (laid out like the LLVM struct of the type).
string DebugValueStruct(Compiler cg, int t, string key, string[] names, int[] memberTypes)
{
    var ir = cg.Ir;
    string id = ir.MetaReserve();
    ir.MetaIds.Set(key, id);
    ir.MetaDefine(id, DebugStruct(cg, cg.Types.Name(t), TypeLayout(cg, t).Size, DebugMembers(cg, names, memberTypes)));
    return id;
}

// A string, an array or a SharedPtr<T>: a pointer to a heap block { refcount, length, the bytes or elements }. The
// variable's type is a typedef with the CShift name (string, int32[], ...), which the pretty printers of
// tools/debug look for.
string DebugBlockType(Compiler cg, int t, string key)
{
    var types = cg.Types;
    var ir = cg.Ir;
    string id = ir.MetaReserve();
    ir.MetaIds.Set(key, id);
    int64 p = (int64)ir.Target.PtrBytes;
    string size = DebugSizeType(cg);
    string data;
    if (types.IsSharedPtr(t))
        data = DebugMember(cg, "value", DebugTypeOrNull(cg, types.Elem(t)), TypeLayout(cg, types.Elem(t)).Size, 2 * p);
    else
    {
        // the elements: an array without a fixed length (the length is in the header)
        int elem = types.IsString(t) ? types.Char : types.Elem(t);
        string array = ir.MetaNode("!DICompositeType(tag: DW_TAG_array_type, baseType: " + DebugTypeOrNull(cg, elem) + ", elements: " +
                                   ir.MetaNode("!{" + ir.MetaNode("!DISubrange(count: -1)") + "}") + ")");
        data = DebugMember(cg, types.IsString(t) ? "chars" : "items", array, 0, 2 * p);
    }
    string items = ir.MetaNode("!{" + DebugMember(cg, "refcount", size, p, 0) + ", " + DebugMember(cg, "length", size, p, p) + ", " + data + "}");
    string block = ir.MetaNode(DebugStruct(cg, types.Name(t) + " (block)", 2 * p, items));
    ir.MetaDefine(id, "!DIDerivedType(tag: DW_TAG_typedef, name: " + IrWriter.MetaString(types.Name(t)) + ", baseType: " +
                      DebugPointer(cg, block) + ")");
    return id;
}
