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
const instance = await WebAssembly.instantiate(module, wasi.getImportObject());
process.exitCode = wasi.start(instance);
