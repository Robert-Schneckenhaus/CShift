# Templates

[app/](app) is the template of a CShift program for a GitHub template repository ("Use this template"): what
`cshiftc new` makes (`cshift.json`, `src/main.cshift`, `.gitignore`), and in addition

* a README for the new repository,
* `.gitattributes` with `*.cshift linguist-language=C#`, so that GitHub counts the program in its language statistics,
* `.github/workflows/build.yml`: builds and runs the program on Linux and Windows with the standalone compiler of the
  latest CShift release (`gh release download`).

Published as its own repository and marked as a template:

```
gh repo create Robert-Schneckenhaus/cshift-app-template --public --source templates/app --push
gh repo edit Robert-Schneckenhaus/cshift-app-template --template
```

(`--source` needs the folder as a git repository of its own: `git init` in a copy of `templates/app` first.) The
template is published as [cshift-app-template](https://github.com/Robert-Schneckenhaus/cshift-app-template).
