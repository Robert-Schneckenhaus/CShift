// Doc comments (docs/language/doc-comments.md): '///' before a declaration documents it, '//!' documents the namespace
// of the file. The text is Markdown with a few tags (@param, @returns, @error, ...) and links to declarations
// ([List<T>.Add]). 'cshiftc doc' writes the documentation of the standard library (or of a program) as JSON and
// checks the comments; 'cshiftc query' shows them in the hover.

namespace CShift.Driver;

using System;
using CShift.Syntax;
using CShift.Sema;
using CShift.CodeGen;
using CShift.Check;

struct DocTag
{
    string Name;    // without the '@'
    string Arg;     // @param/@error: the name it is about; @see: the declaration
    string Text;
}

struct DocComment
{
    string Description;   // the Markdown text without the tags
    string Summary;       // its first sentence
    List<DocTag> Tags;
}

const ReadOnlySlice<string> DocTagNames = ["param", "returns", "error", "panics", "since", "deprecated", "see", "internal"];

bool IsDocTag(string name)
{
    foreach (var t in DocTagNames)
    {
        if (t == name)
            return true;
    }
    return false;
}

string DocText(string s)
{
    return s == null ? "" : s;
}

DocComment ParseDoc(string text)
{
    var doc = DocComment { Tags = List<DocTag>.Create() };
    var desc = StringBuilder.Create();
    bool fence = false;
    int tag = -1;   // the tag that a following line continues
    foreach (var raw in DocText(text).Split('\n'))
    {
        string line = raw.ToString();
        string trimmed = line.Trim().ToString();
        if (trimmed.StartsWith("```"))
        {
            fence = !fence;
            tag = -1;
        }
        else if (!fence && trimmed.StartsWith("@"))
        {
            doc.Tags.Add(DocTagOf(trimmed));
            tag = doc.Tags.Count() - 1;
            continue;
        }
        else if (!fence && tag >= 0 && trimmed.Length > 0)
        {
            var t = doc.Tags.Get(tag);
            t.Text = t.Text.Length > 0 ? t.Text + " " + trimmed : trimmed;
            doc.Tags.Set(tag, t);
            continue;
        }
        else if (trimmed.Length == 0)
        {
            tag = -1;
        }
        desc.Append(line);
        desc.Append('\n');
    }
    doc.Description = desc.ToString().Trim().ToString();
    doc.Summary = DocSummary(doc.Description);
    return doc;
}

// "@param index the position" -> {param, index, the position}
DocTag DocTagOf(string line)
{
    int end = 1;
    while (end < line.Length && line[end] != ' ' && line[end] != '\t')
        end += 1;
    var t = DocTag { Name = line.Substring(1, end - 1).ToString(), Arg = "", Text = line.Substring(end).ToString().Trim().ToString() };
    if (t.Name == "param" || t.Name == "error" || t.Name == "see")
    {
        int space = 0;
        while (space < t.Text.Length && t.Text[space] != ' ' && t.Text[space] != '\t')
            space += 1;
        t.Arg = t.Text.Substring(0, space).ToString();
        t.Text = t.Text.Substring(space).ToString().Trim().ToString();
        if (t.Name == "see" && t.Arg.StartsWith("[") && t.Arg.EndsWith("]"))
            t.Arg = t.Arg.Substring(1, t.Arg.Length - 2).ToString();
    }
    return t;
}

// The first sentence of the first paragraph (all of it if there is no '. ').
string DocSummary(string description)
{
    var sb = StringBuilder.Create();
    foreach (var raw in description.Split('\n'))
    {
        string line = raw.ToString().Trim().ToString();
        if (line.Length == 0 || line.StartsWith("```"))
            break;
        if (sb.Length() > 0)
            sb.Append(' ');
        sb.Append(line);
    }
    string p = sb.ToString();
    for (var i = 0; i < p.Length; i += 1)
    {
        if (p[i] == '.' && (i + 1 == p.Length || p[i + 1] == ' ') && !(i >= 3 && (p.Substring(i - 3, 3).ToString() == "e.g" || p.Substring(i - 3, 3).ToString() == "i.e")))
            return p.Substring(0, i + 1).ToString();
    }
    return p;
}

bool IsDocLinkName(string s)
{
    if (s.Length == 0 || !(Char.IsLetter(s[0]) || s[0] == '_'))
        return false;
    foreach (var c in s)
    {
        if (!(Char.IsLetterOrDigit(c) || c == '_' || c == '.' || c == '<' || c == '>' || c == ',' || c == ' '))
            return false;
    }
    return true;
}

// The links ([Name]) of a Markdown text, outside of code; with 'replace', the text with every link written as code
// (`Name`) instead.
List<string> DocLinks(string text, StringBuilder replaced)
{
    var links = List<string>.Create();
    bool fence = false;
    var lines = text.Split('\n');
    for (var n = 0; n < lines.Length; n += 1)
    {
        string line = lines[n].ToString();
        if (n > 0)
            replaced.Append('\n');
        if (line.Trim().ToString().StartsWith("```"))
            fence = !fence;
        if (fence || line.Trim().ToString().StartsWith("```"))
        {
            replaced.Append(line);
            continue;
        }
        bool code = false;
        int i = 0;
        while (i < line.Length)
        {
            char c = line[i];
            if (c == '`')
                code = !code;
            else if (c == '[' && !code)
            {
                int close = line.IndexOf(']', i + 1);
                if (close > i + 1)
                {
                    string inner = line.Substring(i + 1, close - i - 1).ToString();
                    bool target = close + 1 < line.Length && (line[close + 1] == '(' || line[close + 1] == '[');
                    if (!target && IsDocLinkName(inner))
                    {
                        links.Add(inner);
                        replaced.Append('`');
                        replaced.Append(inner);
                        replaced.Append('`');
                        i = close + 1;
                        continue;
                    }
                }
            }
            replaced.Append(c);
            i += 1;
        }
    }
    return links;
}

// The name a link refers to, as it is looked up: without type arguments and spaces ("List<T>.Add" -> "List.Add").
string DocLinkKey(string link)
{
    var sb = StringBuilder.Create();
    int depth = 0;
    foreach (var c in link)
    {
        if (c == '<')
            depth += 1;
        else if (c == '>')
            depth -= 1;
        else if (depth == 0 && c != ' ')
            sb.Append(c);
    }
    return sb.ToString();
}

// The doc comment as Markdown for a hover: the description, then the tags.
string DocMarkdown(string text)
{
    var d = ParseDoc(text);
    var sb = StringBuilder.Create();
    DocLinks(d.Description, sb);
    var parameters = StringBuilder.Create();
    var errors = StringBuilder.Create();
    var rest = StringBuilder.Create();
    foreach (var t in d.Tags.ToArray())
    {
        var tagText = StringBuilder.Create();
        DocLinks(t.Text, tagText);
        string body = tagText.ToString();
        if (t.Name == "param")
            parameters.Append("\n- `" + t.Arg + "`" + (body.Length > 0 ? ": " + body : ""));
        else if (t.Name == "error")
            errors.Append("\n- `" + t.Arg + "`" + (body.Length > 0 ? ": " + body : ""));
        else if (t.Name == "returns")
            rest.Append("\n\n**Returns** " + body);
        else if (t.Name == "panics")
            rest.Append("\n\n**Panics** " + body);
        else if (t.Name == "since")
            rest.Append("\n\n*Since " + body + "*");
        else if (t.Name == "deprecated")
            rest.Append("\n\n**Deprecated** " + body);
        else if (t.Name == "see")
            rest.Append("\n\n**See** `" + t.Arg + "`" + (body.Length > 0 ? " " + body : ""));
    }
    if (parameters.Length() > 0)
        sb.Append("\n\n**Parameters**" + parameters.ToString());
    if (errors.Length() > 0)
        sb.Append("\n\n**Errors**" + errors.ToString());
    sb.Append(rest.ToString());
    return sb.ToString().Trim().ToString();
}

// ---- the doc comment of a declaration (hover) ----

bool SameLoc(SourceLoc a, SourceLoc b)
{
    return a.File == b.File && a.Line == b.Line && a.Col == b.Col;
}

SourceLoc FuncDocLoc(FuncDecl d)
{
    return d.NameLoc.Line > 0 ? d.NameLoc : d.Loc;
}

// The doc comment of the declaration at 'def' ("" for none).
string DocAt(Compiler cg, SourceLoc def)
{
    if (def.Line <= 0)
        return "";
    foreach (var s in cg.Structs.ToArray())
    {
        if (SameLoc(s.Decl.Loc, def))
            return DocText(s.Decl.Doc);
        foreach (var f in s.Decl.Fields)
        {
            if (SameLoc(f.Loc, def))
                return DocText(f.Doc);
        }
    }
    foreach (var f in cg.Funcs.ToArray())
    {
        if (SameLoc(FuncDocLoc(f.Decl), def))
            return DocText(f.Decl.Doc);
    }
    foreach (var i in cg.Interfaces.ToArray())
    {
        if (SameLoc(i.Decl.Loc, def))
            return DocText(i.Decl.Doc);
    }
    foreach (var e in cg.Enums.ToArray())
    {
        if (SameLoc(e.Decl.Loc, def))
            return DocText(e.Decl.Doc);
        foreach (var m in e.Decl.Members)
        {
            if (SameLoc(m.Loc, def))
                return DocText(m.Doc);
        }
    }
    foreach (var u in cg.Unions.ToArray())
    {
        if (SameLoc(u.Decl.Loc, def))
            return DocText(u.Decl.Doc);
    }
    foreach (var c in cg.Consts.ToArray())
    {
        if (SameLoc(c.Decl.Loc, def))
            return DocText(c.Decl.Doc);
    }
    foreach (var g in cg.Globals.ToArray())
    {
        if (SameLoc(g.Decl.Loc, def))
            return DocText(g.Decl.Doc);
    }
    return "";
}

// ---- cshiftc doc ----

// Every name a link can refer to: declarations with and without their namespace, members as Type.Member.
HashSet<string> DocNames(Compiler cg)
{
    var names = HashSet<string>.Create();
    foreach (var ns in cg.Namespaces.ToArray())
        names.Add(ns);
    foreach (var s in cg.Structs.ToArray())
    {
        var members = List<string>.Create();
        foreach (var f in s.Decl.Fields)
            members.Add(f.Name);
        foreach (var m in s.Decl.Methods)
            members.Add(m.Name);
        AddDocNames(names, cg.Files.Get(s.File).Ns, s.Decl.Name, members);
    }
    foreach (var i in cg.Interfaces.ToArray())
    {
        var members = List<string>.Create();
        foreach (var m in i.Decl.Methods)
            members.Add(m.Name);
        AddDocNames(names, cg.Files.Get(i.File).Ns, i.Decl.Name, members);
    }
    foreach (var e in cg.Enums.ToArray())
    {
        var members = List<string>.Create();
        foreach (var m in e.Decl.Members)
            members.Add(m.Name);
        AddDocNames(names, cg.Files.Get(e.File).Ns, e.Decl.Name, members);
    }
    foreach (var u in cg.Unions.ToArray())
        AddDocNames(names, cg.Files.Get(u.File).Ns, u.Decl.Name, List<string>.Create());
    foreach (var f in cg.Funcs.ToArray())
    {
        if (f.OwnerStruct == -1)
            AddDocNames(names, cg.Files.Get(f.File).Ns, f.Decl.Name, List<string>.Create());
    }
    foreach (var c in cg.Consts.ToArray())
        AddDocNames(names, cg.Files.Get(c.File).Ns, c.Decl.Name, List<string>.Create());
    foreach (var g in cg.Globals.ToArray())
        AddDocNames(names, cg.Files.Get(g.File).Ns, g.Decl.Name, List<string>.Create());
    return names;
}

void AddDocNames(HashSet<string> names, string ns, string name, List<string> members)
{
    names.Add(name);
    if (ns.Length > 0)
        names.Add(ns + "." + name);
    foreach (var m in members.ToArray())
    {
        names.Add(name + "." + m);
        if (ns.Length > 0)
            names.Add(ns + "." + name + "." + m);
    }
}

// Writes the documentation as JSON; checks the doc comments on the way (errors go to 'cg.Diag').
struct DocWriter
{
    Compiler Cg;
    HashSet<string> Names;
    bool RequireDocs;
    StringBuilder Out;

    // The "doc" member of a declaration: null without a comment. 'what' names the declaration in errors; 'fn' is set
    // for functions (their @param tags are checked).
    void Doc(string text, SourceLoc loc, string what, FuncDecl[] fn)
    {
        if (DocText(text).Length == 0)
        {
            if (RequireDocs)
                Cg.Diag.ReportAt(loc, what + " has no doc comment");
            Out.Append("null");
            return;
        }
        var d = ParseDoc(text);
        var plain = StringBuilder.Create();
        var links = DocLinks(d.Description, plain);
        Out.Append("{\"summary\": " + JsonString(d.Summary) + ", \"description\": " + JsonString(d.Description));
        var parameters = StringBuilder.Create();
        var errors = StringBuilder.Create();
        var see = StringBuilder.Create();
        string returns = "";
        string panics = "";
        string since = "";
        string deprecated = "";
        var seenParams = HashSet<string>.Create();
        foreach (var t in d.Tags.ToArray())
        {
            foreach (var l in DocLinks(t.Text, StringBuilder.Create()).ToArray())
                links.Add(l);
            if (!IsDocTag(t.Name))
            {
                Cg.Diag.ReportAt(loc, "unknown tag '@" + t.Name + "' in the doc comment of " + what);
                continue;
            }
            string entry = "{\"name\": " + JsonString(t.Arg) + ", \"text\": " + JsonString(t.Text) + "}";
            if (t.Name == "param")
            {
                if (fn.Length == 0)
                    Cg.Diag.ReportAt(loc, "'@param' in the doc comment of " + what + ", which is not a function");
                else if (!HasParam(fn[0], t.Arg))
                    Cg.Diag.ReportAt(loc, "'@param " + t.Arg + "': " + what + " has no parameter '" + t.Arg + "'");
                else if (seenParams.Contains(t.Arg))
                    Cg.Diag.ReportAt(loc, "'@param " + t.Arg + "' appears twice in the doc comment of " + what);
                seenParams.Add(t.Arg);
                parameters.Append((parameters.Length() > 0 ? ", " : "") + entry);
            }
            else if (t.Name == "error")
            {
                if (!Names.Contains(DocLinkKey(t.Arg)))
                    Cg.Diag.ReportAt(loc, "'@error " + t.Arg + "' in the doc comment of " + what + ": no such error");
                errors.Append((errors.Length() > 0 ? ", " : "") + entry);
            }
            else if (t.Name == "see")
            {
                links.Add(t.Arg);
                see.Append((see.Length() > 0 ? ", " : "") + entry);
            }
            else if (t.Name == "returns")
                returns = t.Text;
            else if (t.Name == "panics")
                panics = t.Text;
            else if (t.Name == "since")
                since = t.Text;
            else if (t.Name == "deprecated")
                deprecated = t.Text.Length > 0 ? t.Text : "deprecated";
        }
        foreach (var l in links.ToArray())
        {
            if (!Names.Contains(DocLinkKey(l)))
                Cg.Diag.ReportAt(loc, "cannot find '" + l + "' (a link in the doc comment of " + what + ")");
        }
        Out.Append(", \"params\": [" + parameters.ToString() + "], \"returns\": " + JsonString(returns));
        Out.Append(", \"errors\": [" + errors.ToString() + "], \"panics\": " + JsonString(panics));
        Out.Append(", \"since\": " + JsonString(since) + ", \"deprecated\": " + JsonString(deprecated));
        Out.Append(", \"see\": [" + see.ToString() + "]}");
    }

    void Begin(string kind, string name, string signature, SourceLoc loc)
    {
        Out.Append("{\"kind\": \"" + kind + "\", \"name\": " + JsonString(name) + ", \"signature\": " + JsonString(signature));
        Out.Append(", \"file\": " + JsonString(DocFileName(Cg, loc)) + ", \"line\": " + loc.Line.ToString());
    }
}

bool HasParam(FuncDecl d, string name)
{
    foreach (var p in d.Params)
    {
        if (p.Name == name)
            return true;
    }
    return false;
}

// A declaration that belongs in the documentation: not private ('_'), not @internal.
bool DocPublic(string name, string doc)
{
    if (name.StartsWith("_"))
        return false;
    foreach (var t in ParseDoc(doc).Tags.ToArray())
    {
        if (t.Name == "internal")
            return false;
    }
    return true;
}

string DocFileName(Compiler cg, SourceLoc loc)
{
    if (loc.File < 0 || loc.File >= cg.Diag.Files.Count())
        return "";
    string name = cg.Diag.Files.Get(loc.File);
    return name.StartsWith("<stdlib>/") ? name.Substring(9).ToString() : name;
}

string TypeParamsText(string[] typeParams)
{
    if (typeParams == null || typeParams.Length == 0)
        return "";
    return "<" + String.Join(", ", typeParams) + ">";
}

string ConstraintsText(Compiler cg, Constraint[] constraints)
{
    var sb = StringBuilder.Create();
    if (constraints == null)
        return "";
    foreach (var c in constraints)
    {
        sb.Append(" where " + c.Param + " : ");
        for (var i = 0; i < c.Bounds.Length; i += 1)
            sb.Append((i > 0 ? ", " : "") + cg.Tree.TypeToString(c.Bounds[i]));
    }
    return sb.ToString();
}

string FuncSignature(Compiler cg, FuncDecl d)
{
    var sb = StringBuilder.Create();
    if (d.IsStatic)
        sb.Append("static ");
    if (d.IsThread)
        sb.Append("thread ");
    if (d.IsExtern)
        sb.Append("extern \"C\" ");
    sb.Append(cg.Tree.TypeToString(d.Ret));
    sb.Append(' ');
    sb.Append(d.Name);
    sb.Append(TypeParamsText(d.TypeParams));
    sb.Append('(');
    for (var i = 0; i < d.Params.Length; i += 1)
    {
        var p = d.Params[i];
        if (i > 0)
            sb.Append(", ");
        sb.Append(p.Ref == RefKind.Ref ? "ref " : p.Ref == RefKind.ConstRef ? "const ref " : "");
        sb.Append(cg.Tree.TypeToString(p.Type));
        sb.Append(' ');
        sb.Append(p.Name);
    }
    if (d.IsVariadic)
        sb.Append(d.Params.Length > 0 ? ", ..." : "...");
    sb.Append(')');
    sb.Append(ConstraintsText(cg, d.Constraints));
    return sb.ToString();
}

string TypeListText(Compiler cg, TypeRef[] types, string before)
{
    if (types == null || types.Length == 0)
        return "";
    var sb = StringBuilder.Create();
    sb.Append(before);
    for (var i = 0; i < types.Length; i += 1)
        sb.Append((i > 0 ? ", " : "") + cg.Tree.TypeToString(types[i]));
    return sb.ToString();
}

// The value of a constant as JSON (null when it is not a number, a bool or a short string).
string DocConstValue(Compiler cg, int index)
{
    ConstVal v = ConstEvalDecl(cg, index);
    if (v.Kind == ConstKind.Slice || v.Kind == ConstKind.Unknown)
        return "null";
    string s = ConstToText(cg, v);
    if (v.Kind == ConstKind.String)
        return s.Length <= 200 ? JsonString("\"" + s + "\"") : "null";
    return JsonString(s);
}

// The documentation of the standard library (stdlib) or of the other sources, as JSON.
string DocJson(Compiler cg, bool stdlib, bool requireDocs)
{
    var w = DocWriter { Cg = cg, Names = DocNames(cg), RequireDocs = requireDocs, Out = StringBuilder.Create() };
    var o = w.Out;
    var none = new FuncDecl[0];
    o.Append("{\"version\": " + JsonString(CshcVersion()) + ",\n\"namespaces\": [");
    var nsDocs = Dictionary<string, string>.Create();
    var nsOrder = List<string>.Create();
    foreach (var f in cg.Files.ToArray())
    {
        if (f.IsPrelude != stdlib)
            continue;
        string doc = DocText(f.Doc).Trim().ToString();
        var known = nsDocs.TryGet(f.Ns);
        if (known is string before)
        {
            if (doc.Length > 0)
                nsDocs.Set(f.Ns, before.Length > 0 ? before + "\n\n" + doc : doc);
        }
        else
        {
            nsOrder.Add(f.Ns);
            nsDocs.Set(f.Ns, doc);
        }
    }
    for (var i = 0; i < nsOrder.Count(); i += 1)
    {
        string ns = nsOrder.Get(i);
        o.Append((i > 0 ? ",\n" : "\n") + "{\"name\": " + JsonString(ns) + ", \"doc\": ");
        w.Doc(nsDocs.GetOrDefault(ns, ""), SourceLoc { }, "namespace " + ns, none);
        o.Append("}");
    }
    o.Append("],\n\"items\": [");
    bool first = true;

    for (var si = 0; si < cg.Structs.Count(); si += 1)
    {
        var s = cg.Structs.Get(si);
        var file = cg.Files.Get(s.File);
        var d = s.Decl;
        if (file.IsPrelude != stdlib || !DocPublic(d.Name, d.Doc))
            continue;
        o.Append(first ? "\n" : ",\n");
        first = false;
        w.Begin("struct", d.Name, "struct " + d.Name + TypeParamsText(d.TypeParams) + TypeListText(cg, d.Bases, " : ") + ConstraintsText(cg, d.Constraints), d.Loc);
        o.Append(", \"namespace\": " + JsonString(file.Ns) + ", \"doc\": ");
        w.Doc(d.Doc, d.Loc, "struct " + d.Name, none);
        o.Append(", \"members\": [");
        bool firstMember = true;
        foreach (var f in d.Fields)
        {
            if (!DocPublic(f.Name, f.Doc))
                continue;
            o.Append(firstMember ? "\n  " : ",\n  ");
            firstMember = false;
            w.Begin("field", f.Name, cg.Tree.TypeToString(f.Type) + " " + f.Name, f.Loc);
            o.Append(", \"doc\": ");
            w.Doc(f.Doc, f.Loc, "field " + d.Name + "." + f.Name, none);
            o.Append("}");
        }
        foreach (var m in d.Methods)
        {
            if (!DocPublic(m.Name, m.Doc))
                continue;
            o.Append(firstMember ? "\n  " : ",\n  ");
            firstMember = false;
            w.Begin("method", m.Name, FuncSignature(cg, m), FuncDocLoc(m));
            o.Append(", \"static\": " + (m.IsStatic ? "true" : "false") + ", \"doc\": ");
            var one = new FuncDecl[] { m };
            w.Doc(m.Doc, FuncDocLoc(m), "method " + d.Name + "." + m.Name, one);
            o.Append("}");
        }
        o.Append("]}");
    }

    for (var ii = 0; ii < cg.Interfaces.Count(); ii += 1)
    {
        var entry = cg.Interfaces.Get(ii);
        var file = cg.Files.Get(entry.File);
        var d = entry.Decl;
        if (file.IsPrelude != stdlib || !DocPublic(d.Name, d.Doc))
            continue;
        o.Append(first ? "\n" : ",\n");
        first = false;
        w.Begin("interface", d.Name, "interface " + d.Name + TypeParamsText(d.TypeParams), d.Loc);
        o.Append(", \"namespace\": " + JsonString(file.Ns) + ", \"doc\": ");
        w.Doc(d.Doc, d.Loc, "interface " + d.Name, none);
        o.Append(", \"members\": [");
        bool firstMember = true;
        foreach (var m in d.Methods)
        {
            o.Append(firstMember ? "\n  " : ",\n  ");
            firstMember = false;
            w.Begin("method", m.Name, FuncSignature(cg, m), FuncDocLoc(m));
            o.Append(", \"static\": false, \"doc\": ");
            var one = new FuncDecl[] { m };
            w.Doc(m.Doc, FuncDocLoc(m), "method " + d.Name + "." + m.Name, one);
            o.Append("}");
        }
        o.Append("]}");
    }

    for (var ei = 0; ei < cg.Enums.Count(); ei += 1)
    {
        var entry = cg.Enums.Get(ei);
        var file = cg.Files.Get(entry.File);
        var d = entry.Decl;
        if (file.IsPrelude != stdlib || !DocPublic(d.Name, d.Doc))
            continue;
        o.Append(first ? "\n" : ",\n");
        first = false;
        string signature = d.IsError ? "error " + d.Name : "enum " + d.Name + " : " + cg.Tree.TypeToString(d.Base);
        w.Begin(d.IsError ? "error" : "enum", d.Name, signature, d.Loc);
        o.Append(", \"namespace\": " + JsonString(file.Ns) + ", \"doc\": ");
        w.Doc(d.Doc, d.Loc, (d.IsError ? "error " : "enum ") + d.Name, none);
        o.Append(", \"members\": [");
        var info = GetEnumInfo(cg, GetEnumType(cg, ei));
        for (var k = 0; k < d.Members.Length; k += 1)
        {
            var m = d.Members[k];
            o.Append(k == 0 ? "\n  " : ",\n  ");
            string value = "";
            int at = FindEnumMember(info, m.Name);
            if (at >= 0)
                value = info.Values[at].ToString();
            w.Begin("value", m.Name, d.Name + "." + m.Name + (value.Length > 0 ? " = " + value : ""), m.Loc);
            o.Append(", \"value\": " + (value.Length > 0 ? value : "null") + ", \"doc\": ");
            w.Doc(m.Doc, m.Loc, "enum value " + d.Name + "." + m.Name, none);
            o.Append("}");
        }
        o.Append("]}");
    }

    for (var ui = 0; ui < cg.Unions.Count(); ui += 1)
    {
        var entry = cg.Unions.Get(ui);
        var file = cg.Files.Get(entry.File);
        var d = entry.Decl;
        if (file.IsPrelude != stdlib || !DocPublic(d.Name, d.Doc))
            continue;
        o.Append(first ? "\n" : ",\n");
        first = false;
        w.Begin("union", d.Name, "union " + d.Name + TypeListText(cg, d.Interfaces, " : ") + " { " + TypeListText(cg, d.Members, "") + " }", d.Loc);
        o.Append(", \"namespace\": " + JsonString(file.Ns) + ", \"cases\": [");
        for (var k = 0; k < d.Members.Length; k += 1)
            o.Append((k > 0 ? ", " : "") + JsonString(cg.Tree.TypeToString(d.Members[k])));
        o.Append("], \"doc\": ");
        w.Doc(d.Doc, d.Loc, "union " + d.Name, none);
        o.Append("}");
    }

    for (var fi = 0; fi < cg.Funcs.Count(); fi += 1)
    {
        var entry = cg.Funcs.Get(fi);
        var file = cg.Files.Get(entry.File);
        var d = entry.Decl;
        // C functions that are only declared are the plumbing of the library, unless they are documented
        // ... and so is the entry point of a program
        if (entry.OwnerStruct != -1 || file.IsPrelude != stdlib || !DocPublic(d.Name, d.Doc) || (!stdlib && d.Name == "Main") ||
            (d.IsExtern && d.Body.IsNull() && DocText(d.Doc).Length == 0))
            continue;
        o.Append(first ? "\n" : ",\n");
        first = false;
        w.Begin("function", d.Name, FuncSignature(cg, d), FuncDocLoc(d));
        o.Append(", \"namespace\": " + JsonString(file.Ns) + ", \"doc\": ");
        var one = new FuncDecl[] { d };
        w.Doc(d.Doc, FuncDocLoc(d), "function " + d.Name, one);
        o.Append("}");
    }

    for (var ci = 0; ci < cg.Consts.Count(); ci += 1)
    {
        var entry = cg.Consts.Get(ci);
        var file = cg.Files.Get(entry.File);
        var d = entry.Decl;
        if (file.IsPrelude != stdlib || !DocPublic(d.Name, d.Doc))
            continue;
        o.Append(first ? "\n" : ",\n");
        first = false;
        w.Begin("const", d.Name, "const " + cg.Tree.TypeToString(d.Type) + " " + d.Name, d.Loc);
        o.Append(", \"namespace\": " + JsonString(file.Ns) + ", \"value\": " + DocConstValue(cg, ci) + ", \"doc\": ");
        w.Doc(d.Doc, d.Loc, "constant " + d.Name, none);
        o.Append("}");
    }

    for (var gi = 0; gi < cg.Globals.Count(); gi += 1)
    {
        var entry = cg.Globals.Get(gi);
        var file = cg.Files.Get(entry.File);
        var d = entry.Decl;
        if (file.IsPrelude != stdlib || !DocPublic(d.Name, d.Doc))
            continue;
        o.Append(first ? "\n" : ",\n");
        first = false;
        w.Begin("global", d.Name, cg.Tree.TypeToString(d.Type) + " " + d.Name, d.Loc);
        o.Append(", \"namespace\": " + JsonString(file.Ns) + ", \"doc\": ");
        w.Doc(d.Doc, d.Loc, "variable " + d.Name, none);
        o.Append("}");
    }
    o.Append("\n]}\n");
    return o.ToString();
}
