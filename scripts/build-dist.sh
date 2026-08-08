#!/usr/bin/env sh
# Build dist/AscensionSuite.zip ready to drop into Interface/AddOns/.
#
#   sh scripts/build-dist.sh
set -eu
cd "$(dirname "$0")/.."

OUT_DIR="dist"
STAGE="$OUT_DIR/AscensionSuite"
ZIP="$OUT_DIR/AscensionSuite.zip"

rm -rf "$STAGE" "$ZIP"
mkdir -p "$STAGE"

# Addon payload only (no .git, tests, dist, docs sketches, scripts).
cp AscensionSuite.toc "$STAGE/"
cp -R core integration ui "$STAGE/"

# Optional player-facing docs inside the zip (keep tiny).
mkdir -p "$STAGE/docs"
if [ -f README.md ]; then cp README.md "$STAGE/docs/"; fi
if [ -f CHANGELOG.md ]; then cp CHANGELOG.md "$STAGE/docs/"; fi
if [ -f SECURITY.md ]; then cp SECURITY.md "$STAGE/docs/"; fi

# Normalize to backslash TOC paths already in .toc; ensure unix zip layout.
rm -f "$ZIP"
(
    cd "$OUT_DIR"
    zip -r -q "AscensionSuite.zip" AscensionSuite \
        -x "*.DS_Store" -x "*__pycache__*"
)

# Basic ZipSlip / layout checks
python3 - <<'PY'
import zipfile, sys
z = zipfile.ZipFile("dist/AscensionSuite.zip")
names = z.namelist()
if not any(n == "AscensionSuite/AscensionSuite.toc" or n.endswith("AscensionSuite/AscensionSuite.toc") for n in names):
    # zip may list with forward slashes
    if "AscensionSuite/AscensionSuite.toc" not in names:
        print("FAIL: toc missing in zip", file=sys.stderr)
        print("\n".join(names[:20]), file=sys.stderr)
        sys.exit(1)
for n in names:
    if ".." in n.split("/") or n.startswith("/"):
        print("FAIL: unsafe path in zip:", n, file=sys.stderr)
        sys.exit(1)
print("OK: dist/AscensionSuite.zip (%d entries)" % len(names))
PY
