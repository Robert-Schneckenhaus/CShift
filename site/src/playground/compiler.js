// The CShift compiler as WebAssembly (cshc.wasm, built by scripts/playground.sh) in the browser: every call runs a
// fresh instance of the module with the program's files in an in-memory file system and collects what it writes.
import { WASI, File, OpenFile, ConsoleStdout, PreopenDirectory } from "@bjorn3/browser_wasi_shim";

/** Compiles the module once (from a URL or the bytes). */
export async function loadCompiler(source) {
    if (typeof source === "string") {
        const response = await fetch(source);
        if (!response.ok) throw new Error(`cannot load the compiler (${response.status})`);
        return WebAssembly.compileStreaming ? await WebAssembly.compileStreaming(response) : await WebAssembly.compile(await response.arrayBuffer());
    }
    return WebAssembly.compile(source);
}

/**
 * Runs cshiftc with the arguments, in a directory that holds the files ({ name: text }).
 * @returns {{ code: number, stdout: string, stderr: string, files: Record<string, Uint8Array> }} the exit code, the
 *   output, and the files of the directory afterwards (what the compiler wrote).
 */
export async function runCompiler(module, args, files) {
    const encoder = new TextEncoder();
    const contents = new Map();
    for (const [name, text] of Object.entries(files)) contents.set(name, new File(encoder.encode(text)));
    let stdout = "";
    let stderr = "";
    const decoder = new TextDecoder();
    const fds = [
        new OpenFile(new File([])),
        new ConsoleStdout((bytes) => (stdout += decoder.decode(bytes, { stream: true }))),
        new ConsoleStdout((bytes) => (stderr += decoder.decode(bytes, { stream: true }))),
        new PreopenDirectory("/", contents),
    ];
    const wasi = new WASI(["cshiftc", ...args], [], fds, { debug: false });
    const instance = await WebAssembly.instantiate(module, { wasi_snapshot_preview1: wasi.wasiImport });
    let code;
    try {
        code = wasi.start(instance);
    } catch (e) {
        code = 70;
        stderr += `\ninternal error of the compiler: ${e}`;
    }
    const out = {};
    for (const [name, inode] of fds[3].dir.contents) if (inode.data) out[name] = inode.data;
    return { code, stdout, stderr, files: out };
}

/** The messages of the compiler ("file:line:col: error: text") as objects; other lines are kept as text. */
export function parseDiagnostics(text) {
    const result = [];
    for (const line of text.split("\n")) {
        const m = line.match(/^([^:]+):(\d+):(\d+): (error|warning): (.*)$/);
        if (m) result.push({ file: m[1], line: +m[2], column: +m[3], severity: m[4], message: m[5] });
        else if (line.trim()) result.push({ message: line.trim() });
    }
    return result;
}

/**
 * Runs a program (the bytes of its .wasm) in a worker; its output goes to onOutput(text, isError) as it comes.
 * @returns {{ done: Promise<number>, stop: () => void }} the exit code when it ends, and a way to end it early.
 */
export function runProgram(bytes, args, onOutput) {
    const worker = new Worker(new URL("./runner.js", import.meta.url), { type: "module" });
    let finish;
    const done = new Promise((resolve) => (finish = resolve));
    worker.onmessage = (event) => {
        const message = event.data;
        if (message.out !== undefined) onOutput(message.out, false);
        else if (message.err !== undefined) onOutput(message.err, true);
        else if (message.exit !== undefined) {
            worker.terminate();
            finish(message.exit);
        }
    };
    worker.onerror = (event) => {
        onOutput(`\n${event.message}\n`, true);
        worker.terminate();
        finish(70);
    };
    worker.postMessage({ bytes, args });
    return {
        done,
        stop() {
            worker.terminate();
            finish(null);
        },
    };
}
