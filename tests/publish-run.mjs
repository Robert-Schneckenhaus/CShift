// Runs a page of "cshiftc publish" without a browser: the program, the assets and the runtime that the page holds (its
// module script up to the page's own code), with node. The output goes to stdout and stderr, the exit code is the
// program's.
//
//   node tests/publish-run.mjs page.html

import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const html = await readFile(process.argv[2], "utf8");
const program = /<script type="application\/octet-stream" id="program">([^<]*)<\/script>/.exec(html);
const module = /<script type="module">([\s\S]*)<\/script>/.exec(html);
if (!program || !module) throw new Error("not a page of cshiftc publish");
const end = module[1].indexOf("// ---- the page");
if (end < 0) throw new Error("the page's own code is missing");
const unescape = (text) => text.replace(/&quot;/g, '"').replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&");
const files = {};
for (const [, path, data] of html.matchAll(/<script type="application\/octet-stream" data-asset="([^"]*)">([^<]*)<\/script>/g))
    files["/" + unescape(path)] = new Uint8Array(Buffer.from(data, "base64"));

const dir = await mkdtemp(join(tmpdir(), "publish-"));
try {
    await writeFile(join(dir, "runtime.mjs"), module[1].slice(0, end));
    const { run } = await import(pathToFileURL(join(dir, "runtime.mjs")).href);
    const started = await run(new Uint8Array(Buffer.from(program[1].trim(), "base64")), {
        files,
        onOutput: (text, isError) => (isError ? process.stderr : process.stdout).write(text),
    });
    process.exitCode = (await started.exited) ?? 1;
} finally {
    await rm(dir, { recursive: true, force: true });
}
