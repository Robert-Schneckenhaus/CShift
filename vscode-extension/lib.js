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

// 'cshiftc query --at <file> <line> <col> <target> [overlays]' -> { hover, definition: { file, line, col } } or null.
async function query(compiler, project, file, line, col, dirty, tempDir) {
    const args = ["query", "--at", file, String(line), String(col), ...targetArgs(project, file)];
    const result = await runWithOverlays(compiler, args, dirty, tempDir, path.dirname(project || file), 30000);
    const text = result.stdout.trim();
    if (!text)
        return null;
    try {
        const answer = JSON.parse(text.split(/\r?\n/).pop());
        return answer.hover ? answer : null;
    } catch (e) {
        return null;
    }
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

module.exports = {
    samePath, projectSources, projectContains, findProject, byteColumn, characterOf, overlayArgs, parseDiagnostics,
    run, query, check,
    tempDirectory: () => path.join(os.tmpdir(), "cshift-vscode-" + process.pid),
};
