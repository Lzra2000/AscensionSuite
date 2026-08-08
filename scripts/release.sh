#!/usr/bin/env sh
# Tag + GitHub Release with AscensionSuite.zip.
#
#   sh scripts/release.sh 0.1.0
#
# Requires: clean tree, CHANGELOG.md top entry matching version, gh auth.
# Does not bump toc — bump version in AscensionSuite.toc + CHANGELOG first.
set -eu
cd "$(dirname "$0")/.."

if [ "$#" -ne 1 ]; then
    echo "Usage: sh scripts/release.sh <version>   (e.g. 0.1.0)" >&2
    exit 1
fi
VERSION="$1"
TAG="v$VERSION"

if [ -n "$(git status --porcelain)" ]; then
    echo "Working tree not clean — commit or stash first." >&2
    git status --short
    exit 1
fi

if ! grep -q "^## Version: $VERSION$" AscensionSuite.toc; then
    echo "AscensionSuite.toc ## Version: does not match $VERSION" >&2
    exit 1
fi

if ! grep -q "^### $VERSION" CHANGELOG.md; then
    echo "CHANGELOG.md missing ### $VERSION entry" >&2
    exit 1
fi

sh scripts/check.sh
sh scripts/build-dist.sh

# Extract changelog body for this version (until next ### heading).
NOTES="$(python3 - <<PY
from pathlib import Path
import re
text = Path("CHANGELOG.md").read_text()
m = re.search(r"(### $VERSION.*?)(?=\n### |\Z)", text, re.S)
print(m.group(1).strip() if m else "AscensionSuite $VERSION")
PY
)"

if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "Tag $TAG already exists locally."
else
    git tag -a "$TAG" -m "AscensionSuite $VERSION"
fi

git push origin HEAD
git push origin "$TAG"

# Create or update GitHub Release with zip asset.
if gh release view "$TAG" >/dev/null 2>&1; then
    gh release upload "$TAG" dist/AscensionSuite.zip --clobber
    gh release edit "$TAG" --title "AscensionSuite $VERSION" --notes "$NOTES"
else
    gh release create "$TAG" dist/AscensionSuite.zip \
        --title "AscensionSuite $VERSION" \
        --notes "$NOTES"
fi

echo "OK: GitHub Release $TAG with dist/AscensionSuite.zip"
echo "    https://github.com/Lzra2000/AscensionSuite/releases/tag/$TAG"
