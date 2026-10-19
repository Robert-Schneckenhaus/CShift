// System.Audio in the browser without a browser: runs tests/audio/tone.cshift (wasm backend) with web/cshift.js and an
// AudioContext that only pretends. Its clock moves on by a millisecond each time it is read (and stands still while
// the context is suspended), so the run does not depend on the speed of the machine. It checks that the program
// played all its frames, that each AudioBuffer starts where the one before it ends, and that the samples of the
// buffers are the ones the program wrote (left and right). Then it runs the program without Web Audio: the output
// reports AudioError.NotSupported.
//
//   cshiftc --backend wasm --target wasm32-wasi tests/audio/tone.cshift -o tone.wasm && node tests/audio-web-check.mjs tone.wasm

import { readFile } from "node:fs/promises";
import { argv, exit } from "node:process";

const { run } = await import(new URL("../web/cshift.js", import.meta.url).href);

const sources = [];

class Buffer {
    constructor(channels, length, rate) {
        this.numberOfChannels = channels;
        this.length = length;
        this.sampleRate = rate;
        this.data = Array.from({ length: channels }, () => new Float32Array(length));
    }
    getChannelData(c) {
        return this.data[c];
    }
}

class Context {
    constructor(options) {
        this.sampleRate = options?.sampleRate ?? 48000;
        this.state = "running";
        this.time = 0;
        this.destination = {};
    }
    get currentTime() {
        if (this.state === "running") this.time += 0.001;
        return this.time;
    }
    createBuffer(channels, length, rate) {
        return new Buffer(channels, length, rate);
    }
    createBufferSource() {
        const source = {
            buffer: null,
            connect() {},
            disconnect() {},
            start(when) {
                source.when = when;
                sources.push(source);
            },
            stop() {
                source.stopped = true;
            },
        };
        return source;
    }
    suspend() {
        this.state = "suspended";
        return Promise.resolve();
    }
    resume() {
        this.state = "running";
        return Promise.resolve();
    }
    close() {
        this.state = "closed";
        return Promise.resolve();
    }
}

const wasm = await readFile(argv[2]);
const problems = [];

async function runProgram() {
    const output = [];
    const program = await run(wasm, { onOutput: (text) => output.push(text) });
    const code = await program.exited;
    return { code, text: output.join("") };
}

globalThis.AudioContext = Context;
const played = await runProgram();
if (played.code !== 0 || !played.text.includes("audio: 22050 frames played"))
    problems.push(`the program ended with ${played.code}: ${played.text.trim()}`);

// the buffers of the stereo output (the program opens a mono one at the end, without writing)
const left = [];
const right = [];
let end = null;
for (const s of sources) {
    const b = s.buffer;
    if (b.sampleRate !== 44100 || b.numberOfChannels !== 2) problems.push(`a buffer of ${b.numberOfChannels} channels at ${b.sampleRate} Hz`);
    if (end !== null && Math.abs(s.when - end) > 1e-9) problems.push(`a buffer starts at ${s.when}, the one before it ends at ${end}`);
    end = s.when + b.length / b.sampleRate;
    for (let i = 0; i < b.length; i++) {
        left.push(Math.round(b.data[0][i] * 32768));
        right.push(Math.round(b.data[1][i] * 32768));
    }
}
const signed8 = (v) => (v > 127 ? v - 256 : v) * 256;
if (left.length !== 22050) problems.push(`${left.length} frames in the buffers`);
for (let i = 0; i < left.length; i++) {
    const l = i < 20000 ? ((i * 37) % 2000) - 1000 : signed8((i * 7) % 256);
    const r = i < 20000 ? ((i * 91) % 3000) - 1500 : signed8((i * 13) % 256);
    if (left[i] !== l || right[i] !== r) {
        problems.push(`frame ${i}: ${left[i]}, ${right[i]} instead of ${l}, ${r}`);
        break;
    }
}

delete globalThis.AudioContext;
const without = await runProgram();
if (without.code !== 0 || !without.text.includes("audio: not supported"))
    problems.push(`without Web Audio: ${without.code}: ${without.text.trim()}`);

if (problems.length > 0) {
    console.log("audio in the browser: FAILED");
    for (const p of problems) console.log("  " + p);
    exit(1);
}
console.log(`audio in the browser: ok (${sources.length} buffers)`);
