// Runs a WebAssembly program (wasm32-wasi) with node: node tests/wasi-run.mjs program.wasm [args...]
// The program sees the whole file system and starts in the current directory (PWD, see stdlib/os/wasi/stubs.csh); its
// exit code is the exit code of node. A program that suspends itself in glfwPollEvents (a game's loop from the wasm
// backend, see web/cshift.js) is resumed right away; it gets no window and no events.
import { readFile } from 'node:fs/promises';
import { WASI } from 'node:wasi';
import { argv, cwd, env } from 'node:process';

const wasi = new WASI({
    version: 'preview1',
    args: argv.slice(2),
    env: { ...env, PWD: cwd() },
    preopens: { '/': '/' },
    returnOnExit: true,
});
const module = await WebAssembly.compile(await readFile(argv[2]));
// The functions of WASI are called through JavaScript functions: node's own (called directly by V8) crash once the
// memory of the program has grown large (node 22: a segmentation fault after some 150 MB).
const imports = {};
for (const [name, f] of Object.entries(wasi.getImportObject().wasi_snapshot_preview1))
    imports[name] = (...args) => f(...args);
// Functions of the host (the module "env", from the wasm backend: functions without a body) fail when they are called.
const host = {};
for (const entry of WebAssembly.Module.imports(module)) {
    if (entry.module === 'env')
        host[entry.name] = () => { throw new Error(`the program called '${entry.name}', which node does not have`); };
}
let instance;
let data = 0;
let suspended = false;
let rewinding = false;
// glfwPollEvents and glfwWaitEvents suspend the program, like a frame in the browser
const suspend = () => {
    if (rewinding) {
        instance.exports.__cs_wasm_stop_rewind();
        rewinding = false;
        return;
    }
    instance.exports.__cs_wasm_start_unwind(data);
    suspended = true;
};
for (const name of ['glfwPollEvents', 'glfwWaitEvents', 'glfwWaitEventsTimeout'])
    if (name in host) host[name] = suspend;
class Exit {
    constructor(code) { this.code = code; }
}
imports.proc_exit = (code) => { throw new Exit(code); };
instance = await WebAssembly.instantiate(module, { wasi_snapshot_preview1: imports, env: host });
if (instance.exports.__cs_wasm_start_unwind) {
    data = instance.exports.malloc(65536 + 8);
    const view = new DataView(instance.exports.memory.buffer);
    view.setUint32(data, data + 8, true);
    view.setUint32(data + 4, data + 8 + 65536, true);
}
let first = true;
for (;;) {
    suspended = false;
    try {
        if (first)
            wasi.start(instance);
        else
            instance.exports._start();
    } catch (e) {
        if (!(e instanceof Exit))
            throw e;
        process.exitCode = e.code;
        break;
    }
    first = false;
    if (!suspended) {
        process.exitCode = 0;
        break;
    }
    instance.exports.__cs_wasm_stop_unwind();
    instance.exports.__cs_wasm_start_rewind(data);
    rewinding = true;
}
