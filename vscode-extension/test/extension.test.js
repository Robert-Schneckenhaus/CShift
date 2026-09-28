// Tests of extension.js against a small stand-in for the 'vscode' module (only what the extension uses): activation,
// hover, go to definition, and the errors of a program while it is edited. Needs CSHIFTC like lib.test.js.
"use strict";

const test = require("node:test");
const assert = require("node:assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const Module = require("module");

const compiler = process.env.CSHIFTC;

// ---- the stand-in ----
function makeVscode(root, settings) {
    const handlers = { open: [], save: [], change: [] };
    const providers = {};
    const diagnostics = new Map();
    const documents = [];
    class Position { constructor(line, character) { this.line = line; this.character = character; } }
    class Range { constructor(a, b, c, d) { this.start = new Position(a, b); this.end = new Position(c, d); } }
    class Location { constructor(uri, pos) { this.uri = uri; this.range = new Range(pos.line, pos.character, pos.line, pos.character); } }
    class MarkdownString { constructor() { this.value = ""; } appendCodeblock(code, lang) { this.value += "```" + lang + "\n" + code + "\n```\n"; return this; } }
    class Hover { constructor(contents) { this.contents = [contents]; } }
    class Diagnostic { constructor(range, message, severity) { this.range = range; this.message = message; this.severity = severity; } }
    const Uri = { file: (p) => ({ fsPath: p, scheme: "file", toString: () => "file://" + p }) };
    const vscode = {
        Position, Range, Location, MarkdownString, Hover, Diagnostic, Uri,
        DiagnosticSeverity: { Error: 0, Warning: 1 },
        workspace: {
            textDocuments: documents,
            getConfiguration: () => ({ get: (k) => settings[k] }),
            findFiles: async () => [Uri.file(path.join(root, "cshift.json"))],
            createFileSystemWatcher: () => ({ onDidCreate() {}, onDidDelete() {}, dispose() {} }),
            onDidOpenTextDocument: (f) => { handlers.open.push(f); return { dispose() {} }; },
            onDidSaveTextDocument: (f) => { handlers.save.push(f); return { dispose() {} }; },
            onDidChangeTextDocument: (f) => { handlers.change.push(f); return { dispose() {} }; },
            onDidChangeConfiguration: () => ({ dispose() {} }),
        },
        languages: {
            createDiagnosticCollection: () => ({
                set: (uri, items) => diagnostics.set(uri.fsPath, items),
                delete: (uri) => diagnostics.delete(uri.fsPath),
                dispose() {},
            }),
            registerHoverProvider: (sel, p) => { providers.hover = p; return { dispose() {} }; },
            registerDefinitionProvider: (sel, p) => { providers.definition = p; return { dispose() {} }; },
        },
        commands: { registerCommand: () => ({ dispose() {} }) },
        window: { showWarningMessage: (m) => { throw new Error("warning: " + m); }, activeTextEditor: null },
    };
    // a document with an editable text
    function openDocument(file) {
        let text = fs.readFileSync(file, "utf8");
        const doc = {
            uri: Uri.file(file), languageId: "cshift", isDirty: false,
            getText: () => text,
            get lineCount() { return text.split("\n").length; },
            lineAt: (n) => ({ text: text.split("\n")[n] }),
            setText(t) { text = t; this.isDirty = true; },
        };
        documents.push(doc);
        return doc;
    }
    return { vscode, handlers, providers, diagnostics, openDocument };
}

test("extension: hover, definition and errors while editing", { skip: !compiler }, async () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), "cshift-ext-"));
    fs.mkdirSync(path.join(root, "src"));
    fs.writeFileSync(path.join(root, "cshift.json"), JSON.stringify({ name: "demo", sources: ["src"] }));
    const mainFile = path.join(root, "src", "Main.csh");
    fs.writeFileSync(mainFile, "using System;\n\nint Main()\n{\n    var p = Person { Name = \"Ann\", Age = 30 };\n" +
        "    Console.WriteLine(Describe(p));\n    return 0;\n}\n");
    fs.writeFileSync(path.join(root, "src", "Person.csh"), "struct Person\n{\n    string Name;\n    int Age;\n}\n\n" +
        "string Describe(Person p)\n{\n    return p.Name + \" \" + p.Age.ToString();\n}\n");

    const env = makeVscode(root, { compilerPath: compiler, checkWhileTyping: true, checkDelay: 50 });
    const load = Module._load;
    Module._load = function (request, ...rest) { return request === "vscode" ? env.vscode : load.call(this, request, ...rest); };
    const extension = require("../extension");
    await extension.activate({ subscriptions: [] });

    const doc = env.openDocument(mainFile);
    const line = doc.lineAt(5).text;
    const at = new env.vscode.Position(5, line.indexOf("Describe") + 2);

    const hover = await env.providers.hover.provideHover(doc, at);
    assert.match(hover.contents[0].value, /string Describe\(Person p\)/);

    const def = await env.providers.definition.provideDefinition(doc, at);
    assert.strictEqual(path.basename(def.uri.fsPath), "Person.csh");
    assert.deepStrictEqual([def.range.start.line, def.range.start.character], [6, 7]); // the name "Describe"

    // opening the (correct) document reports nothing
    for (const h of env.handlers.open) await h(doc);
    assert.strictEqual(env.diagnostics.size, 0);

    // an error typed but not saved: reported after the pause
    doc.setText(doc.getText().replace("    return 0;", "    int bad = \"x\";\n    return 0;"));
    for (const h of env.handlers.change) h({ document: doc });
    await new Promise((r) => setTimeout(r, 2500));
    const items = env.diagnostics.get(mainFile);
    assert.ok(items && items.length === 1, "one error expected");
    assert.strictEqual(items[0].message, "cannot implicitly convert 'string' to 'int32'");
    assert.deepStrictEqual([items[0].range.start.line, items[0].range.start.character], [6, 14]);

    // fixed again: the error goes away
    doc.setText(doc.getText().replace("    int bad = \"x\";\n", ""));
    for (const h of env.handlers.save) await h(doc);
    assert.ok(!env.diagnostics.get(mainFile) || env.diagnostics.get(mainFile).length === 0);

    Module._load = load;
    extension.deactivate();
    fs.rmSync(root, { recursive: true, force: true });
});
