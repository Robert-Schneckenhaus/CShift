// Runs a WebAssembly program (wasm32-wasi) with node: node tests/wasi-run.mjs program.wasm [args...]
// The program sees the whole file system and starts in the current directory (PWD, see stdlib/os/wasi/stubs.csh); its
// exit code is the exit code of node.
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
const instance = await WebAssembly.instantiate(module, { wasi_snapshot_preview1: imports, env: host });
process.exitCode = wasi.start(instance);
