// The browser side of CShift programs from the wasm backend (cshiftc --backend wasm): one ES module without
// dependencies. It gives a program
//
//   * WASI (wasi_snapshot_preview1): arguments, environment, the clock, the console (stdout/stderr to a callback) and
//     an in-memory file system with the files given to run() (assets of a game, fetched before the start);
//   * GLFW: the window is a <canvas>, keyboard and mouse events go to the callbacks the program set, glfwGetTime;
//   * OpenGL on WebGL 2: the functions of OpenGL 3.3 core that WebGL 2 has (called directly or through
//     glfwGetProcAddress), GLSL 330 shaders (rewritten to GLSL ES 300), and glDrawPixels/glPixelZoom/glRasterPos of
//     OpenGL 1.1 (drawn as a texture);
//   * the game loop: glfwPollEvents (and glfwWaitEvents) suspends the program until the next frame of the browser
//     (requestAnimationFrame), the backend saves and restores the functions on the way (selfhost/src/Wasm/Gen.csh).
//
//   import { run } from "./cshift.js";
//   const program = await run("game.wasm", { canvas, files: { "/data/map.json": "data/map.json" }, onOutput });
//   await program.exited;   // the exit code
//
// Functions of "env" that are neither GLFW nor OpenGL can be given as options.imports ({ name: function }).

const WASI_ESUCCESS = 0, WASI_EBADF = 8, WASI_EEXIST = 20, WASI_EINVAL = 28, WASI_EISDIR = 31, WASI_ENOENT = 44,
    WASI_ENOSYS = 52, WASI_ENOTDIR = 54, WASI_ENOTEMPTY = 55;

class ExitStatus {
    constructor(code) {
        this.code = code;
    }
}

// ---------------------------------------------------------------------------------------------------------------
// The file system: directories are Maps of names to nodes, files hold their bytes
// ---------------------------------------------------------------------------------------------------------------

function newDir() {
    return { dir: new Map(), mtime: Date.now() };
}

function newFile(data) {
    return { data: data ?? new Uint8Array(0), mtime: Date.now() };
}

function splitPath(path) {
    return path.split("/").filter((p) => p.length > 0 && p !== ".");
}

// ---------------------------------------------------------------------------------------------------------------
// The key codes of GLFW for KeyboardEvent.code
// ---------------------------------------------------------------------------------------------------------------

const KEYS = {
    Space: 32, Quote: 39, Comma: 44, Minus: 45, Period: 46, Slash: 47, Semicolon: 59, Equal: 61, BracketLeft: 91,
    Backslash: 92, BracketRight: 93, Backquote: 96, Escape: 256, Enter: 257, Tab: 258, Backspace: 259, Insert: 260,
    Delete: 261, ArrowRight: 262, ArrowLeft: 263, ArrowDown: 264, ArrowUp: 265, PageUp: 266, PageDown: 267, Home: 268,
    End: 269, CapsLock: 280, ScrollLock: 281, NumLock: 282, PrintScreen: 283, Pause: 284, NumpadDecimal: 330,
    NumpadDivide: 331, NumpadMultiply: 332, NumpadSubtract: 333, NumpadAdd: 334, NumpadEnter: 335, NumpadEqual: 336,
    ShiftLeft: 340, ControlLeft: 341, AltLeft: 342, MetaLeft: 343, ShiftRight: 344, ControlRight: 345, AltRight: 346,
    MetaRight: 347, ContextMenu: 348, IntlBackslash: 162,
};
for (let i = 0; i < 26; i++) KEYS["Key" + String.fromCharCode(65 + i)] = 65 + i;
for (let i = 0; i < 10; i++) {
    KEYS["Digit" + i] = 48 + i;
    KEYS["Numpad" + i] = 320 + i;
}
for (let i = 1; i <= 25; i++) KEYS["F" + i] = 289 + i;

function modsOf(e) {
    return (e.shiftKey ? 1 : 0) | (e.ctrlKey ? 2 : 0) | (e.altKey ? 4 : 0) | (e.metaKey ? 8 : 0);
}

// ---------------------------------------------------------------------------------------------------------------
// Small WebAssembly modules that wrap JavaScript functions, so that they can go into the function table
// (glfwGetProcAddress returns a slot of the table)
// ---------------------------------------------------------------------------------------------------------------

const VALTYPE = { i: 0x7f, j: 0x7e, f: 0x7d, d: 0x7c };

function leb(n) {
    const out = [];
    do {
        let b = n & 0x7f;
        n >>>= 7;
        if (n !== 0) b |= 0x80;
        out.push(b);
    } while (n !== 0);
    return out;
}

function str(s) {
    const bytes = [...new TextEncoder().encode(s)];
    return [...leb(bytes.length), ...bytes];
}

function section(id, bytes) {
    return [id, ...leb(bytes.length), ...bytes];
}

// signature: "result_params", e.g. "v_iif" (void (i32, i32, f32)), "i_" (i32 ())
function wrapperModule(signature) {
    const [r, p] = signature.split("_");
    const type = [0x60, ...leb(p.length), ...[...p].map((c) => VALTYPE[c]), ...(r === "v" ? [0] : [1, VALTYPE[r]])];
    const bytes = [0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00,
        ...section(1, [1, ...type]),
        ...section(2, [1, ...str("env"), ...str("f"), 0x00, 0]),
        ...section(7, [1, ...str("f"), 0x00, 0])];
    return new WebAssembly.Module(new Uint8Array(bytes));
}

// ---------------------------------------------------------------------------------------------------------------
// The runtime of one program
// ---------------------------------------------------------------------------------------------------------------

class Program {
    constructor(options) {
        this.options = options;
        this.args = ["main", ...(options.args ?? [])];
        this.env = Object.entries(options.env ?? { PWD: "/" }).map(([k, v]) => `${k}=${v}`);
        this.root = newDir();
        this.fds = new Map();
        this.nextFd = 4;
        this.decoders = [new TextDecoder(), new TextDecoder()];
        this.onOutput = options.onOutput ?? ((text, isError) => (isError ? console.error : console.log)(text));
        this.canvas = options.canvas ?? null;
        this.events = [];
        this.callbacks = {};
        this.keys = new Map();
        this.buttons = [0, 0, 0, 0, 0, 0, 0, 0];
        this.cursor = [0, 0];
        this.shouldClose = 0;
        this.startTime = performance.now();
        this.suspended = false;
        this.rewinding = false;
        this.gl = null;
        this.procs = new Map();
        this.stopped = false;
    }

    // ---- memory helpers ----
    get memory() {
        return this.instance.exports.memory.buffer;
    }
    u8() {
        return new Uint8Array(this.memory);
    }
    view() {
        return new DataView(this.memory);
    }
    cstring(ptr) {
        if (!ptr) return "";
        const bytes = this.u8();
        let end = ptr;
        while (bytes[end] !== 0) end++;
        return new TextDecoder().decode(bytes.subarray(ptr, end));
    }
    text(ptr, length) {
        return new TextDecoder().decode(this.u8().subarray(ptr, ptr + length));
    }
    // a C string in the program's memory (malloc); kept for the program's lifetime
    newCString(text) {
        const bytes = new TextEncoder().encode(text);
        const ptr = this.instance.exports.malloc(bytes.length + 1);
        this.u8().set(bytes, ptr);
        this.u8()[ptr + bytes.length] = 0;
        return ptr;
    }
    callback(slot, ...args) {
        if (slot) this.instance.exports.__indirect_function_table.get(slot)(...args);
    }

    // ---- files ----
    addFile(path, data) {
        const parts = splitPath(path);
        let dir = this.root;
        for (let i = 0; i < parts.length - 1; i++) {
            let next = dir.dir.get(parts[i]);
            if (!next) {
                next = newDir();
                dir.dir.set(parts[i], next);
            }
            dir = next;
        }
        dir.dir.set(parts[parts.length - 1], newFile(data));
    }
    // the node of a path relative to a directory fd: { parent, name, node }
    lookup(fd, path) {
        const base = this.fds.get(fd);
        if (!base || !base.node.dir) return null;
        const stack = [base.node];
        const parts = path.split("/").filter((p) => p.length > 0 && p !== ".");
        for (let i = 0; i < parts.length - 1; i++) {
            const part = parts[i];
            if (part === "..") {
                if (stack.length > 1) stack.pop();
                continue;
            }
            const next = stack[stack.length - 1].dir.get(part);
            if (!next || !next.dir) return null;
            stack.push(next);
        }
        const parent = stack[stack.length - 1];
        const name = parts.length > 0 ? parts[parts.length - 1] : null;
        if (name === null) return { parent, name: null, node: parent };
        if (name === "..") {
            if (stack.length > 1) stack.pop();
            return { parent: stack[stack.length - 1], name: null, node: stack[stack.length - 1] };
        }
        return { parent, name, node: parent.dir.get(name) ?? null };
    }

    // ---- WASI ----
    wasi() {
        const self = this;
        const ok = WASI_ESUCCESS;
        const writeStats = (ptr, node) => {
            const v = self.view();
            for (let i = 0; i < 64; i += 8) v.setBigUint64(ptr + i, 0n, true);
            v.setUint8(ptr + 16, node.dir ? 3 : 4);
            v.setBigUint64(ptr + 24, 1n, true);
            v.setBigUint64(ptr + 32, BigInt(node.data ? node.data.length : 0), true);
            const time = BigInt(Math.round(node.mtime)) * 1000000n;
            v.setBigUint64(ptr + 40, time, true);
            v.setBigUint64(ptr + 48, time, true);
            v.setBigUint64(ptr + 56, time, true);
        };
        const strings = (list, ptrs, buffer) => {
            const v = self.view();
            const u8 = self.u8();
            let at = buffer;
            list.forEach((s, i) => {
                const bytes = new TextEncoder().encode(s);
                v.setUint32(ptrs + i * 4, at, true);
                u8.set(bytes, at);
                u8[at + bytes.length] = 0;
                at += bytes.length + 1;
            });
            return ok;
        };
        const sizes = (list, count, size) => {
            const v = self.view();
            v.setUint32(count, list.length, true);
            v.setUint32(size, list.reduce((n, s) => n + new TextEncoder().encode(s).length + 1, 0), true);
            return ok;
        };
        return {
            args_sizes_get: (count, size) => sizes(self.args, count, size),
            args_get: (ptrs, buffer) => strings(self.args, ptrs, buffer),
            environ_sizes_get: (count, size) => sizes(self.env, count, size),
            environ_get: (ptrs, buffer) => strings(self.env, ptrs, buffer),
            clock_time_get(id, precision, out) {
                const ns = id === 0 ? BigInt(Date.now()) * 1000000n : BigInt(Math.round((performance.now() - self.startTime) * 1e6));
                self.view().setBigUint64(out, ns, true);
                return ok;
            },
            clock_res_get(id, out) {
                self.view().setBigUint64(out, 1000n, true);
                return ok;
            },
            fd_write(fd, iovs, count, written) {
                const v = self.view();
                let total = 0;
                const chunks = [];
                for (let i = 0; i < count; i++) {
                    const ptr = v.getUint32(iovs + i * 8, true);
                    const len = v.getUint32(iovs + i * 8 + 4, true);
                    chunks.push(self.u8().slice(ptr, ptr + len));
                    total += len;
                }
                if (fd === 1 || fd === 2) {
                    let text = "";
                    for (const c of chunks) text += self.decoders[fd - 1].decode(c, { stream: true });
                    if (text) self.onOutput(text, fd === 2);
                } else {
                    const f = self.fds.get(fd);
                    if (!f || !f.node.data) return WASI_EBADF;
                    if (f.append) f.pos = f.node.data.length;
                    const end = f.pos + total;
                    if (end > f.node.data.length) {
                        const grown = new Uint8Array(end);
                        grown.set(f.node.data);
                        f.node.data = grown;
                    }
                    for (const c of chunks) {
                        f.node.data.set(c, f.pos);
                        f.pos += c.length;
                    }
                    f.node.mtime = Date.now();
                }
                v.setUint32(written, total, true);
                return ok;
            },
            fd_read(fd, iovs, count, read) {
                const v = self.view();
                const f = self.fds.get(fd);
                let total = 0;
                if (f && f.node.data) {
                    for (let i = 0; i < count; i++) {
                        const ptr = v.getUint32(iovs + i * 8, true);
                        const len = v.getUint32(iovs + i * 8 + 4, true);
                        const part = f.node.data.subarray(f.pos, Math.min(f.pos + len, f.node.data.length));
                        self.u8().set(part, ptr);
                        f.pos += part.length;
                        total += part.length;
                        if (part.length < len) break;
                    }
                } else if (fd !== 0) return WASI_EBADF;
                v.setUint32(read, total, true);
                return ok;
            },
            fd_close(fd) {
                self.fds.delete(fd);
                return ok;
            },
            fd_seek(fd, offset, whence, out) {
                const f = self.fds.get(fd);
                if (!f || !f.node.data) return WASI_EBADF;
                const base = whence === 0 ? 0 : whence === 1 ? f.pos : f.node.data.length;
                const pos = base + Number(offset);
                if (pos < 0) return WASI_EINVAL;
                f.pos = pos;
                self.view().setBigUint64(out, BigInt(pos), true);
                return ok;
            },
            fd_tell(fd, out) {
                const f = self.fds.get(fd);
                if (!f) return WASI_EBADF;
                self.view().setBigUint64(out, BigInt(f.pos), true);
                return ok;
            },
            fd_fdstat_get(fd, out) {
                const f = self.fds.get(fd);
                if (!f && fd > 2) return WASI_EBADF;
                const v = self.view();
                v.setUint8(out, f ? (f.node.dir ? 3 : 4) : 2);
                v.setUint16(out + 2, 0, true);
                v.setBigUint64(out + 8, 0x1fffffffn, true);
                v.setBigUint64(out + 16, 0x1fffffffn, true);
                return ok;
            },
            fd_fdstat_set_flags: () => ok,
            fd_filestat_get(fd, out) {
                const f = self.fds.get(fd);
                if (!f) return WASI_EBADF;
                writeStats(out, f.node);
                return ok;
            },
            fd_prestat_get(fd, out) {
                if (fd !== 3) return WASI_EBADF;
                const v = self.view();
                v.setUint8(out, 0);
                v.setUint32(out + 4, 1, true);
                return ok;
            },
            fd_prestat_dir_name(fd, path, len) {
                if (fd !== 3) return WASI_EBADF;
                self.u8()[path] = 47; // "/"
                return ok;
            },
            fd_readdir(fd, buffer, length, cookie, used) {
                const f = self.fds.get(fd);
                if (!f || !f.node.dir) return WASI_ENOTDIR;
                const names = [".", "..", ...f.node.dir.keys()];
                const v = self.view();
                let at = 0;
                for (let i = Number(cookie); i < names.length; i++) {
                    const name = new TextEncoder().encode(names[i]);
                    const entry = new Uint8Array(24 + name.length);
                    const ev = new DataView(entry.buffer);
                    ev.setBigUint64(0, BigInt(i + 1), true);
                    ev.setBigUint64(8, BigInt(i + 1), true);
                    ev.setUint32(16, name.length, true);
                    const node = i < 2 ? f.node : f.node.dir.get(names[i]);
                    ev.setUint8(20, node.dir ? 3 : 4);
                    entry.set(name, 24);
                    const room = length - at;
                    self.u8().set(entry.subarray(0, Math.min(room, entry.length)), buffer + at);
                    at += Math.min(room, entry.length);
                    if (at >= length) break;
                }
                v.setUint32(used, at, true);
                return ok;
            },
            path_open(fd, dirflags, path, pathLength, oflags, rights, inheriting, fdflags, out) {
                const p = self.lookup(fd, self.text(path, pathLength));
                if (!p) return WASI_ENOENT;
                let node = p.node;
                if (node && (oflags & 4)) return WASI_EEXIST; // excl
                if (!node) {
                    if (!(oflags & 1) || p.name === null) return WASI_ENOENT;
                    node = newFile();
                    p.parent.dir.set(p.name, node);
                }
                if ((oflags & 2) && !node.dir) return WASI_ENOTDIR;
                if (node.data && (oflags & 8)) node.data = new Uint8Array(0);
                const id = self.nextFd++;
                self.fds.set(id, { node, pos: 0, append: (fdflags & 1) !== 0 });
                self.view().setUint32(out, id, true);
                return ok;
            },
            path_filestat_get(fd, flags, path, pathLength, out) {
                const p = self.lookup(fd, self.text(path, pathLength));
                if (!p || !p.node) return WASI_ENOENT;
                writeStats(out, p.node);
                return ok;
            },
            path_create_directory(fd, path, pathLength) {
                const p = self.lookup(fd, self.text(path, pathLength));
                if (!p || p.name === null) return WASI_ENOENT;
                if (p.node) return WASI_EEXIST;
                p.parent.dir.set(p.name, newDir());
                return ok;
            },
            path_remove_directory(fd, path, pathLength) {
                const p = self.lookup(fd, self.text(path, pathLength));
                if (!p || !p.node || p.name === null) return WASI_ENOENT;
                if (!p.node.dir) return WASI_ENOTDIR;
                if (p.node.dir.size > 0) return WASI_ENOTEMPTY;
                p.parent.dir.delete(p.name);
                return ok;
            },
            path_unlink_file(fd, path, pathLength) {
                const p = self.lookup(fd, self.text(path, pathLength));
                if (!p || !p.node || p.name === null) return WASI_ENOENT;
                if (p.node.dir) return WASI_EISDIR;
                p.parent.dir.delete(p.name);
                return ok;
            },
            path_rename(fd, path, pathLength, newFd, newPath, newLength) {
                const a = self.lookup(fd, self.text(path, pathLength));
                const b = self.lookup(newFd, self.text(newPath, newLength));
                if (!a || !a.node || !b || b.name === null || a.name === null) return WASI_ENOENT;
                a.parent.dir.delete(a.name);
                b.parent.dir.set(b.name, a.node);
                return ok;
            },
            poll_oneoff(subscriptions, events, count, done) {
                // sleeping cannot block the browser: every timeout has passed at once
                self.view().setUint32(done, 0, true);
                return ok;
            },
            random_get(ptr, len) {
                crypto.getRandomValues(self.u8().subarray(ptr, ptr + len));
                return ok;
            },
            sched_yield: () => ok,
            proc_exit(code) {
                throw new ExitStatus(code);
            },
        };
    }

    // ---- GLFW ----
    glfw() {
        const self = this;
        const v = () => self.view();
        const listen = () => {
            const canvas = self.canvas;
            if (!canvas || self.listening) return;
            self.listening = true;
            canvas.tabIndex = canvas.tabIndex >= 0 ? canvas.tabIndex : 0;
            const key = (e, action) => {
                const code = KEYS[e.code] ?? -1;
                if (code >= 0 || action === 1) e.preventDefault();
                self.events.push(() => {
                    if (code >= 0) self.keys.set(code, action === 0 ? 0 : 1);
                    self.callback(self.callbacks.key, 1, code, 0, action, modsOf(e));
                    if (action !== 0 && e.key.length === 1 && !e.ctrlKey && !e.metaKey)
                        self.callback(self.callbacks.char, 1, e.key.codePointAt(0));
                });
            };
            canvas.addEventListener("keydown", (e) => key(e, e.repeat ? 2 : 1));
            canvas.addEventListener("keyup", (e) => key(e, 0));
            const position = (e) => {
                const r = canvas.getBoundingClientRect();
                return [((e.clientX - r.left) * canvas.width) / r.width / self.pixelRatio, ((e.clientY - r.top) * canvas.height) / r.height / self.pixelRatio];
            };
            canvas.addEventListener("mousemove", (e) => {
                const [x, y] = position(e);
                self.events.push(() => {
                    self.cursor = [x, y];
                    self.callback(self.callbacks.cursor, 1, x, y);
                });
            });
            const button = (e, action) => {
                canvas.focus();
                const b = e.button === 1 ? 2 : e.button === 2 ? 1 : e.button;
                self.events.push(() => {
                    self.buttons[b] = action;
                    self.callback(self.callbacks.mouseButton, 1, b, action, modsOf(e));
                });
            };
            canvas.addEventListener("mousedown", (e) => button(e, 1));
            canvas.addEventListener("mouseup", (e) => button(e, 0));
            canvas.addEventListener("contextmenu", (e) => e.preventDefault());
            canvas.addEventListener("wheel", (e) => {
                e.preventDefault();
                self.events.push(() => self.callback(self.callbacks.scroll, 1, -e.deltaX / 100, -e.deltaY / 100));
            }, { passive: false });
        };
        // a frame of the browser: the program is suspended in the call (see run)
        const suspend = () => {
            if (self.rewinding) {
                self.instance.exports.__cs_wasm_stop_rewind();
                self.rewinding = false;
                const events = self.events;
                self.events = [];
                for (const e of events) e();
                return;
            }
            self.instance.exports.__cs_wasm_start_unwind(self.asyncData);
            self.suspended = true;
        };
        return {
            glfwInit: () => 1,
            glfwTerminate() {},
            glfwWindowHint() {},
            glfwSetErrorCallback: (cb) => {
                const old = self.callbacks.error ?? 0;
                self.callbacks.error = cb;
                return old;
            },
            glfwCreateWindow(width, height, title) {
                if (!self.canvas) return 0;
                self.pixelRatio = self.options.pixelRatio ?? 1;
                self.canvas.width = width * self.pixelRatio;
                self.canvas.height = height * self.pixelRatio;
                if (self.options.resizeCanvas !== false && !self.canvas.style.width) self.canvas.style.width = width + "px";
                if (self.options.setTitle !== false && title) document.title = self.cstring(title);
                listen();
                return 1;
            },
            glfwDestroyWindow() {},
            glfwMakeContextCurrent() {
                if (!self.gl) self.createContext();
            },
            glfwSwapInterval() {},
            glfwSwapBuffers() {},
            glfwPollEvents: suspend,
            glfwWaitEvents: suspend,
            glfwWaitEventsTimeout: suspend,
            glfwWindowShouldClose: () => self.shouldClose,
            glfwSetWindowShouldClose: (w, value) => {
                self.shouldClose = value;
            },
            glfwSetWindowTitle: (w, title) => {
                if (self.options.setTitle !== false) document.title = self.cstring(title);
            },
            glfwGetTime: () => (performance.now() - self.startTime) / 1000,
            glfwSetTime: (t) => {
                self.startTime = performance.now() - t * 1000;
            },
            glfwGetFramebufferSize(w, width, height) {
                if (width) v().setInt32(width, self.canvas.width, true);
                if (height) v().setInt32(height, self.canvas.height, true);
            },
            glfwGetWindowSize(w, width, height) {
                if (width) v().setInt32(width, self.canvas.width / self.pixelRatio, true);
                if (height) v().setInt32(height, self.canvas.height / self.pixelRatio, true);
            },
            glfwSetWindowSize(w, width, height) {
                self.canvas.width = width * self.pixelRatio;
                self.canvas.height = height * self.pixelRatio;
            },
            glfwGetCursorPos(w, x, y) {
                if (x) v().setFloat64(x, self.cursor[0], true);
                if (y) v().setFloat64(y, self.cursor[1], true);
            },
            glfwGetKey: (w, key) => self.keys.get(key) ?? 0,
            glfwGetMouseButton: (w, button) => self.buttons[button] ?? 0,
            glfwSetInputMode() {},
            glfwGetPrimaryMonitor: () => 0,
            glfwSetKeyCallback: (w, cb) => self.setCallback("key", cb),
            glfwSetCharCallback: (w, cb) => self.setCallback("char", cb),
            glfwSetCursorPosCallback: (w, cb) => self.setCallback("cursor", cb),
            glfwSetMouseButtonCallback: (w, cb) => self.setCallback("mouseButton", cb),
            glfwSetScrollCallback: (w, cb) => self.setCallback("scroll", cb),
            glfwSetFramebufferSizeCallback: (w, cb) => self.setCallback("framebufferSize", cb),
            glfwSetWindowSizeCallback: (w, cb) => self.setCallback("windowSize", cb),
            glfwGetProcAddress: (name) => self.procAddress(self.cstring(name)),
        };
    }

    setCallback(kind, cb) {
        const old = this.callbacks[kind] ?? 0;
        this.callbacks[kind] = cb;
        return old;
    }

    createContext() {
        const gl = this.canvas.getContext("webgl2", { antialias: true, preserveDrawingBuffer: true, alpha: false });
        if (!gl) throw new Error("this browser has no WebGL 2");
        this.gl = gl;
        this.names = { buffer: [null], texture: [null], vao: [null], program: [null], shader: [null], framebuffer: [null], renderbuffer: [null], query: [null], sampler: [null] };
        this.uniforms = new Map(); // program -> [locations]
        this.strings = new Map();
        this.raster = [-1, -1];
        this.zoom = [1, 1];
    }

    // the slot of the function table with a wrapper of an OpenGL function
    procAddress(name) {
        if (this.procs.has(name)) return this.procs.get(name);
        const entry = this.glFunctions()[name];
        if (!entry) return 0;
        const [signature, f] = entry;
        const wrapper = new WebAssembly.Instance(wrapperModule(signature), { env: { f } });
        const table = this.instance.exports.__indirect_function_table;
        const slot = table.grow(1);
        table.set(slot, wrapper.exports.f);
        this.procs.set(name, slot);
        return slot;
    }

    // ---- OpenGL on WebGL 2: name -> [signature, function] (signature: see wrapperModule) ----
    glFunctions() {
        if (this.glTable) return this.glTable;
        const self = this;
        const g = () => self.gl;
        const v = () => self.view();
        const names = (kind) => self.names[kind];
        const add = (kind, object) => {
            names(kind).push(object);
            return names(kind).length - 1;
        };
        const get = (kind, id) => names(kind)[id] ?? null;
        const gen = (kind, create) => (n, ptr) => {
            for (let i = 0; i < n; i++) v().setUint32(ptr + i * 4, add(kind, create()), true);
        };
        const del = (kind, destroy) => (n, ptr) => {
            for (let i = 0; i < n; i++) {
                const id = v().getUint32(ptr + i * 4, true);
                if (names(kind)[id]) destroy(names(kind)[id]);
                names(kind)[id] = null;
            }
        };
        const floats = (ptr, count) => new Float32Array(self.memory, ptr, count);
        const ints = (ptr, count) => new Int32Array(self.memory, ptr, count);
        const pixelsView = (type, ptr, size) => {
            if (!ptr) return null;
            if (type === 0x1406) return new Float32Array(self.memory, ptr, size / 4);
            if (type === 0x1403 || type === 0x8363 || type === 0x8033) return new Uint16Array(self.memory, ptr, size / 2);
            if (type === 0x1405 || type === 0x1404) return new Uint32Array(self.memory, ptr, size / 4);
            return new Uint8Array(self.memory, ptr, size);
        };
        const channels = (format) => ({ 0x1908: 4, 0x1907: 3, 0x1903: 1, 0x8227: 2, 0x1909: 1, 0x190a: 2, 0x1906: 1 })[format] ?? 4;
        const bytesPer = (type) => (type === 0x1406 || type === 0x1405 || type === 0x1404 ? 4 : type === 0x1403 || type === 0x1402 ? 2 : 1);
        const imageSize = (w, h, format, type) => {
            const row = w * channels(format) * bytesPer(type);
            const align = self.unpackAlignment ?? 4;
            return Math.ceil(row / align) * align * (h - 1) + row;
        };
        const uniform = (program, location) => {
            const list = self.uniforms.get(program);
            return list ? list[location] ?? null : null;
        };
        const location = (loc) => {
            if (loc < 0 || !self.currentProgram) return null;
            return uniform(self.currentProgram, loc);
        };
        const string = (key, text) => {
            if (!self.strings.has(key)) self.strings.set(key, self.newCString(text));
            return self.strings.get(key);
        };
        // GLSL of OpenGL 3.3 to GLSL ES 3.00
        const glsl = (source, kind) => {
            let s = source.replace(/^\s*#version\s+\d+(\s+core)?\s*$/m, "#version 300 es");
            if (!/^\s*#version/m.test(s)) s = "#version 300 es\n" + s;
            if (!/precision\s+\w+\s+float/.test(s))
                s = s.replace(/#version 300 es\s*\n/, `#version 300 es\nprecision highp float;\nprecision highp int;\n`);
            return s;
        };
        const T = {
            glGetError: ["i_", () => g().getError()],
            glGetString: ["i_i", (name) => {
                const gl = g();
                const text = name === 0x1f02 ? "3.3 (WebGL 2: " + gl.getParameter(gl.VERSION) + ")" : name === 0x1f01 ? gl.getParameter(gl.RENDERER) : name === 0x1f00 ? gl.getParameter(gl.VENDOR) : name === 0x8b8c ? "3.30" : "";
                return string("s" + name, text);
            }],
            glGetIntegerv: ["v_ii", (pname, ptr) => {
                const value = g().getParameter(pname);
                if (value instanceof Int32Array || Array.isArray(value)) ints(ptr, value.length).set(value);
                else v().setInt32(ptr, typeof value === "number" ? value : value ? 1 : 0, true);
            }],
            glGetFloatv: ["v_ii", (pname, ptr) => {
                const value = g().getParameter(pname);
                if (value instanceof Float32Array) floats(ptr, value.length).set(value);
                else v().setFloat32(ptr, value, true);
            }],
            glViewport: ["v_iiii", (x, y, w, h) => {
                self.viewportRect = [x, y, w, h];
                g().viewport(x, y, w, h);
            }],
            glScissor: ["v_iiii", (x, y, w, h) => g().scissor(x, y, w, h)],
            glClearColor: ["v_ffff", (r, gg, b, a) => g().clearColor(r, gg, b, a)],
            glClearDepth: ["v_d", (d) => g().clearDepth(d)],
            glClearDepthf: ["v_f", (d) => g().clearDepth(d)],
            glClear: ["v_i", (mask) => g().clear(mask)],
            glEnable: ["v_i", (cap) => {
                if (cap !== 0x809d && cap !== 0x8642 && cap !== 0x0b10 && cap !== 0x0b20) g().enable(cap); // not: multisample, program point size, smooth
            }],
            glDisable: ["v_i", (cap) => {
                if (cap !== 0x809d && cap !== 0x8642 && cap !== 0x0b10 && cap !== 0x0b20) g().disable(cap);
            }],
            glBlendFunc: ["v_ii", (s, d) => g().blendFunc(s, d)],
            glBlendFuncSeparate: ["v_iiii", (a, b, c, d) => g().blendFuncSeparate(a, b, c, d)],
            glBlendEquation: ["v_i", (m) => g().blendEquation(m)],
            glDepthFunc: ["v_i", (f) => g().depthFunc(f)],
            glDepthMask: ["v_i", (f) => g().depthMask(!!f)],
            glColorMask: ["v_iiii", (r, gg, b, a) => g().colorMask(!!r, !!gg, !!b, !!a)],
            glCullFace: ["v_i", (m) => g().cullFace(m)],
            glFrontFace: ["v_i", (m) => g().frontFace(m)],
            glLineWidth: ["v_f", (w) => g().lineWidth(w)],
            glPolygonMode: ["v_ii", () => {}],
            glFlush: ["v_", () => g().flush()],
            glFinish: ["v_", () => g().finish()],
            glPixelStorei: ["v_ii", (pname, value) => {
                if (pname === 0x0cf5) self.unpackAlignment = value;
                g().pixelStorei(pname, value);
            }],
            // shaders and programs
            glCreateShader: ["i_i", (kind) => add("shader", g().createShader(kind))],
            glDeleteShader: ["v_i", (id) => {
                if (get("shader", id)) g().deleteShader(get("shader", id));
                names("shader")[id] = null;
            }],
            glShaderSource: ["v_iiii", (id, count, strings, lengths) => {
                let source = "";
                for (let i = 0; i < count; i++) {
                    const ptr = v().getUint32(strings + i * 4, true);
                    const len = lengths ? v().getInt32(lengths + i * 4, true) : -1;
                    source += len < 0 ? self.cstring(ptr) : self.text(ptr, len);
                }
                const shader = get("shader", id);
                g().shaderSource(shader, glsl(source, g().getShaderParameter(shader, g().SHADER_TYPE)));
            }],
            glCompileShader: ["v_i", (id) => g().compileShader(get("shader", id))],
            glGetShaderiv: ["v_iii", (id, pname, ptr) => {
                const shader = get("shader", id);
                let value;
                if (pname === 0x8b84) value = (g().getShaderInfoLog(shader) ?? "").length + 1; // info log length
                else if (pname === 0x8b88) value = (g().getShaderSource(shader) ?? "").length + 1;
                else value = g().getShaderParameter(shader, pname);
                v().setInt32(ptr, typeof value === "boolean" ? (value ? 1 : 0) : value, true);
            }],
            glGetShaderInfoLog: ["v_iiii", (id, max, length, out) => writeLog(g().getShaderInfoLog(get("shader", id)), max, length, out)],
            glCreateProgram: ["i_", () => add("program", g().createProgram())],
            glDeleteProgram: ["v_i", (id) => {
                if (get("program", id)) g().deleteProgram(get("program", id));
                names("program")[id] = null;
            }],
            glAttachShader: ["v_ii", (p, s) => g().attachShader(get("program", p), get("shader", s))],
            glDetachShader: ["v_ii", (p, s) => g().detachShader(get("program", p), get("shader", s))],
            glBindAttribLocation: ["v_iii", (p, index, name) => g().bindAttribLocation(get("program", p), index, self.cstring(name))],
            glLinkProgram: ["v_i", (id) => {
                g().linkProgram(get("program", id));
                self.uniforms.set(id, [null]);
            }],
            glGetProgramiv: ["v_iii", (id, pname, ptr) => {
                const program = get("program", id);
                let value;
                if (pname === 0x8b84) value = (g().getProgramInfoLog(program) ?? "").length + 1;
                else value = g().getProgramParameter(program, pname);
                v().setInt32(ptr, typeof value === "boolean" ? (value ? 1 : 0) : value, true);
            }],
            glGetProgramInfoLog: ["v_iiii", (id, max, length, out) => writeLog(g().getProgramInfoLog(get("program", id)), max, length, out)],
            glUseProgram: ["v_i", (id) => {
                self.currentProgram = id;
                g().useProgram(get("program", id));
            }],
            glGetUniformLocation: ["i_ii", (id, name) => {
                const loc = g().getUniformLocation(get("program", id), self.cstring(name));
                if (!loc) return -1;
                const list = self.uniforms.get(id) ?? [null];
                self.uniforms.set(id, list);
                list.push(loc);
                return list.length - 1;
            }],
            glGetAttribLocation: ["i_ii", (id, name) => g().getAttribLocation(get("program", id), self.cstring(name))],
            glGetUniformBlockIndex: ["i_ii", (id, name) => g().getUniformBlockIndex(get("program", id), self.cstring(name))],
            glUniformBlockBinding: ["v_iii", (id, index, binding) => g().uniformBlockBinding(get("program", id), index, binding)],
            glUniform1i: ["v_ii", (l, a) => g().uniform1i(location(l), a)],
            glUniform2i: ["v_iii", (l, a, b) => g().uniform2i(location(l), a, b)],
            glUniform3i: ["v_iiii", (l, a, b, c) => g().uniform3i(location(l), a, b, c)],
            glUniform4i: ["v_iiiii", (l, a, b, c, d) => g().uniform4i(location(l), a, b, c, d)],
            glUniform1f: ["v_if", (l, a) => g().uniform1f(location(l), a)],
            glUniform2f: ["v_iff", (l, a, b) => g().uniform2f(location(l), a, b)],
            glUniform3f: ["v_ifff", (l, a, b, c) => g().uniform3f(location(l), a, b, c)],
            glUniform4f: ["v_iffff", (l, a, b, c, d) => g().uniform4f(location(l), a, b, c, d)],
            glUniform1iv: ["v_iii", (l, n, p) => g().uniform1iv(location(l), ints(p, n))],
            glUniform1fv: ["v_iii", (l, n, p) => g().uniform1fv(location(l), floats(p, n))],
            glUniform2fv: ["v_iii", (l, n, p) => g().uniform2fv(location(l), floats(p, n * 2))],
            glUniform3fv: ["v_iii", (l, n, p) => g().uniform3fv(location(l), floats(p, n * 3))],
            glUniform4fv: ["v_iii", (l, n, p) => g().uniform4fv(location(l), floats(p, n * 4))],
            glUniformMatrix2fv: ["v_iiii", (l, n, t, p) => g().uniformMatrix2fv(location(l), !!t, floats(p, n * 4))],
            glUniformMatrix3fv: ["v_iiii", (l, n, t, p) => g().uniformMatrix3fv(location(l), !!t, floats(p, n * 9))],
            glUniformMatrix4fv: ["v_iiii", (l, n, t, p) => g().uniformMatrix4fv(location(l), !!t, floats(p, n * 16))],
            // buffers and vertex arrays
            glGenBuffers: ["v_ii", gen("buffer", () => g().createBuffer())],
            glDeleteBuffers: ["v_ii", del("buffer", (b) => g().deleteBuffer(b))],
            glBindBuffer: ["v_ii", (target, id) => g().bindBuffer(target, get("buffer", id))],
            glBindBufferBase: ["v_iii", (target, index, id) => g().bindBufferBase(target, index, get("buffer", id))],
            glBufferData: ["v_iiii", (target, size, data, usage) => {
                if (data) g().bufferData(target, new Uint8Array(self.memory, data, size), usage);
                else g().bufferData(target, size, usage);
            }],
            glBufferSubData: ["v_iiii", (target, offset, size, data) => g().bufferSubData(target, offset, new Uint8Array(self.memory, data, size))],
            glGenVertexArrays: ["v_ii", gen("vao", () => g().createVertexArray())],
            glDeleteVertexArrays: ["v_ii", del("vao", (a) => g().deleteVertexArray(a))],
            glBindVertexArray: ["v_i", (id) => g().bindVertexArray(get("vao", id))],
            glVertexAttribPointer: ["v_iiiiii", (index, size, type, normalized, stride, offset) => g().vertexAttribPointer(index, size, type, !!normalized, stride, offset)],
            glVertexAttribIPointer: ["v_iiiii", (index, size, type, stride, offset) => g().vertexAttribIPointer(index, size, type, stride, offset)],
            glEnableVertexAttribArray: ["v_i", (i) => g().enableVertexAttribArray(i)],
            glDisableVertexAttribArray: ["v_i", (i) => g().disableVertexAttribArray(i)],
            glVertexAttribDivisor: ["v_ii", (i, d) => g().vertexAttribDivisor(i, d)],
            glDrawArrays: ["v_iii", (mode, first, count) => g().drawArrays(mode, first, count)],
            glDrawElements: ["v_iiii", (mode, count, type, offset) => g().drawElements(mode, count, type, offset)],
            glDrawArraysInstanced: ["v_iiii", (mode, first, count, n) => g().drawArraysInstanced(mode, first, count, n)],
            glDrawElementsInstanced: ["v_iiiii", (mode, count, type, offset, n) => g().drawElementsInstanced(mode, count, type, offset, n)],
            // textures
            glGenTextures: ["v_ii", gen("texture", () => g().createTexture())],
            glDeleteTextures: ["v_ii", del("texture", (t) => g().deleteTexture(t))],
            glBindTexture: ["v_ii", (target, id) => g().bindTexture(target, get("texture", id))],
            glActiveTexture: ["v_i", (unit) => g().activeTexture(unit)],
            glTexParameteri: ["v_iii", (target, pname, value) => g().texParameteri(target, pname, value)],
            glTexParameterf: ["v_iif", (target, pname, value) => g().texParameterf(target, pname, value)],
            glTexImage2D: ["v_iiiiiiiii", (target, level, internal, w, h, border, format, type, data) => {
                const gl = g();
                const internalFormat = internal === 0x1908 && type === 0x1401 ? gl.RGBA8 : internal === 0x1907 && type === 0x1401 ? gl.RGB8 : internal;
                gl.texImage2D(target, level, internalFormat, w, h, border, format, type, pixelsView(type, data, imageSize(w, h, format, type)));
            }],
            glTexSubImage2D: ["v_iiiiiiiii", (target, level, x, y, w, h, format, type, data) => g().texSubImage2D(target, level, x, y, w, h, format, type, pixelsView(type, data, imageSize(w, h, format, type)))],
            glGenerateMipmap: ["v_i", (target) => g().generateMipmap(target)],
            // framebuffers
            glGenFramebuffers: ["v_ii", gen("framebuffer", () => g().createFramebuffer())],
            glDeleteFramebuffers: ["v_ii", del("framebuffer", (f) => g().deleteFramebuffer(f))],
            glBindFramebuffer: ["v_ii", (target, id) => g().bindFramebuffer(target, get("framebuffer", id))],
            glFramebufferTexture2D: ["v_iiiii", (target, attachment, textarget, id, level) => g().framebufferTexture2D(target, attachment, textarget, get("texture", id), level)],
            glCheckFramebufferStatus: ["i_i", (target) => g().checkFramebufferStatus(target)],
            glGenRenderbuffers: ["v_ii", gen("renderbuffer", () => g().createRenderbuffer())],
            glDeleteRenderbuffers: ["v_ii", del("renderbuffer", (r) => g().deleteRenderbuffer(r))],
            glBindRenderbuffer: ["v_ii", (target, id) => g().bindRenderbuffer(target, get("renderbuffer", id))],
            glRenderbufferStorage: ["v_iiii", (target, format, w, h) => g().renderbufferStorage(target, format, w, h)],
            glFramebufferRenderbuffer: ["v_iiii", (target, attachment, rtarget, id) => g().framebufferRenderbuffer(target, attachment, rtarget, get("renderbuffer", id))],
            glReadBuffer: ["v_i", () => {}],
            glReadPixels: ["v_iiiiiii", (x, y, w, h, format, type, data) => g().readPixels(x, y, w, h, format, type, pixelsView(type, data, imageSize(w, h, format, type)))],
            // OpenGL 1.1: images drawn at the raster position, scaled by the pixel zoom
            glRasterPos2f: ["v_ff", (x, y) => {
                self.raster = [x, y];
            }],
            glRasterPos2i: ["v_ii", (x, y) => {
                self.raster = [x, y];
            }],
            glPixelZoom: ["v_ff", (x, y) => {
                self.zoom = [x, y];
            }],
            glDrawPixels: ["v_iiiii", (w, h, format, type, data) => self.drawPixels(w, h, format, type, pixelsView(type, data, imageSize(w, h, format, type)))],
        };
        const writeLog = (text, max, length, out) => {
            const bytes = new TextEncoder().encode(text ?? "");
            const n = Math.max(0, Math.min(bytes.length, max - 1));
            if (out && max > 0) {
                self.u8().set(bytes.subarray(0, n), out);
                self.u8()[out + n] = 0;
            }
            if (length) v().setInt32(length, n, true);
        };
        this.glTable = T;
        return T;
    }

    // glDrawPixels: the image as a texture on a rectangle from the raster position (window coordinates: the
    // viewport maps -1..1), w * zoom x wide and h * zoom y high (a negative zoom draws downwards)
    drawPixels(w, h, format, type, pixels) {
        const gl = this.gl;
        if (!this.pixelProgram) {
            const vs = gl.createShader(gl.VERTEX_SHADER);
            gl.shaderSource(vs, "#version 300 es\nin vec2 p; in vec2 t; out vec2 uv; void main() { uv = t; gl_Position = vec4(p, 0.0, 1.0); }");
            gl.compileShader(vs);
            const fs = gl.createShader(gl.FRAGMENT_SHADER);
            gl.shaderSource(fs, "#version 300 es\nprecision mediump float; in vec2 uv; uniform sampler2D image; out vec4 color; void main() { color = texture(image, uv); }");
            gl.compileShader(fs);
            const program = gl.createProgram();
            gl.attachShader(program, vs);
            gl.attachShader(program, fs);
            gl.bindAttribLocation(program, 0, "p");
            gl.bindAttribLocation(program, 1, "t");
            gl.linkProgram(program);
            this.pixelProgram = program;
            this.pixelTexture = gl.createTexture();
            this.pixelBuffer = gl.createBuffer();
            this.pixelVao = gl.createVertexArray();
            gl.bindVertexArray(this.pixelVao);
            gl.bindBuffer(gl.ARRAY_BUFFER, this.pixelBuffer);
            gl.enableVertexAttribArray(0);
            gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 16, 0);
            gl.enableVertexAttribArray(1);
            gl.vertexAttribPointer(1, 2, gl.FLOAT, false, 16, 8);
            gl.bindVertexArray(null);
        }
        const [vx, vy, vw, vh] = this.viewportRect ?? [0, 0, this.canvas.width, this.canvas.height];
        const px = ((this.raster[0] + 1) / 2) * vw + vx;
        const py = ((this.raster[1] + 1) / 2) * vh + vy;
        const qx = px + w * this.zoom[0];
        const qy = py + h * this.zoom[1];
        const nx = (x) => (x / this.canvas.width) * 2 - 1;
        const ny = (y) => (y / this.canvas.height) * 2 - 1;
        // row 0 of the image is at the raster position
        const quad = new Float32Array([nx(px), ny(py), 0, 0, nx(qx), ny(py), 1, 0, nx(px), ny(qy), 0, 1, nx(qx), ny(qy), 1, 1]);
        const savedProgram = gl.getParameter(gl.CURRENT_PROGRAM);
        const savedVao = gl.getParameter(gl.VERTEX_ARRAY_BINDING);
        const savedTexture = gl.getParameter(gl.TEXTURE_BINDING_2D);
        gl.useProgram(this.pixelProgram);
        gl.bindVertexArray(this.pixelVao);
        gl.bindBuffer(gl.ARRAY_BUFFER, this.pixelBuffer);
        gl.bufferData(gl.ARRAY_BUFFER, quad, gl.STREAM_DRAW);
        gl.bindTexture(gl.TEXTURE_2D, this.pixelTexture);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        gl.texImage2D(gl.TEXTURE_2D, 0, format === gl.RGB ? gl.RGB8 : gl.RGBA8, w, h, 0, format, type, pixels);
        gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
        gl.bindTexture(gl.TEXTURE_2D, savedTexture);
        gl.bindVertexArray(savedVao);
        gl.useProgram(savedProgram);
    }

    // ---- start and the frames ----
    async start(module) {
        const env = { ...this.glfw() };
        for (const [name, [, f]] of Object.entries(this.glFunctions())) env[name] = f;
        Object.assign(env, this.options.imports ?? {});
        // a function the program needs but nobody has: an error when it is called
        for (const entry of WebAssembly.Module.imports(module)) {
            if (entry.module === "env" && !(entry.name in env)) {
                env[entry.name] = () => {
                    throw new Error(`the program called '${entry.name}', which the browser does not have`);
                };
            }
        }
        this.instance = await WebAssembly.instantiate(module, { wasi_snapshot_preview1: this.wasi(), env });
        this.fds.set(3, { node: this.root, pos: 0 });
        if (this.instance.exports.__cs_wasm_start_unwind) {
            const size = 1 << 16;
            this.asyncData = this.instance.exports.malloc(size + 8);
            const v = this.view();
            v.setUint32(this.asyncData, this.asyncData + 8, true);
            v.setUint32(this.asyncData + 4, this.asyncData + 8 + size, true);
        }
        this.exited = new Promise((resolve, reject) => {
            this.resolveExit = resolve;
            this.rejectExit = reject;
        });
        this.step();
        return this;
    }

    step() {
        if (this.stopped) return;
        this.suspended = false;
        try {
            this.instance.exports._start();
        } catch (e) {
            if (e instanceof ExitStatus) {
                this.resolveExit(e.code);
                return;
            }
            this.onOutput(`\n${e.message ?? e}\n`, true);
            this.rejectExit(e);
            return;
        }
        if (!this.suspended) {
            this.resolveExit(0);
            return;
        }
        this.instance.exports.__cs_wasm_stop_unwind();
        requestAnimationFrame(() => {
            this.instance.exports.__cs_wasm_start_rewind(this.asyncData);
            this.rewinding = true;
            this.step();
        });
    }

    // ends the program at its next frame
    stop() {
        this.stopped = true;
        this.resolveExit(null);
    }
}

/**
 * Runs a program: the URL or the bytes of its .wasm. Options: canvas (for GLFW and OpenGL), args, env, files
 * ({ path: URL string | Uint8Array | ArrayBuffer }, fetched before the start), onOutput(text, isError), imports
 * (more functions of "env"), pixelRatio, setTitle (false: the window title does not become the page's title),
 * resizeCanvas (false: the canvas keeps its size on the page; glfwCreateWindow sets only its pixels).
 * @returns the program: program.exited is a promise of the exit code, program.stop() ends it.
 */
export async function run(wasm, options = {}) {
    const program = new Program(options);
    for (const [path, source] of Object.entries(options.files ?? {})) {
        let data;
        if (typeof source === "string") {
            const response = await fetch(source);
            if (!response.ok) throw new Error(`cannot load ${source} (${response.status})`);
            data = new Uint8Array(await response.arrayBuffer());
        } else data = source instanceof Uint8Array ? source : new Uint8Array(source);
        program.addFile(path, data);
    }
    let module;
    if (wasm instanceof WebAssembly.Module) module = wasm;
    else if (typeof wasm === "string") module = await WebAssembly.compileStreaming(fetch(wasm));
    else module = await WebAssembly.compile(wasm);
    return program.start(module);
}
