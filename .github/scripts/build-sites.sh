#!/usr/bin/env bash
# Builds the published website (.github/workflows/pages.yml): one version per major release, each from the newest
# release branch of that major version (with its own site/, compiler and standard library), into <out>/vN/; <out>/
# redirects to the newest major version.
#
#   .github/scripts/build-sites.sh <out-dir>
#
# Needs git (the release branches are fetched here), gh (stage 0, selfhost/fetch-stage0.sh), clang in PATH (with the C
# library of WASI for the playground) and node.
set -euo pipefail
OUT="$(mkdir -p "${1:?output directory}" && cd "$1" && pwd)"
ROOT="$(git rev-parse --show-toplevel)"
BASE="/CShift"
WORK="$(mktemp -d)"
trap 'git -C "$ROOT" worktree prune; rm -rf "$WORK"' EXIT

git -C "$ROOT" fetch -q origin 'refs/heads/release/*:refs/remotes/origin/release/*'
versions="$(git -C "$ROOT" for-each-ref --format='%(refname:short)' 'refs/remotes/origin/release/v*' | sed 's|.*/v||' | sort -V)"

# the newest release of every major version that has a site
entries=()
for major in $(printf '%s\n' $versions | sed 's/\..*//' | sort -un); do
    for v in $(printf '%s\n' $versions | grep "^$major\." | sort -rV); do
        if git -C "$ROOT" cat-file -e "origin/release/v$v:site/package.json" 2> /dev/null; then
            entries+=("$major $v")
            break
        fi
    done
done
if [ ${#entries[@]} -eq 0 ]; then
    echo "no release has a site yet"
    exit 1
fi
json="["
for e in "${entries[@]}"; do
    set -- $e
    json+="{\"major\":$1,\"version\":\"$2\",\"url\":\"$BASE/v$1/\"},"
done
json="${json%,}]"
echo "versions: $json"

for e in "${entries[@]}"; do
    set -- $e
    major="$1"
    version="$2"
    tree="$WORK/v$major"
    echo "::group::v$major: release $version"
    git -C "$ROOT" worktree add -q --detach "$tree" "origin/release/v$version"
    (
        cd "$tree"
        stage0="${CSHIFT_STAGE0:-$(bash selfhost/fetch-stage0.sh build/stage0)}"   # CSHIFT_STAGE0: for a local test
        printf '%s\n' "$version" > selfhost/version/version.txt
        "$stage0" build selfhost -O0 -o build/cshc
        bash site/scripts/history.sh "$tree/build/cshc" "$tree/build/history" "$version"
        # the compiler of the playground (releases that have one)
        if [ -f site/scripts/playground.sh ]; then
            bash site/scripts/playground.sh "$tree/build/cshc"
        fi
        cd site
        npm ci --no-audit --no-fund
        SITE_BASE="$BASE/v$major" SITE_VERSION="$version" SITE_VERSIONS="$json" SITE_BRANCH="release/v$version" \
            SITE_HISTORY="$tree/build/history" CSHIFTC="$tree/build/cshc" npm run build
        cp -r dist "$OUT/v$major"
    )
    echo "::endgroup::"
done

# the root: to the newest major version (also for unknown pages)
newest="${entries[${#entries[@]}-1]%% *}"
cat > "$OUT/index.html" <<HTML
<!doctype html>
<meta charset="utf-8">
<title>CShift</title>
<meta http-equiv="refresh" content="0; url=$BASE/v$newest/">
<link rel="canonical" href="$BASE/v$newest/">
<a href="$BASE/v$newest/">CShift documentation</a>
HTML
cp "$OUT/v$newest/404.html" "$OUT/404.html"
echo "built: $(printf '%s, ' "${entries[@]}")"
