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
    const errors = [];               // error messages shown
    const installed = new Set();     // the ids of installed extensions
    const providers = {};
    const diagnostics = new Map();
    const documents = [];
    class Position { constructor(line, character) { this.line = line; this.character = character; } }
    class Range { constructor(a, b, c, d) { this.start = new Position(a, b); this.end = new Position(c, d); } }
    class Location {
        constructor(uri, where) {
            this.uri = uri;
            this.range = where.start ? where : new Range(where.line, where.character, where.line, where.character);
        }
    }
    class DocumentSymbol { constructor(name, detail, kind, range, selection) { Object.assign(this, { name, detail, kind, range, selection, children: [] }); } }
    class CompletionItem { constructor(label, kind) { this.label = label; this.kind = kind; } }
    class MarkdownString { constructor() { this.value = ""; } appendCodeblock(code, lang) { this.value += "```" + lang + "\n" + code + "\n```\n"; return this; } }
    class Hover { constructor(contents) { this.contents = [contents]; } }
    class Diagnostic { constructor(range, message, severity) { this.range = range; this.message = message; this.severity = severity; } }
    const Uri = { file: (p) => ({ fsPath: p, scheme: "file", toString: () => "file://" + p }) };
    const vscode = {
        Position, Range, Location, MarkdownString, Hover, Diagnostic, Uri, DocumentSymbol, CompletionItem,
        DiagnosticSeverity: { Error: 0, Warning: 1 },
        SymbolKind: { Struct: 22, Interface: 10, Enum: 9, Class: 4, Function: 11, Method: 5, Field: 7, EnumMember: 21, Constant: 13, Variable: 12 },
        CompletionItemKind: { Field: 4, Method: 1, EnumMember: 19, Property: 9, Text: 0 },
        workspace: {
            textDocuments: documents,
            getConfiguration: () => ({ get: (k) => settings[k] }),
            findFiles: async () => [Uri.file(path.join(root, "cshift.json"))],
            createFileSystemWatcher: () => ({ onDidCreate() {}, onDidDelete() {}, dispose() {} }),
            onDidOpenTextDocument: (f) => { handlers.open.push(f); return { dispose() {} }; },
            onDidSaveTextDocument: (f) => { handlers.save.push(f); return { dispose() {} }; },
            onDidChangeTextDocument: (f) => { handlers.change.push(f); return { dispose() {} }; },
            onDidChangeConfiguration: () => ({ dispose() {} }),
            saveAll: async () => true,
        },
        languages: {
            createDiagnosticCollection: () => ({
                set: (uri, items) => diagnostics.set(uri.fsPath, items),
                delete: (uri) => diagnostics.delete(uri.fsPath),
                dispose() {},
            }),
            registerHoverProvider: (sel, p) => { providers.hover = p; return { dispose() {} }; },
            registerDefinitionProvider: (sel, p) => { providers.definition = p; return { dispose() {} }; },
            registerReferenceProvider: (sel, p) => { providers.references = p; return { dispose() {} }; },
            registerDocumentSymbolProvider: (sel, p) => { providers.symbols = p; return { dispose() {} }; },
            registerCompletionItemProvider: (sel, p) => { providers.completion = p; return { dispose() {} }; },
        },
        commands: { registerCommand: () => ({ dispose() {} }), executeCommand: async () => undefined },
        window: {
            showWarningMessage: (m) => { throw new Error("warning: " + m); },
            showErrorMessage: async (m) => { errors.push(m); return undefined; },
            createOutputChannel: () => ({ appendLine() {}, append() {}, show() {} }),
            activeTextEditor: null,
        },
        debug: { registerDebugConfigurationProvider: (type, p) => { providers.debug = p; return { dispose() {} }; } },
        extensions: { getExtension: (id) => (installed.has(id) ? {} : undefined) },
    };
    // a document with an editable text
    function openDocument(file) {
        let text = fs.readFileSync(file, "utf8");
        const doc = {
            uri: Uri.file(file), languageId: "cshift", isDirty: false,
            getText: () => text,
            get lineCount() { return text.split("\n").length; },
            lineAt: (n) => ({ text: text.split("\n")[n] }),
            offsetAt: (pos) => text.split("\n").slice(0, pos.line).reduce((sum, l) => sum + l.length + 1, 0) + pos.character,
            setText(t) { text = t; this.isDirty = true; },
        };
        documents.push(doc);
        return doc;
    }
    return { vscode, handlers, providers, diagnostics, openDocument, errors, installed };
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

    // find all references: the declaration and the call
    const refs = await env.providers.references.provideReferences(doc, at);
    assert.deepStrictEqual(refs.map((r) => [path.basename(r.uri.fsPath), r.range.start.line]).sort(),
        [["Main.csh", 5], ["Person.csh", 6]]);

    // the outline of Person.csh
    const personDoc = env.openDocument(path.join(root, "src", "Person.csh"));
    const symbols = await env.providers.symbols.provideDocumentSymbols(personDoc);
    assert.deepStrictEqual(symbols.map((s) => s.name), ["Person", "Describe"]);
    assert.deepStrictEqual(symbols[0].children.map((s) => s.name), ["Name", "Age"]);

    // completion after 'p.' while typing
    const typed = doc.getText().replace("    return 0;", "    p.\n    return 0;");
    doc.setText(typed);
    const dotLine = typed.split("\n").findIndex((l) => l === "    p.");
    const items0 = await env.providers.completion.provideCompletionItems(doc, new env.vscode.Position(dotLine, 6));
    assert.deepStrictEqual(items0.map((i) => i.label), ["Name", "Age"]);
    doc.setText(typed.replace("    p.\n", ""));
    doc.isDirty = false;

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

    // F5: without CodeLLDB an error (and nothing is started); with it the program is built with -g -O0 and the
    // configuration for CodeLLDB comes back
    env.vscode.window.activeTextEditor = { document: doc };
    assert.strictEqual(await env.providers.debug.resolveDebugConfiguration(undefined, {}), undefined);
    assert.match(env.errors.pop(), /CodeLLDB/);
    env.installed.add("vadimcn.vscode-lldb");
    const launch = await env.providers.debug.resolveDebugConfiguration(undefined, {});
    assert.strictEqual(launch.type, "lldb");
    assert.strictEqual(launch.program, path.join(root, "bin", "debug", "demo") + (process.platform === "win32" ? ".exe" : ""));
    assert.ok(fs.existsSync(launch.program), "the debug build exists");
    assert.match(launch.initCommands[0], /cshift_lldb\.py"$/);

    Module._load = load;
    extension.deactivate();
    fs.rmSync(root, { recursive: true, force: true });
});
