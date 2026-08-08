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
cp -R core integration automation ui "$STAGE/"

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

# Layout checks: ZipSlip, and every TOC-listed Lua file present in the archive.
# The TOC cross-check is the guard against shipping a zip that omits a whole
# directory the TOC loads (v0.2.0 shipped without automation/ this way).
python3 - <<'PY'
import zipfile, sys
from pathlib import Path

z = zipfile.ZipFile("dist/AscensionSuite.zip")
names = set(z.namelist())

if "AscensionSuite/AscensionSuite.toc" not in names:
    print("FAIL: toc missing in zip", file=sys.stderr)
    print("\n".join(sorted(names)[:20]), file=sys.stderr)
    sys.exit(1)

for n in names:
    if ".." in n.split("/") or n.startswith("/"):
        print("FAIL: unsafe path in zip:", n, file=sys.stderr)
        sys.exit(1)

listed = []
for line in Path("AscensionSuite.toc").read_text().splitlines():
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    if line.lower().endswith(".lua"):
        listed.append(line.replace("\\", "/"))

if not listed:
    print("FAIL: no Lua files listed in AscensionSuite.toc", file=sys.stderr)
    sys.exit(1)

missing = [p for p in listed if "AscensionSuite/" + p not in names]
if missing:
    print("FAIL: TOC lists files absent from zip:", file=sys.stderr)
    for p in missing:
        print("  " + p, file=sys.stderr)
    sys.exit(1)

print("OK: dist/AscensionSuite.zip (%d entries, %d TOC Lua files verified)"
      % (len(names), len(listed)))
PY
