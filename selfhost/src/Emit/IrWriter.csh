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
    StringBuilder Body;       // the function being written
    StringBuilder Allocas;    // its allocas (they must be in the entry block)
    HashSet<string> Declared;
    HashSet<string> Preds;     // labels that a branch jumps to (to know whether a block can be reached)
    Dictionary<string, string> Literals; // string literals and C strings by content

    static IrWriter Create()
    {
        var w = IrWriter { S = new IrState[1] };
        w.Globals = StringBuilder.Create();
        w.Declares = StringBuilder.Create();
        w.Functions = StringBuilder.Create();
        w.Body = StringBuilder.Create();
        w.Allocas = StringBuilder.Create();
        w.Declared = HashSet<string>.Create();
        w.Preds = HashSet<string>.Create();
        w.Literals = Dictionary<string, string>.Create();
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
    // Block layout: { i64 refcount, i64 length, bytes... }.
    string StringLiteral(string s)
    {
        var found = Literals.TryGet("s:" + s);
        if (found is string existing)
            return existing;
        string name = NewGlobal("str");
        string arr = "[" + (s.Length + 1).ToString() + " x i8]";
        Globals.Append(name + " = private global { i64, i64, " + arr + " } { i64 1152921504606846976, i64 " + s.Length.ToString() +
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
    }

    // Function definitions that are written on their own (runtime helpers).
    void AppendFunctionText(string text)
    {
        Functions.Append(text);
        Functions.Append('\n');
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
        Line(t + " = getelementptr i8, ptr " + ptr + ", i64 " + offset);
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
