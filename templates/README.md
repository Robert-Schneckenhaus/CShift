# Templates

[app/](app) is the template of a CShift program for a GitHub template repository ("Use this template"): what
`cshiftc new` makes (`cshift.json`, `src/main`, `.gitignore`), and in addition

* a README for the new repository,
* `.gitattributes` with `*.csh linguist-language=C#`, so that GitHub does not count the files as C shell scripts,
* `.github/workflows/build.yml`: builds and runs the program on Linux and Windows with the standalone compiler of the
  latest CShift release (`gh release download`).

Published as its own repository and marked as a template:

```
gh repo create Robert-Schneckenhaus/cshift-app-template --public --source templates/app --push
gh repo edit Robert-Schneckenhaus/cshift-app-template --template
```

(`--source` needs the folder as a git repository of its own: `git init` in a copy of `templates/app` first.)

**The extension:** the template keeps `src/main.csh` until a release reads `.cshift` (0.32): its workflow builds with
the latest release, and 0.31 knows only `.csh`. Then `src/main.csh` becomes `src/main.cshift`, here and in
[cshift-app-template](https://github.com/Robert-Schneckenhaus/cshift-app-template), and the `.gitattributes` of the
template names `*.cshift`.
