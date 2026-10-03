// Runs a compiled program (the .wasm of the wasm backend) in a worker, so that a program that runs long does not stop
// the page (the page can end the worker). Messages to the page: { out: text }, { err: text }, { exit: code }.
import { WASI, File, OpenFile, ConsoleStdout, PreopenDirectory } from "@bjorn3/browser_wasi_shim";

self.onmessage = async (event) => {
    const { bytes, args } = event.data;
    const decoder = new TextDecoder();
    const errors = new TextDecoder();
    const fds = [
        new OpenFile(new File([])),
        new ConsoleStdout((chunk) => self.postMessage({ out: decoder.decode(chunk, { stream: true }) })),
        new ConsoleStdout((chunk) => self.postMessage({ err: errors.decode(chunk, { stream: true }) })),
        new PreopenDirectory("/", new Map()),
    ];
    const wasi = new WASI(["main", ...args], ["PWD=/"], fds, { debug: false });
    let code;
    try {
        const { instance } = await WebAssembly.instantiate(bytes, {
            wasi_snapshot_preview1: wasi.wasiImport,
            env: new Proxy({}, { get: (_, name) => () => { throw new Error(`the program calls '${String(name)}', which the browser does not have`); } }),
        });
        code = wasi.start(instance);
    } catch (e) {
        self.postMessage({ err: `\n${e.message ?? e}\n` });
        code = 70;
    }
    self.postMessage({ exit: code });
};
