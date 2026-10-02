# The CShift website

An [Astro Starlight](https://starlight.astro.build) site with the guides and the reference of the standard library,
published on GitHub Pages by [.github/workflows/pages.yml](../.github/workflows/pages.yml) when a release is made.

| Part | Comes from |
|---|---|
| Home page | `src/content/docs/index.mdx` |
| Language guide, topics | `docs/**/*.md`, copied by `scripts/prepare.mjs` (title from the first heading, links rewritten to the site; links to other files go to GitHub) |
| Reference | the JSON of `cshiftc doc` for the standard library and the built-in types (`stdlib/builtin`), host and `m68k-amigaos`, turned into pages by `scripts/prepare.mjs` |
| Search | Pagefind (built into Starlight), indexed when the site is built |
| Syntax highlighting | the TextMate grammar of the VS Code extension (`vscode-extension/syntaxes`) |

## Building it locally

```
cd site
npm ci
CSHIFTC=<a cshiftc that knows 'doc'> npm run build     # or: npm run dev
npx astro preview
```

Without `CSHIFTC`, `scripts/prepare.mjs` takes the JSON from `site/api/host.json` and `site/api/amiga.json` if they are
there, otherwise the site has no reference. The generated pages (`src/content/docs/docs`, `language`, `reference`) are
not committed.

## Versions

Before 1.0 there is one version: the site of the newest release, at the root. From 1.0 on there will be one version
per major release (`/v1/`, `/v2/`, ...), each updated by the releases of its major version; the workflow then has to
build the newest release branch of every major version into its folder.
