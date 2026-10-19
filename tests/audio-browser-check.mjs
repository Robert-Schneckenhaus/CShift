// System.Audio in real browsers: a page of "cshiftc publish" of tests/audio/browser.cshift, opened as a file (file://)
// with Playwright in Chromium and Firefox (those that are installed). The page is clicked first (browsers start the
// sound only after the user did something on the page), then the program plays a second of a tone with Web Audio:
// it must take about a second (the output plays in real time, and does not end before the sound was heard). Without
// Playwright it says so and ends with 0. CSHIFT_BROWSERS (e.g. "chromium,firefox", in CI) names browsers that must be
// there.
//
//   cshiftc publish tests/audio/browser.cshift -o audio.html && node tests/audio-browser-check.mjs audio.html

import { createRequire } from "node:module";
import { execSync } from "node:child_process";
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
        console.log("audio in a real browser: skipped (no Playwright)");
        process.exit(0);
    }
}

const page = pathToFileURL(resolve(process.argv[2])).href;
const required = (process.env.CSHIFT_BROWSERS ?? "").split(",").filter((b) => b.length > 0);
const failures = [];
const tested = [];

for (const name of ["chromium", "firefox"]) {
    let browser;
    try {
        // Firefox: sound without a click of the user, and without a sound device (a runner of the CI) a context that
        // plays into nothing on a clock of its own (else its clock stands still); Chromium headless has both anyway
        browser = await playwright[name].launch(name === "firefox" ? {
            firefoxUserPrefs: { "media.autoplay.default": 0, "media.autoplay.blocking_policy": 0,
                                "media.cubeb.force_null_context": true },
        } : {});
    } catch {
        if (required.includes(name)) failures.push(`${name}: cannot be started`);
        else console.log(`${name}: not installed`);
        continue;
    }
    tested.push(name);
    try {
        const p = await (await browser.newContext()).newPage();
        const lines = [];
        p.on("console", (m) => lines.push(...m.text().split("\n")));
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
        const waitFor = async (prefix, ms) => {
            const end = Date.now() + ms;
            while (Date.now() < end) {
                const line = lines.find((l) => l.startsWith(prefix));
                if (line) return line;
                await new Promise((r) => setTimeout(r, 20));
            }
            return null;
        };
        if (!(await waitFor("audio: open", 10000))) {
            failures.push(`${name}: the output did not open (${lines.slice(0, 3).join(" | ")})`);
            continue;
        }
        await p.mouse.click(100, 50);
        const done = await waitFor("audio: done", 10000);
        if (!done) {
            failures.push(`${name}: the second was not played (${lines.filter((l) => l.startsWith("audio")).slice(-3).join(" | ")})`);
            continue;
        }
        const seconds = Number(done.split(" ")[3]);
        if (!(seconds >= 0.8 && seconds <= 3.0)) failures.push(`${name}: a second of sound took ${seconds} s`);
        else console.log(`${name}: ok (${seconds} s)`);
    } finally {
        await browser.close();
    }
}
for (const f of failures) console.log(`FAILED: ${f}`);
if (tested.length === 0) console.log("audio in a real browser: skipped (no browser of Playwright installed)");
else console.log(`audio in a real browser: ${failures.length === 0 ? "ok" : `${failures.length} failed`} (${tested.join(", ")})`);
process.exit(failures.length === 0 ? 0 : 1);
