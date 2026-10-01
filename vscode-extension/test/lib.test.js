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
    const out = "src/a.csh:3:13: error: cannot implicitly convert 'string' to 'int32'\n" +
                "<stdlib>/list.csh:1:1: error: internal\n" +
                "error: too many errors (50), stopping\n" +
                "C:/w/b.csh:4:2: warning: something\n";
    const list = lib.parseDiagnostics(out, "/work");
    assert.strictEqual(list.length, 2);
    assert.strictEqual(list[0].file, path.resolve("/work", "src/a.csh"));
    assert.deepStrictEqual([list[0].line, list[0].col, list[0].severity], [3, 13, "error"]);
    assert.strictEqual(list[0].message, "cannot implicitly convert 'string' to 'int32'");
    assert.strictEqual(list[1].severity, "warning");
});

test("projects: the project whose sources contain the file", () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), "cshift-lib-"));
    const mk = (p, text) => {
        fs.mkdirSync(path.dirname(path.join(root, p)), { recursive: true });
        fs.writeFileSync(path.join(root, p), text);
    };
    mk("src/Base/Text.csh", "");
    mk("src/Cli/Program.csh", "");
    mk("src/Cli/cshift.json", JSON.stringify({ name: "cli", sources: ["Program.csh", "../Base"] }));
    mk("tests/cshift.json", JSON.stringify({ name: "tests", sources: ["."] }));
    mk("tests/T.csh", "");
    mk("other/Alone.csh", "");
    const projects = [path.join(root, "src/Cli/cshift.json"), path.join(root, "tests/cshift.json")];
    assert.strictEqual(lib.findProject(projects, path.join(root, "src/Base/Text.csh")), projects[0]);
    assert.strictEqual(lib.findProject(projects, path.join(root, "src/Cli/Program.csh")), projects[0]);
    assert.strictEqual(lib.findProject(projects, path.join(root, "tests/T.csh")), projects[1]);
    assert.strictEqual(lib.findProject(projects, path.join(root, "other/Alone.csh")), null);
    fs.rmSync(root, { recursive: true, force: true });
});

const compiler = process.env.CSHIFTC;

test("cshiftc check and query (with an unsaved text)", { skip: !compiler }, async () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "cshift-lib-"));
    const file = path.join(dir, "main.csh");
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
    const file = path.join(dir, "main.csh");
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
