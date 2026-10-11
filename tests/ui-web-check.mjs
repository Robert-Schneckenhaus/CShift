// System.Ui in the browser without a browser: runs a program of the wasm backend (tests/ui/web.cshift) with web/cshift.js
// and a canvas that only pretends (events are sent to it, putImageData keeps the image). It clicks the button and types
// into the text box at the places the program tells, pastes, and checks the output, the pixels of the frame and that
// the program waits for input between the frames.
//
//   cshiftc --backend wasm tests/ui/web.cshift -o web.wasm && node tests/ui-web-check.mjs web.wasm

import { readFile } from "node:fs/promises";
import { argv } from "node:process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const { run } = await import(new URL("../web/cshift.js", import.meta.url).href);

class Target {
    constructor() {
        this.listeners = {};
    }
    addEventListener(type, f) {
        (this.listeners[type] ??= []).push(f);
    }
    send(type, fields = {}) {
        for (const f of this.listeners[type] ?? []) f({ preventDefault() {}, button: 0, ctrlKey: false, shiftKey: false, altKey: false, metaKey: false, ...fields });
    }
}

const document = new Target();
let frames = 0;
let image = null;
const canvas = new Target();
Object.assign(canvas, {
    width: 0,
    height: 0,
    style: {},
    tabIndex: -1,
    ownerDocument: document,
    focus() {},
    getBoundingClientRect: () => ({ left: 0, top: 0, width: canvas.width, height: canvas.height }),
    getContext: () => ({
        createImageData: (width, height) => ({ width, height, data: new Uint8ClampedArray(width * height * 4) }),
        putImageData(data) {
            image = data;
            frames += 1;
        },
    }),
});
globalThis.requestAnimationFrame = (f) => setTimeout(f, 1);

const output = [];
const lines = [];
let resolveLine = null;
const program = await run(await readFile(argv[2]), {
    canvas,
    pixelRatio: 1,
    setTitle: false,
    onOutput: (text) => {
        output.push(text);
        for (const line of text.split("\n").filter((l) => l.length > 0)) {
            lines.push(line);
            resolveLine?.();
        }
    },
});
const fail = (message) => {
    console.error(`FAILED: ${message}\noutput:\n${output.join("")}`);
    process.exit(1);
};
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const waitFor = async (prefix) => {
    for (let i = 0; i < 200; i++) {
        const line = lines.find((l) => l.startsWith(prefix));
        if (line) return line;
        await new Promise((resolve) => {
            resolveLine = resolve;
            setTimeout(resolve, 10);
        });
    }
    fail(`no line '${prefix}'`);
};

const layout = (await waitFor("layout ")).split(" ").map(Number);
const [bx, by, tx, ty] = layout.slice(1, 5);
// the frame: the background of the light theme, as R, G, B, A
if (!image || image.data[0] !== 243 || image.data[1] !== 243 || image.data[2] !== 243 || image.data[3] !== 255)
    fail(`the pixel at (0, 0) is ${image ? [...image.data.slice(0, 4)] : "missing"}`);
// without input the program waits: no frames
await sleep(5);
const before = frames;
await sleep(50);
if (frames > before + 1) fail(`${frames - before} frames without input`);

const click = (x, y) => {
    canvas.send("mousemove", { clientX: x, clientY: y });
    canvas.send("mousedown", { clientX: x, clientY: y });
    document.send("mouseup", { clientX: x, clientY: y });
};
click(bx, by);
await waitFor("clicked");
click(tx, ty);
await sleep(20);
for (const key of ["h", "i"]) canvas.send("keydown", { key, keyCode: key.toUpperCase().charCodeAt(0) });
await waitFor("text hi");
canvas.send("paste", { clipboardData: { getData: () => " there" } });
const exit = await program.exited;
if (exit !== 0) fail(`exit code ${exit}`);
if (!lines.includes("text hi there")) fail("the pasted text is missing");
console.log(`ui web ok: ${lines.at(-1)}`);
