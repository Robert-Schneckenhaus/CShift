// The parts of the extension that do not need VS Code: finding the project of a file, running cshiftc (check, query)
// and reading its answers. extension.js connects them to the editor; test/lib.test.js tests them with node.
"use strict";

const childProcess = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

// ---------------------------------------------------------------------------
// Projects
// ---------------------------------------------------------------------------

// A path in the form in which two names of the same file compare equal (like SamePath in cshiftc).
function samePath(p) {
    const full = path.resolve(p);
    return process.platform === "win32" ? full.toLowerCase() : full;
}

// The .csh files of a project file (cshift.json): its "sources" (files, or folders searched recursively), relative to
// the folder of the project file. Returns null if the file cannot be read.
function projectSources(projectFile) {
    let json;
    try {
        json = JSON.parse(fs.readFileSync(projectFile, "utf8").replace(/^﻿/, ""));
    } catch (e) {
        return null;
    }
    const dir = path.dirname(projectFile);
    const entries = Array.isArray(json.sources) ? json.sources : ["."];
    return entries.map((entry) => samePath(path.join(dir, String(entry))));
}

// True if the file is one of the sources (a source that is a folder contains it).
function projectContains(sources, file) {
    const f = samePath(file);
    return sources.some((s) => f === s || f.startsWith(s.endsWith(path.sep) ? s : s + path.sep));
}

// The project file (cshift.json) that the file belongs to, from the given project files: the one whose sources contain
// it (the nearest one if several do), or null (the file is checked alone).
function findProject(projectFiles, file) {
    let best = null;
    let bestDistance = Infinity;
    for (const projectFile of projectFiles) {
        const sources = projectSources(projectFile);
        if (!sources || !projectContains(sources, file))
            continue;
        const distance = path.relative(path.dirname(projectFile), file).split(path.sep).length;
        if (distance < bestDistance) {
            best = projectFile;
            bestDistance = distance;
        }
    }
    return best;
}

// ---------------------------------------------------------------------------
// Columns: cshiftc counts the bytes of a line (UTF-8, from 1), VS Code counts UTF-16 code units (from 0)
// ---------------------------------------------------------------------------

function byteColumn(lineText, character) {
    return Buffer.byteLength(lineText.substring(0, character), "utf8") + 1;
}

function characterOf(lineText, byteCol) {
    const bytes = Buffer.from(lineText, "utf8");
    return bytes.subarray(0, Math.max(0, byteCol - 1)).toString("utf8").length;
}

const KEYWORDS = new Set([
    "break", "case", "const", "continue", "default", "do", "else", "embed", "embed_filenames", "embed_lines", "enum",
    "extern", "for", "foreach", "if", "interface", "namespace", "return", "start", "struct", "switch", "thread", "union",
    "unsafe", "using", "var", "while", "void", "static",
]);

// Where the underline of an error that cshiftc reports at character 'start' of a line ends (exclusive). cshiftc gives
// only the start: of an expression (a name with its members, calls and indexes, a literal, a cast) just that is marked,
// 'Bar(foo[i])' in 'foo[i] = Bar(foo[i]);'. At a keyword or a declaration ('int Sign(int x)') the rest of the line is.
function errorRangeEnd(lineText, start) {
    const n = lineText.length;
    const isIdent = (c) => c !== undefined && /[A-Za-z0-9_]/.test(c);
    // the end of a string or char literal that starts at i (with the quote), or n if it does not end on this line
    const literalEnd = (i) => {
        const quote = lineText[i];
        for (let j = i + 1; j < n; j++) {
            if (lineText[j] === "\\")
                j++;
            else if (lineText[j] === quote)
                return j + 1;
        }
        return n;
    };
    // the end of the brackets that open at i, with nested brackets and literals; n if they close on a later line
    const groupEnd = (i) => {
        const stack = [];
        for (let j = i; j < n; j++) {
            const c = lineText[j];
            if (c === '"' || c === "'")
                j = literalEnd(j) - 1;
            else if (c === "(" || c === "[" || c === "{")
                stack.push(c === "(" ? ")" : c === "[" ? "]" : "}");
            else if (c === ")" || c === "]" || c === "}") {
                if (stack.pop() !== c)
                    return j + 1;
                if (stack.length === 0)
                    return j + 1;
            }
        }
        return n;
    };
    let i = start;
    let parts = 0; // the pieces of the expression: names, literals, brackets
    let word = "";
    while (i < n) {
        const c = lineText[i];
        if (c === '"' || c === "'" || (c === "$" && lineText[i + 1] === '"')) {
            i = literalEnd(c === "$" ? i + 1 : i);
        } else if (isIdent(c)) {
            const from = i;
            while (isIdent(lineText[i]))
                i++;
            if (parts === 0)
                word = lineText.substring(from, i);
            // type arguments of a generic call or type: List<int>.Create(), Max<T>(a, b)
            const typeArgs = /^<[A-Za-z0-9_,\s\[\]<>?*]*>(?=[.(])/.exec(lineText.substring(i));
            if (typeArgs)
                i += typeArgs[0].length;
        } else if (c === "(" || c === "[") {
            i = groupEnd(i);
        } else if (c === "." && isIdent(lineText[i + 1]) && parts > 0) {
            i++;
            continue;
        } else if (c === "-" && lineText[i + 1] === ">" && parts > 0) {
            i += 2;
            continue;
        } else
            break;
        parts++;
    }
    if (parts === 0) {
        // an operator ('+', '+=', '==') or a single character
        let j = start;
        while (j < n && /[+\-*/%=<>!&|^~?:]/.test(lineText[j]))
            j++;
        return Math.max(j, Math.min(n, start + 1));
    }
    const rest = lineText.substring(i);
    // a keyword or a declaration: 'int Sign(int x)', 'List<string> names = ...', 'using (...)'
    if (parts === 1 && word.length > 0 && (KEYWORDS.has(word) || /^\s+[A-Za-z_]/.test(rest) || /^<[^>]*>\s+[A-Za-z_]/.test(rest)))
        return n;
    return i;
}

// ---------------------------------------------------------------------------
// Running cshiftc
// ---------------------------------------------------------------------------

// Writes the texts of unsaved documents to temporary files: [{ file, text }] -> the arguments '--overlay <file> <tmp>'.
function overlayArgs(dirty, tempDir) {
    const args = [];
    dirty.forEach((d, i) => {
        const tmp = path.join(tempDir, "overlay" + i + ".csh");
        fs.writeFileSync(tmp, d.text, "utf8");
        args.push("--overlay", d.file, tmp);
    });
    return args;
}

// The program to check: the project file, or the file alone.
function targetArgs(project, file) {
    return [project ? project : file];
}

// Runs cshiftc and returns { code, stdout, stderr } (code -1 if it could not be started).
function run(compiler, args, cwd, timeoutMs) {
    return new Promise((resolve) => {
        childProcess.execFile(compiler, args, { cwd, timeout: timeoutMs || 30000, maxBuffer: 16 * 1024 * 1024, windowsHide: true },
            (error, stdout, stderr) => {
                let code = 0;
                if (error)
                    code = typeof error.code === "number" ? error.code : -1;
                resolve({ code, stdout: String(stdout), stderr: String(stderr), error: code === -1 ? error : null });
            });
    });
}

// Runs cshiftc with the overlays of the unsaved documents in a folder of their own (requests can run at the same time).
async function runWithOverlays(compiler, args, dirty, tempDir, cwd, timeoutMs) {
    fs.mkdirSync(tempDir, { recursive: true });
    const dir = fs.mkdtempSync(path.join(tempDir, "r"));
    try {
        return await run(compiler, [...args, ...overlayArgs(dirty, dir)], cwd, timeoutMs);
    } finally {
        fs.rmSync(dir, { recursive: true, force: true });
    }
}

// Runs 'cshiftc query <args> <target> [overlays]' and returns its JSON answer (null if there is none).
async function queryJson(compiler, project, file, args, dirty, tempDir) {
    const result = await runWithOverlays(compiler, ["query", ...args, ...targetArgs(project, file)], dirty, tempDir,
        path.dirname(project || file), 30000);
    const text = result.stdout.trim();
    if (!text)
        return null;
    try {
        return JSON.parse(text.split(/\r?\n/).pop());
    } catch (e) {
        return null;
    }
}

// 'cshiftc query --at <file> <line> <col> [--references] [--members]' -> { hover, definition: { file, line, col },
// references: [{ file, line, col, length }], members: [{ name, kind, detail }] } or null.
async function query(compiler, project, file, line, col, dirty, tempDir, extra) {
    const answer = await queryJson(compiler, project, file, ["--at", file, String(line), String(col), ...(extra || [])], dirty, tempDir);
    return answer && answer.hover ? answer : null;
}

// 'cshiftc query --outline <file>' -> [{ name, kind, line, col, children }] (the declarations of the file) or null.
async function outline(compiler, project, file, dirty, tempDir) {
    const answer = await queryJson(compiler, project, file, ["--outline", file], dirty, tempDir);
    return answer && Array.isArray(answer.symbols) ? answer.symbols : null;
}

// Completion after 'name.': the text with what is typed after the '.' taken out, so that the program can be checked,
// and the position of the name. 'offset' is the cursor in 'text'. Returns null if no 'name.' is before the cursor.
function memberContext(text, offset) {
    const before = text.substring(0, offset);
    const m = /([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*([A-Za-z0-9_]*)$/.exec(before);
    if (!m)
        return null;
    const nameEnd = m.index + m[1].length;
    const lineStart = before.lastIndexOf("\n") + 1;
    // the rest of the member name after the cursor goes too
    const end = offset + /^[A-Za-z0-9_]*/.exec(text.substring(offset))[0].length;
    const lineEnd = text.indexOf("\n", end) < 0 ? text.length : text.indexOf("\n", end);
    const restOfLine = text.substring(end, lineEnd);
    // 'x.Fo' at the end of a line becomes 'x;' (a statement), inside a line just 'x'
    const replacement = restOfLine.trim().length === 0 ? ";" : "";
    const edited = text.substring(0, nameEnd) + replacement + text.substring(end);
    const lineNumber = before.split("\n").length;
    return { text: edited, line: lineNumber, nameColumn: nameEnd - lineStart, prefix: m[2] };
}

// The messages of cshiftc ("file:line:col: error: text") -> [{ file, line, col, severity, message }]; files as full
// paths, messages without a file (e.g. "too many errors") and those in the embedded standard library are left out.
function parseDiagnostics(output, cwd) {
    const list = [];
    const re = /^(.*?):(\d+):(\d+):\s+(warning|error):\s+(.*)$/;
    for (const raw of output.split(/\r?\n/)) {
        const m = re.exec(raw);
        if (!m || m[1].startsWith("<"))
            continue;
        list.push({ file: path.resolve(cwd, m[1]), line: Number(m[2]), col: Number(m[3]), severity: m[4], message: m[5] });
    }
    return list;
}

// 'cshiftc check <target> [overlays]' -> { diagnostics, failed } (failed: cshiftc could not be run; the reason in
// 'error').
async function check(compiler, project, file, dirty, tempDir) {
    const cwd = path.dirname(project || file);
    const result = await runWithOverlays(compiler, ["check", ...targetArgs(project, file)], dirty, tempDir, cwd, 60000);
    if (result.code === -1)
        return { diagnostics: [], failed: true, error: result.error };
    return { diagnostics: parseDiagnostics(result.stderr, cwd), failed: false };
}

// ---------------------------------------------------------------------------
// Debugging (F5): build with -g -O0, then run the program under lldb (the CodeLLDB extension)
// ---------------------------------------------------------------------------

// The name of a project (cshift.json "name"), or null.
function projectName(projectFile) {
    try {
        const json = JSON.parse(fs.readFileSync(projectFile, "utf8").replace(/^\uFEFF/, ""));
        return typeof json.name === "string" && json.name.length > 0 ? json.name : null;
    } catch (e) {
        return null;
    }
}

// What F5 builds: the project of the launch configuration ("project": a cshift.json or its folder), else the project
// of the active file, else the active file alone. Returns { project, file } (one of them null) or null.
function debugTarget(projectFiles, activeFile, configuredProject) {
    if (configuredProject) {
        const file = configuredProject.endsWith(".json") ? configuredProject : path.join(configuredProject, "cshift.json");
        return fs.existsSync(file) ? { project: path.resolve(file), file: null } : null;
    }
    if (!activeFile)
        return projectFiles.length === 1 ? { project: projectFiles[0], file: null } : null;
    const project = findProject(projectFiles, activeFile);
    return project ? { project, file: null } : { project: null, file: activeFile };
}

// The cshiftc command line of a debug build and the program it writes: a project goes to <folder>/bin/debug/<name>,
// a single file to bin/debug/<stem> next to it (so the normal build of the program stays as it is).
function debugBuild(target, platform) {
    const exe = (platform || process.platform) === "win32" ? ".exe" : "";
    if (target.project) {
        const dir = path.dirname(target.project);
        const name = projectName(target.project) || path.basename(dir);
        const program = path.join(dir, "bin", "debug", name) + exe;
        return { args: ["build", dir, "-g", "-O0", "-o", program], program, cwd: dir };
    }
    const dir = path.dirname(target.file);
    const program = path.join(dir, "bin", "debug", path.basename(target.file, ".csh")) + exe;
    return { args: [target.file, "-g", "-O0", "-o", program], program, cwd: dir };
}

// The lldb formatters for CShift values (tools/debug/cshift_lldb.py): packaged with the extension, next to the
// extension in the repository, or in the tools folder of the cshiftc release.
function findLldbScript(extensionPath, compiler) {
    const candidates = [
        path.join(extensionPath, "debug", "cshift_lldb.py"),
        path.join(extensionPath, "..", "tools", "debug", "cshift_lldb.py"),
    ];
    if (compiler && path.isAbsolute(compiler))
        candidates.push(path.join(path.dirname(compiler), "tools", "debug", "cshift_lldb.py"));
    return candidates.find((c) => fs.existsSync(c)) || null;
}

// The launch configuration for CodeLLDB.
function lldbConfiguration(config, build, script) {
    return {
        type: "lldb",
        request: "launch",
        name: config.name || "Debug CShift program",
        program: build.program,
        args: Array.isArray(config.args) ? config.args : [],
        cwd: config.cwd || build.cwd,
        env: config.env || {},
        stopOnEntry: !!config.stopOnEntry,
        initCommands: script ? ["command script import \"" + script.replace(/\\/g, "/") + "\""] : [],
    };
}

module.exports = {
    samePath, projectSources, projectContains, findProject, byteColumn, characterOf, errorRangeEnd, overlayArgs, parseDiagnostics,
    run, query, queryJson, outline, memberContext, check, projectName, debugTarget, debugBuild, findLldbScript,
    lldbConfiguration,
    tempDirectory: () => path.join(os.tmpdir(), "cshift-vscode-" + process.pid),
};
