// Generates the content of the site (src/content/docs) before Astro builds it:
//
//   - the guides: docs/**/*.md, with a title from their first heading and their links rewritten to the pages of the
//     site (links to other files of the repository go to GitHub);
//   - the reference: pages for the namespaces and types of the standard library and the built-in types, from the JSON
//     of `cshiftc doc` (the host and the AmigaOS part).
//
// The JSON comes from $CSHIFTC (a cshiftc that knows `doc`, run on ../stdlib) or from api/*.json if it is there.
// Generated files are not committed (see .gitignore).

import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const site = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const root = path.resolve(site, "..");
const content = path.join(site, "src/content/docs");
const base = process.env.SITE_BASE ?? "/CShift/v0";
const repo = "https://github.com/Robert-Schneckenhaus/CShift";
const branch = process.env.SITE_BRANCH ?? "master";
// the version that is built ("dev" outside of a release) and the versions of the site (one per major release)
const version = process.env.SITE_VERSION ?? "dev";
const versions = process.env.SITE_VERSIONS ? JSON.parse(process.env.SITE_VERSIONS) : [];

// ---------------------------------------------------------------------------------------------------------------------
// Guides
// ---------------------------------------------------------------------------------------------------------------------

// The folders of docs/ that are sections of their own on the site (the language guide, the language reference); the
// other files are the topics under /docs/.
const sections = ["language", "spec"];

// docs/<file> -> the page's path on the site (without base), e.g. language/basics.md -> /language/basics/
function guideUrl(rel) {
    let p = rel.replace(/\\/g, "/").replace(/\.md$/, "");
    if (p === "README") return "/docs/";
    for (const s of sections) {
        if (p === s + "/README") return "/" + s + "/";
        if (p.startsWith(s + "/")) return "/" + p + "/";
    }
    return "/docs/" + p + "/";
}

function guideFile(rel) {
    const url = guideUrl(rel);
    // a flat file per page (a directory per page would become a group in the sidebar)
    return url.endsWith("/docs/") || sections.some((s) => url === "/" + s + "/")
        ? path.join(content, url.slice(1), "index.md")
        : path.join(content, url.slice(1, -1) + ".md");
}

// The order of the language guide's chapters: the order of the links in language/README.md.
function chapterOrder() {
    const text = fs.readFileSync(path.join(root, "docs/language/README.md"), "utf8");
    const order = new Map();
    let n = 1;
    for (const m of text.matchAll(/^\d+\.\s+\[[^\]]*\]\(([^)#]+\.md)\)/gm)) order.set(m[1], n++);
    return order;
}

// The order of the other guides: the order of the links in the table of docs/README.md (of docs/spec/README.md for the
// language reference).
function topicOrder(readme = "docs/README.md") {
    const text = fs.readFileSync(path.join(root, readme), "utf8");
    const order = new Map();
    let n = 1;
    for (const m of text.matchAll(/^\| \[[^\]]*\]\(([^)#]+\.md)\)/gm)) order.set(m[1], n++);
    return order;
}

function rewriteLinks(markdown, fromRel) {
    const fromDir = path.posix.dirname("docs/" + fromRel.replace(/\\/g, "/"));
    let fence = false;
    return markdown
        .split("\n")
        .map((line) => {
            if (/^\s*(```|~~~)/.test(line)) fence = !fence;
            if (fence) return line;
            return line.replace(/\]\(([^)\s]+)\)/g, (all, target) => {
                if (/^[a-z]+:|^#|^\//i.test(target)) return all;
                const [file, anchor] = target.split("#");
                const resolved = path.posix.normalize(path.posix.join(fromDir, file));
                let url;
                if (resolved.startsWith("docs/") && resolved.endsWith(".md")) {
                    url = base + guideUrl(resolved.slice(5));
                } else {
                    const isDir = fs.existsSync(path.join(root, resolved)) && fs.statSync(path.join(root, resolved)).isDirectory();
                    url = `${repo}/${isDir ? "tree" : "blob"}/${branch}/${resolved}`;
                }
                return "](" + url + (anchor ? "#" + anchor : "") + ")";
            });
        })
        .join("\n");
}

function yamlString(s) {
    return JSON.stringify(s);
}

function writeGuides() {
    const order = chapterOrder();
    const topics = topicOrder();
    const specChapters = topicOrder("docs/spec/README.md");
    const files = [];
    (function walk(dir) {
        for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
            const full = path.join(dir, e.name);
            if (e.isDirectory()) walk(full);
            else if (e.name.endsWith(".md")) files.push(path.relative(path.join(root, "docs"), full));
        }
    })(path.join(root, "docs"));
    for (const rel of files) {
        let text = fs.readFileSync(path.join(root, "docs", rel), "utf8");
        const h1 = text.match(/^# (.+)$/m);
        const title = h1 ? h1[1].trim() : path.basename(rel, ".md");
        if (h1) text = text.replace(h1[0] + "\n", "");
        const relPosix = rel.replace(/\\/g, "/");
        const front = ["---", "title: " + yamlString(title.replace(/`/g, ""))];
        if (relPosix.startsWith("language/")) {
            const chapter = order.get(relPosix.slice(9));
            if (relPosix === "language/README.md") front.push("sidebar:", "  label: Overview", "  order: 0");
            else if (chapter) front.push("sidebar:", "  order: " + chapter);
        } else if (relPosix.startsWith("spec/")) {
            if (relPosix === "spec/README.md") front.push("sidebar:", "  label: Overview", "  order: 0");
            else front.push("sidebar:", "  order: " + (specChapters.get(relPosix.slice(5)) ?? 100));
        } else if (relPosix === "README.md") {
            front.push("sidebar:", "  label: Overview", "  order: 0");
        } else {
            front.push("sidebar:", "  order: " + (topics.get(relPosix) ?? 100));
        }
        front.push("editUrl: " + yamlString(`${repo}/edit/${branch}/docs/${relPosix}`), "---", "");
        const out = guideFile(rel);
        fs.mkdirSync(path.dirname(out), { recursive: true });
        fs.writeFileSync(out, front.join("\n") + rewriteLinks(text, rel));
    }
    return files.length;
}

// ---------------------------------------------------------------------------------------------------------------------
// Reference
// ---------------------------------------------------------------------------------------------------------------------

function loadApi() {
    const apiDir = path.join(site, "api");
    if (process.env.CSHIFTC) {
        fs.mkdirSync(apiDir, { recursive: true });
        const run = (target, file) => {
            const args = ["doc", "--require-docs", "--stdlib", path.join(root, "stdlib"), "-o", path.join(apiDir, file)];
            if (target) args.push("--target", target);
            execFileSync(process.env.CSHIFTC, args, { stdio: "inherit" });
        };
        run("", "host.json");
        run("m68k-amigaos", "amiga.json");
    }
    const read = (f) => (fs.existsSync(path.join(apiDir, f)) ? JSON.parse(fs.readFileSync(path.join(apiDir, f), "utf8")) : null);
    const host = read("host.json");
    const amiga = read("amiga.json");
    if (!host) return null;
    // the AmigaOS part: what only the m68k-amigaos target has
    const known = new Set(host.items.map((i) => i.namespace + "." + i.name + "." + i.kind));
    const amigaOnly = amiga ? amiga.items.filter((i) => !known.has(i.namespace + "." + i.name + "." + i.kind)) : [];
    for (const i of amigaOnly) i.amiga = true;
    const namespaces = [...host.namespaces];
    for (const n of amiga ? amiga.namespaces : []) if (!namespaces.some((h) => h.name === n.name)) namespaces.push({ ...n, amiga: true });
    return { version: host.version, namespaces, items: [...host.items, ...amigaOnly] };
}

const slug = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
// the page of a namespace: "" (the global one) and the built-in types have their own
const nsSlug = (ns) => (ns === "" ? "global" : slug(ns));
const hasPage = (item) => ["struct", "interface", "enum", "error", "union"].includes(item.kind);

function itemGroup(item) {
    return item.builtin ? "builtin" : nsSlug(item.namespace);
}

function itemUrl(item) {
    return `${base}/reference/${itemGroup(item)}/${hasPage(item) ? slug(item.name) + "/" : "#" + slug(item.name)}`;
}

// The names a link ([List<T>.Add]) can use -> the URL of the page or section.
function linkTargets(api) {
    const map = new Map();
    const add = (key, url) => {
        if (!map.has(key)) map.set(key, url);
    };
    for (const n of api.namespaces) if (n.name) add(n.name, `${base}/reference/${nsSlug(n.name)}/`);
    for (const item of api.items) {
        const url = itemUrl(item);
        add(item.name, url);
        if (item.namespace) add(item.namespace + "." + item.name, url);
        for (const m of item.members ?? []) {
            const murl = url.replace(/#.*$/, "") + "#" + slug(m.name);
            add(item.name + "." + m.name, murl);
            if (item.namespace) add(item.namespace + "." + item.name + "." + m.name, murl);
        }
    }
    return map;
}

const linkKey = (s) => {
    let depth = 0;
    let out = "";
    for (const c of s) {
        if (c === "<") depth++;
        else if (c === ">") depth--;
        else if (depth === 0 && c !== " ") out += c;
    }
    return out;
};

// Markdown of a doc comment: [Name] becomes a link to the declaration, code blocks without a language are CShift.
function renderMarkdown(text, targets) {
    if (!text) return "";
    let fence = false;
    return text
        .split("\n")
        .map((line) => {
            const t = line.trim();
            if (t.startsWith("```")) {
                fence = !fence;
                return fence && t === "```" ? line.replace("```", "```cshift") : line;
            }
            if (fence) return line;
            let out = "";
            let code = false;
            for (let i = 0; i < line.length; i++) {
                const c = line[i];
                if (c === "`") code = !code;
                if (c === "[" && !code) {
                    const close = line.indexOf("]", i + 1);
                    const next = line[close + 1];
                    const inner = close > i ? line.slice(i + 1, close) : "";
                    if (close > i + 1 && next !== "(" && next !== "[" && /^[A-Za-z_][\w.<>, ]*$/.test(inner)) {
                        const url = targets.get(linkKey(inner));
                        out += url ? `[\`${inner}\`](${url})` : "`" + inner + "`";
                        i = close;
                        continue;
                    }
                }
                out += !code && c === "<" ? "&lt;" : c;
            }
            return out;
        })
        .join("\n");
}

// The parts of a doc comment after the description: parameters, result, errors, panics, ...
function renderTags(doc, targets) {
    if (!doc) return "";
    const r = (s) => renderMarkdown(s, targets);
    const out = [];
    if (doc.params.length) out.push("**Parameters**\n\n" + doc.params.map((p) => `- \`${p.name}\`: ${r(p.text)}`).join("\n"));
    if (doc.returns) out.push("**Returns** " + r(doc.returns));
    if (doc.errors.length) out.push("**Errors**\n\n" + doc.errors.map((e) => `- ${r("[" + e.name + "]")}: ${r(e.text)}`).join("\n"));
    if (doc.panics) out.push("**Panics** " + r(doc.panics));
    if (doc.deprecated) out.push(":::caution[Deprecated]\n" + r(doc.deprecated) + "\n:::");
    if (doc.see.length) out.push("**See also** " + doc.see.map((s) => r("[" + s.name + "]") + (s.text ? " " + r(s.text) : "")).join(", "));
    if (doc.since) out.push(`<span class="cs-since">Since ${doc.since}</span>`);
    return out.join("\n\n");
}

const code = (signature) => "```cshift\n" + signature + "\n```";
const summary = (doc, targets) => (doc ? renderMarkdown(doc.summary, targets).replace(/\n/g, " ").replace(/\|/g, "\\|") : "");

// The members (or functions) of one name: a heading, then each overload's signature and documentation.
function renderMembers(name, list, targets, level) {
    const parts = [`${"#".repeat(level)} ${name}`];
    for (const m of list) {
        parts.push(code(m.signature));
        if (m.doc) {
            parts.push(renderMarkdown(m.doc.description, targets));
            const tags = renderTags(m.doc, targets);
            if (tags) parts.push(tags);
        }
    }
    return parts.join("\n\n");
}

// A summary table of members, then their sections.
function renderMemberList(label, list, targets) {
    const names = [...new Set(list.map((m) => m.name))];
    const parts = [`## ${label}\n\n| Name | Description |\n|---|---|\n` +
        names.map((n) => `| [\`${n}\`](#${slug(n)}) | ${summary(list.find((m) => m.name === n).doc, targets)} |`).join("\n")];
    for (const n of names) parts.push(renderMembers(n, list.filter((m) => m.name === n), targets, 3));
    return parts.join("\n\n");
}

function frontMatter(title, description, extra = []) {
    return ["---", "title: " + yamlString(title), "description: " + yamlString(description || title), ...extra, "---", ""].join("\n");
}

const kindName = { struct: "Struct", interface: "Interface", enum: "Enum", error: "Error enum", union: "Union" };

function typeTitle(item) {
    const m = item.signature.match(/^(?:struct|interface|union|enum|error) ([^\s:]+)/);
    return m ? m[1] : item.name;
}

function renderTypePage(item, targets) {
    const nsLabel = item.builtin ? "built-in type" : item.namespace ? `namespace ${item.namespace}` : "global namespace";
    const parts = [frontMatter(typeTitle(item), item.doc ? item.doc.summary : "")];
    const since = item.doc && item.doc.since ? ` · <span class="cs-since">Since ${item.doc.since}</span>` : "";
    parts.push(`<p class="cs-kind">${kindName[item.kind]} · ${nsLabel}${item.amiga ? " · AmigaOS only" : ""}${since}</p>`);
    parts.push(code(item.signature));
    if (item.doc) {
        parts.push(renderMarkdown(item.doc.description, targets));
        const tags = renderTags({ ...item.doc, since: "" }, targets);
        if (tags) parts.push(tags);
    }
    const members = item.members ?? [];
    const groups = [
        ["Values", members.filter((m) => m.kind === "value")],
        ["Static fields", members.filter((m) => m.kind === "field" && m.static)],
        ["Fields", members.filter((m) => m.kind === "field" && !m.static)],
        ["Static methods", members.filter((m) => m.kind === "method" && m.static)],
        ["Methods", members.filter((m) => m.kind === "method" && !m.static)],
    ];
    for (const [label, list] of groups) {
        if (!list.length) continue;
        if (label === "Values") {
            parts.push("## Values\n\n| Value | Number | Description |\n|---|---|---|\n" +
                list.map((m) => `| <span id="${slug(m.name)}">\`${m.name}\`</span> | \`${m.value ?? ""}\` | ${summary(m.doc, targets)} |`).join("\n"));
            continue;
        }
        parts.push(renderMemberList(label, list, targets));
    }
    return parts.join("\n\n") + "\n";
}

function renderNamespacePage(ns, title, items, targets, order) {
    const parts = [frontMatter(title, ns.doc ? ns.doc.summary : title, ["sidebar:", "  label: Overview", "  order: 0"])];
    if (ns.amiga) parts.push('<p class="cs-kind">AmigaOS only (<code>--target m68k-amigaos</code>)</p>');
    if (ns.doc) parts.push(renderMarkdown(ns.doc.description, targets));
    const types = items.filter(hasPage);
    if (types.length) {
        parts.push("## Types\n\n| Type | Description |\n|---|---|\n" +
            types.map((t) => `| [\`${typeTitle(t)}\`](${itemUrl(t)}) | ${summary(t.doc, targets)} |`).join("\n"));
    }
    for (const [label, kind] of [["Constants", "const"], ["Variables", "global"], ["Functions", "function"]]) {
        const list = items.filter((i) => i.kind === kind);
        if (!list.length) continue;
        parts.push(renderMemberList(label, list.map((m) => (m.value != null ? { ...m, signature: m.signature + " = " + m.value } : m)), targets));
    }
    return parts.join("\n\n") + "\n";
}

function writeReference(api) {
    const targets = linkTargets(api);
    const dir = path.join(content, "reference");
    const groups = new Map(); // group slug -> {title, ns, items, order}
    const group = (key, title, ns, order) => {
        if (!groups.has(key)) groups.set(key, { title, ns, items: [], order });
        return groups.get(key);
    };
    group("builtin", "Built-in types", { name: "", doc: null }, 1);
    api.namespaces.forEach((n, i) => group(nsSlug(n.name), n.name === "" ? "Global namespace" : n.name, n, n.name === "System" ? 2 : 10 + i));
    for (const item of api.items) groups.get(itemGroup(item))?.items.push(item);
    // the built-in types: the //! comment of the builtin files is the second paragraph of the global namespace's
    const builtins = groups.get("builtin");
    builtins.ns = { name: "", doc: { summary: "The types and functions that the compiler provides itself.", description: "The types, functions and namespaces that the compiler provides itself: they need no `using`. Their declarations (for this documentation) are in `stdlib/builtin`." } };

    let pages = 0;
    for (const [key, g] of groups) {
        if (!g.items.length && !(g.ns.doc && g.ns.doc.description)) continue;
        const gdir = path.join(dir, key);
        fs.mkdirSync(gdir, { recursive: true });
        fs.writeFileSync(path.join(gdir, "index.md"), renderNamespacePage(g.ns, g.title, g.items, targets));
        pages++;
        for (const item of g.items.filter(hasPage)) {
            fs.writeFileSync(path.join(gdir, slug(item.name) + ".md"), renderTypePage(item, targets));
            pages++;
        }
        // the order of the groups in the sidebar: a directory's label and order come from its index page
        groups.get(key).written = true;
    }
    const list = [...groups.entries()].filter(([, g]) => g.written).sort((a, b) => a[1].order - b[1].order || a[1].title.localeCompare(b[1].title));
    const index = [frontMatter("Reference", "The standard library and the built-in types of CShift", ["sidebar:", "  label: Overview", "  order: 0"]),
        `The reference of CShift ${api.version}: the built-in types and every public declaration of the standard library, made from their doc comments by \`cshiftc doc\`.`,
        "| Namespace | Description |\n|---|---|\n" + list.map(([key, g]) => `| [${g.title}](${base}/reference/${key}/) | ${summary(g.ns.doc, targets)} |`).join("\n")];
    fs.writeFileSync(path.join(dir, "index.md"), index.join("\n\n") + "\n");
    // the sidebar groups in this order
    fs.writeFileSync(path.join(site, "src/reference-groups.json"), JSON.stringify(list.map(([key, g]) => ({ key, label: g.title }))));
    return pages + 1;
}

// ---------------------------------------------------------------------------------------------------------------------
// "Since": the first release whose standard library has a declaration
// ---------------------------------------------------------------------------------------------------------------------

// The number of parameters in a signature ("void Add(T value)": 1), -1 without parentheses: overloads are told apart
// by it (not by the types, which changed over time, e.g. from string to StringSlice).
function arity(signature) {
    const open = signature.indexOf("(");
    if (open < 0) return -1;
    let depth = 0;
    let count = 0;
    let any = false;
    for (const c of signature.slice(open + 1)) {
        if (c === "<" || c === "(") depth++;
        else if ((c === ">" || c === ")") && depth > 0) depth--;
        else if (c === ")") break;
        else if (c === "," && depth === 0) count++;
        else if (c !== " ") any = true;
    }
    return any ? count + 1 : 0;
}

const itemKey = (i) => `${i.namespace}|${i.name}|${["function", "const", "global"].includes(i.kind) ? arity(i.signature) : ""}`;
const memberKey = (i, m) => `${itemKey(i)}|${m.name}|${arity(m.signature)}`;

// Sets doc.since of the declarations that have none, from the documentation of the earlier releases in
// $SITE_HISTORY (X.XX.json, X.XX-amiga.json; scripts/history.sh). What the oldest release has gets none; what no
// release has is new in this version. The built-in types are left out (older releases have no declarations of them).
function addSince(api) {
    const dir = process.env.SITE_HISTORY;
    if (!dir || !fs.existsSync(dir)) return;
    const cmp = (a, b) => a.localeCompare(b, undefined, { numeric: true });
    const releases = [...new Set(fs.readdirSync(dir).filter((f) => f.endsWith(".json")).map((f) => f.replace(/(-amiga)?\.json$/, "")))].sort(cmp);
    if (!releases.length) return;
    const first = new Map();
    for (const r of releases) {
        for (const file of [r + ".json", r + "-amiga.json"]) {
            if (!fs.existsSync(path.join(dir, file))) continue;
            for (const i of JSON.parse(fs.readFileSync(path.join(dir, file), "utf8")).items) {
                if (!first.has(itemKey(i))) first.set(itemKey(i), r);
                for (const m of i.members ?? []) if (!first.has(memberKey(i, m))) first.set(memberKey(i, m), r);
            }
        }
    }
    const oldest = releases[0];
    const sinceOf = (key) => {
        const r = first.get(key);
        if (r) return r === oldest ? "" : r;
        return /^\d/.test(version) ? version : "";
    };
    let count = 0;
    for (const i of api.items) {
        if (i.builtin) continue;
        const own = sinceOf(itemKey(i));
        if (i.doc && !i.doc.since && own) {
            i.doc.since = own;
            count++;
        }
        for (const m of i.members ?? []) {
            const s = sinceOf(memberKey(i, m));
            // a member that came with its type needs no "since" of its own
            if (m.doc && !m.doc.since && s && s !== own) {
                m.doc.since = s;
                count++;
            }
        }
    }
    console.log(`since: ${releases.length} releases (${oldest} .. ${releases[releases.length - 1]}), ${count} declarations marked`);
}

// ---------------------------------------------------------------------------------------------------------------------

// the version switch in the header (src/components/SiteTitle.astro)
{
    const major = /^\d/.test(version) ? version.split(".")[0] : "dev";
    const list = versions.map((v) => ({ major: String(v.major), label: `${v.version}`, url: `${v.url}` }));
    fs.writeFileSync(path.join(site, "src/versions.json"), JSON.stringify({ major, label: version === "dev" ? "dev" : version, versions: list }));
}

for (const d of ["docs", "language", "reference"]) fs.rmSync(path.join(content, d), { recursive: true, force: true });
const guides = writeGuides();
const api = loadApi();
let reference = 0;
if (api) {
    addSince(api);
    reference = writeReference(api);
}
else {
    fs.writeFileSync(path.join(site, "src/reference-groups.json"), "[]");
    console.warn("no reference: set CSHIFTC to a cshiftc with 'doc', or put host.json/amiga.json into site/api");
}
console.log(`prepare: ${guides} guide pages, ${reference} reference pages`);
