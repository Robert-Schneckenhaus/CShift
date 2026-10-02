# The CShift website

An [Astro Starlight](https://starlight.astro.build) site with the guides and the reference of the standard library,
published on GitHub Pages by [.github/workflows/pages.yml](../.github/workflows/pages.yml) when a release is made
(one version per major release).

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
git fetch origin 'refs/heads/release/*:refs/remotes/origin/release/*'
bash scripts/history.sh <cshiftc> /tmp/history      # optional: "since"
CSHIFTC=<a cshiftc that knows 'doc'> SITE_HISTORY=/tmp/history npm run build     # or: npm run dev
npx astro preview
```

Without `CSHIFTC`, `scripts/prepare.mjs` takes the JSON from `site/api/host.json` and `site/api/amiga.json` if they are
there, otherwise the site has no reference. The generated pages (`src/content/docs/docs`, `language`, `reference`) are
not committed.

## Versions and "since"

There is one version of the site per major release, at `/CShift/v0/`, `/CShift/v1/`, ...; `/CShift/` goes to the
newest one, and a switch next to the title goes to the others. `.github/scripts/build-sites.sh` builds each version
from the newest release branch of its major version (with that release's `site/`, compiler and library), so the
releases of a major version update its documentation. Release branches without `site/` (before 0.22) are skipped.

"Since" comes from the history: `scripts/history.sh` documents the standard library of every earlier release
branch with this version's `cshiftc doc` (it reads the older sources as well), and `scripts/prepare.mjs` gives every
declaration the first release that has it (`$SITE_HISTORY`). What the oldest release (0.01) has gets no "since";
overloads are told apart by their number of parameters. A `@since` in the doc comment wins.

| Variable | For `scripts/prepare.mjs` |
|---|---|
| `CSHIFTC` | the compiler that writes the reference (otherwise `site/api/*.json`) |
| `SITE_BASE` | the path of the version (default `/CShift/v0`) |
| `SITE_VERSION` | the release that is built (default `dev`) |
| `SITE_VERSIONS` | all versions, as JSON (`[{"major": 0, "version": "0.22", "url": "/CShift/v0/"}]`), for the switch |
| `SITE_HISTORY` | the directory of `scripts/history.sh` |
| `SITE_BRANCH` | the branch the GitHub links go to (default `master`) |
