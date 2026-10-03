// The CShift website: the guides (docs/), the reference of the standard library (made by scripts/prepare.mjs from the
// doc comments) and a search (Pagefind, built into Starlight). See README.md.
import { defineConfig } from "astro/config";
import starlight from "@astrojs/starlight";
import fs from "node:fs";

const grammar = JSON.parse(fs.readFileSync(new URL("../vscode-extension/syntaxes/cshift.tmLanguage.json", import.meta.url), "utf8"));
const groups = fs.existsSync(new URL("./src/reference-groups.json", import.meta.url))
    ? JSON.parse(fs.readFileSync(new URL("./src/reference-groups.json", import.meta.url), "utf8"))
    : [];

export default defineConfig({
    site: process.env.SITE_URL ?? "https://robert-schneckenhaus.github.io",
    base: process.env.SITE_BASE ?? "/CShift/v0",
    trailingSlash: "always",
    integrations: [
        starlight({
            title: "CShift",
            description: "A C#-like language that compiles to native code: the guide and the reference.",
            social: [{ icon: "github", label: "GitHub", href: "https://github.com/Robert-Schneckenhaus/CShift" }],
            customCss: ["./src/styles/cshift.css"],
            components: { SiteTitle: "./src/components/SiteTitle.astro" },
            expressiveCode: {
                shiki: { langs: [{ ...grammar, name: "cshift", aliases: ["csh"] }] },
            },
            sidebar: [
                {
                    label: "Start",
                    items: [
                        { label: "Overview", link: "/docs/" },
                        { label: "Installation", link: "/docs/install/" },
                        { label: "Playground", link: "/playground/" },
                    ],
                },
                { label: "Language guide", items: [{ autogenerate: { directory: "language" } }] },
                { label: "Language reference", items: [{ autogenerate: { directory: "spec" } }] },
                { label: "Topics", items: [{ autogenerate: { directory: "docs" } }] },
                {
                    label: "Reference",
                    items: [
                        { label: "Overview", link: "/reference/" },
                        ...groups.map((g) => ({ label: g.label, collapsed: true, items: [{ autogenerate: { directory: "reference/" + g.key } }] })),
                    ],
                },
            ],
        }),
    ],
});
