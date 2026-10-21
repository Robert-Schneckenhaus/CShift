// Tests of lib.js (node --test test/). The tests that run cshiftc need CSHIFTC (the path of a cshiftc with 'check' and
// 'query'); without it they are skipped.
"use strict";

const test = require("node:test");
const assert = require("node:assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const lib = require("../lib");

test("columns: UTF-8 bytes of cshiftc <-> characters of VS Code", () => {
    const line = "    string s = \"Grüße\"; int x = s.Length;";
    const character = line.indexOf("s.Length");
    const col = lib.byteColumn(line, character);
    assert.strictEqual(col, character + 1 + 2); // ü and ß take two bytes each
    assert.strictEqual(lib.characterOf(line, col), character);
    assert.strictEqual(lib.byteColumn("abc", 0), 1);
});

test("diagnostics: file:line:col: error: text", () => {
    const out = "src/a.cshift:3:13: error: cannot implicitly convert 'string' to 'int32'\n" +
                "<stdlib>/list.cshift:1:1: error: internal\n" +
                "error: too many errors (50), stopping\n" +
                "C:/w/b.cshift:4:2: warning: something\n";
    const list = lib.parseDiagnostics(out, "/work");
    assert.strictEqual(list.length, 2);
    assert.strictEqual(list[0].file, path.resolve("/work", "src/a.cshift"));
    assert.deepStrictEqual([list[0].line, list[0].col, list[0].severity], [3, 13, "error"]);
    assert.strictEqual(list[0].message, "cannot implicitly convert 'string' to 'int32'");
    assert.strictEqual(list[1].severity, "warning");
});

test("diagnostics: the underline covers the expression at the error, not the rest of the line", () => {
    const marked = (line, at) => {
        const start = line.indexOf(at);
        return line.substring(start, lib.errorRangeEnd(line, start));
    };
    assert.strictEqual(marked("        foo[i] = Bar(foo[i]);", "Bar"), "Bar(foo[i])");
    assert.strictEqual(marked("    string s = text.Trim().ToUpper();", "text"), "text.Trim().ToUpper()");
    assert.strictEqual(marked("    var n = List<int>.Create().Count();", "List"), "List<int>.Create().Count()");
    assert.strictEqual(marked("    int x = \"a(b\" + 1;", "\""), "\"a(b\"");
    assert.strictEqual(marked("    Console.WriteLine($\"{a}\");", "$"), "$\"{a}\"");
    assert.strictEqual(marked("    int y = (int)value;", "(int)"), "(int)value");
    assert.strictEqual(marked("    p->Next = q;", "p->"), "p->Next");
    assert.strictEqual(marked("    x += 1.5;", "+="), "+=");
    assert.strictEqual(marked("    Call(a,", "Call"), "Call(a,"); // the call goes on in the next line
    // a declaration or a statement: the rest of the line
    assert.strictEqual(marked("int Sign(int x)", "int"), "int Sign(int x)");
    assert.strictEqual(marked("    using (var f = Open()) {", "using"), "using (var f = Open()) {");
    assert.strictEqual(marked("    List<string> names = [];", "List"), "List<string> names = [];");
});

test("projects: the project whose sources contain the file", () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), "cshift-lib-"));
    const mk = (p, text) => {
        fs.mkdirSync(path.dirname(path.join(root, p)), { recursive: true });
        fs.writeFileSync(path.join(root, p), text);
    };
    mk("src/Base/Text.cshift", "");
    mk("src/Cli/Program.cshift", "");
    mk("src/Cli/cshift.json", JSON.stringify({ name: "cli", sources: ["Program.cshift", "../Base"] }));
    mk("tests/cshift.json", JSON.stringify({ name: "tests", sources: ["."] }));
    mk("tests/T.cshift", "");
    mk("other/Alone.cshift", "");
    const projects = [path.join(root, "src/Cli/cshift.json"), path.join(root, "tests/cshift.json")];
    assert.strictEqual(lib.findProject(projects, path.join(root, "src/Base/Text.cshift")), projects[0]);
    assert.strictEqual(lib.findProject(projects, path.join(root, "src/Cli/Program.cshift")), projects[0]);
    assert.strictEqual(lib.findProject(projects, path.join(root, "tests/T.cshift")), projects[1]);
    assert.strictEqual(lib.findProject(projects, path.join(root, "other/Alone.cshift")), null);
    fs.rmSync(root, { recursive: true, force: true });
});

const compiler = process.env.CSHIFTC;

test("cshiftc check and query (with an unsaved text)", { skip: !compiler }, async () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "cshift-lib-"));
    const file = path.join(dir, "main.cshift");
    const saved = "int Add(int a, int b)\n{\n    return a + b;\n}\n\nint Main()\n{\n    return Add(1, 2);\n}\n";
    fs.writeFileSync(file, saved);
    const temp = path.join(dir, "tmp");

    let result = await lib.check(compiler, null, file, [], temp);
    assert.strictEqual(result.failed, false);
    assert.deepStrictEqual(result.diagnostics, []);

    // the editor's text has an error that is not saved yet
    const edited = saved.replace("return Add(1, 2);", "return Add(1, missing);");
    result = await lib.check(compiler, null, file, [{ file, text: edited }], temp);
    assert.strictEqual(result.diagnostics.length, 1);
    assert.strictEqual(result.diagnostics[0].message, "undefined name 'missing'");
    assert.strictEqual(lib.samePath(result.diagnostics[0].file), lib.samePath(file));
    assert.strictEqual(result.diagnostics[0].line, 8);

    const answer = await lib.query(compiler, null, file, 8, 12, [], temp);
    assert.strictEqual(answer.hover, "int32 Add(int32 a, int32 b)");
    assert.strictEqual(lib.samePath(answer.definition.file), lib.samePath(file));
    assert.strictEqual(answer.definition.line, 1);
    assert.strictEqual(await lib.query(compiler, null, file, 8, 5, [], temp), null); // 'return'
    fs.rmSync(dir, { recursive: true, force: true });
});

test("completion: the name before '.' and the text without what follows it", () => {
    const text = "int Main()\n{\n    var p = new Point();\n    p.Su\n    return 0;\n}\n";
    const offset = text.indexOf("p.Su") + 4;
    const c = lib.memberContext(text, offset);
    assert.strictEqual(c.line, 4);
    assert.strictEqual(c.nameColumn, 5); // just after 'p'
    assert.strictEqual(c.prefix, "Su");
    assert.ok(c.text.includes("\n    p;\n")); // at the end of a line: a statement
    const inside = "int x = Max(p.X, 2);";
    const c2 = lib.memberContext(inside, inside.indexOf("p.X") + 2);
    assert.strictEqual(c2.text, "int x = Max(p, 2);"); // 'p.X' in the middle of a line: just 'p'
    assert.strictEqual(lib.memberContext("int x = 1 + ", 12), null);
});

test("cshiftc query: references, members, outline", { skip: !compiler }, async () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "cshift-lib-"));
    const file = path.join(dir, "main.cshift");
    const saved = "struct Point\n{\n    int X;\n    int Sum() { return X; }\n}\n\n" +
                  "int Twice(int v) { return v * 2; }\n\nint Main()\n{\n    var p = Point { X = 1 };\n" +
                  "    return Twice(p.Sum()) + Twice(1);\n}\n";
    fs.writeFileSync(file, saved);
    const temp = path.join(dir, "tmp");

    const refs = await lib.query(compiler, null, file, 7, 5, [], temp, ["--references"]);
    assert.deepStrictEqual(refs.references.map((r) => [r.line, r.col]), [[7, 5], [12, 12], [12, 29]]);

    const members = await lib.query(compiler, null, file, 12, 18, [], temp, ["--members"]);
    assert.deepStrictEqual(members.members.map((m) => m.name), ["X", "Sum"]);

    // completion after 'p.' in an unsaved text: the text without what follows the '.'
    const typing = saved.replace("    return Twice(p.Sum()) + Twice(1);", "    p.S\n    return 0;");
    const c = lib.memberContext(typing, typing.indexOf("p.S") + 3);
    const lineText = c.text.split("\n")[c.line - 1];
    const typed = await lib.query(compiler, null, file, c.line, lib.byteColumn(lineText, c.nameColumn - 1),
        [{ file, text: c.text }], temp, ["--members"]);
    assert.deepStrictEqual(typed.members.map((m) => m.name), ["X", "Sum"]);

    const symbols = await lib.outline(compiler, null, file, [], temp);
    assert.deepStrictEqual(symbols.map((s) => [s.name, s.kind]), [["Point", "struct"], ["Twice", "function"], ["Main", "function"]]);
    assert.deepStrictEqual(symbols[0].children.map((s) => s.name), ["X", "Sum"]);
    fs.rmSync(dir, { recursive: true, force: true });
});

test("debugging: target, build command and the lldb configuration", () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), "cshift-lib-"));
    fs.mkdirSync(path.join(root, "app", "src"), { recursive: true });
    fs.writeFileSync(path.join(root, "app", "cshift.json"), JSON.stringify({ name: "demo", sources: ["src"] }));
    const main = path.join(root, "app", "src", "main.cshift");
    const alone = path.join(root, "tool.cshift");
    fs.writeFileSync(main, "");
    fs.writeFileSync(alone, "");
    const projects = [path.join(root, "app", "cshift.json")];

    // the project of the active file, the file alone, the configured project
    assert.deepStrictEqual(lib.debugTarget(projects, main, null), { project: projects[0], file: null });
    assert.deepStrictEqual(lib.debugTarget(projects, alone, null), { project: null, file: alone });
    assert.deepStrictEqual(lib.debugTarget(projects, alone, path.join(root, "app")), { project: path.resolve(projects[0]), file: null });
    assert.strictEqual(lib.debugTarget(projects, null, path.join(root, "missing")), null);

    const p = lib.debugBuild({ project: projects[0], file: null }, "linux");
    assert.deepStrictEqual(p.args, ["build", path.join(root, "app"), "-g", "-O0", "-o", path.join(root, "app", "bin", "debug", "demo")]);
    assert.strictEqual(lib.debugBuild({ project: null, file: alone }, "win32").program, path.join(root, "bin", "debug", "tool.exe"));

    const config = lib.lldbConfiguration({ name: "x", args: ["a"] }, p, "C:\\cshift\\tools\\debug\\cshift_lldb.py");
    assert.deepStrictEqual([config.type, config.request, config.program, config.cwd], ["lldb", "launch", p.program, p.cwd]);
    assert.deepStrictEqual(config.args, ["a"]);
    assert.deepStrictEqual(config.initCommands, ['command script import "C:/cshift/tools/debug/cshift_lldb.py"']);

    // the formatters: next to the extension in the repository
    assert.strictEqual(lib.findLldbScript(path.join(__dirname, ".."), null), path.join(__dirname, "..", "..", "tools", "debug", "cshift_lldb.py"));
    fs.rmSync(root, { recursive: true, force: true });
});

test("rename: the new name, and the edits of the places", () => {
    assert.strictEqual(lib.renameProblem("Total_2"), "");
    assert.match(lib.renameProblem("2nd"), /is not a name/);
    assert.match(lib.renameProblem("a-b"), /is not a name/);
    assert.match(lib.renameProblem("while"), /keyword/);
    assert.match(lib.renameProblem("int32"), /built-in type/);
    // columns are bytes: 'ü' takes two of them
    const lines = { 1: "struct Über { int X; }", 2: "Über u = Über { X = 1 };" };
    const text = (file, line) => lines[line];
    const places = [{ file: "/a.cshift", line: 1, col: 8, length: 5 }, { file: "/a.cshift", line: 2, col: 1, length: 5 },
                    { file: "/a.cshift", line: 2, col: 11, length: 5 }];
    const ok = lib.renameEdits(places, "Über", text);
    assert.strictEqual(ok.problem, "");
    assert.deepStrictEqual(ok.edits.map((e) => [e.line, e.start, e.end]), [[0, 7, 11], [1, 0, 4], [1, 9, 13]]);
    // a place whose text is not the old name any more: nothing is renamed
    lines[2] = "Uber u = Über { X = 1 };";
    const stale = lib.renameEdits(places, "Über", text);
    assert.deepStrictEqual(stale.edits, []);
    assert.match(stale.problem, /changed/);
});

test("cshiftc query --rename: the declaration, initializers, interface methods", { skip: !compiler }, async () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "cshift-lib-"));
    const file = path.join(dir, "main.cshift");
    const saved = "interface IArea\n{\n    int Area();\n}\n\nstruct Box : IArea\n{\n    int W;\n    int Area() { return W; }\n}\n\n" +
                  "int Main()\n{\n    var b = Box { W = 2 };\n    return b.Area() + b.W;\n}\n";
    fs.writeFileSync(file, saved);
    const temp = path.join(dir, "tmp");
    const places = async (line, col) => {
        const answer = await lib.query(compiler, null, file, line, col, [], temp, ["--rename"]);
        return answer.rename.places.map((p) => [p.line, p.col]).sort((a, b) => a[0] - b[0] || a[1] - b[1]);
    };
    // the field from its declaration: the initializer and the use
    assert.deepStrictEqual(await places(8, 9), [[8, 9], [9, 25], [14, 19], [15, 25]]);
    // the method of the struct: also the method of the interface it implements
    assert.deepStrictEqual(await places(15, 14), [[3, 9], [9, 9], [15, 14]]);
    const builtin = await lib.query(compiler, null, file, 15, 5, [], temp, ["--rename"]);
    assert.strictEqual(builtin, null); // 'return': no name
    fs.rmSync(dir, { recursive: true, force: true });
});

test("cshiftc query --rename: names of another namespace, written with it", { skip: !compiler }, async () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "cshift-lib-"));
    fs.mkdirSync(path.join(dir, "src"));
    const project = path.join(dir, "cshift.json");
    fs.writeFileSync(project, JSON.stringify({ name: "ns", sources: ["src"] }));
    const geo = path.join(dir, "src", "geo.cshift");
    const main = path.join(dir, "src", "main.cshift");
    fs.writeFileSync(geo, "namespace Geo;\n\nstruct Point\n{\n    int X;\n    static Point Make(int x) { return Point { X = x }; }\n}\n\n" +
                          "enum Kind : uint8 { A, B }\n");
    fs.writeFileSync(main, "int Main()\n{\n    Geo.Point p = Geo.Point.Make(1);\n    var q = Geo.Point { X = 2 };\n" +
                           "    Geo.Kind k = Geo.Kind.B;\n    return p.X + q.X;\n}\n");
    const temp = path.join(dir, "tmp");
    const places = async (file, line, col) => {
        const answer = await lib.query(compiler, project, file, line, col, [], temp, ["--rename"]);
        return answer.rename.places.map((p) => [path.basename(p.file), p.line, p.col])
            .sort((a, b) => a[0].localeCompare(b[0]) || a[1] - b[1] || a[2] - b[2]);
    };
    // 'Point' in 'Geo.Point' (a type, a call, an initializer): the name after 'Geo.'
    assert.deepStrictEqual(await places(geo, 3, 8), [["geo.cshift", 3, 8], ["geo.cshift", 6, 12], ["geo.cshift", 6, 39],
        ["main.cshift", 3, 9], ["main.cshift", 3, 23], ["main.cshift", 4, 17]]);
    assert.deepStrictEqual(await places(main, 5, 23), [["geo.cshift", 9, 6], ["main.cshift", 5, 9], ["main.cshift", 5, 22]]);
    fs.rmSync(dir, { recursive: true, force: true });
});
