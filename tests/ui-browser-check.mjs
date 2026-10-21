// System.Ui in real browsers: a page of "cshiftc publish" of tests/ui/browser.cshift, opened as a file (file://) with
// Playwright, in every browser of Playwright that is installed (Chromium, Firefox, WebKit), at the pixel ratios 1, 1.25,
// 1.5 and 2. It drags the slider with the mouse, clicks the area quickly and with a 100 ms press, drags the slider by
// touch (Chromium), opens files with the browser's file chooser (one, several, a folder) and saves a download.
// Without Playwright it says so and ends with 0. CSHIFT_BROWSERS (e.g. "chromium,firefox", in CI) names browsers that
// must be there: one that cannot be started is then a failure.
//
//   cshiftc publish tests/ui/browser.cshift -o browser.html && node tests/ui-browser-check.mjs browser.html

import { createRequire } from "node:module";
import { execSync } from "node:child_process";
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

let playwright;
try {
    playwright = await import("playwright");
} catch {
    try {
        const root = execSync("npm root -g", { encoding: "utf8" }).trim();
        playwright = createRequire(join(root, "noop.js"))("playwright");
    } catch {
        console.log("ui in a real browser: skipped (no Playwright)");
        process.exit(0);
    }
}

const page = pathToFileURL(resolve(process.argv[2])).href;
const failures = [];
const fail = (what) => {
    failures.push(what);
    console.log(`FAILED: ${what}`);
};

// files to open: two in a folder, the folder with a sub folder
const files = await mkdtemp(join(tmpdir(), "ui-browser-"));
await writeFile(join(files, "one.txt"), "first file");
await writeFile(join(files, "two.txt"), "second file");
await mkdir(join(files, "data", "sub"), { recursive: true });
await writeFile(join(files, "data", "a.bin"), "a");
await writeFile(join(files, "data", "sub", "b.bin"), "b");

// the output of the program, line by line, and waiting for a line
class Output {
    constructor(p) {
        this.lines = [];
        p.on("console", (m) => {
            for (const line of m.text().split("\n")) if (line.length > 0) this.lines.push(line);
        });
    }
    async waitFor(prefix, after = 0, ms = 5000) {
        const end = Date.now() + ms;
        while (Date.now() < end) {
            const line = this.lines.slice(after).find((l) => l.startsWith(prefix));
            if (line) return line;
            await new Promise((r) => setTimeout(r, 20));
        }
        return null;
    }
    last(prefix) {
        return [...this.lines].reverse().find((l) => l.startsWith(prefix)) ?? null;
    }
}

async function check(name, browserType, ratio, touch) {
    const tag = `${name} ${ratio}${touch ? " touch" : ""}`;
    let browser;
    try {
        browser = await browserType.launch();
    } catch {
        console.log(`${name}: not installed`);
        return false;
    }
    try {
        const context = await browser.newContext({ deviceScaleFactor: ratio, hasTouch: touch, acceptDownloads: true,
                                                    viewport: { width: 800, height: 700 } });
        const p = await context.newPage();
        const out = new Output(p);
        // the file choosers of the page (listened to from the start: Playwright then takes them over; one that opens
        // before would be cancelled by the browser without a window)
        const choosers = [];
        p.on("filechooser", (c) => choosers.push(c));
        // the page prints the output into its <pre> and to the console of the page through onOutput? it prints into the
        // page only: mirror the <pre> to the console
        await p.addInitScript(() => {
            const observe = () => {
                const pre = document.getElementById("output");
                if (!pre) return setTimeout(observe, 10);
                new MutationObserver((records) => {
                    for (const r of records) for (const n of r.addedNodes) console.log(n.textContent);
                }).observe(pre, { childList: true });
            };
            observe();
        });
        await p.goto(page);
        if (!(await out.waitFor("layout "))) return fail(`${tag}: the program did not start (${out.lines.slice(0, 3).join(" | ")})`), true;
        await p.waitForTimeout(300); // the layout settles
        const n = out.last("layout ").split(" ").slice(1).map(Number);
        const scale = n[0];
        const [sx, sy, sw, sh] = n.slice(2, 6);
        const [ax, ay, aw, ah] = n.slice(7, 11);
        const canvas = await p.locator("canvas").boundingBox();
        // canvas pixels -> CSS pixels of the page
        const cssPerPixel = canvas.width / (await p.evaluate(() => document.querySelector("canvas").width));
        const at = (x, y) => ({ x: canvas.x + x * cssPerPixel, y: canvas.y + y * cssPerPixel });
        const thumb = Math.round(8 * scale);
        const track = (f) => at(sx + thumb + (sw - 2 * thumb) * f, sy + sh / 2);

        // ---- the slider: dragged with the mouse ----
        if (!touch) {
            const from = track(0.1);
            const to = track(0.7);
            await p.mouse.move(from.x, from.y);
            await p.mouse.down();
            for (let i = 1; i <= 5; i++) await p.mouse.move(from.x + ((to.x - from.x) * i) / 5, from.y, { steps: 2 });
            await p.mouse.up();
            await p.waitForTimeout(150);
            const v = Number(out.last("slider ")?.split(" ")[1]);
            if (!(v >= 66 && v <= 74)) fail(`${tag}: the slider dragged to 70 shows ${v}`);
        } else if (name === "chromium") {
            // by touch: pointer events of a finger (CDP), as on a phone
            const cdp = await context.newCDPSession(p);
            const from = track(0.2);
            const to = track(0.6);
            const touchAt = (type, pt) => cdp.send("Input.dispatchTouchEvent", { type, touchPoints: type === "touchEnd" ? [] : [{ x: pt.x, y: pt.y }] });
            await touchAt("touchStart", from);
            for (let i = 1; i <= 5; i++) await touchAt("touchMove", { x: from.x + ((to.x - from.x) * i) / 5, y: from.y });
            await touchAt("touchEnd", to);
            await p.waitForTimeout(150);
            const v = Number(out.last("slider ")?.split(" ")[1]);
            if (!(v >= 56 && v <= 64)) fail(`${tag}: the slider dragged by touch to 60 shows ${v}`);
        }

        // ---- the area: a quick click, a click held for 100 ms (and a tap) ----
        const center = at(ax + aw / 2, ay + ah / 2);
        const clicks = out.lines.length;
        if (touch) await p.touchscreen.tap(center.x, center.y);
        else await p.mouse.click(center.x, center.y);
        if (!(await out.waitFor("click ", clicks, 2000))) fail(`${tag}: a quick ${touch ? "tap" : "click"} on the area is not a click`);
        if (!touch) {
            const slow = out.lines.length;
            await p.mouse.click(center.x, center.y, { delay: 100 });
            if (!(await out.waitFor("click ", slow, 2000))) fail(`${tag}: a click of 100 ms on the area is not a click`);
            if (!(await out.waitFor("held ", slow, 2000))) fail(`${tag}: the area is not held while the button is down (${out.lines.slice(-6).join(" | ")})`);
        }

        // ---- the file chooser: one file, several, a folder; a download ----
        if (!touch && ratio === 1.5) {
            const button = async (i) => {
                const pt = at(n[11 + 2 * i], n[12 + 2 * i]);
                await p.mouse.click(pt.x, pt.y);
            };
            // the dialog of a button: its button "Choose file..." is armed on the canvas. A click on the button of the
            // program can come in a frame that does not take it (seldom, on a busy runner): then it is clicked again,
            // once, before the check fails
            const open = async (i) => {
                await button(i);
                const armed = () => p.waitForFunction(() => document.querySelector("canvas").dataset.fileButton, null,
                                                       { timeout: 3000 }).then(() => true, () => false);
                if (await armed()) return;
                await button(i);
                if (!(await armed())) throw new Error(`button ${i} opens no dialog: ${out.lines.slice(-4).join(" | ")}`);
            };
            const choose = async (paths) => {
                await p.waitForTimeout(200); // the dialog settles (its first frame finds its size)
                const arm = await p.evaluate(() => document.querySelector("canvas").dataset.fileButton);
                if (!arm) throw new Error(`the dialog closed: ${out.lines.slice(-5).join(" | ")}`);
                const [x, y, w, h] = arm.split(",").map(Number);
                const pt = at(x + w / 2, y + h / 2);
                const before = choosers.length;
                await p.mouse.click(pt.x, pt.y);
                for (let i = 0; i < 150 && choosers.length === before; i++) await p.waitForTimeout(20);
                if (choosers.length === before) throw new Error(`no file chooser: ${out.lines.slice(-4).join(" | ")}`);
                await choosers[choosers.length - 1].setFiles(paths);
            };
            let mark = out.lines.length;
            await open(0);
            await choose(join(files, "one.txt"));
            const one = await out.waitFor("opened ", mark);
            if (one !== "opened 1 /home/web_user/files/one.txt first file") fail(`${tag}: open one file: ${one}`);
            mark = out.lines.length;
            await open(1);
            await choose([join(files, "one.txt"), join(files, "two.txt")]);
            const many = await out.waitFor("opened ", mark);
            if (many !== "opened 2 /home/web_user/files/one.txt first file") fail(`${tag}: open two files: ${many}`);
            mark = out.lines.length;
            await open(3);
            await choose(join(files, "data"));
            const folder = await out.waitFor("folder ", mark);
            if (folder !== "folder /home/web_user/files/data 2") fail(`${tag}: open a folder: ${folder}`);
            // save: the name, then one download
            mark = out.lines.length;
            await button(2);
            await p.waitForTimeout(200);
            const downloads = [];
            p.on("download", (d) => downloads.push(d));
            await p.keyboard.type("result.txt");
            await p.keyboard.press("Enter");
            const saved = await out.waitFor("saved ", mark);
            await p.waitForTimeout(500);
            if (saved !== "saved /home/web_user/downloads/result.txt") fail(`${tag}: save: ${saved}`);
            if (downloads.length !== 1) fail(`${tag}: ${downloads.length} downloads instead of 1`);
            else {
                const where = join(files, "downloaded.txt");
                await downloads[0].saveAs(where);
                const text = (await import("node:fs")).readFileSync(where, "utf8");
                if (downloads[0].suggestedFilename() !== "result.txt" || text !== "saved by the program")
                    fail(`${tag}: the download is ${downloads[0].suggestedFilename()}: '${text}'`);
            }
        }
        console.log(`${tag}: ok`);
        return true;
    } finally {
        await browser.close();
    }
}

const tested = [];
for (const name of ["chromium", "firefox", "webkit"]) {
    let any = false;
    for (const ratio of [1, 1.25, 1.5, 2]) any = (await check(name, playwright[name], ratio, false)) || any;
    if (any) {
        if (name !== "firefox") await check(name, playwright[name], 2, true); // Firefox: no touch in Playwright
        tested.push(name);
    }
}
await rm(files, { recursive: true, force: true });
for (const name of (process.env.CSHIFT_BROWSERS ?? "").split(",").filter((n) => n.length > 0)) {
    if (!tested.includes(name)) fail(`${name} was asked for (CSHIFT_BROWSERS) but cannot be started`);
}
if (tested.length === 0) {
    console.log("ui in a real browser: skipped (no browser of Playwright installed)");
    process.exit(0);
}
console.log(`ui in a real browser: ${failures.length === 0 ? "ok" : `${failures.length} failed`} (${tested.join(", ")})`);
process.exit(failures.length === 0 ? 0 : 1);
