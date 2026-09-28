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
