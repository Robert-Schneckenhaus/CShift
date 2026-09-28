// The CShift extension: hover, go to definition and the errors of the program, from cshiftc (the compiler's 'query'
// and 'check' commands, which run the front end without generating code). The work that does not need VS Code is in
// lib.js.
"use strict";

const vscode = require("vscode");
const fs = require("fs");
const path = require("path");
const lib = require("./lib");

let projectFiles = [];          // the cshift.json files of the workspace
let diagnostics;                // the errors reported by 'cshiftc check'
let checkedFiles = new Map();   // program (project file or single file) -> the files it had errors in
const pending = new Map();      // program -> the timer of a check that waits for typing to pause
let warnedMissing = false;
const tempDir = lib.tempDirectory();

function settings() {
    return vscode.workspace.getConfiguration("cshift");
}

function compilerPath() {
    const configured = settings().get("compilerPath") || "";
    return configured.length > 0 ? configured : "cshiftc";
}

async function refreshProjects() {
    const uris = await vscode.workspace.findFiles("**/cshift.json", "**/{node_modules,obj,bin}/**");
    projectFiles = uris.map((u) => u.fsPath);
}

// The texts of the CShift documents that have unsaved changes.
function dirtyDocuments() {
    return vscode.workspace.textDocuments
        .filter((d) => d.languageId === "cshift" && d.isDirty && d.uri.scheme === "file")
        .map((d) => ({ file: d.uri.fsPath, text: d.getText() }));
}

function reportMissingCompiler(error) {
    if (warnedMissing)
        return;
    warnedMissing = true;
    vscode.window.showWarningMessage("CShift: cannot run '" + compilerPath() + "' (" + (error ? error.message : "not found") +
        "). Set 'cshift.compilerPath' to the cshiftc of a CShift release (0.11 or later).");
}

// ---------------------------------------------------------------------------
// Hover and go to definition
// ---------------------------------------------------------------------------

async function queryAt(document, position) {
    if (document.uri.scheme !== "file")
        return null;
    const file = document.uri.fsPath;
    const lineText = document.lineAt(position.line).text;
    return lib.query(compilerPath(), lib.findProject(projectFiles, file), file, position.line + 1,
        lib.byteColumn(lineText, position.character), dirtyDocuments(), tempDir);
}

const hoverProvider = {
    async provideHover(document, position) {
        const answer = await queryAt(document, position);
        if (!answer)
            return null;
        const text = new vscode.MarkdownString();
        text.appendCodeblock(answer.hover, "cshift");
        return new vscode.Hover(text);
    },
};

// The line of a file, from the open document if there is one (it may have unsaved changes).
function lineOf(file, line) {
    const open = vscode.workspace.textDocuments.find((d) => lib.samePath(d.uri.fsPath) === lib.samePath(file));
    if (open)
        return line - 1 < open.lineCount ? open.lineAt(line - 1).text : "";
    try {
        return fs.readFileSync(file, "utf8").split(/\r?\n/)[line - 1] || "";
    } catch (e) {
        return "";
    }
}

const definitionProvider = {
    async provideDefinition(document, position) {
        const answer = await queryAt(document, position);
        if (!answer || !answer.definition)
            return null;
        const d = answer.definition;
        const character = lib.characterOf(lineOf(d.file, d.line), d.col);
        return new vscode.Location(vscode.Uri.file(d.file), new vscode.Position(d.line - 1, character));
    },
};

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

async function checkDocument(document) {
    if (document.languageId !== "cshift" || document.uri.scheme !== "file")
        return;
    const file = document.uri.fsPath;
    const project = lib.findProject(projectFiles, file);
    const program = project || file;
    const result = await lib.check(compilerPath(), project, file, dirtyDocuments(), tempDir);
    if (result.failed) {
        reportMissingCompiler(result.error);
        return;
    }
    // the errors of this program replace its earlier ones
    const byFile = new Map();
    for (const d of result.diagnostics) {
        const key = lib.samePath(d.file);
        if (!byFile.has(key))
            byFile.set(key, { file: d.file, items: [] });
        const range = new vscode.Range(d.line - 1, Math.max(0, lib.characterOf(lineOf(d.file, d.line), d.col)), d.line - 1, Number.MAX_SAFE_INTEGER);
        const item = new vscode.Diagnostic(range, d.message, d.severity === "warning" ? vscode.DiagnosticSeverity.Warning : vscode.DiagnosticSeverity.Error);
        item.source = "cshiftc";
        byFile.get(key).items.push(item);
    }
    for (const old of checkedFiles.get(program) || []) {
        if (!byFile.has(lib.samePath(old)))
            diagnostics.delete(vscode.Uri.file(old));
    }
    for (const entry of byFile.values())
        diagnostics.set(vscode.Uri.file(entry.file), entry.items);
    if (!byFile.has(lib.samePath(file)))
        diagnostics.delete(document.uri);
    checkedFiles.set(program, [...byFile.values()].map((e) => e.file));
}

// A check after the user stopped typing for a moment.
function scheduleCheck(document) {
    if (document.languageId !== "cshift" || !settings().get("checkWhileTyping"))
        return;
    const key = document.uri.toString();
    clearTimeout(pending.get(key));
    pending.set(key, setTimeout(() => {
        pending.delete(key);
        checkDocument(document);
    }, settings().get("checkDelay") || 700));
}

// ---------------------------------------------------------------------------

async function activate(context) {
    diagnostics = vscode.languages.createDiagnosticCollection("cshift");
    context.subscriptions.push(diagnostics);
    await refreshProjects();

    const watcher = vscode.workspace.createFileSystemWatcher("**/cshift.json");
    watcher.onDidCreate(refreshProjects);
    watcher.onDidDelete(refreshProjects);
    context.subscriptions.push(watcher);

    const selector = { language: "cshift", scheme: "file" };
    context.subscriptions.push(
        vscode.languages.registerHoverProvider(selector, hoverProvider),
        vscode.languages.registerDefinitionProvider(selector, definitionProvider),
        vscode.workspace.onDidOpenTextDocument(checkDocument),
        vscode.workspace.onDidSaveTextDocument(checkDocument),
        vscode.workspace.onDidChangeTextDocument((e) => scheduleCheck(e.document)),
        vscode.workspace.onDidChangeConfiguration((e) => {
            if (e.affectsConfiguration("cshift.compilerPath"))
                warnedMissing = false;
        }),
        vscode.commands.registerCommand("cshift.checkProgram", () => {
            const editor = vscode.window.activeTextEditor;
            if (editor)
                checkDocument(editor.document);
        }));
    vscode.workspace.textDocuments.forEach(checkDocument);
}

function deactivate() {
    try {
        fs.rmSync(tempDir, { recursive: true, force: true });
    } catch (e) {
        // nothing to clean up
    }
}

module.exports = { activate, deactivate };
