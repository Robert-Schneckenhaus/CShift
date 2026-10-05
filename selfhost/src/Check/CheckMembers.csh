// The checker for members and calls through them (obj.Name, Type.Name, Namespace.F(...), Console.WriteLine(...),
// string and number methods), indexing, slices, 'new' and struct initializers. It follows EmitMember, EmitMemberCall,
// EmitBuiltinStatic, EmitBuiltinMethod, EmitIndex/EmitElement, EmitSlice, EmitNewArray, EmitNewObject and
// EmitStructInit, with the same messages; a case it does not follow yet has the unknown type.

namespace CShift.Check;

using System;
using CShift.Syntax;
using CShift.Sema;
using CShift.CodeGen;

// True if 'obj.Name' / 'obj.Method()' may start with a type, a namespace or a builtin name (Console, Math, ...)
// rather than a value (see EmitMember and EmitMemberCall).
bool IsStaticPath(const ref Compiler cg, Expr obj, string member, SourceLoc loc)
{
    string dotted = DottedName(cg, obj);
    if (dotted.Length == 0)
        return false;
    string first = dotted.Split('.')[0].ToString();
    if (ColorColorMeansType(cg, dotted, member, loc))
        return true;
    if (IsLocalName(cg, first))
        return false;
    int owner = CurrentOwner(cg);
    return owner == 0 || !FindField(cg, owner, first).Found;
}

// "" if the current code may use an unsafe operation, otherwise the message (see RequireUnsafe).
string UnsafeError(const ref Compiler cg, string what)
{
    return cg.Fn[0].UnsafeDepth == 0 ? what + " is only allowed in an 'unsafe' context" : "";
}

// Reports the message if it is not empty; true if it was.
bool ReportIf(const ref Compiler cg, SourceLoc loc, string message)
{
    if (message.Length == 0)
        return false;
    if (message != AlreadyReported())
        CheckError(cg, loc, message);
    return true;
}

// The reason of a decision that failed because of an error reported before (an unknown type): not reported again.
string AlreadyReported()
{
    return "(already reported)";
}

// ---------------------------------------------------------------------------
// obj.Name, Type.Name
// ---------------------------------------------------------------------------

Value CheckMember(const ref Compiler cg, Expr e)
{
    var types = cg.Types;
    var m = cg.Tree.GetMember(e);
    int file = cg.Fn[0].File;
    if (m.NameLoc.Line > 0)
        e.Loc = m.NameLoc; // errors point at the member's name, not at the '.' (the place of the node)

    int metaEnum = EnumMetaType(cg, m.Object, file, cg.Fn[0].Env);
    if (metaEnum != 0)
        return ConstToValue(cg, EnumMeta(cg, metaEnum, m.Name, e.Loc));

    string dotted = DottedName(cg, m.Object);
    bool colorColor = dotted.Length > 0 && ColorColorMeansType(cg, dotted, m.Name, e.Loc);
    if (dotted.Length > 0 && (!IsLocalName(cg, dotted.Split('.')[0].ToString()) || colorColor))
    {
        int prim = PrimitiveType(cg, dotted);
        if (prim != 0)
        {
            var constant = Value { };
            if (EmitBuiltinStaticMember(cg, prim, m.Name, ref constant))
                return constant;
            CheckError(cg, e.Loc, "type '" + dotted + "' has no member '" + m.Name + "'");
            return UnknownValue(cg);
        }
        var entry = TypeDeclEntry { };
        int owner = CurrentOwner(cg);
        if (colorColor || owner == 0 || !FindField(cg, owner, dotted.Split('.')[0].ToString()).Found)
        {
            bool isTypeName = LookupTypeDecl(cg, file, dotted, ref entry);
            if (isTypeName && dotted == "Thread" && m.Name == "Cancelled" && entry.Kind == DeclKind.Struct)
            {
                // see EmitThreadCancelled; a lambda belongs to the function it is written in
                var fi = cg.Instances.Get(cg.Fn[0].Func);
                if (fi.Entry < 0 || !cg.Funcs.Get(fi.Entry).Decl.IsThread)
                {
                    CheckError(cg, e.Loc, "'Thread.Cancelled' can only be used inside a 'thread' function");
                    return UnknownValue(cg);
                }
                return Rvalue(types.Bool, "", false);
            }
            if (isTypeName && entry.Kind == DeclKind.Enum)
            {
                int et = GetEnumType(cg, entry.Index);
                var einfo = GetEnumInfo(cg, et);
                int member = FindEnumMember(einfo, m.Name);
                IndexTypeName(cg, m.Object.Loc, TypeNameLength(cg, m.Object, dotted), entry, types.Name(et));
                if (member < 0)
                {
                    CheckError(cg, e.Loc, "enum '" + types.Name(et) + "' has no member '" + m.Name + "'");
                    return UnknownValue(cg);
                }
                IndexEnumMember(cg, m.NameLoc, m.Name.Length, entry.Index, et, member);
                return ConstInt(cg, et, einfo.Values[member]);
            }
            if (isTypeName || IsNamespace(cg, file, dotted))
            {
                if (isTypeName)
                    IndexTypeName(cg, m.Object.Loc, TypeNameLength(cg, m.Object, dotted), entry, dotted);
                else
                    IndexNamespace(cg, m.Object, dotted);
                int c = LookupConst(cg, file, dotted + "." + m.Name);
                if (c >= 0)
                {
                    IndexConst(cg, m.NameLoc, m.Name.Length, c);
                    return EmitConst(cg, c, e.Loc);
                }
                int g = LookupGlobal(cg, file, dotted + "." + m.Name);
                if (g >= 0)
                {
                    IndexGlobal(cg, m.NameLoc, m.Name.Length, g);
                    return GlobalUse(cg, g);
                }
                // Type.Method or Namespace.Function as a value: it converts to a matching Action/Func type
                if (isTypeName && entry.Kind == DeclKind.Struct)
                {
                    if (m.TypeArgs.Length > 0 || LastTypeArgs(cg, m.Object).Length > 0 || cg.Structs.Get(entry.Index).Decl.TypeParams.Length > 0)
                        return UnknownValue(cg);
                    int owner = GetStructType(cg, entry.Index, new int[0], e.Loc);
                    var methods = MethodCandidates(cg, owner, m.Name);
                    if (methods.Length > 0)
                        return GroupValue(cg, methods, new int[0], cg.Types.Name(owner) + "." + m.Name);
                    return UnknownValue(cg);
                }
                var functions = FreeCandidates(cg, file, dotted + "." + m.Name);
                if (functions.Length > 0)
                    return m.TypeArgs.Length > 0 ? UnknownValue(cg) : GroupValue(cg, functions, new int[0], dotted + "." + m.Name);
                CheckError(cg, e.Loc, "'" + dotted + "' has no value member '" + m.Name + "'");
                return UnknownValue(cg);
            }
        }
    }

    Value obj = SettleChecked(cg, CheckExpr(cg, m.Object)); // [1, 2].Length: an array
    int t = obj.Type;
    if (types.IsUnknown(t) || m.ViaArrow)
        return UnknownValue(cg);
    if (types.IsPointer(t))
    {
        CheckError(cg, e.Loc, "use '->' to access members through a pointer");
        return UnknownValue(cg);
    }
    if (types.IsStruct(t))
    {
        IndexField(cg, m.NameLoc, t, m.Name);
        return CheckField(cg, obj, m.Name, e.Loc);
    }
    if (m.Name == "Length" && (types.IsString(t) || types.IsArray(t) || types.IsSlice(t)))
        return IndexBuiltinMember(cg, m, t, Rvalue(types.I32, "", false), "");
    if (m.Name == "Length" && types.IsFixed(t))
        return IndexBuiltinMember(cg, m, t, ConstInt(cg, types.I32, (int64)types.Count(t)), " = " + types.Count(t).ToString());
    if (types.IsError(t) && m.Name == "Message")
        return IndexBuiltinMember(cg, m, t, Rvalue(types.String, "", false), "");
    if (types.IsError(t) && m.Name == "Code")
        return IndexBuiltinMember(cg, m, t, Rvalue(types.Code(t) != 0 ? types.Code(t) : types.I32, "", false), "");
    CheckError(cg, e.Loc, "type '" + types.Name(t) + "' has no member '" + m.Name + "'");
    return UnknownValue(cg);
}

// ---------------------------------------------------------------------------
// obj.Method(args), Type.Method(args), Namespace.Function(args), Console.WriteLine(...)
// ---------------------------------------------------------------------------

Value CheckMemberCall(const ref Compiler cg, Expr e, CallExpr call, MemberExpr m, bool viaStart)
{
    var types = cg.Types;
    int file = cg.Fn[0].File;
    bool known = true;
    string dotted = DottedName(cg, m.Object);
    if (IsStaticPath(cg, m.Object, m.Name, e.Loc))
    {
        string startError = viaStart ? "'start' can only be used with a direct call to a 'thread' function" : "";
        if (dotted == "Console" || dotted == "Environment" || dotted == "Memory")
        {
            var builtinArgs = CheckArgs(cg, call.Args, ref known);
            if (ReportIf(cg, e.Loc, startError))
                return UnknownValue(cg);
            Value builtin = CheckBuiltinStatic(cg, dotted, m.Name, builtinArgs, e.Loc);
            if (m.Object.Kind == ExprKind.Name)
                IndexAt(cg, m.Object.Loc, dotted.Length, SourceLoc { }, "namespace " + dotted + " (built-in)");
            IndexBuiltinCall(cg, m.NameLoc, dotted, m.Name, builtinArgs, builtin, false, cg.Index.Count());
            return builtin;
        }
        var entry = TypeDeclEntry { };
        if (dotted == "Array")
        {
            CheckArgs(cg, call.Args, ref known);
            if (!ReportIf(cg, e.Loc, startError) && m.Name != "Copy")
                CheckError(cg, e.Loc, "Array has no function '" + m.Name + "'");
            return UnknownValue(cg); // Array.Copy: checked by code generation for now
        }
        if (dotted == "string")
        {
            var stringArgs = CheckArgs(cg, call.Args, ref known);
            if (ReportIf(cg, e.Loc, startError))
                return UnknownValue(cg);
            if (m.Name == "FromCStr" || m.Name == "FromBytes")
            {
                Value fromC = Rvalue(types.String, "", false);
                IndexBuiltinCall(cg, m.NameLoc, "string", m.Name, stringArgs, fromC, true, cg.Index.Count());
                return fromC;
            }
            var cands = FreeCandidates(cg, file, "String." + m.Name);
            if (cands.Length == 0)
            {
                CheckError(cg, e.Loc, "type 'string' has no static method '" + m.Name + "'");
                return UnknownValue(cg);
            }
            return CheckResolvedCallAt(cg, cands, stringArgs, known, new int[0], m.Name, e.Loc, m.NameLoc);
        }
        if (dotted == "SharedPtr" && !LookupTypeDecl(cg, file, dotted, ref entry))
        {
            CheckArgs(cg, call.Args, ref known);
            return UnknownValue(cg);
        }
        if (PrimitiveType(cg, dotted) != 0)
        {
            CheckArgs(cg, call.Args, ref known);
            CheckError(cg, e.Loc, "cshc does not support '" + dotted + "." + m.Name + "' yet");
            return UnknownValue(cg);
        }
        if (LookupTypeDecl(cg, file, dotted, ref entry))
        {
            UseBareThread(cg, file, dotted, LastTypeArgs(cg, m.Object).Length, ref entry);
            if (entry.Kind != DeclKind.Struct)
            {
                CheckArgs(cg, call.Args, ref known);
                CheckError(cg, e.Loc, "cshc does not support enums and interfaces yet ('" + dotted + "')");
                return UnknownValue(cg);
            }
            int st = GetStructType(cg, entry.Index, ResolveTypeArgs(cg, LastTypeArgs(cg, m.Object)), e.Loc);
            if (types.IsUnknown(st))
            {
                CheckArgs(cg, call.Args, ref known);
                return UnknownValue(cg); // List<Foo>.Create() with an unknown Foo
            }
            IndexTypeName(cg, m.Object.Loc, TypeNameLength(cg, m.Object, dotted), entry, types.Name(st));
            var scands = MethodCandidates(cg, st, m.Name);
            var targs = CheckArgsFor(cg, call.Args, scands, ref known);
            if (scands.Length == 0)
            {
                CheckError(cg, e.Loc, "struct '" + types.Name(st) + "' has no method '" + m.Name + "'");
                return UnknownValue(cg);
            }
            if (!known)
                return UnknownValue(cg);
            string why = "";
            int instance = CheckOverload(cg, scands, targs, ResolveTypeArgs(cg, m.TypeArgs), e.Loc, m.Name, ref why);
            if (ReportIf(cg, e.Loc, why))
                return UnknownValue(cg);
            IndexFunction(cg, m.NameLoc, m.Name.Length, instance);
            var fi = cg.Instances.Get(instance);
            if (fi.HasThis)
            {
                CheckError(cg, e.Loc, "'" + types.Name(st) + "." + m.Name + "' is an instance method and needs an object");
                return UnknownValue(cg);
            }
            if (m.Name.Length > 0 && m.Name[0] == '_' && CurrentOwner(cg) != fi.Owner)
            {
                CheckError(cg, e.Loc, "method '" + m.Name + "' is private to '" + types.Name(fi.Owner) + "'");
                return UnknownValue(cg);
            }
            return CheckThreadUse(cg, instance, viaStart, "the 'thread' method '" + types.Name(st) + "." + m.Name + "' must be prefixed with 'start'",
                                  types.Name(st) + "." + m.Name, e.Loc);
        }
        if (IsNamespace(cg, file, dotted))
        {
            var ncands = FreeCandidates(cg, file, dotted + "." + m.Name);
            IndexNamespace(cg, m.Object, dotted);
            var nargs = CheckArgsFor(cg, call.Args, ncands, ref known);
            if (ncands.Length == 0)
            {
                CheckError(cg, e.Loc, "namespace '" + dotted + "' has no function '" + m.Name + "'");
                return UnknownValue(cg);
            }
            if (!known)
                return UnknownValue(cg);
            string why = "";
            int instance = CheckOverload(cg, ncands, nargs, ResolveTypeArgs(cg, m.TypeArgs), e.Loc, m.Name, ref why);
            if (ReportIf(cg, e.Loc, why))
                return UnknownValue(cg);
            IndexFunction(cg, m.NameLoc, m.Name.Length, instance);
            return CheckThreadUse(cg, instance, viaStart, "the 'thread' function '" + dotted + "." + m.Name + "' must be prefixed with 'start'",
                                  dotted + "." + m.Name, e.Loc);
        }
    }

    // an instance call
    if (viaStart)
    {
        CheckError(cg, e.Loc, "'start' can only be used with a direct call to a 'thread' function");
        CheckArgs(cg, call.Args, ref known);
        return UnknownValue(cg);
    }
    Value obj = SettleChecked(cg, CheckExpr(cg, m.Object));
    int t = obj.Type;
    if (types.IsPointer(t) && !m.ViaArrow)
    {
        CheckError(cg, e.Loc, "use '->' to call methods through a pointer");
        CheckArgs(cg, call.Args, ref known);
        return UnknownValue(cg);
    }
    if (types.IsStruct(t) && MethodCandidates(cg, t, m.Name).Length == 0)
    {
        var fieldPath = FindField(cg, t, m.Name);
        if (fieldPath.Found && IsCallableType(cg, fieldPath.Type))
        {
            IndexField(cg, m.NameLoc, t, m.Name); // a field with a function type, called like a method
            CheckArgs(cg, call.Args, ref known);
            return UnknownValue(cg);
        }
    }
    var args = types.IsStruct(t) && !m.ViaArrow ? CheckArgsFor(cg, call.Args, MethodCandidates(cg, t, m.Name), ref known) : CheckArgs(cg, call.Args, ref known);
    if (types.IsUnknown(t) && !m.ViaArrow && m.Object.Kind == ExprKind.Name)
        ReportIf(cg, e.Loc, TypeParamMethodError(cg, cg.Tree.GetName(m.Object).Name, m.Name));
    if (types.IsUnknown(t) || m.ViaArrow || (IsCallableType(cg, t) && m.Name == "Invoke"))
        return UnknownValue(cg);
    if (types.Kind(t) == TypeKind.Interface)
        return CheckInterfaceCall(cg, t, m.Name, args, known, e.Loc);
    if (IsUnionType(cg, t))
    {
        // a method of one of the union's interfaces (see EmitUnionCall)
        foreach (var iface in GetUnionInfo(cg, t).Interfaces)
        {
            int count = InterfaceMethodCount(cg, iface);
            for (var k = 0; k < count; k += 1)
            {
                if (InterfaceMethod(cg, iface, k).Name == m.Name)
                    return CheckInterfaceCall(cg, iface, m.Name, args, known, e.Loc);
            }
        }
        CheckError(cg, e.Loc, "union '" + types.Name(t) + "' has no method '" + m.Name + "' (it can call the methods of the interfaces it lists)");
        return UnknownValue(cg);
    }
    if (!types.IsStruct(t))
    {
        int before = cg.Index.Count();
        Value r = CheckBuiltinMethod(cg, obj, m.Name, args, known, e.Loc, m.NameLoc);
        IndexBuiltinCall(cg, m.NameLoc, types.Name(t), m.Name, args, r, false, before);
        return r;
    }
    return CheckMethodCallOnAt(cg, obj, m.Name, args, known, ResolveTypeArgs(cg, m.TypeArgs), e.Loc, m.NameLoc);
}

// A 'thread' function is only called with 'start', and 'start' only calls 'thread' functions (see EmitMemberCall).
Value CheckThreadUse(const ref Compiler cg, int instance, bool viaStart, string mustStart, string name, SourceLoc loc)
{
    if (IsThreadInstance(cg, instance))
    {
        if (!viaStart)
            CheckError(cg, loc, "call to " + mustStart);
        return UnknownValue(cg);
    }
    if (viaStart)
    {
        CheckError(cg, loc, "'start' can only be used with a 'thread' function, not '" + name + "'");
        return UnknownValue(cg);
    }
    return Rvalue(cg.Instances.Get(instance).Ret, "", false);
}

// A call of a function that was found by name: the overload and its result.
Value CheckResolvedCall(const ref Compiler cg, Candidate[] cands, Arg[] args, bool known, int[] typeArgs, string name, SourceLoc loc)
{
    return CheckResolvedCallAt(cg, cands, args, known, typeArgs, name, loc, SourceLoc { });
}

// ... with the place of the function's name for the symbol index (Line 0: not indexed).
Value CheckResolvedCallAt(const ref Compiler cg, Candidate[] cands, Arg[] args, bool known, int[] typeArgs, string name, SourceLoc loc, SourceLoc nameLoc)
{
    if (!known)
    {
        IndexCandidates(cg, nameLoc, name.Length, cands);
        return UnknownValue(cg);
    }
    string why = "";
    int instance = CheckOverload(cg, cands, args, typeArgs, loc, name, ref why);
    if (ReportIf(cg, loc, why))
        return UnknownValue(cg);
    IndexFunction(cg, nameLoc, name.Length, instance);
    return Rvalue(cg.Instances.Get(instance).Ret, "", false);
}

// obj.Method(args) for a struct value (see EmitMethodCallOn).
Value CheckMethodCallOn(const ref Compiler cg, Value obj, string name, Arg[] args, bool known, int[] typeArgs, SourceLoc loc)
{
    return CheckMethodCallOnAt(cg, obj, name, args, known, typeArgs, loc, SourceLoc { });
}

// ... with the place of the method's name for the symbol index (Line 0: not indexed).
Value CheckMethodCallOnAt(const ref Compiler cg, Value obj, string name, Arg[] args, bool known, int[] typeArgs, SourceLoc loc, SourceLoc nameLoc)
{
    var types = cg.Types;
    var cands = MethodCandidates(cg, obj.Type, name);
    if (cands.Length == 0)
    {
        CheckError(cg, loc, "struct '" + types.Name(obj.Type) + "' has no method '" + name + "'");
        return UnknownValue(cg);
    }
    if (!known)
    {
        IndexCandidates(cg, nameLoc, name.Length, cands);
        return UnknownValue(cg);
    }
    string why = "";
    int instance = CheckOverload(cg, cands, args, typeArgs, loc, name, ref why);
    if (ReportIf(cg, loc, why))
    {
        IndexCandidates(cg, nameLoc, name.Length, cands);
        return UnknownValue(cg);
    }
    IndexFunction(cg, nameLoc, name.Length, instance);
    var fi = cg.Instances.Get(instance);
    if (!fi.HasThis)
    {
        CheckError(cg, loc, "'" + name + "' is a static method, call it as '" + types.Name(fi.Owner) + "." + name + "(...)'");
        return UnknownValue(cg);
    }
    if (name.Length > 0 && name[0] == '_' && CurrentOwner(cg) != fi.Owner)
    {
        CheckError(cg, loc, "method '" + name + "' is private to '" + types.Name(fi.Owner) + "'");
        return UnknownValue(cg);
    }
    return Rvalue(fi.Ret, "", false);
}

// Console, Environment and Memory (see EmitBuiltinStatic).
Value CheckBuiltinStatic(const ref Compiler cg, string type, string method, Arg[] args, SourceLoc loc)
{
    var types = cg.Types;
    Value none = Rvalue(types.Void, "", false);
    if (type == "Console")
    {
        bool toStderr = method == "WriteError" || method == "WriteErrorLine";
        if (method != "Write" && method != "WriteLine" && !toStderr)
        {
            CheckError(cg, loc, "Console has no function '" + method + "'");
            return none;
        }
        bool newline = method == "WriteLine" || method == "WriteErrorLine";
        if (args.Length > 1)
            CheckError(cg, loc, "Console." + method + " takes at most one argument");
        else if (args.Length == 0 && !newline)
            CheckError(cg, loc, "Console.Write needs an argument");
        else if (args.Length == 1)
            ReportIf(cg, args[0].Source.Loc, TextConversionError(cg, args[0].V.Type));
        return none;
    }
    if (type == "Memory" && method == "CopyForThread")
    {
        if (args.Length != 1)
        {
            CheckError(cg, loc, "Memory.CopyForThread takes one argument");
            return UnknownValue(cg);
        }
        int t = args[0].V.Type;
        if (types.IsUnknown(t))
            return UnknownValue(cg);
        if (!IsThreadTransferable(cg, t))
        {
            CheckError(cg, loc, "'" + types.Name(t) + "' cannot be copied for another thread (only values, strings, SharedPtr<T> of " +
                                "thread-safe values, and Optional<T>/Error<T>/structs of them)");
            return UnknownValue(cg);
        }
        return Rvalue(t, "", false);
    }
    if (type == "Memory")
    {
        if (ReportIf(cg, loc, UnsafeError(cg, "Memory." + method)))
            return UnknownValue(cg);
        if (method == "Allocate")
        {
            if (args.Length != 1)
                CheckError(cg, loc, "Memory.Allocate takes one argument (size in bytes)");
            else if (!types.IsUnknown(args[0].V.Type) && !types.IsIntegral(args[0].V.Type))
                CheckError(cg, loc, "Memory.Allocate needs an integer size");
            return Rvalue(types.PointerTo(types.Void), "", false);
        }
        if (method == "Free")
        {
            if (args.Length != 1)
                CheckError(cg, loc, "Memory.Free takes one argument");
            else if (!types.IsUnknown(args[0].V.Type) && !types.IsPointer(args[0].V.Type) && types.Kind(args[0].V.Type) != TypeKind.Null)
                CheckError(cg, loc, "Memory.Free needs a pointer");
            return none;
        }
        if (method == "VolatileRead" || method == "VolatileWrite")
        {
            bool write = method == "VolatileWrite";
            if (args.Length != (write ? 2 : 1))
            {
                CheckError(cg, loc, write ? "Memory.VolatileWrite takes two arguments (pointer, value)" : "Memory.VolatileRead takes one argument (pointer)");
                return UnknownValue(cg);
            }
            int pt = args[0].V.Type;
            string why = VolatileTargetError(cg, pt, method);
            if (why.Length > 0)
            {
                CheckError(cg, loc, why);
                return UnknownValue(cg);
            }
            if (types.IsUnknown(pt) || types.IsUnknown(types.Elem(pt)))
                return write ? none : UnknownValue(cg);
            if (write)
            {
                CheckConversion(cg, args[1].V, types.Elem(pt), loc);
                return none;
            }
            return Rvalue(types.Elem(pt), "", false);
        }
        CheckError(cg, loc, "Memory has no function '" + method + "'");
        return none;
    }
    // Environment
    if (method == "Exit" || method == "Panic")
    {
        if (args.Length != 1)
            CheckError(cg, loc, method == "Exit" ? "Environment.Exit takes one argument (exit code)" : "Environment.Panic takes one argument (message)");
        else
            CheckConversion(cg, args[0].V, method == "Exit" ? types.I32 : types.String, loc);
        return none;
    }
    CheckError(cg, loc, "Environment has no function '" + method + "'");
    return none;
}

// "" if the call has n arguments, otherwise the message (see ExpectArgs).
string ArgCountError(const ref Compiler cg, Arg[] args, int n, string type, string method)
{
    if (args.Length == n)
        return "";
    return "'" + type + "." + method + "' takes " + n.ToString() + " argument(s)";
}

// Methods of strings, arrays, slices, Fixed values, numbers, bool, enums and SharedPtr (see EmitBuiltinMethod).
Value CheckBuiltinMethod(const ref Compiler cg, Value obj, string method, Arg[] args, bool known, SourceLoc loc, SourceLoc nameLoc)
{
    var types = cg.Types;
    int t = obj.Type;
    string tname = types.Name(t);
    if (method == "ToString" && args.Length == 1 && !types.IsNumeric(t) &&
        (types.IsString(t) || types.IsStringSlice(t) || types.IsBool(t) || types.IsChar(t) || types.IsEnum(t)))
    {
        CheckError(cg, loc, "a number format (like ':F2' or ToString(\"F2\")) is only for numbers, not for '" + tname + "'");
        return UnknownValue(cg);
    }
    if (types.IsSharedPtr(t))
    {
        int elem = types.Elem(t);
        if (method == "IsNull" || method == "Get" || method == "Ptr")
        {
            if (ReportIf(cg, loc, ArgCountError(cg, args, 0, tname, method)))
                return UnknownValue(cg);
            if (method == "IsNull")
                return Rvalue(types.Bool, "", false);
            if (method == "Get")
                return Rvalue(elem, "", false);
            if (ReportIf(cg, loc, UnsafeError(cg, "SharedPtr.Ptr()")))
                return UnknownValue(cg);
            return Rvalue(types.PointerTo(elem), "", false);
        }
    }
    else if (types.IsString(t))
    {
        if (method == "ToString" || method == "Clone" || method == "CStr")
        {
            if (ReportIf(cg, loc, ArgCountError(cg, args, 0, tname, method)))
                return UnknownValue(cg);
            if (method != "CStr")
                return Rvalue(types.String, "", false);
            if (ReportIf(cg, loc, UnsafeError(cg, "string.CStr()")))
                return UnknownValue(cg);
            return Rvalue(types.PointerTo(types.Char), "", false);
        }
        if (method == "AsBytes")
            return ReportIf(cg, loc, ArgCountError(cg, args, 0, tname, method)) ? UnknownValue(cg) : Rvalue(types.ReadOnlySliceOf(types.U8), "", false);
        if (method == "Substring")
        {
            if (args.Length == 0 || args.Length > 2)
                CheckError(cg, loc, "string.Substring takes (start) or (start, length)");
            else
            {
                foreach (var a in args)
                    CheckConversion(cg, a.V, types.I32, loc);
            }
            return Rvalue(types.String, "", false);
        }
        var cands = FreeCandidates(cg, cg.Fn[0].File, "String." + method);
        if (cands.Length > 0)
            return CheckResolvedCallAt(cg, cands, WithSelf(obj, args), known, new int[0], method, loc, nameLoc);
        if (!cg.St[0].StdlibLoaded)
            CheckError(cg, loc, "cshc does not support the string method '" + method + "' yet (the standard library is not loaded)");
        else
            CheckError(cg, loc, "type 'string' has no method '" + method + "'");
        return UnknownValue(cg);
    }
    else if (types.IsArray(t))
    {
        if (method == "Clone")
            return ReportIf(cg, loc, ArgCountError(cg, args, 0, tname, method)) ? UnknownValue(cg) : Rvalue(t, "", false);
    }
    else if (types.IsFixed(t))
    {
        if (method == "ToArray")
            return ReportIf(cg, loc, ArgCountError(cg, args, 0, tname, method)) ? UnknownValue(cg) : Rvalue(types.ArrayOf(types.Elem(t)), "", false);
    }
    else if (types.IsSlice(t))
    {
        if (method == "ToString" && types.IsStringSlice(t))
            return ReportIf(cg, loc, ArgCountError(cg, args, 0, tname, method)) ? UnknownValue(cg) : Rvalue(types.String, "", false);
        if (method == "ToArray" && !types.IsStringSlice(t))
            return ReportIf(cg, loc, ArgCountError(cg, args, 0, tname, method)) ? UnknownValue(cg) : Rvalue(types.ArrayOf(SliceElemType(cg, t)), "", false);
        if (method == "CStr" && types.IsStringSlice(t))
        {
            if (ReportIf(cg, loc, ArgCountError(cg, args, 0, tname, method)) || ReportIf(cg, loc, UnsafeError(cg, "StringSlice.CStr()")))
                return UnknownValue(cg);
            return Rvalue(types.PointerTo(types.Char), "", false);
        }
        if (method == "AsBytes" && types.IsStringSlice(t))
            return ReportIf(cg, loc, ArgCountError(cg, args, 0, tname, method)) ? UnknownValue(cg) : Rvalue(types.ReadOnlySliceOf(types.U8), "", false);
        if (method == "Ptr")
        {
            if (ReportIf(cg, loc, ArgCountError(cg, args, 0, tname, method)) || ReportIf(cg, loc, UnsafeError(cg, tname + ".Ptr()")))
                return UnknownValue(cg);
            return Rvalue(types.PointerTo(SliceElemType(cg, t)), "", false);
        }
        if (types.IsStringSlice(t))
        {
            var cands = FreeCandidates(cg, cg.Fn[0].File, "String." + method);
            if (cands.Length > 0)
                return CheckResolvedCallAt(cg, cands, WithSelf(obj, args), known, new int[0], method, loc, nameLoc);
        }
    }
    else if (types.IsNumeric(t) || types.IsBool(t) || types.IsEnum(t))
    {
        if (method == "ToString")
        {
            if (args.Length == 1 && types.IsNumeric(t))
            {
                var format = args[0];
                if (!format.Source.IsNull() && format.Source.Kind == ExprKind.StringLit)
                    ReportIf(cg, format.Source.Loc, CheckNumberFormat(cg.Tree.GetStringLit(format.Source).Value, types.IsFloat(t)));
                return Rvalue(types.String, "", false);
            }
            return ReportIf(cg, loc, ArgCountError(cg, args, 0, tname, method)) ? UnknownValue(cg) : Rvalue(types.String, "", false);
        }
        if (method == "Equals" || (method == "CompareTo" && types.IsNumeric(t)))
        {
            if (ReportIf(cg, loc, ArgCountError(cg, args, 1, tname, method)))
                return UnknownValue(cg);
            CheckConversion(cg, args[0].V, t, loc);
            return Rvalue(method == "Equals" ? types.Bool : types.I32, "", false);
        }
        if (method == "GetHashCode")
            return ReportIf(cg, loc, ArgCountError(cg, args, 0, tname, method)) ? UnknownValue(cg) : Rvalue(types.I32, "", false);
    }
    CheckError(cg, loc, "type '" + tname + "' has no method '" + method + "'");
    return UnknownValue(cg);
}

// The arguments of an extension-style call: the object first.
Arg[] WithSelf(Value self, Arg[] args)
{
    var all = new Arg[args.Length + 1];
    all[0] = Arg { V = self };
    for (var i = 0; i < args.Length; i += 1)
        all[i + 1] = args[i];
    return all;
}

// ---------------------------------------------------------------------------
// a[i], a[i..j]
// ---------------------------------------------------------------------------

// An index must be an integer (see EmitElement, SliceBound).
void CheckIndexValue(const ref Compiler cg, Expr index)
{
    Value idx = CheckRValue(cg, index);
    if (!IsUnknown(cg, idx) && !cg.Types.IsIntegral(idx.Type))
        CheckError(cg, index.Loc, "an index must be an integer, not '" + cg.Types.Name(idx.Type) + "'");
}

Value CheckIndex(const ref Compiler cg, Expr e)
{
    var types = cg.Types;
    var n = cg.Tree.GetIndex(e);
    Value obj = SettleChecked(cg, CheckExpr(cg, n.Object));
    int t = obj.Type;
    if (types.IsUnknown(t))
    {
        CheckExpr(cg, n.Index);
        return UnknownValue(cg);
    }
    if (types.IsStruct(t))
    {
        if (n.FromEnd)
        {
            CheckError(cg, e.Loc, "'^' (from the end) needs an array, a string or a slice");
            CheckExpr(cg, n.Index);
            return UnknownValue(cg);
        }
        if (MethodCandidates(cg, t, "Get").Length == 0)
        {
            CheckError(cg, e.Loc, "cannot index a value of type '" + types.Name(t) + "' (it has no method 'Get')");
            CheckExpr(cg, n.Index);
            return UnknownValue(cg);
        }
        bool known = true;
        var args = new Arg[1];
        args[0] = Arg { V = CheckRValue(cg, n.Index), Source = n.Index };
        if (IsUnknown(cg, args[0].V))
            known = false;
        return CheckMethodCallOn(cg, obj, "Get", args, known, new int[0], e.Loc);
    }
    if (types.IsSlice(t))
    {
        CheckIndexValue(cg, n.Index);
        int elem = SliceElemType(cg, t);
        if (types.IsStringSlice(t) || types.IsReadOnlySlice(t))
            return Rvalue(elem, "", false);
        return Lvalue(elem, "%e", false);
    }
    if (types.IsFixed(t))
    {
        CheckExpr(cg, n.Index);
        ReportIf(cg, n.Index.Loc, FixedIndexError(cg, t, n.Index, n.FromEnd));
        if (!obj.IsLValue)
            return Rvalue(types.Elem(t), "", false);
        return Lvalue(types.Elem(t), "%e", obj.IsConst);
    }
    if (n.FromEnd && !types.IsArray(t) && !types.IsString(t))
    {
        CheckError(cg, e.Loc, "'^' (from the end) needs an array, a string or a slice, not '" + types.Name(t) + "'");
        CheckExpr(cg, n.Index);
        return UnknownValue(cg);
    }
    if (types.IsArray(t) || types.IsString(t))
    {
        CheckIndexValue(cg, n.Index);
        return types.IsString(t) ? Rvalue(types.Char, "", false) : Lvalue(types.Elem(t), "%e", false);
    }
    CheckIndexValue(cg, n.Index);
    if (types.IsPointer(t))
    {
        if (ReportIf(cg, e.Loc, UnsafeError(cg, "pointer indexing")))
            return UnknownValue(cg);
        if (types.IsVoid(types.Elem(t)))
        {
            CheckError(cg, e.Loc, "cannot index 'void*'");
            return UnknownValue(cg);
        }
        return Lvalue(types.Elem(t), "%e", false);
    }
    CheckError(cg, e.Loc, "cannot index a value of type '" + types.Name(t) + "'");
    return UnknownValue(cg);
}

Value CheckSliceExpr(const ref Compiler cg, Expr e)
{
    var types = cg.Types;
    var n = cg.Tree.GetSlice(e);
    Value obj = SettleChecked(cg, CheckRValue(cg, n.Object));
    int sliceType = types.Unknown;
    if (!IsUnknown(cg, obj))
    {
        sliceType = SliceTypeOf(cg, obj.Type);
        if (sliceType == 0)
        {
            CheckError(cg, e.Loc, "cannot slice a value of type '" + types.Name(obj.Type) + "' (only arrays, strings and slices)");
            sliceType = types.Unknown;
        }
    }
    if (!n.Start.IsNull())
        CheckIndexValue(cg, n.Start);
    if (!n.End.IsNull())
        CheckIndexValue(cg, n.End);
    return Rvalue(sliceType, "", false);
}

// ---------------------------------------------------------------------------
// new T[n], new T[] { ... }, new T(), T { A = 1 }
// ---------------------------------------------------------------------------

Value CheckNewArray(const ref Compiler cg, Expr e)
{
    var types = cg.Types;
    var n = cg.Tree.GetNewArray(e);
    int elem = DeclTypeOf(cg, n.ElemType);
    if (types.IsVoid(elem))
    {
        CheckError(cg, e.Loc, "cannot create an array of 'void'");
        return UnknownValue(cg);
    }
    if (n.HasInit)
    {
        if (!n.Size.IsNull() && (n.Size.Kind != ExprKind.IntLit || (int64)cg.Tree.GetIntLit(n.Size).Value != n.Init.Length))
            CheckError(cg, e.Loc, "the array size must match the number of initializers");
        foreach (var item in n.Init)
            CheckConversion(cg, CheckExprAs(cg, item, elem), elem, cg.Tree.StartOf(item));
    }
    else
    {
        Value size = CheckRValue(cg, n.Size);
        if (!IsUnknown(cg, size) && !types.IsIntegral(size.Type))
            CheckError(cg, n.Size.Loc, "the array size must be an integer");
    }
    return Rvalue(types.ArrayOf(elem), "", false);
}

Value CheckNewObject(const ref Compiler cg, Expr e)
{
    var types = cg.Types;
    if (cg.Tree.GetNewObject(e).Type.IsNull())
    {
        CheckError(cg, e.Loc, TypelessNewError());
        return UnknownValue(cg);
    }
    int t = DeclTypeOf(cg, cg.Tree.GetNewObject(e).Type);
    if (!types.IsStruct(t))
    {
        CheckError(cg, e.Loc, "'new' can only create structs and arrays, not '" + types.Name(t) + "'");
        return UnknownValue(cg);
    }
    return Rvalue(t, "", false);
}

Value CheckStructInit(const ref Compiler cg, Expr e)
{
    var types = cg.Types;
    var n = cg.Tree.GetStructInit(e);
    if (n.Type.IsNull())
    {
        CheckError(cg, e.Loc, TypelessNewError());
        foreach (var f in n.Fields)
            CheckExpr(cg, f.Value);
        return UnknownValue(cg);
    }
    int t = DeclTypeOf(cg, n.Type);
    if (!types.IsStruct(t))
    {
        CheckError(cg, e.Loc, "'" + types.Name(t) + "' is not a struct, initializers are only available for structs");
        foreach (var f in n.Fields)
            CheckExpr(cg, f.Value);
        return UnknownValue(cg);
    }
    return CheckStructInitOf(cg, e, t);
}

// new { ... } / new() as the struct of a target type (see EmitTypelessNew).
Value CheckTypelessNew(const ref Compiler cg, Expr e, int target)
{
    int t = TypelessNewType(cg, target);
    if (t == 0)
    {
        if (!cg.Types.IsUnknown(target))
            CheckError(cg, e.Loc, TypelessNewError());
        if (e.Kind == ExprKind.StructInit)
        {
            foreach (var f in cg.Tree.GetStructInit(e).Fields)
                CheckExpr(cg, f.Value);
        }
        return UnknownValue(cg);
    }
    if (e.Kind == ExprKind.NewObject)
        return Rvalue(t, "", false);
    return CheckStructInitOf(cg, e, t);
}

Value CheckStructInitOf(const ref Compiler cg, Expr e, int t)
{
    var types = cg.Types;
    var n = cg.Tree.GetStructInit(e);
    var seen = HashSet<string>.Create();
    foreach (var f in n.Fields)
    {
        var p = FindField(cg, t, f.Name);
        string why = "";
        if (!p.Found)
            why = "struct '" + types.Name(t) + "' has no field '" + f.Name + "'";
        else if (p.IsPrivate && CurrentOwner(cg) != p.Owner)
            why = "field '" + f.Name + "' is private to '" + types.Name(p.Owner) + "'";
        else if (!seen.Add(f.Name))
            why = "field '" + f.Name + "' is initialized twice";
        ReportIf(cg, f.Loc, why);
        Value v = why.Length == 0 ? CheckExprAs(cg, f.Value, p.Type) : CheckRValue(cg, f.Value);
        if (why.Length == 0)
            CheckConversion(cg, v, p.Type, cg.Tree.StartOf(f.Value));
    }
    return Rvalue(t, "", false);
}

// iface.Method(args) (see EmitInterfaceCall).
Value CheckInterfaceCall(const ref Compiler cg, int iface, string name, Arg[] args, bool known, SourceLoc loc)
{
    if (!known)
        return UnknownValue(cg);
    int chosen = ChooseInterfaceMethod(cg, iface, name, args);
    if (chosen < 0)
    {
        CheckError(cg, loc, "interface '" + cg.Types.Name(iface) + "' has no method '" + name + "' that takes these arguments");
        return UnknownValue(cg);
    }
    return Rvalue(InterfaceMethod(cg, iface, chosen).Ret, "", false);
}
