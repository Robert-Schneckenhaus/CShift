// Checks a running "cshiftc serve" of tests/publish/assets (a copy): the page and the number of the build, a new build
// after a change of a source, the page with the errors after a broken change, and a working build again.
//
//   node tests/serve-check.mjs <port> <the copied project folder>

import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";

const [port, project] = process.argv.slice(2);
const base = `http://127.0.0.1:${port}`;
const source = join(project, "src", "main.csh");

async function get(path) {
    const answer = await fetch(base + path, { cache: "no-store" });
    return { status: answer.status, text: await answer.text() };
}

// waits until the number of the build is 'number' (the server may still be starting)
async function waitForBuild(number) {
    const end = Date.now() + 60000;
    let last = "";
    while (Date.now() < end) {
        try {
            last = (await get("/__cshift/build")).text.trim();
            if (last === String(number)) return;
        } catch {}
        await new Promise((resolve) => setTimeout(resolve, 200));
    }
    throw new Error(`build ${number} did not come (last: '${last}')`);
}

function check(condition, message) {
    if (!condition) throw new Error(message);
}

await waitForBuild(1);
let page = await get("/");
check(page.status === 200, `the page: status ${page.status}`);
check(page.text.includes('id="program"') && page.text.includes("data-asset="), "the page holds no program or assets");
check(page.text.includes("/__cshift/build"), "the page does not reload itself");
check((await get("/missing")).status === 404, "a missing path is not 404");

const text = await readFile(source, "utf8");
await writeFile(source, text.replace("Hello from the page", "Hello again"));
await waitForBuild(2);

await writeFile(source, text.replace("return 3;", "return 3"));
await waitForBuild(3);
page = await get("/");
check(page.text.includes("The build failed") && page.text.includes("main.csh"), "no errors on the page of a failed build");
check(page.text.includes("/__cshift/build"), "the page of the errors does not reload itself");

await writeFile(source, text);
await waitForBuild(4);
page = await get("/");
check(page.text.includes('id="program"'), "the page did not come back after the errors were fixed");
console.log("serve ok");
