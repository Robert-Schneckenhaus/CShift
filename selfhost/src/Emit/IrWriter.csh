// Writes LLVM IR as text. The compiler produces a .ll file and lets clang optimize it, generate the object file and
// link it, so cshc itself does not depend on LLVM.
//
// The writer keeps the module (constants, declarations, finished functions) and the function that is being written.
// Instruction helpers return the operand that holds the result ("%t5", or a constant).

namespace CShift.Emit;

using System;
using CShift.Syntax;

struct IrState
{
    int Temp;         // counter for %t<N>
    int Label;        // counter for block labels
    int Global;       // counter for constants
    bool BlockOpen;   // the current block has no terminator yet
    string Block;     // label of the current block
    bool InFunction;
    bool Live;        // the current block can be reached
}

struct IrWriter
{
    IrState[] S;
    StringBuilder Globals;    // constants
    StringBuilder Declares;   // declarations of external functions and intrinsics
    StringBuilder Functions;  // finished function definitions
    StringBuilder Helpers;    // helper functions that are created while another function is written
    StringBuilder Body;       // the function being written
    StringBuilder Allocas;    // its allocas (they must be in the entry block)
    HashSet<string> Declared;
    HashSet<string> Preds;     // labels that a branch jumps to (to know whether a block can be reached)
    Dictionary<string, string> Literals; // string literals and C strings by content
    TargetInfo Target;
    // Debug information (-g): the metadata nodes of the module (shared with the writers of lambdas) and, per writer,
    // [0] the subprogram of the function being written, [1] the location of the next instructions, [2] the subprogram
    // for the next BeginFunction, [3] its file, [4] the file of the function being written; DbgScopes the lexical
    // blocks that are open (innermost last).
    bool Debug;
    StringBuilder Meta;
    int[] MetaCount;
    Dictionary<string, string> MetaIds;
    string[] Dbg;
    List<string> DbgScopes;
    List<string> DbgGlobals;   // the global variables (shared with the writers of lambdas)

    static IrWriter Create(TargetInfo target)
    {
        var w = IrWriter { S = new IrState[1], Target = target };
        w.Globals = StringBuilder.Create();
        w.Declares = StringBuilder.Create();
        w.Functions = StringBuilder.Create();
        w.Helpers = StringBuilder.Create();
        w.Body = StringBuilder.Create();
        w.Allocas = StringBuilder.Create();
        w.Declared = HashSet<string>.Create();
        w.Preds = HashSet<string>.Create();
        w.Literals = Dictionary<string, string>.Create();
        w.Meta = StringBuilder.Create();
        w.MetaCount = new int[1];
        w.MetaIds = Dictionary<string, string>.Create();
        w.Dbg = new string[] { "", "", "", "", "" };
        w.DbgScopes = List<string>.Create();
        w.DbgGlobals = List<string>.Create();
        return w;
    }

    // ---- names ----

    string NewTemp()
    {
        S[0].Temp += 1;
        return "%t" + S[0].Temp.ToString();
    }

    string NewLabel(string hint)
    {
        S[0].Label += 1;
        return hint + "." + S[0].Label.ToString();
    }

    string NewGlobal(string prefix)
    {
        S[0].Global += 1;
        return "@" + prefix + "." + S[0].Global.ToString();
    }

    // ---- constants ----

    static string Hex2(int value)
    {
        string digits = "0123456789ABCDEF";
        return digits.Substring((value >> 4) & 15, 1) + digits.Substring(value & 15, 1);
    }

    // The bytes of a string as an LLVM c"..." literal (without the terminating NUL).
    static string EscapeBytes(string s)
    {
        var sb = StringBuilder.Create();
        for (var i = 0; i < s.Length; i += 1)
        {
            char c = s[i];
            if (c >= 32 && c < 127 && c != '"' && c != '\\')
                sb.Append(c);
            else
                sb.Append("\\" + Hex2((int)c));
        }
        return sb.ToString();
    }

    // A NUL-terminated C string constant (for printf formats and messages).
    string CString(string s)
    {
        var found = Literals.TryGet("c:" + s);
        if (found is string existing)
            return existing;
        string name = NewGlobal("cstr");
        Globals.Append(name + " = private constant [" + (s.Length + 1).ToString() + " x i8] c\"" + EscapeBytes(s) + "\\00\"\n");
        Literals.Set("c:" + s, name);
        return name;
    }

    // A string literal: a heap block header that never reaches a zero count (immortal), followed by the bytes.
    // Block layout: { size refcount, size length, bytes... } (size: i64, or i32 on a 32-bit target).
    string StringLiteral(string s)
    {
        var found = Literals.TryGet("s:" + s);
        if (found is string existing)
            return existing;
        string name = NewGlobal("str");
        string arr = "[" + (s.Length + 1).ToString() + " x i8]";
        string size = Target.SizeIr;
        Globals.Append(name + " = private global { " + size + ", " + size + ", " + arr + " } { " + size + " " + Target.ImmortalCount() + ", " +
                       size + " " + s.Length.ToString() +
                       ", " + arr + " c\"" + EscapeBytes(s) + "\\00\" }\n");
        Literals.Set("s:" + s, name);
        return name;
    }

    // LLVM writes floating point constants as the hex digits of the double.
    static string DoubleConst(double value)
    {
        return "0x" + DoubleBits(value).ToUpper();
    }

    static string FloatConst(double value)
    {
        float narrowed = (float)value;
        return DoubleConst((double)narrowed);
    }

    // The elements of a constant slice: an array block like a string literal's (immortal, never freed).
    // 'items' are the typed element constants ("i32 5", "ptr @str.3").
    string ConstArrayBlock(string elemIr, string[] items)
    {
        string arr = "[" + items.Length.ToString() + " x " + elemIr + "]";
        string init = items.Length == 0 ? "zeroinitializer" : "[" + string.Join(", ", items) + "]";
        string key = "a:" + arr + " " + init;
        var found = Literals.TryGet(key);
        if (found is string existing)
            return existing;
        string name = NewGlobal("carr");
        string size = Target.SizeIr;
        Globals.Append(name + " = private global { " + size + ", " + size + ", " + arr + " } { " + size + " " + Target.ImmortalCount() + ", " +
                       size + " " + items.Length.ToString() +
                       ", " + arr + " " + init + " }\n");
        Literals.Set(key, name);
        return name;
    }

    // ---- declarations ----

    // Adds a declaration once ("declare i32 @printf(ptr, ...)").
    void Declare(string name, string declaration)
    {
        if (Declared.Add(name))
            Declares.Append(declaration + "\n");
    }

    // ---- functions ----

    void BeginFunction(string header)
    {
        Body.Clear();
        Allocas.Clear();
        S[0].Temp = 0;
        S[0].InFunction = true;
        // with debug information: the subprogram that DebugFunction prepared, and its first line as the location
        Dbg[0] = Dbg[2];
        Dbg[1] = "";
        Dbg[2] = "";
        Dbg[4] = Dbg[3];
        DbgScopes.Clear();
        if (Dbg[0].Length > 0)
        {
            header += " !dbg " + Dbg[0];
            SetDebugLocArtificial();
        }
        Functions.Append(header + "\n{\nentry:\n");
        S[0].Block = "entry";
        S[0].BlockOpen = true;
        S[0].Live = true;
    }

    // Finishes the function. The allocas go to the top of the entry block.
    void EndFunction()
    {
        if (S[0].BlockOpen)
            Line("unreachable");
        Functions.Append(Allocas.ToString());
        Functions.Append(Body.ToString());
        Functions.Append("}\n\n");
        S[0].InFunction = false;
        Dbg[0] = "";
        Dbg[1] = "";
        DbgScopes.Clear();
    }

    // Function definitions that are written on their own (runtime helpers).
    void AppendFunctionText(string text)
    {
        Functions.Append(text);
        Functions.Append('\n');
    }

    // A helper function that is needed while another function is being written (it goes after the finished functions).
    void AppendHelper(string text)
    {
        Helpers.Append(text);
        Helpers.Append('\n');
    }

    // ---- blocks ----

    bool BlockOpen()
    {
        return S[0].BlockOpen;
    }

    string CurrentBlock()
    {
        return S[0].Block;
    }

    void Line(string text)
    {
        Body.Append("  ");
        Body.Append(text);
        // the source location (LLVM requires one on every call in a function with debug information; phis have none)
        if (Dbg[1].Length > 0 && !text.Contains(" = phi "))
        {
            Body.Append(", !dbg ");
            Body.Append(Dbg[1]);
        }
        Body.Append('\n');
    }

    // Starts a block; the previous block must have been terminated.
    void SetBlock(string label)
    {
        Body.Append(label);
        Body.Append(":\n");
        S[0].Block = label;
        S[0].BlockOpen = true;
        S[0].Live = label == "entry" || Preds.Contains(label);
    }

    // True if the current block can be reached at run time (it is the entry block or something branches to it).
    bool Reachable()
    {
        return S[0].BlockOpen && S[0].Live;
    }

    // After a terminator (return/break/continue) further statements go into a block that nothing jumps to.
    void EnsureInsertPoint()
    {
        if (S[0].BlockOpen)
            return;
        SetBlock(NewLabel("dead"));
    }

    // ---- capturing code ----
    //
    // Code that has to be placed after code that is generated later (the branches of '?:' need the common type of
    // both branches for their conversions) is cut out of the body and appended again when it is complete.

    int Mark()
    {
        return Body.Length();
    }

    // The code written since 'mark'; it is removed from the body.
    string TakeSince(int mark)
    {
        string text = Body.Substring(mark);
        Body.Truncate(mark);
        return text;
    }

    void AppendCode(string text)
    {
        Body.Append(text);
    }

    // Continues in a block that was captured: its label and state (the block must be open).
    void ResumeBlock(string label)
    {
        S[0].Block = label;
        S[0].BlockOpen = true;
    }

    // A branch is only written if the current block is still open (code after 'return' is dead).
    void Br(string label)
    {
        if (!S[0].BlockOpen)
            return;
        Line("br label %" + label);
        Preds.Add(label);
        S[0].BlockOpen = false;
    }

    void CondBr(string cond, string thenLabel, string elseLabel)
    {
        if (!S[0].BlockOpen)
            return;
        Line("br i1 " + cond + ", label %" + thenLabel + ", label %" + elseLabel);
        Preds.Add(thenLabel);
        Preds.Add(elseLabel);
        S[0].BlockOpen = false;
    }

    void Ret(string type, string value)
    {
        if (!S[0].BlockOpen)
            return;
        if (type == "void")
            Line("ret void");
        else
            Line("ret " + type + " " + value);
        S[0].BlockOpen = false;
    }

    void Unreachable()
    {
        if (!S[0].BlockOpen)
            return;
        Line("unreachable");
        S[0].BlockOpen = false;
    }

    // ---- instructions ----

    string Alloca(string type, string name)
    {
        S[0].Temp += 1;
        string slot = "%" + name + "." + S[0].Temp.ToString();
        Allocas.Append("  " + slot + " = alloca " + type + "\n");
        return slot;
    }

    string Load(string type, string ptr)
    {
        string t = NewTemp();
        Line(t + " = load " + type + ", ptr " + ptr);
        return t;
    }

    void Store(string type, string value, string ptr)
    {
        Line("store " + type + " " + value + ", ptr " + ptr);
    }

    // Binary operation: add, sub, mul, sdiv, udiv, srem, urem, and, or, xor, shl, ashr, lshr, fadd, ...
    string Bin(string op, string type, string a, string b)
    {
        string t = NewTemp();
        Line(t + " = " + op + " " + type + " " + a + ", " + b);
        return t;
    }

    string ICmp(string pred, string type, string a, string b)
    {
        string t = NewTemp();
        Line(t + " = icmp " + pred + " " + type + " " + a + ", " + b);
        return t;
    }

    string FCmp(string pred, string type, string a, string b)
    {
        string t = NewTemp();
        Line(t + " = fcmp " + pred + " " + type + " " + a + ", " + b);
        return t;
    }

    string Select(string cond, string type, string a, string b)
    {
        string t = NewTemp();
        Line(t + " = select i1 " + cond + ", " + type + " " + a + ", " + type + " " + b);
        return t;
    }

    // Conversion: trunc, zext, sext, fptrunc, fpext, fptosi, fptoui, sitofp, uitofp, ptrtoint, inttoptr, bitcast
    string Cast(string op, string fromType, string value, string toType)
    {
        string t = NewTemp();
        Line(t + " = " + op + " " + fromType + " " + value + " to " + toType);
        return t;
    }

    string Gep(string elemType, string ptr, string indices)
    {
        string t = NewTemp();
        Line(t + " = getelementptr inbounds " + elemType + ", ptr " + ptr + ", " + indices);
        return t;
    }

    // Byte offset from a pointer.
    string ByteGep(string ptr, string offset)
    {
        string t = NewTemp();
        Line(t + " = getelementptr i8, ptr " + ptr + ", " + Target.SizeIr + " " + offset);
        return t;
    }

    string ExtractValue(string aggType, string agg, string indices)
    {
        string t = NewTemp();
        Line(t + " = extractvalue " + aggType + " " + agg + ", " + indices);
        return t;
    }

    string InsertValue(string aggType, string agg, string valueType, string value, string indices)
    {
        string t = NewTemp();
        Line(t + " = insertvalue " + aggType + " " + agg + ", " + valueType + " " + value + ", " + indices);
        return t;
    }

    // A call; 'args' is the finished argument list, e.g. "i32 %t1, ptr %t2". Returns the result ("" for void).
    string Call(string retType, string callee, string args)
    {
        if (retType == "void")
        {
            Line("call void " + callee + "(" + args + ")");
            return "";
        }
        string t = NewTemp();
        Line(t + " = call " + retType + " " + callee + "(" + args + ")");
        return t;
    }

    // Call of a variadic function: the function type in front of the callee is needed.
    string CallVariadic(string retType, string fixedTypes, string callee, string args)
    {
        string t = NewTemp();
        Line(t + " = call " + retType + " (" + fixedTypes + ", ...) " + callee + "(" + args + ")");
        return t;
    }

    string Phi(string type, string incoming)
    {
        string t = NewTemp();
        Line(t + " = phi " + type + " " + incoming);
        return t;
    }

    // ---- debug information ----

    // A metadata node: "!<n> = <text>" (the same text gives the same node, unless it is distinct).
    string MetaNode(string text)
    {
        bool distinct = text.StartsWith("distinct ");
        if (!distinct)
        {
            var found = MetaIds.TryGet(text);
            if (found is string existing)
                return existing;
        }
        string id = "!" + MetaCount[0].ToString();
        MetaCount[0] += 1;
        Meta.Append(id + " = " + text + "\n");
        if (!distinct)
            MetaIds.Set(text, id);
        return id;
    }

    // A metadata string: "...", with the characters LLVM needs escaped.
    static string MetaString(string s)
    {
        var sb = StringBuilder.Create();
        sb.Append('"');
        for (var i = 0; i < s.Length; i += 1)
        {
            char c = s[i];
            if (c >= 32 && c < 127 && c != '"' && c != '\\')
                sb.Append(c);
            else
                sb.Append("\\" + Hex2((int)c));
        }
        sb.Append('"');
        return sb.ToString();
    }

    // The file node of a source file ("dir/name.csh": the directory and the name).
    string DebugFile(string directory, string name)
    {
        return MetaNode("!DIFile(filename: " + MetaString(name) + ", directory: " + MetaString(directory) + ")");
    }

    // The compile unit; it is created once, with the main file of the program, and written at the end of the module
    // (DebugModuleText), when its global variables are known.
    string DebugUnit(string file)
    {
        var found = MetaIds.TryGet("unit");
        if (found is string existing)
            return existing;
        string id = MetaReserve();
        MetaIds.Set("unit", id);
        MetaIds.Set("unit file", file);
        return id;
    }

    // A global variable of the program: the node to attach to its definition (", !dbg !N").
    string DebugGlobal(string name, string unit, string file, int line, string type)
    {
        string v = MetaNode("distinct !DIGlobalVariable(name: " + MetaString(name) + ", scope: " + unit + ", file: " + file +
                            ", line: " + line.ToString() + ", type: " + type + ", isLocal: true, isDefinition: true)");
        string e = MetaNode("!DIGlobalVariableExpression(var: " + v + ", expr: !DIExpression())");
        DbgGlobals.Add(e);
        return e;
    }

    // Prepares the subprogram of the function that the next BeginFunction starts.
    void DebugFunction(string name, string file, string unit, int line)
    {
        string type = MetaNode("!DISubroutineType(types: " + MetaNode("!{}") + ")");
        Dbg[3] = file;
        Dbg[2] = MetaNode("distinct !DISubprogram(name: " + MetaString(name) + ", scope: " + file + ", file: " + file +
                          ", line: " + line.ToString() + ", type: " + type + ", scopeLine: " + line.ToString() +
                          ", spFlags: DISPFlagDefinition, unit: " + unit + ")");
    }

    // The innermost scope: the open lexical block, or the function.
    string DebugScope()
    {
        return DbgScopes.Count() > 0 ? DbgScopes.Get(DbgScopes.Count() - 1) : Dbg[0];
    }

    // The source location of the instructions that follow (inside a function with a subprogram).
    void SetDebugLoc(int line, int col)
    {
        if (Dbg[0].Length == 0 || line <= 0)
            return;
        Dbg[1] = MetaNode("!DILocation(line: " + line.ToString() + ", column: " + col.ToString() + ", scope: " + DebugScope() + ")");
    }

    // Code that belongs to no line (line 0): the prologue that stores the parameters, so that a debugger stops after it
    // (at the first line of the body) when it stops at a function.
    void SetDebugLocArtificial()
    {
        if (Dbg[0].Length > 0)
            Dbg[1] = MetaNode("!DILocation(line: 0, scope: " + DebugScope() + ")");
    }

    // A block of the source with variables of its own ({ ... }, a loop): variables declared in it are only visible
    // while the program is in it, so two variables with the same name in different blocks do not mix.
    void PushDebugScope(int line, int col)
    {
        if (Dbg[0].Length == 0)
            return;
        DbgScopes.Add(MetaNode("distinct !DILexicalBlock(scope: " + DebugScope() + ", file: " + Dbg[4] + ", line: " +
                               line.ToString() + ", column: " + col.ToString() + ")"));
    }

    void PopDebugScope()
    {
        if (DbgScopes.Count() > 0)
            DbgScopes.RemoveAt(DbgScopes.Count() - 1);
    }

    // A node whose text is written later (for types that refer to themselves).
    string MetaReserve()
    {
        string id = "!" + MetaCount[0].ToString();
        MetaCount[0] += 1;
        return id;
    }

    void MetaDefine(string id, string text)
    {
        Meta.Append(id + " = " + text + "\n");
    }

    // A local variable (arg > 0: the parameter with this number) in the current scope; 'slot' is its alloca.
    void DebugVariable(string name, int arg, string type, string slot, int line)
    {
        if (Dbg[0].Length == 0)
            return;
        string v = MetaNode("!DILocalVariable(name: " + MetaString(name) + (arg > 0 ? ", arg: " + arg.ToString() : "") +
                            ", scope: " + (arg > 0 ? Dbg[0] : DebugScope()) + ", file: " + Dbg[4] + ", line: " + line.ToString() +
                            ", type: " + type + ")");
        Declare("@llvm.dbg.declare", "declare void @llvm.dbg.declare(metadata, metadata, metadata)");
        Line("call void @llvm.dbg.declare(metadata ptr " + slot + ", metadata " + v + ", metadata !DIExpression())");
    }

    // The named metadata that tells LLVM about the debug information ("" without any).
    string DebugModuleText()
    {
        var unit = MetaIds.TryGet("unit");
        string cu = unit is string found ? found : "";
        if (cu.Length == 0)
            return "";
        var unitFile = MetaIds.TryGet("unit file");
        string globals = DbgGlobals.Count() > 0 ? ", globals: " + MetaNode("!{" + string.Join(", ", DbgGlobals.ToArray()) + "}") : "";
        MetaDefine(cu, "distinct !DICompileUnit(language: DW_LANG_C, file: " + (unitFile is string f ? f : "null") +
                       ", producer: \"cshiftc\", isOptimized: false, runtimeVersion: 0, emissionKind: FullDebug" + globals + ")");
        string version = MetaNode("!{i32 7, !\"Dwarf Version\", i32 4}");
        string info = MetaNode("!{i32 2, !\"Debug Info Version\", i32 3}");
        return "\n!llvm.dbg.cu = !{" + cu + "}\n!llvm.module.flags = !{" + version + ", " + info + "}\n" + Meta.ToString();
    }

    // ---- the module ----

    string ModuleText(string triple)
    {
        var sb = StringBuilder.Create();
        sb.Append("; cshc\n");
        if (triple.Length > 0)
            sb.Append("target triple = \"" + triple + "\"\n\n");
        sb.Append(Globals.ToString());
        sb.Append('\n');
        sb.Append(Functions.ToString());
        sb.Append(Declares.ToString());
        return sb.ToString();
    }
}
